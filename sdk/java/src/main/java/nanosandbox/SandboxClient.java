package nanosandbox;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

/**
 * A stateless protocol client bound to one helper socket. Each call dials and
 * re-negotiates a fresh connection (mirroring the Python and Go SDKs), so the
 * client holds only the socket path and the capabilities advertised by the
 * helper's handshake.
 */
public final class SandboxClient {

    private final String socket;
    private final List<String> caps;

    private SandboxClient(String socket, List<String> caps) {
        this.socket = socket;
        this.caps = caps;
    }

    /**
     * Dials the helper socket, performs the hello handshake, and returns a
     * client bound to it.
     */
    public static SandboxClient connect(String socketPath) throws IOException, NanosbError {
        try (Connection conn = new Connection(socketPath)) {
            conn.open();
            return new SandboxClient(socketPath, conn.capabilities());
        }
    }

    /** Returns the capabilities advertised by the helper. */
    public List<String> capabilities() {
        return caps;
    }

    /** Reports whether the helper advertises the given capability. */
    public boolean supports(String cap) {
        return caps.contains(cap);
    }

    /** Sends a request on a fresh connection and returns the response. */
    public Json call(Json msg) throws IOException, NanosbError {
        try (Connection conn = new Connection(socket)) {
            conn.open();
            return conn.call(msg);
        }
    }

    /** Returns the helper's protocol version. */
    public String ping() throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("ping"));
        String v = call(req).getStr("version");
        return v == null ? "" : v;
    }

    /** Lists sandbox handles, optionally including stopped ones. */
    public List<Json> list(boolean all) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("list"));
        req.set("all", Json.ofBool(all));
        return call(req).getArr("sandboxes");
    }

    /** Lists all snapshots. */
    public List<Json> snapshots() throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("snapshot_list"));
        return call(req).getArr("snapshots");
    }

    /** Fetches a sandbox's info by name. */
    public Json get(String name) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("get"));
        req.set("name", Json.ofString(name));
        return call(req);
    }

    /** Creates a sandbox from a spec and returns a handle. */
    public Sandbox create(Json spec) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("create"));
        req.set("spec", spec);
        call(req);
        String name = spec.getStr("name");
        return new Sandbox(this, name == null ? "" : name);
    }

    /** Creates a sandbox from a builder. */
    public Sandbox createWith(SandboxBuilder builder) throws IOException, NanosbError {
        Json spec = builder.build();
        String name = spec.getStr("name");
        if (name == null || name.isEmpty()) {
            throw new NanosbError("internal", "spec.name is required to create");
        }
        return create(spec);
    }

    /** Returns a handle bound to the named sandbox. */
    public Sandbox sandbox(String name) {
        return new Sandbox(this, name);
    }

    /** Returns the socket path this client is bound to. */
    public String socket() {
        return socket;
    }

    /** Returns a copy of the advertised capabilities. */
    public List<String> capsCopy() {
        return new ArrayList<>(caps);
    }
}