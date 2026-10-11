//! Shared protocol types.
//!
//! These are the language-neutral types that cross the wire between the helper
//! and every SDK. They intentionally do **not** depend on the runtime crate so
//! that `nanosb-protocol` stays a leaf dependency.

use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};

/// Sandbox lifecycle state as reported by the helper.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SandboxState {
    Starting,
    Running,
    Stopped,
    Error,
}

/// A summarised view of a sandbox (`get` / `list`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SandboxInfo {
    pub name: String,
    pub state: SandboxState,
    pub image: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pid: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub exit_code: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub started_at: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub config_hash: Option<String>,
    /// Lightweight handle mode: read-only handles are not backed by a live VM.
    #[serde(default)]
    pub detached: bool,
    /// Ephemeral sandboxes are removed automatically when they stop.
    #[serde(default)]
    pub ephemeral: bool,
    #[serde(default)]
    pub labels: HashMap<String, String>,
}

/// Result of a buffered command execution.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ExecResult {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
    #[serde(default)]
    pub duration_ms: u64,
}

/// Which output stream a chunk came from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Stream {
    Stdout,
    Stderr,
}

/// A single entry returned by `fs.list`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FsEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    #[serde(default)]
    pub is_symlink: bool,
    #[serde(default)]
    pub size: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mode: Option<u32>,
}

/// Metadata returned by `fs.stat`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FsStat {
    pub path: String,
    pub is_dir: bool,
    #[serde(default)]
    pub is_symlink: bool,
    #[serde(default)]
    pub size: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mode: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub modified_ms: Option<u64>,
}

/// Resource usage snapshot returned by `metrics`.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Metrics {
    #[serde(default)]
    pub cpu_percent: f64,
    #[serde(default)]
    pub memory_used_bytes: u64,
    #[serde(default)]
    pub memory_total_bytes: u64,
    #[serde(default)]
    pub disk_used_bytes: u64,
    #[serde(default)]
    pub disk_total_bytes: u64,
    #[serde(default)]
    pub net_rx_bytes: u64,
    #[serde(default)]
    pub net_tx_bytes: u64,
    #[serde(default)]
    pub timestamp_ms: u64,
}

/// A structured log line returned by `logs`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LogLine {
    /// Monotonic cursor the client passes back to resume after this line.
    pub cursor: u64,
    #[serde(default)]
    pub timestamp_ms: u64,
    pub source: LogSource,
    pub data: String,
}

/// Origin of a log line.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LogSource {
    Stdout,
    Stderr,
    Pty,
    System,
}

/// Mount specification in a create request.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MountSpec {
    /// Host path (bind / virtiofs) or image-backed volume name.
    pub host_path: String,
    /// Mount point inside the guest.
    pub guest_path: String,
    #[serde(default)]
    pub readonly: bool,
    #[serde(default)]
    pub mount_type: MountType,
    /// Guest file mount (host path is a file, not a directory).
    #[serde(default)]
    pub file: bool,
    /// tmpfs mount (host_path ignored).
    #[serde(default)]
    pub tmpfs: bool,
    /// Disk-image backed volume (`raw`/`qcow2`/`vmdk`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub disk_image: Option<String>,
    /// Mount options such as `noexec`, `nosuid`, `nodev`.
    #[serde(default)]
    pub options: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub uid: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gid: Option<u32>,
}

impl MountSpec {
    pub fn bind(host: impl Into<String>, guest: impl Into<String>) -> Self {
        Self {
            host_path: host.into(),
            guest_path: guest.into(),
            readonly: false,
            mount_type: MountType::Bind,
            file: false,
            tmpfs: false,
            disk_image: None,
            options: Vec::new(),
            uid: None,
            gid: None,
        }
    }

    pub fn virtiofs(host: impl Into<String>, guest: impl Into<String>) -> Self {
        Self {
            mount_type: MountType::Virtiofs,
            ..Self::bind(host, guest)
        }
    }
}

/// Backing type for a mount.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MountType {
    #[default]
    Bind,
    Virtiofs,
    Tmpfs,
}

/// An inbound published port (WS5 config surface).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PortPublish {
    pub host_port: u16,
    pub container_port: u16,
    #[serde(default = "default_protocol_str")]
    pub protocol: String,
    /// Explicit host bind address; loopback by default.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bind_address: Option<String>,
}

fn default_protocol_str() -> String {
    "tcp".to_string()
}

impl PortPublish {
    pub fn tcp(host: u16, container: u16) -> Self {
        Self {
            host_port: host,
            container_port: container,
            protocol: "tcp".to_string(),
            bind_address: None,
        }
    }

    pub fn udp(host: u16, container: u16) -> Self {
        Self {
            protocol: "udp".to_string(),
            ..Self::tcp(host, container)
        }
    }
}

/// Networking config surface (WS5). The enforcement engine is Epic 3; here we
/// only carry the configuration through the protocol.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct NetworkSpec {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scope: Option<String>,
    #[serde(default)]
    pub publish: Vec<PortPublish>,
    #[serde(default)]
    pub dns: Vec<String>,
    #[serde(default)]
    pub dns_zones: HashMap<String, String>,
    /// Opaque policy-config passthrough (validated by Epic 3).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub policy: Option<serde_json::Value>,
}

fn default_true() -> bool {
    true
}

/// A POSIX resource limit applied to executions.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Rlimit {
    pub resource: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub soft: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hard: Option<u64>,
}

/// Image pull policy.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PullPolicy {
    /// Always pull (current behaviour).
    #[default]
    Always,
    /// Pull only if not present in the local cache.
    Missing,
    /// Never pull; fail if the image is not cached.
    Never,
}

/// A named volume backed by a host directory.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct VolumeSpec {
    pub name: String,
    /// Host directory backing the volume (`dir`-backed).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dir: Option<String>,
    /// Disk-image volume (`raw`/`qcow2`/`vmdk`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub disk_image: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fstype: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub quota_bytes: Option<u64>,
}

/// A resolved volume.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct VolumeInfo {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dir: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub disk_image: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fstype: Option<String>,
    #[serde(default)]
    pub used_bytes: u64,
}

/// A named secret entry. Values are never returned (`value` is always empty in
/// responses) and never persisted to disk.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SecretEntry {
    pub key: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
}

/// Metadata for a snapshot of a sandbox.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SnapshotInfo {
    pub id: String,
    pub sandbox: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image: Option<String>,
    /// Path to the snapshot on the host.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    /// Optional integrity hash of the snapshot manifest.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hash: Option<String>,
    #[serde(default)]
    pub created_at_ms: u64,
    /// Whether memory/process state was captured (currently always false).
    #[serde(default)]
    pub includes_memory: bool,
}

/// A modification request for a live sandbox.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ModifySpec {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub idle_timeout_secs: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_duration_secs: Option<u64>,
    #[serde(default)]
    pub labels: HashMap<String, String>,
}

/// A full sandbox creation specification.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SandboxSpec {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    pub image: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cpus: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub memory_mb: Option<u32>,
    #[serde(default)]
    pub env: HashMap<String, String>,
    #[serde(default)]
    pub mounts: Vec<MountSpec>,
    #[serde(default)]
    pub network: NetworkSpec,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workdir: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timeout_secs: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub user: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub home: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub command: Option<String>,
    #[serde(default)]
    pub command_args: Vec<String>,
    #[serde(default)]
    pub rlimits: Vec<Rlimit>,
    #[serde(default)]
    pub labels: HashMap<String, String>,
    #[serde(default)]
    pub ephemeral: bool,
    #[serde(default)]
    pub pull_policy: PullPolicy,
    /// Named scripts materialised at `/.nanosb/scripts/<name>`.
    #[serde(default)]
    pub scripts: HashMap<String, String>,
    /// Start detached (helper owns the lifecycle).
    #[serde(default = "default_true")]
    pub detached: bool,
    /// Replace an existing sandbox of the same name.
    #[serde(default)]
    pub replace: bool,
    /// Guest hostname override.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hostname: Option<String>,
    /// Env keys sourced from the secret store (`env key` -> `secret key`).
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub secret_env: BTreeMap<String, String>,
}

impl SandboxSpec {
    pub fn new(image: impl Into<String>) -> Self {
        Self {
            name: None,
            image: image.into(),
            cpus: None,
            memory_mb: None,
            env: HashMap::new(),
            mounts: Vec::new(),
            network: NetworkSpec::default(),
            workdir: None,
            timeout_secs: None,
            user: None,
            home: None,
            command: None,
            command_args: Vec::new(),
            rlimits: Vec::new(),
            labels: HashMap::new(),
            ephemeral: false,
            pull_policy: PullPolicy::default(),
            scripts: HashMap::new(),
            detached: true,
            replace: false,
            hostname: None,
            secret_env: BTreeMap::new(),
        }
    }
}

/// One paginated page of sandbox handles.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct SandboxList {
    pub sandboxes: Vec<SandboxInfo>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub next_cursor: Option<String>,
}

/// A single decoded guest event, as re-emitted by the helper over NDJSON.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum GuestEvent {
    Started { pid: u32 },
    Stdout { data: String },
    Stderr { data: String },
    Exit { code: i32 },
    Error { message: String },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sandbox_spec_new_fields_roundtrip() {
        let mut spec = SandboxSpec::new("alpine");
        spec.hostname = Some("box".into());
        spec.secret_env.insert("API_KEY".into(), "api-key".into());
        let s = serde_json::to_string(&spec).unwrap();
        let back: SandboxSpec = serde_json::from_str(&s).unwrap();
        assert_eq!(back.hostname.as_deref(), Some("box"));
        assert_eq!(back.secret_env.get("API_KEY").map(String::as_str), Some("api-key"));
    }

    #[test]
    fn sandbox_spec_legacy_json_still_parses() {
        // A create frame written before the additive fields must still decode.
        let legacy = r#"{"name":"a","image":"alpine","detached":true,"replace":false}"#;
        let spec: SandboxSpec = serde_json::from_str(legacy).unwrap();
        assert_eq!(spec.hostname, None);
        assert!(spec.secret_env.is_empty());
    }
}
