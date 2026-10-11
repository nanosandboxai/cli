package nanosandbox;

import java.io.IOException;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;

/**
 * Filesystem, storage, secrets, and snapshot verbs for {@link Sandbox}. Kept
 * in a separate file so each source file stays focused (mirroring the Go SDK's
 * {@code sandbox_fs.go}).
 *
 * <p>allow: SIZE_OK — the verb surface mirrors the Go reference's
 * {@code sandbox_fs.go} (395 LOC); the verbs are one cohesive protocol group.
 */
final class SandboxFs {

    private final SandboxClient client;
    private final String name;

    SandboxFs(SandboxClient client, String name) {
        this.client = client;
        this.name = name;
    }

    /** Reads bytes from a guest file. */
    byte[] fsRead(String path) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("fs_read"));
        req.set("name", Json.ofString(name));
        req.set("path", Json.ofString(path));
        String b64 = client.call(req).getStr("data_base64");
        return Base64.getDecoder().decode(b64 == null ? "" : b64);
    }

    /** Reads a guest file as UTF-8 text. */
    String fsReadToString(String path) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("fs_read_to_string"));
        req.set("name", Json.ofString(name));
        req.set("path", Json.ofString(path));
        String content = client.call(req).getStr("content");
        return content == null ? "" : content;
    }

    /** Writes bytes to a guest file. */
    void fsWrite(String path, byte[] data, boolean append) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("fs_write"));
        req.set("name", Json.ofString(name));
        req.set("path", Json.ofString(path));
        req.set("data_base64", Json.ofString(Base64.getEncoder().encodeToString(data)));
        req.set("append", Json.ofBool(append));
        client.call(req);
    }

    /** Streams a file write in {@code fs_data} chunks. */
    void fsWriteStream(String path, byte[] data, int chunkSize) throws IOException, NanosbError {
        if (chunkSize < 1) {
            chunkSize = 1;
        }
        try (Connection conn = new Connection(client.socket())) {
            conn.open();
            Json req = Json.object();
            req.set("type", Json.ofString("fs_write_stream"));
            req.set("name", Json.ofString(name));
            req.set("path", Json.ofString(path));
            conn.send(req);
            Json ack = conn.recv();
            if ("error".equals(ack.getStr("type"))) {
                throw errorFrom(ack);
            }
            int chunks = data.length == 0 ? 1 : (data.length + chunkSize - 1) / chunkSize;
            for (int i = 0; i < chunks; i++) {
                int start = i * chunkSize;
                int end = Math.min(start + chunkSize, data.length);
                Json body = Json.object();
                body.set("type", Json.ofString("fs_data"));
                body.set("data_base64", Json.ofString(Base64.getEncoder().encodeToString(
                        Arrays.copyOfRange(data, start, end))));
                body.set("eof", Json.ofBool(i == chunks - 1));
                conn.call(body);
            }
        }
    }

    /** Lists a guest directory. */
    List<Json> fsList(String path) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("fs_list"));
        req.set("name", Json.ofString(name));
        req.set("path", Json.ofString(path));
        return client.call(req).getArr("entries");
    }

    /** Stats a guest path. */
    Json fsStat(String path) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("fs_stat"));
        req.set("name", Json.ofString(name));
        req.set("path", Json.ofString(path));
        return client.call(req);
    }

    /** Reports whether a guest path exists. */
    boolean fsExists(String path) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("fs_exists"));
        req.set("name", Json.ofString(name));
        req.set("path", Json.ofString(path));
        return client.call(req).getBool("exists");
    }

    /** Creates a guest directory. */
    void fsMkdir(String path, boolean recursive) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("fs_mkdir"));
        req.set("name", Json.ofString(name));
        req.set("path", Json.ofString(path));
        req.set("recursive", Json.ofBool(recursive));
        client.call(req);
    }

    /** Removes a guest file. */
    void fsRemove(String path) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("fs_remove"));
        req.set("name", Json.ofString(name));
        req.set("path", Json.ofString(path));
        client.call(req);
    }

    /** Removes a guest directory. */
    void fsRemoveDir(String path, boolean recursive) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("fs_remove_dir"));
        req.set("name", Json.ofString(name));
        req.set("path", Json.ofString(path));
        req.set("recursive", Json.ofBool(recursive));
        client.call(req);
    }

    /** Copies a file inside the guest. */
    void fsCopy(String from, String to) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("fs_copy"));
        req.set("name", Json.ofString(name));
        req.set("from", Json.ofString(from));
        req.set("to", Json.ofString(to));
        client.call(req);
    }

    /** Renames a file inside the guest. */
    void fsRename(String from, String to) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("fs_rename"));
        req.set("name", Json.ofString(name));
        req.set("from", Json.ofString(from));
        req.set("to", Json.ofString(to));
        client.call(req);
    }

    /** Copies a host file into the guest. */
    void fsCopyFromHost(String hostPath, String guestPath) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("fs_copy_from_host"));
        req.set("name", Json.ofString(name));
        req.set("host_path", Json.ofString(hostPath));
        req.set("guest_path", Json.ofString(guestPath));
        client.call(req);
    }

    /** Copies a guest file to the host. */
    void fsCopyToHost(String guestPath, String hostPath) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("fs_copy_to_host"));
        req.set("name", Json.ofString(name));
        req.set("host_path", Json.ofString(hostPath));
        req.set("guest_path", Json.ofString(guestPath));
        client.call(req);
    }

    /** Creates a named volume. */
    Json volumeCreate(String volumeName, String dir) throws IOException, NanosbError {
        Json vol = Json.object();
        vol.set("name", Json.ofString(volumeName));
        if (dir != null && !dir.isEmpty()) {
            vol.set("dir", Json.ofString(dir));
        }
        Json req = Json.object();
        req.set("type", Json.ofString("volume_create"));
        req.set("name", Json.ofString(name));
        req.set("volume", vol);
        return client.call(req);
    }

    /** Lists the sandbox's volumes. */
    List<Json> volumeList() throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("volume_list"));
        req.set("name", Json.ofString(name));
        return client.call(req).getArr("volumes");
    }

    /** Fetches one volume's info. */
    Json volumeGet(String volume) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("volume_get"));
        req.set("name", Json.ofString(name));
        req.set("volume", Json.ofString(volume));
        return client.call(req);
    }

    /** Removes a named volume. */
    void volumeRemove(String volume) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("volume_remove"));
        req.set("name", Json.ofString(name));
        req.set("volume", Json.ofString(volume));
        client.call(req);
    }

    /** Mounts a volume into the running sandbox. */
    void mountAdd(Json mount) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("mount_add"));
        req.set("name", Json.ofString(name));
        req.set("mount", mount);
        client.call(req);
    }

    /** Sets a named secret. */
    void secretSet(String key, String value) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("secret_set"));
        req.set("name", Json.ofString(name));
        req.set("key", Json.ofString(key));
        req.set("value", Json.ofString(value));
        client.call(req);
    }

    /** Lists the sandbox's secrets (values redacted). */
    List<Json> secretList() throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("secret_list"));
        req.set("name", Json.ofString(name));
        return client.call(req).getArr("secrets");
    }

    /** Removes a named secret. */
    void secretRemove(String key) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("secret_remove"));
        req.set("name", Json.ofString(name));
        req.set("key", Json.ofString(key));
        client.call(req);
    }

    /** Creates a snapshot of the sandbox. */
    Json snapshotCreate(String dest) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("snapshot_create"));
        req.set("name", Json.ofString(name));
        if (dest != null && !dest.isEmpty()) {
            req.set("dest", Json.ofString(dest));
        }
        req.set("include_memory", Json.ofBool(false));
        return client.call(req);
    }

    /** Restores a sandbox from a snapshot. */
    void snapshotRestore(String snapshot, String snapshotName) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("snapshot_restore"));
        req.set("snapshot", Json.ofString(snapshot));
        req.set("name", Json.ofString(snapshotName));
        client.call(req);
    }

    /** Forks a new sandbox from a snapshot. */
    void snapshotFork(String snapshot, String snapshotName) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("snapshot_fork"));
        req.set("snapshot", Json.ofString(snapshot));
        req.set("name", Json.ofString(snapshotName));
        client.call(req);
    }

    /** Removes a snapshot. */
    void snapshotRemove(String snapshot) throws IOException, NanosbError {
        Json req = Json.object();
        req.set("type", Json.ofString("snapshot_remove"));
        req.set("snapshot", Json.ofString(snapshot));
        client.call(req);
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