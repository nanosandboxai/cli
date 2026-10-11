// conn.mjs — connection, handshake, and NDJSON framing for the nanosandbox helper.
//
// The helper speaks NDJSON over a Unix stream socket. Every connection begins
// with a `hello` handshake; each request yields one response frame, and
// streaming verbs then emit additional `guest`/`event` frames terminated by an
// exit/done frame. This module owns the wire: dialing, line framing, and the
// typed error surface. It is stdlib-only (`node:net`).
import { connect } from "node:net";

export const PROTOCOL_VERSION = "1.0.0";
export const CLIENT_NAME = "nanosandbox-typescript";

/** A structured error returned by the helper. */
export class NanosbError extends Error {
  constructor(code, message) {
    super(`${code}: ${message}`);
    this.code = code;
    this.message = message;
  }

  isNotFound() {
    return this.code === "not_found";
  }
}

/** Base64-encode bytes for the wire. */
export function b64(data) {
  return Buffer.from(data).toString("base64");
}

/** Base64-decode bytes from the wire. */
export function unb64(text) {
  return Buffer.from(text, "base64");
}

/**
 * Dial a Unix stream socket, resolving once the connection is established.
 * `node:net`'s `connect()` returns the socket immediately; the connection
 * completes asynchronously via the `connect`/`error` events.
 */
export async function dial(path) {
  const sock = connect({ type: "unix", path });
  await new Promise((resolve, reject) => {
    sock.once("connect", resolve);
    sock.once("error", reject);
  });
  return sock;
}

/**
 * An event-driven line reader over a `node:net` Socket (or any object with
 * `on("data"|"end"|"error")`). `readLine()` resolves with the next line
 * (without the trailing newline) or `null` at EOF. `node:net`'s `read()` is
 * non-blocking (returns `null` when the buffer is empty), so lines are
 * assembled from `data` events instead.
 */
export function makeLineReader(sock) {
  let buf = Buffer.alloc(0);
  let eof = false;
  let error = null;
  const waiters = [];

  const pump = () => {
    while (waiters.length) {
      const idx = buf.indexOf(Buffer.from("\n"));
      if (idx >= 0) {
        const line = buf.subarray(0, idx).toString();
        buf = buf.subarray(idx + 1);
        waiters.shift()(line);
      } else if (eof) {
        const line = buf.toString();
        buf = Buffer.alloc(0);
        waiters.shift()(line.length ? line : null);
      } else {
        break;
      }
    }
  };

  sock.on("data", (data) => {
    buf = Buffer.concat([buf, data]);
    pump();
  });
  sock.on("end", () => {
    eof = true;
    pump();
  });
  sock.on("error", (err) => {
    error = err;
    while (waiters.length) waiters.shift()(null);
  });

  return async function readLine() {
    if (error) throw error;
    const idx = buf.indexOf(Buffer.from("\n"));
    if (idx >= 0) {
      const line = buf.subarray(0, idx).toString();
      buf = buf.subarray(idx + 1);
      return line;
    }
    if (eof) {
      const line = buf.toString();
      buf = Buffer.alloc(0);
      return line.length ? line : null;
    }
    return new Promise((resolve) => waiters.push(resolve));
  };
}

/** One negotiated connection: dial -> hello -> request -> response. */
export class Conn {
  constructor(path, clientName = CLIENT_NAME) {
    this._path = path;
    this._clientName = clientName;
    this._sock = null;
    this._readLine = null;
    this._closed = false;
    this.hello = null;
  }

  async open() {
    this._sock = await dial(this._path);
    // Silence late socket errors so a peer reset cannot crash the process.
    this._sock.on?.("error", () => {});
    this._readLine = makeLineReader(this._sock);
    this.hello = await this._handshake();
    return this;
  }

  async _handshake() {
    this.send({
      type: "hello",
      client: this._clientName,
      sdk_version: PROTOCOL_VERSION,
      protocol_min: PROTOCOL_VERSION,
      protocol_max: PROTOCOL_VERSION,
    });
    const resp = await this.recv();
    if (resp.type !== "hello_ok") {
      throw new NanosbError(resp.code ?? "internal", resp.message ?? "bad handshake");
    }
    if (resp.protocol !== PROTOCOL_VERSION) {
      throw new NanosbError(
        "incompatible_version",
        `helper speaks ${resp.protocol}, client needs ${PROTOCOL_VERSION}`,
      );
    }
    return resp;
  }

  send(message) {
    this._sock.write(JSON.stringify(message) + "\n");
  }

  async recv() {
    const line = await this._readLine();
    if (line === null) throw new NanosbError("transport", "connection closed");
    return JSON.parse(line);
  }

  async call(message) {
    this.send(message);
    const resp = await this.recv();
    if (resp.type === "error") {
      throw new NanosbError(resp.code ?? "internal", resp.message ?? "");
    }
    return resp;
  }

  close() {
    if (this._closed) return;
    this._closed = true;
    const sock = this._sock;
    if (!sock) return;
    try {
      sock.destroySoon();
    } catch {
      // already closed
    }
  }
}