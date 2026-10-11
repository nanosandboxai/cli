package nanosandbox;

import java.io.IOException;
import java.util.List;
import java.util.function.Consumer;

/**
 * Logs and metrics verbs for {@link Sandbox}. Kept in a separate file so each
 * source file stays focused (mirroring the Go SDK's split of the sandbox
 * handle across {@code sandbox.go} and {@code sandbox_fs.go}).
 */
final class SandboxObs {

    private final SandboxClient client;
    private final String name;

    SandboxObs(SandboxClient client, String name) {
        this.client = client;
        this.name = name;
    }

    /** Returns a resource usage snapshot. */
    Json metrics() throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("metrics"));
        req.set("name", Json.ofString(name));
        return client.call(req);
    }

    /** Streams metrics samples to {@code onEvent} until the done event. */
    void metricsStream(int intervalMs, Consumer<Json> onEvent) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("metrics_stream"));
        req.set("name", Json.ofString(name));
        if (intervalMs > 0) {
            req.set("interval_ms", Json.ofNumber(intervalMs));
        }
        streamEvents(req, "metrics", onEvent);
    }

    /** Returns buffered log lines. */
    List<Json> logs(int tail) throws IOException, NanosbError {
        return logsWith(tail, -1, "");
    }

    /** Returns buffered log lines with tail/cursor/source filters. */
    List<Json> logsWith(int tail, int cursor, String source) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("logs"));
        req.set("name", Json.ofString(name));
        req.set("follow", Json.ofBool(false));
        if (tail > 0) {
            req.set("tail", Json.ofNumber(tail));
        }
        if (cursor >= 0) {
            req.set("cursor", Json.ofNumber(cursor));
        }
        if (source != null && !source.isEmpty()) {
            req.set("source", Json.ofString(source));
        }
        return client.call(req).getArr("lines");
    }

    /** Streams log lines to {@code onLine} until the done event. */
    void logsFollow(Consumer<Json> onLine, int tail) throws IOException, NanosbError {
        logsFollowWith(onLine, tail, -1, "");
    }

    /** Streams log lines with tail/cursor/source filters. */
    void logsFollowWith(Consumer<Json> onLine, int tail, int cursor, String source)
            throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("logs"));
        req.set("name", Json.ofString(name));
        req.set("follow", Json.ofBool(true));
        if (tail > 0) {
            req.set("tail", Json.ofNumber(tail));
        }
        if (cursor >= 0) {
            req.set("cursor", Json.ofNumber(cursor));
        }
        if (source != null && !source.isEmpty()) {
            req.set("source", Json.ofString(source));
        }
        streamEvents(req, "log", onLine);
    }

    private void streamEvents(Json req, String eventName, Consumer<Json> onEvent)
            throws IOException, NanosbError {
        try (Connection conn = new Connection(client.socket())) {
            conn.open();
            conn.send(req);
            Json ack = conn.recv();
            if ("error".equals(ack.getStr("type"))) {
                throw errorFrom(ack);
            }
            while (true) {
                Json resp = conn.recv();
                if (!"event".equals(resp.getStr("type"))) {
                    continue;
                }
                String ev = resp.getStr("event");
                if ("done".equals(ev)) {
                    break;
                }
                if (eventName.equals(ev)) {
                    onEvent.accept(resp);
                }
            }
        }
    }

    private static NanosbError errorFrom(Json v) {
        String code = v.getStr("code");
        String message = v.getStr("message");
        if (code == null || code.isEmpty()) {
            code = "internal";
        }
        return new NanosbError(code, message == null ? "" : message);
    }
}