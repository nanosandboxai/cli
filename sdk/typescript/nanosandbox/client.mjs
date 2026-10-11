// client.mjs — the stateless protocol client. Each call dials and re-negotiates
// a fresh connection (mirroring the Python SDK), so the client holds only the
// socket path and the capabilities advertised by the helper's handshake.
import { Conn, NanosbError, PROTOCOL_VERSION, CLIENT_NAME } from "./conn.mjs";
import { Sandbox } from "./sandbox.mjs";
import "./sandbox-fs.mjs"; // attach fs/storage/secrets/snapshots to Sandbox
import { SandboxBuilder, VolumeBuilder } from "./builders.mjs";

export class SandboxClient {
  constructor(socketPath, caps) {
    this._socket = socketPath;
    this._caps = caps;
  }

  /** Dial the helper socket, perform the hello handshake, and return a client. */
  static async connect(socketPath) {
    const conn = new Conn(socketPath);
    try {
      await conn.open();
      return new SandboxClient(socketPath, conn.hello.capabilities ?? []);
    } finally {
      conn.close();
    }
  }

  capabilities() {
    return [...this._caps];
  }

  supports(capability) {
    return this._caps.includes(capability);
  }

  async _call(message) {
    const conn = new Conn(this._socket);
    try {
      await conn.open();
      return await conn.call(message);
    } finally {
      conn.close();
    }
  }

  async ping() {
    return (await this._call({ type: "ping" })).version;
  }

  async list(all = false, label) {
    const req = { type: "list", all };
    if (label !== undefined && label !== null) req.label = label;
    return (await this._call(req)).sandboxes;
  }

  async listWithLabel(label, all = false) {
    return (await this._call({ type: "list", all, label })).sandboxes;
  }

  async listPage(limit, cursor, label) {
    const req = { type: "list", all: true };
    if (limit !== undefined && limit !== null) req.limit = limit;
    if (cursor !== undefined && cursor !== null) req.cursor = cursor;
    if (label !== undefined && label !== null) req.label = label;
    return this._call(req);
  }

  async snapshots() {
    return (await this._call({ type: "snapshot_list" })).snapshots;
  }

  async get(name) {
    return this._call({ type: "get", name });
  }

  async create(spec) {
    await this._call({ type: "create", spec });
    return new Sandbox(this, spec.name);
  }

  async createWith(builder) {
    const spec = builder.build();
    if (!spec.name) throw new Error("spec.name is required to create");
    return this.create(spec);
  }

  sandbox(name) {
    return new Sandbox(this, name);
  }
}

export { NanosbError, PROTOCOL_VERSION, CLIENT_NAME, Sandbox, SandboxBuilder, VolumeBuilder };