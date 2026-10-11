package nanosandbox;

import java.io.IOException;
import java.net.StandardProtocolFamily;
import java.net.UnixDomainSocketAddress;
import java.nio.ByteBuffer;
import java.nio.channels.SocketChannel;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/**
 * One negotiated connection to the nanosandbox helper: dial the Unix stream
 * socket, perform the {@code hello} handshake, then exchange NDJSON frames
 * (one JSON object per line). Streaming verbs hold one connection for the
 * duration of the stream; every other call dials a fresh connection.
 */
public final class Connection implements AutoCloseable {

    /** The protocol version this SDK speaks. */
    public static final String PROTOCOL_VERSION = "1.0.0";

    /** Identifies this SDK in the hello handshake. */
    public static final String CLIENT_NAME = "nanosandbox-java";

    private final String path;
    private SocketChannel channel;
    private final StringBuilder lineBuf = new StringBuilder();
    private Json hello;
    private boolean closed;

    /** Creates a connection handle for the given Unix socket path. */
    public Connection(String path) {
        this.path = path;
    }

    /** Dials the socket and performs the hello handshake. */
    public void open() throws IOException, NanosbError {
        channel = SocketChannel.open(StandardProtocolFamily.UNIX);
        channel.connect(UnixDomainSocketAddress.of(path));
        hello = handshake();
    }

    private Json handshake() throws IOException, NanosbError {
        Json msg = Json.object();
        msg.set("type", Json.ofString("hello"));
        msg.set("client", Json.ofString(CLIENT_NAME));
        msg.set("sdk_version", Json.ofString(PROTOCOL_VERSION));
        msg.set("protocol_min", Json.ofString(PROTOCOL_VERSION));
        msg.set("protocol_max", Json.ofString(PROTOCOL_VERSION));
        send(msg);
        Json resp = recv();
        String rtype = resp.getStr("type");
        if (!"hello_ok".equals(rtype)) {
            String code = resp.getStr("code");
            String message = resp.getStr("message");
            if (code == null || code.isEmpty()) {
                code = "internal";
            }
            if (message == null || message.isEmpty()) {
                message = "bad handshake";
            }
            throw new NanosbError(code, message);
        }
        String proto = resp.getStr("protocol");
        if (!PROTOCOL_VERSION.equals(proto)) {
            throw new NanosbError(
                    "incompatible_version",
                    "helper speaks " + proto + ", client needs " + PROTOCOL_VERSION);
        }
        return resp;
    }

    /** Writes one JSON frame followed by a newline. */
    public void send(Json msg) throws IOException {
        byte[] bytes = (msg.stringify() + "\n").getBytes(StandardCharsets.UTF_8);
        ByteBuffer buf = ByteBuffer.wrap(bytes);
        while (buf.hasRemaining()) {
            channel.write(buf);
        }
    }

    /** Reads and parses the next response frame. */
    public Json recv() throws IOException, NanosbError {
        while (true) {
            int idx = lineBuf.indexOf("\n");
            if (idx >= 0) {
                String line = lineBuf.substring(0, idx);
                lineBuf.delete(0, idx + 1);
                if (line.isEmpty()) {
                    throw new NanosbError("transport", "connection closed");
                }
                return Json.parse(line);
            }
            ByteBuffer buf = ByteBuffer.allocate(8192);
            int n = channel.read(buf);
            if (n < 0) {
                if (lineBuf.length() == 0) {
                    throw new NanosbError("transport", "connection closed");
                }
                String line = lineBuf.toString();
                lineBuf.setLength(0);
                return Json.parse(line);
            }
            if (n == 0) {
                continue;
            }
            buf.flip();
            lineBuf.append(StandardCharsets.UTF_8.decode(buf));
        }
    }

    /**
     * Sends a request and returns the response, throwing a {@link NanosbError}
     * for an {@code error} frame.
     */
    public Json call(Json msg) throws IOException, NanosbError {
        send(msg);
        Json resp = recv();
        if ("error".equals(resp.getStr("type"))) {
            String code = resp.getStr("code");
            String message = resp.getStr("message");
            if (code == null || code.isEmpty()) {
                code = "internal";
            }
            throw new NanosbError(code, message == null ? "" : message);
        }
        return resp;
    }

    /** Returns the hello_ok response from the handshake. */
    public Json hello() {
        return hello;
    }

    /** Returns the capabilities advertised by the helper's handshake. */
    public List<String> capabilities() {
        List<String> caps = new ArrayList<>();
        if (hello != null) {
            for (Json c : hello.getArr("capabilities")) {
                caps.add(c.asString());
            }
        }
        return caps;
    }

    /** Closes the underlying socket (idempotent). */
    @Override
    public void close() {
        if (closed) {
            return;
        }
        closed = true;
        if (channel != null) {
            try {
                channel.close();
            } catch (IOException ignored) {
                // closing is best-effort
            }
        }
    }
}