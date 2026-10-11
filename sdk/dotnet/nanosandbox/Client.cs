// Client.cs — the stateless protocol client. Each call dials and re-negotiates
// a fresh connection (mirroring the Python SDK), so the client holds only the
// socket path and the capabilities advertised by the helper's handshake.

using System.Collections.Generic;
using System;

/// A protocol client bound to one helper socket.
class SandboxClient {
    private String socketPath;
    private List<String> caps;

    private SandboxClient(String socketPath, List<String> caps) {
        this.socketPath = socketPath;
        this.caps = caps;
    }

    /// Dial the helper socket, perform the hello handshake, and return a client.
    public static SandboxClient connect(String socketPath) {
        Conn conn = new Conn(socketPath);
        List<String> caps = new List<String>();
        JsonValue capsVal = conn.hello.get("capabilities");
        if (capsVal != null && capsVal.isArray()) {
            for (int i = 0; i < capsVal.size(); i++) {
                caps.Add(capsVal.getAt(i).stringValue);
            }
        }
        conn.close();
        return new SandboxClient(socketPath, caps);
    }

    /// The capabilities advertised by the helper.
    public List<String> capabilities() {
        return caps;
    }

    /// Whether the helper advertises the given capability.
    public bool supports(String capability) {
        for (int i = 0; i < caps.Count; i++) {
            if (caps[i].Equals(capability)) {
                return true;
            }
        }
        return false;
    }

    /// Send a request on a fresh connection and return the response.
    public JsonValue call(JsonValue message) {
        Conn conn = new Conn(socketPath);
        try {
            return conn.call(message);
        } finally {
            conn.close();
        }
    }

    public String getSocketPath() {
        return socketPath;
    }

    /// The helper's protocol version.
    public String ping() {
        JsonValue req = JsonValue.makeObject();
        req.put("type", JsonValue.of("ping"));
        JsonValue resp = call(req);
        return resp.str("version");
    }

    /// List sandbox handles, optionally including stopped ones.
    public List<JsonValue> list(bool all) {
        JsonValue req = JsonValue.makeObject();
        req.put("type", JsonValue.of("list"));
        req.put("all", JsonValue.of(all));
        JsonValue resp = call(req);
        return resp.get("sandboxes").arrayValue;
    }

    /// List all snapshots.
    public List<JsonValue> snapshots() {
        JsonValue req = JsonValue.makeObject();
        req.put("type", JsonValue.of("snapshot_list"));
        JsonValue resp = call(req);
        return resp.get("snapshots").arrayValue;
    }

    /// Fetch a sandbox's info by name.
    public JsonValue get(String name) {
        JsonValue req = JsonValue.makeObject();
        req.put("type", JsonValue.of("get"));
        req.put("name", JsonValue.of(name));
        return call(req);
    }

    /// Create a sandbox from a spec and return a handle.
    public Sandbox create(JsonValue spec) {
        JsonValue req = JsonValue.makeObject();
        req.put("type", JsonValue.of("create"));
        req.put("spec", spec);
        call(req);
        return new Sandbox(this, spec.str("name"));
    }

    /// Create a sandbox from a builder.
    public Sandbox createWith(SandboxBuilder builder) {
        JsonValue spec = builder.build();
        if (!spec.has("name") || spec.str("name").Length == 0) {
            throw new NanosbError("internal", "spec.name is required to create");
        }
        return create(spec);
    }

    /// A handle bound to the named sandbox.
    public Sandbox sandbox(String name) {
        return new Sandbox(this, name);
    }
}