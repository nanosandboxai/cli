//! Helper control plane: materialise a protocol `SandboxSpec` into a running
//! supervisor-managed sandbox. Shared by the `nanosb-runtime` daemon.

use std::collections::HashMap;
use std::path::PathBuf;

use nanosb_protocol::SandboxSpec;
use runtime::config::{
    ExtraMount, Mount, NetworkConfig, NetworkMode, NetworkScope, PortMapping, RuntimeMode,
    SandboxConfig,
};

use crate::deploy::{self, Origin};
use crate::supervisor::client::SupervisorClient;

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
        if m.tmpfs {
            anyhow::bail!("tmpfs mounts are not supported by this helper build");
        }
        if m.disk_image.is_some() {
            anyhow::bail!("disk-image mounts are not supported by this helper build");
        }
        let mut mount = match m.mount_type {
            nanosb_protocol::MountType::Virtiofs => {
                Mount::virtiofs(PathBuf::from(&m.host_path), &m.guest_path)
            }
            _ => Mount::bind(PathBuf::from(&m.host_path), &m.guest_path),
        };
        mount.readonly = m.readonly;
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

/// Create, boot, and wait for a sandbox to reach the running state.
pub fn create_sandbox(spec: &SandboxSpec) -> anyhow::Result<()> {
    let name = spec
        .name
        .clone()
        .ok_or_else(|| anyhow::anyhow!("spec.name is required"))?;
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
