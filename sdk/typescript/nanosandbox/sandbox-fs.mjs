// sandbox-fs.mjs — filesystem, storage, secrets, and snapshot verbs for
// `Sandbox`. Attached to `Sandbox.prototype` so the class surface stays
// complete while each file stays small.
import { homedir } from "node:os";
import { join } from "node:path";
import { Conn, NanosbError, b64, unb64 } from "./conn.mjs";
import { Sandbox } from "./sandbox.mjs";

Object.assign(Sandbox.prototype, {
  // ── filesystem ───────────────────────────────────────────────────────
  async fsRead(path, offset, length) {
    const req = { type: "fs_read", name: this._name, path };
    if (offset !== undefined && offset !== null) req.offset = offset;
    if (length !== undefined && length !== null) req.length = length;
    return unb64((await this._client._call(req)).data_base64);
  },

  async fsReadRange(path, offset, length) {
    return unb64(
      (await this._client._call({ type: "fs_read", name: this._name, path, offset, length }))
        .data_base64,
    );
  },

  async fsReadStream(path, chunkSize, onChunk) {
    chunkSize = Math.max(chunkSize, 1);
    let offset = 0;
    while (true) {
      const chunk = await this.fsReadRange(path, offset, chunkSize);
      if (chunk.length === 0) break;
      onChunk(chunk);
      if (chunk.length < chunkSize) break;
      offset += chunk.length;
    }
  },

  async fsWriteStream(path, data, chunkSize) {
    const conn = new Conn(this._client._socket);
    try {
      await conn.open();
      conn.send({ type: "fs_write_stream", name: this._name, path });
      const ack = await conn.recv();
      if (ack.type === "error") {
        throw new NanosbError(ack.code ?? "internal", ack.message ?? "");
      }
      chunkSize = Math.max(chunkSize, 1);
      let chunks = [];
      for (let i = 0; i < data.length; i += chunkSize) {
        chunks.push(data.subarray(i, i + chunkSize));
      }
      if (chunks.length === 0) chunks = [Buffer.alloc(0)];
      for (let i = 0; i < chunks.length; i++) {
        await conn.call({
          type: "fs_data",
          data_base64: b64(chunks[i]),
          eof: i === chunks.length - 1,
        });
      }
    } finally {
      conn.close();
    }
  },

  async fsReadToString(path) {
    return (await this._client._call({ type: "fs_read_to_string", name: this._name, path }))
      .content;
  },

  async fsWrite(path, data, append = false) {
    await this._client._call({
      type: "fs_write",
      name: this._name,
      path,
      data_base64: b64(data),
      append,
    });
  },

  async fsList(path) {
    return (await this._client._call({ type: "fs_list", name: this._name, path })).entries;
  },

  async fsStat(path) {
    return this._client._call({ type: "fs_stat", name: this._name, path });
  },

  async fsExists(path) {
    return (await this._client._call({ type: "fs_exists", name: this._name, path })).exists;
  },

  async fsMkdir(path, recursive = false) {
    await this._client._call({ type: "fs_mkdir", name: this._name, path, recursive });
  },

  async fsRemove(path) {
    await this._client._call({ type: "fs_remove", name: this._name, path });
  },

  async fsRemoveDir(path, recursive = false) {
    await this._client._call({ type: "fs_remove_dir", name: this._name, path, recursive });
  },

  async fsCopy(src, dst) {
    await this._client._call({ type: "fs_copy", name: this._name, from: src, to: dst });
  },

  async fsRename(src, dst) {
    await this._client._call({ type: "fs_rename", name: this._name, from: src, to: dst });
  },

  async fsCopyFromHost(hostPath, guestPath) {
    await this._client._call({
      type: "fs_copy_from_host",
      name: this._name,
      host_path: hostPath,
      guest_path: guestPath,
    });
  },

  async fsCopyToHost(guestPath, hostPath) {
    await this._client._call({
      type: "fs_copy_to_host",
      name: this._name,
      host_path: hostPath,
      guest_path: guestPath,
    });
  },

  // ── storage / secrets / snapshots ────────────────────────────────────
  async volumeCreate(name, dir) {
    return this._client._call({
      type: "volume_create",
      name: this._name,
      volume: { name, dir },
    });
  },

  async volumeList() {
    return (await this._client._call({ type: "volume_list", name: this._name })).volumes;
  },

  async volumeGet(volume) {
    return this._client._call({ type: "volume_get", name: this._name, volume });
  },

  async volumeRemove(volume) {
    await this._client._call({ type: "volume_remove", name: this._name, volume });
  },

  async volumeFs(name) {
    const info = await this.volumeGet(name);
    if (info.dir) return info.dir;
    const home = process.env.NANOSB_HOME || join(homedir(), ".nanosandbox");
    return join(home, "volumes", name);
  },

  async mountAdd(mount) {
    await this._client._call({ type: "mount_add", name: this._name, mount });
  },

  async secretSet(key, value) {
    await this._client._call({ type: "secret_set", name: this._name, key, value });
  },

  async secretList() {
    return (await this._client._call({ type: "secret_list", name: this._name })).secrets;
  },

  async secretRemove(key) {
    await this._client._call({ type: "secret_remove", name: this._name, key });
  },

  async snapshotCreate(dest) {
    return this._client._call({
      type: "snapshot_create",
      name: this._name,
      dest,
      include_memory: false,
    });
  },

  async snapshotRestore(snapshot, name) {
    await this._client._call({ type: "snapshot_restore", snapshot, name });
  },

  async snapshotFork(snapshot, name) {
    await this._client._call({ type: "snapshot_fork", snapshot, name });
  },

  async snapshotRemove(snapshot) {
    await this._client._call({ type: "snapshot_remove", snapshot });
  },
});