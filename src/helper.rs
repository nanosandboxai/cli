//! Helper control plane: materialise a protocol `SandboxSpec` into a running
//! supervisor-managed sandbox. Shared by the `nanosb-runtime` daemon.

use std::collections::HashMap;
use std::path::PathBuf;

use nanosb_protocol::{MountSpec, SandboxSpec};
use runtime::config::{
    ExtraMount, Mount, NetworkConfig, NetworkMode, NetworkScope, PortMapping, RuntimeMode,
    SandboxConfig,
};

use crate::deploy::{self, Origin};
use crate::supervisor::client::SupervisorClient;

/// Typed error for mount conversion. `Unsupported` maps to the protocol
/// `unsupported` code at the verb boundary; the create path downcasts it so a
/// spec with an unsupported backing fails cleanly instead of as `internal`.
#[derive(Debug)]
pub enum MountError {
    Unsupported(String),
}

impl std::fmt::Display for MountError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MountError::Unsupported(msg) => write!(f, "unsupported mount: {msg}"),
        }
    }
}

impl std::error::Error for MountError {}

/// Convert a protocol `MountSpec` into a runtime `Mount`.
///
/// Only dir-backed bind/virtiofs mounts are supported by this build (see
/// `docs/decisions/volume-backings.md`). tmpfs, disk-image, single-file,
/// mount-option, and uid/gid mounts return [`MountError::Unsupported`] — never
/// a half-applied mount.
pub fn mount_spec_to_mount(spec: &MountSpec) -> Result<Mount, MountError> {
    if spec.tmpfs {
        return Err(MountError::Unsupported(
            "tmpfs mounts are not supported by this build".to_string(),
        ));
    }
    if spec.disk_image.is_some() {
        return Err(MountError::Unsupported(
            "disk-image mounts are not supported by this build".to_string(),
        ));
    }
    if spec.file {
        return Err(MountError::Unsupported(
            "single-file mounts are not supported by this build".to_string(),
        ));
    }
    if !spec.options.is_empty() {
        return Err(MountError::Unsupported(
            "mount options (noexec/nosuid/nodev) are not supported by this build".to_string(),
        ));
    }
    if spec.uid.is_some() || spec.gid.is_some() {
        return Err(MountError::Unsupported(
            "mount owner (uid/gid) is not supported by this build".to_string(),
        ));
    }
    let mut mount = match spec.mount_type {
        nanosb_protocol::MountType::Virtiofs => {
            Mount::virtiofs(PathBuf::from(&spec.host_path), &spec.guest_path)
        }
        nanosb_protocol::MountType::Bind => {
            Mount::bind(PathBuf::from(&spec.host_path), &spec.guest_path)
        }
        nanosb_protocol::MountType::Tmpfs => {
            return Err(MountError::Unsupported(
                "tmpfs mounts are not supported by this build".to_string(),
            ))
        }
    };
    mount.readonly = spec.readonly;
    Ok(mount)
}

/// Append a runtime mount to a stopped sandbox's config so it applies on the
/// next boot. Used by `mount_add` for stopped sandboxes — live mounts are not
/// supported by the libkrun attach path (see `docs/decisions/volume-backings.md`).
pub fn persist_mount(sandbox_dir: &std::path::Path, mount: &Mount) -> anyhow::Result<()> {
    let path = sandbox_dir.join("config.json");
    let mut cfg: SandboxConfig = std::fs::read_to_string(&path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default();
    cfg.mounts.push(mount.clone());
    let json = serde_json::to_string_pretty(&cfg)?;
    std::fs::write(&path, json)?;
    Ok(())
}

/// Build a runtime sandbox config from a protocol spec (without spawning).
pub fn spec_to_config(spec: &SandboxSpec) -> anyhow::Result<SandboxConfig> {
    let image = sandbox::normalize_image(&spec.image);
    let mut config = SandboxConfig::builder()
        .name(spec.name.clone().unwrap_or_default())
        .image(&image)
        .cpus(spec.cpus.unwrap_or(2))
        .memory_mb(spec.memory_mb.unwrap_or(4096))
        .timeout_secs(spec.timeout_secs.unwrap_or(3600))
        .runtime_mode(RuntimeMode::Next)
        .build();

    if let Some(w) = &spec.workdir {
        config.workdir = w.clone();
    }
    if let Some(u) = &spec.user {
        config.user = Some(u.clone());
    }
    if let Some(h) = &spec.home {
        config.home = Some(h.clone());
    }
    config.env = spec.env.clone();
    config.labels = spec.labels.clone();
    config.ephemeral = spec.ephemeral;

    for m in &spec.mounts {
        let mount = mount_spec_to_mount(m)?;
        config.mounts.push(mount);
    }

    config.network = NetworkConfig {
        enabled: spec.network.enabled,
        mode: match spec.network.mode.as_deref() {
            Some("none") => NetworkMode::None,
            Some("bridge") => NetworkMode::Bridge,
            Some("tsi") | None => NetworkMode::Tsi,
            Some(other) => anyhow::bail!("unknown network mode '{other}'"),
        },
        scope: match spec.network.scope.as_deref() {
            Some("none") => NetworkScope::None,
            Some("group") => NetworkScope::Group,
            Some("public") => NetworkScope::Public,
            Some("any") | None => NetworkScope::Any,
            Some(other) => anyhow::bail!("unknown network scope '{other}'"),
        },
        port_mappings: spec
            .network
            .publish
            .iter()
            .map(|p| PortMapping {
                host_port: p.host_port,
                container_port: p.container_port,
                protocol: p.protocol.clone(),
                bind_address: p.bind_address.clone(),
            })
            .collect(),
        dns: spec.network.dns.clone(),
        dns_zones: spec.network.dns_zones.clone(),
    };

    if let Some(cmd) = &spec.command {
        config.command = Some(cmd.clone());
        config.command_args = spec.command_args.clone();
    }

    Ok(config)
}

/// Enforce `SandboxSpec.pull_policy` against the local image cache before the
/// supervisor pulls.
///
/// The supervisor always pulls, but `ImageManager::pull` is layer-cache-aware:
/// a fully cached image is not re-downloaded. So `Always` and `Missing` need no
/// gate here (a cached image under `Missing` is effectively a no-op pull), and
/// `Never` errors when the image is absent from the cache.
fn ensure_image_policy(spec: &SandboxSpec) -> anyhow::Result<()> {
    let mgr = runtime::ImageManager::with_default_cache()?;
    ensure_image_policy_with(spec, &mgr)
}

fn ensure_image_policy_with(spec: &SandboxSpec, mgr: &runtime::ImageManager) -> anyhow::Result<()> {
    use nanosb_protocol::PullPolicy;
    match spec.pull_policy {
        PullPolicy::Always | PullPolicy::Missing => Ok(()),
        PullPolicy::Never => {
            let image = sandbox::normalize_image(&spec.image);
            let rt = tokio::runtime::Runtime::new()?;
            let cached = rt.block_on(mgr.exists(&image))?;
            if cached {
                Ok(())
            } else {
                anyhow::bail!("image '{image}' is not cached and pull_policy is 'never'")
            }
        }
    }
}

/// Create, boot, and wait for a sandbox to reach the running state.
pub fn create_sandbox(spec: &SandboxSpec) -> anyhow::Result<()> {
    let name = spec
        .name
        .clone()
        .ok_or_else(|| anyhow::anyhow!("spec.name is required"))?;
    ensure_image_policy(spec)?;
    let mut config = spec_to_config(spec)?;

    let client = SupervisorClient::new(&name);
    let sandbox_dir = client.sandbox_dir().to_path_buf();

    let agent_dir = sandbox_dir.join("agent");
    let guest_path = deploy::stage_exec_agent(&agent_dir)?;
    let exec_sock = sandbox_dir.join("exec.sock");
    let _ = std::fs::remove_file(&exec_sock);
    let extra_mounts = vec![ExtraMount {
        tag: "agent".to_string(),
        host_path: agent_dir.to_string_lossy().to_string(),
        target: "/agent".to_string(),
        readonly: false,
    }];
    config.vsock_socket = Some(exec_sock.to_string_lossy().to_string());
    config.vsock_port = Some(deploy::EXEC_VSOCK_PORT);
    if config.command.is_none() {
        config.command = Some(guest_path);
        config.command_args = vec![deploy::EXEC_VSOCK_PORT.to_string()];
    }

    let extra_mounts_json = serde_json::to_string(&extra_mounts)?;
    let config_json = serde_json::to_string(&config)?;
    let (config_json, boot_env_json) = deploy::extract_boot_env(&config_json)?;
    let origin = Origin::cli(Vec::new(), Vec::new()).to_json();

    deploy::spawn_supervisor(
        &name,
        &config_json,
        &extra_mounts_json,
        &boot_env_json,
        &origin,
        config.timeout_secs,
    )?;

    wait_until_running(&client, 60)?;
    wait_for_exec_channel(&client, 20)?;
    Ok(())
}

fn wait_for_exec_channel(client: &SupervisorClient, timeout_secs: u64) -> anyhow::Result<()> {
    let exec_sock = client.sandbox_dir().join("exec.sock");
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(timeout_secs);
    while !exec_sock.exists() {
        if std::time::Instant::now() >= deadline {
            anyhow::bail!("timed out waiting for the guest exec channel to come up");
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    Ok(())
}

fn wait_until_running(client: &SupervisorClient, timeout_secs: u64) -> anyhow::Result<()> {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(timeout_secs);
    loop {
        if let Some(state) = client.read_state() {
            match state.state {
                crate::supervisor::SandboxState::Running => return Ok(()),
                crate::supervisor::SandboxState::Stopped
                | crate::supervisor::SandboxState::Error => {
                    anyhow::bail!("sandbox failed to start (state: {:?})", state.state);
                }
                crate::supervisor::SandboxState::Starting => {}
            }
        }
        if std::time::Instant::now() >= deadline {
            anyhow::bail!("timed out waiting for sandbox to start");
        }
        std::thread::sleep(std::time::Duration::from_millis(200));
    }
}

/// Default label map helper (kept for SDK parity in future verbs).
pub fn empty_labels() -> HashMap<String, String> {
    HashMap::new()
}

#[cfg(test)]
mod tests {
    use super::*;
    use nanosb_protocol::{PortPublish, PullPolicy};

    fn spec_with_publish(bind_address: Option<&str>) -> SandboxSpec {
        let mut spec = SandboxSpec::new("alpine");
        spec.name = Some("t".to_string());
        spec.network.publish.push(PortPublish {
            host_port: 8080,
            container_port: 80,
            protocol: "tcp".to_string(),
            bind_address: bind_address.map(String::from),
        });
        spec
    }

    #[test]
    fn spec_to_config_threads_bind_address() {
        let spec = spec_with_publish(Some("127.0.0.1"));
        let config = spec_to_config(&spec).unwrap();
        let pm = &config.network.port_mappings[0];
        assert_eq!(pm.host_port, 8080);
        assert_eq!(pm.container_port, 80);
        assert_eq!(pm.protocol, "tcp");
        assert_eq!(pm.bind_address.as_deref(), Some("127.0.0.1"));
    }

    #[test]
    fn spec_to_config_bind_address_none_when_unset() {
        let spec = spec_with_publish(None);
        let config = spec_to_config(&spec).unwrap();
        assert!(config.network.port_mappings[0].bind_address.is_none());
    }

    fn temp_cache() -> (tempfile::TempDir, runtime::ImageManager) {
        let dir = tempfile::tempdir().unwrap();
        let mgr = runtime::ImageManager::new(dir.path().to_path_buf()).unwrap();
        (dir, mgr)
    }

    fn mark_cached(mgr: &runtime::ImageManager, image: &str) {
        let image = sandbox::normalize_image(image);
        let (name, tag) = image.split_once(':').unwrap_or((image.as_str(), "latest"));
        let (registry, repo) = match name.split_once('/') {
            Some((r, rest)) => (r, rest),
            None => ("docker.io", name),
        };
        let path = mgr
            .cache_dir()
            .join("manifests")
            .join(registry.replace('/', "_"))
            .join(repo.replace('/', "_"))
            .join(tag);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, "{}").unwrap();
    }

    #[test]
    fn pull_policy_never_errors_when_image_absent() {
        let (_dir, mgr) = temp_cache();
        let mut spec = SandboxSpec::new("alpine");
        spec.pull_policy = PullPolicy::Never;
        let err = ensure_image_policy_with(&spec, &mgr).unwrap_err();
        assert!(err.to_string().contains("pull_policy is 'never'"), "{err}");
    }

    #[test]
    fn pull_policy_never_ok_when_image_cached() {
        let (_dir, mgr) = temp_cache();
        mark_cached(&mgr, "alpine");
        let mut spec = SandboxSpec::new("alpine");
        spec.pull_policy = PullPolicy::Never;
        ensure_image_policy_with(&spec, &mgr).unwrap();
    }

    #[test]
    fn pull_policy_always_and_missing_never_gate() {
        let (_dir, mgr) = temp_cache();
        let mut spec = SandboxSpec::new("alpine");
        spec.pull_policy = PullPolicy::Always;
        ensure_image_policy_with(&spec, &mgr).unwrap();
        spec.pull_policy = PullPolicy::Missing;
        ensure_image_policy_with(&spec, &mgr).unwrap();
    }

    // ── mount_spec_to_mount (decision-backed conversions) ───────────────

    fn mount_spec(mount_type: nanosb_protocol::MountType) -> MountSpec {
        MountSpec {
            host_path: "/host/data".to_string(),
            guest_path: "/mnt/data".to_string(),
            readonly: false,
            mount_type,
            file: false,
            tmpfs: false,
            disk_image: None,
            options: Vec::new(),
            uid: None,
            gid: None,
        }
    }

    #[test]
    fn bind_spec_converts_to_bind_mount() {
        let m = mount_spec_to_mount(&mount_spec(nanosb_protocol::MountType::Bind)).unwrap();
        assert_eq!(m.mount_type, runtime::config::MountType::Bind);
        assert_eq!(m.host_path, PathBuf::from("/host/data"));
        assert_eq!(m.container_path, "/mnt/data");
        assert!(!m.readonly);
    }

    #[test]
    fn virtiofs_spec_converts_to_virtiofs_mount() {
        let m = mount_spec_to_mount(&mount_spec(nanosb_protocol::MountType::Virtiofs)).unwrap();
        assert_eq!(m.mount_type, runtime::config::MountType::VirtioFs);
    }

    #[test]
    fn readonly_is_threaded_through() {
        let mut s = mount_spec(nanosb_protocol::MountType::Bind);
        s.readonly = true;
        let m = mount_spec_to_mount(&s).unwrap();
        assert!(m.readonly);
    }

    #[test]
    fn tmpfs_spec_is_unsupported() {
        let mut s = mount_spec(nanosb_protocol::MountType::Bind);
        s.tmpfs = true;
        assert!(matches!(
            mount_spec_to_mount(&s),
            Err(MountError::Unsupported(_))
        ));
        let s = mount_spec(nanosb_protocol::MountType::Tmpfs);
        assert!(matches!(
            mount_spec_to_mount(&s),
            Err(MountError::Unsupported(_))
        ));
    }

    #[test]
    fn disk_image_spec_is_unsupported() {
        let mut s = mount_spec(nanosb_protocol::MountType::Bind);
        s.disk_image = Some("qcow2".to_string());
        assert!(matches!(
            mount_spec_to_mount(&s),
            Err(MountError::Unsupported(_))
        ));
    }

    #[test]
    fn file_spec_is_unsupported() {
        let mut s = mount_spec(nanosb_protocol::MountType::Bind);
        s.file = true;
        assert!(matches!(
            mount_spec_to_mount(&s),
            Err(MountError::Unsupported(_))
        ));
    }

    #[test]
    fn options_and_owner_are_unsupported() {
        let mut s = mount_spec(nanosb_protocol::MountType::Bind);
        s.options = vec!["noexec".to_string()];
        assert!(matches!(
            mount_spec_to_mount(&s),
            Err(MountError::Unsupported(_))
        ));
        let mut s = mount_spec(nanosb_protocol::MountType::Bind);
        s.uid = Some(1000);
        assert!(matches!(
            mount_spec_to_mount(&s),
            Err(MountError::Unsupported(_))
        ));
        let mut s = mount_spec(nanosb_protocol::MountType::Bind);
        s.gid = Some(1000);
        assert!(matches!(
            mount_spec_to_mount(&s),
            Err(MountError::Unsupported(_))
        ));
    }

    #[test]
    fn spec_to_config_rejects_unsupported_mount_backing() {
        let mut spec = SandboxSpec::new("alpine");
        let mut m = mount_spec(nanosb_protocol::MountType::Bind);
        m.tmpfs = true;
        spec.mounts.push(m);
        let err = spec_to_config(&spec).unwrap_err();
        assert!(
            err.downcast_ref::<MountError>().is_some(),
            "expected MountError, got {err}"
        );
    }

    #[test]
    fn persist_mount_appends_to_stopped_config() {
        let dir = std::env::temp_dir().join(format!("nsb-persist-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("config.json"),
            r#"{"name":"t","image":"alpine","mounts":[]}"#,
        )
        .unwrap();
        let mount = Mount::bind("/host/data", "/mnt/data");
        persist_mount(&dir, &mount).unwrap();
        let cfg: SandboxConfig =
            serde_json::from_str(&std::fs::read_to_string(dir.join("config.json")).unwrap())
                .unwrap();
        assert_eq!(cfg.mounts.len(), 1);
        assert_eq!(cfg.mounts[0].host_path, PathBuf::from("/host/data"));
        assert_eq!(cfg.mounts[0].container_path, "/mnt/data");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
