// builders.mjs — fluent builders for sandbox and volume creation specs.
//
// The builders produce the wire-shaped `SandboxSpec` / `VolumeSpec` objects
// from `crates/protocol/src/types.rs` (snake_case keys). JS methods are
// camelCase; only the emitted spec uses wire keys.

const SPEC_FIELDS = [
  ["name", "name"],
  ["cpus", "cpus"],
  ["memory_mb", "memoryMb"],
  ["workdir", "workdir"],
  ["timeout_secs", "timeoutSecs"],
  ["user", "user"],
  ["home", "home"],
  ["command", "command"],
];

/** Fluent builder for a sandbox creation spec. */
export class SandboxBuilder {
  constructor(image) {
    this.image = image;
    this.name = null;
    this.cpus = null;
    this.memoryMb = null;
    this.env = {};
    this.mounts = [];
    this.network = {};
    this.workdir = null;
    this.timeoutSecs = null;
    this.user = null;
    this.home = null;
    this.command = null;
    this.commandArgs = [];
    this.labels = {};
    this.ephemeral = false;
    this.replace = false;
    this._detached = true;
    this._hostname = null;
    this._secretEnv = {};
  }

  withName(name) {
    this.name = name;
    return this;
  }

  withResources(cpus, memoryMb) {
    this.cpus = cpus;
    this.memoryMb = memoryMb;
    return this;
  }

  withEnv(key, value) {
    this.env[key] = value;
    return this;
  }

  withLabel(key, value) {
    this.labels[key] = value;
    return this;
  }

  mount(hostPath, guestPath, readonly = false) {
    this.mounts.push({
      host_path: hostPath,
      guest_path: guestPath,
      readonly,
      mount_type: "virtiofs",
    });
    return this;
  }

  publishTcp(hostPort, guestPort) {
    this.network.enabled ??= true;
    (this.network.publish ??= []).push({
      host_port: hostPort,
      container_port: guestPort,
      protocol: "tcp",
    });
    return this;
  }

  publishUdp(hostPort, guestPort) {
    this.network.enabled ??= true;
    (this.network.publish ??= []).push({
      host_port: hostPort,
      container_port: guestPort,
      protocol: "udp",
    });
    return this;
  }

  detached(detached) {
    this._detached = detached;
    return this;
  }

  hostname(hostname) {
    this._hostname = hostname;
    return this;
  }

  mountFile(hostPath, guestPath) {
    this.mounts.push({
      host_path: hostPath,
      guest_path: guestPath,
      readonly: false,
      mount_type: "virtiofs",
      file: true,
    });
    return this;
  }

  mountTmpfs(guestPath) {
    this.mounts.push({
      host_path: "",
      guest_path: guestPath,
      readonly: false,
      mount_type: "tmpfs",
      tmpfs: true,
    });
    return this;
  }

  mountOptions(options) {
    if (this.mounts.length) this.mounts[this.mounts.length - 1].options = [...options];
    return this;
  }

  mountOwner(uid, gid) {
    if (this.mounts.length) {
      const mount = this.mounts[this.mounts.length - 1];
      mount.uid = uid;
      mount.gid = gid;
    }
    return this;
  }

  secretEnv(key, secretKey) {
    this._secretEnv[key] = secretKey;
    return this;
  }

  build() {
    const spec = { image: this.image, detached: this._detached };
    for (const [wireKey, field] of SPEC_FIELDS) {
      if (this[field] !== null) spec[wireKey] = this[field];
    }
    if (this._hostname !== null) spec.hostname = this._hostname;
    if (Object.keys(this.env).length) spec.env = this.env;
    if (this.mounts.length) spec.mounts = this.mounts;
    if (Object.keys(this.network).length) spec.network = this.network;
    if (this.commandArgs.length) spec.command_args = this.commandArgs;
    if (Object.keys(this.labels).length) spec.labels = this.labels;
    if (this.ephemeral) spec.ephemeral = true;
    if (this.replace) spec.replace = true;
    if (Object.keys(this._secretEnv).length) spec.secret_env = this._secretEnv;
    return spec;
  }
}

const VOLUME_FIELDS = [
  ["dir", "dir"],
  ["disk_image", "diskImage"],
  ["fstype", "fstype"],
  ["quota_bytes", "quotaBytes"],
];

/** Fluent builder for a volume creation spec. */
export class VolumeBuilder {
  constructor(name) {
    this.name = name;
    this.dir = null;
    this.diskImage = null;
    this.fstype = null;
    this.quotaBytes = null;
  }

  withDir(dir) {
    this.dir = dir;
    return this;
  }

  diskImage(image) {
    this.diskImage = image;
    return this;
  }

  fstype(fstype) {
    this.fstype = fstype;
    return this;
  }

  volumeQuota(bytes) {
    this.quotaBytes = bytes;
    return this;
  }

  build() {
    const spec = { name: this.name };
    for (const [wireKey, field] of VOLUME_FIELDS) {
      if (this[field] !== null) spec[wireKey] = this[field];
    }
    return spec;
  }
}