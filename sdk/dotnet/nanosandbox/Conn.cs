// Conn.cs — NanosbError and the NDJSON-over-Unix-socket connection.
//
// One `Conn` dials the helper socket, performs the `hello` handshake, and
// speaks NDJSON: each request is one compact JSON line, each response is one
// line. `call` raises `NanosbError` for `error` frames; `recv` returns the raw
// frame so drivers can observe error frames without aborting.

using System.Net.Sockets;
using System.Text;
using System;

/// A structured error returned by the helper.
class NanosbError : Exception {
    public String errorCode;
    public String message;

    public NanosbError(String code, String message) : base(message) {
        this.errorCode = code;
        this.message = message;
    }

    public bool isNotFound() {
        return errorCode == "not_found";
    }
}

/// One negotiated connection (dial -> hello -> request -> response).
class Conn {
    public static String PROTOCOL_VERSION = "1.0.0";
    public static String CLIENT_NAME = "nanosandbox-dotnet";

    private Socket socket;
    private UTF8Encoding utf8;
    private byte[] readBuf;
    private int readPos;
    public JsonValue hello;

    public Conn(String path) {
        this.utf8 = new UTF8Encoding();
        this.readBuf = new byte[0];
        this.readPos = 0;
        this.socket = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
        this.socket.Connect(new UnixDomainSocketEndPoint(path));
        this.hello = handshake();
    }

    private JsonValue handshake() {
        JsonValue req = JsonValue.makeObject();
        req.put("type", JsonValue.of("hello"));
        req.put("client", JsonValue.of(CLIENT_NAME));
        req.put("sdk_version", JsonValue.of(PROTOCOL_VERSION));
        req.put("protocol_min", JsonValue.of(PROTOCOL_VERSION));
        req.put("protocol_max", JsonValue.of(PROTOCOL_VERSION));
        send(req);
        JsonValue resp = recv();
        if (!resp.str("type").Equals("hello_ok")) {
            throw new NanosbError(resp.str("code"), resp.str("message"));
        }
        if (!resp.str("protocol").Equals(PROTOCOL_VERSION)) {
            throw new NanosbError(
                "incompatible_version",
                "helper speaks " + resp.str("protocol") + ", client needs " + PROTOCOL_VERSION
            );
        }
        return resp;
    }

    public void send(JsonValue message) {
        String line = message.stringify() + "\n";
        socket.Send(utf8.GetBytes(line));
    }

    /// Read one response frame without raising on `error` frames.
    public JsonValue recv() {
        String line = readLine();
        if (line == null || line.Length == 0) {
            throw new NanosbError("transport", "connection closed");
        }
        return JsonValue.parse(line);
    }

    /// Send a request and raise `NanosbError` if the response is an error frame.
    public JsonValue call(JsonValue message) {
        send(message);
        JsonValue resp = recv();
        if (resp.str("type").Equals("error")) {
            throw new NanosbError(resp.str("code"), resp.str("message"));
        }
        return resp;
    }

    /// Set the socket receive timeout in milliseconds (0 disables).
    public void setReadTimeout(int millis) {
        socket.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReceiveTimeout, millis);
    }

    public UTF8Encoding utf8Codec() {
        return utf8;
    }

    public void close() {
        try {
            socket.Close();
        } catch (Exception e) {
            // already closed
        }
    }

    // Line framing ------------------------------------------------------

    private String readLine() {
        while (true) {
            int idx = indexOfNewline();
            if (idx >= 0) {
                String line = utf8.GetString(readBuf, readPos, idx - readPos);
                readPos = idx + 1;
                return line;
            }
            compact();
            byte[] chunk = new byte[4096];
            int n;
            try {
                n = socket.Receive(chunk);
            } catch (Exception e) {
                throw new NanosbError("transport", "read failed: " + e.Message);
            }
            if (n <= 0) {
                if (readBuf.Length == 0) {
                    return null;
                }
                String line = utf8.GetString(readBuf, 0, readBuf.Length);
                readBuf = new byte[0];
                return line;
            }
            byte[] newBuf = new byte[readBuf.Length + n];
            for (int i = 0; i < readBuf.Length; i++) {
                newBuf[i] = readBuf[i];
            }
            for (int i = 0; i < n; i++) {
                newBuf[readBuf.Length + i] = chunk[i];
            }
            readBuf = newBuf;
        }
    }

    private void compact() {
        if (readPos > 0) {
            byte[] rest = new byte[readBuf.Length - readPos];
            for (int i = readPos; i < readBuf.Length; i++) {
                rest[i - readPos] = readBuf[i];
            }
            readBuf = rest;
            readPos = 0;
        }
    }

    private int indexOfNewline() {
        for (int i = readPos; i < readBuf.Length; i++) {
            if (readBuf[i] == (byte) '\n') {
                return i;
            }
        }
        return -1;
    }
}