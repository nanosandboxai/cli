//! FFI-free deploy helpers shared by the CLI and host-side consumers.

use std::path::{Path, PathBuf};

/// Guest vsock port the exec agent listens on (bridged to a host socket).
pub const EXEC_VSOCK_PORT: u32 = 1024;

/// Host directory holding the cross-compiled guest binaries (exec agent).
///
/// Resolution order: `NANOSB_GUEST_BIN_DIR`, then `$NANOSB_HOME/guest-bin`,
/// then `~/.nanosandbox/guest-bin`.
pub fn guest_bin_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("NANOSB_GUEST_BIN_DIR") {
        return PathBuf::from(dir);
    }
    if let Ok(dir) = std::env::var("NANOSB_HOME") {
        return PathBuf::from(dir).join("guest-bin");
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    PathBuf::from(home).join(".nanosandbox").join("guest-bin")
}

/// Path to the guest exec-agent binary for the host architecture, if staged.
pub fn exec_agent_path() -> Option<PathBuf> {
    let p = guest_bin_dir().join("exec-agent");
    p.exists().then_some(p)
}

/// Stage the exec agent into `dest` for injection into the guest.
///
/// Returns the guest-visible path to run as PID 1.
pub fn stage_exec_agent(dest: &Path) -> anyhow::Result<String> {
    let src = exec_agent_path().ok_or_else(|| {
        anyhow::anyhow!(
            "exec agent not found at {}; build it with:\n  \
             cd guest/crates/exec-agent && \
             RUSTFLAGS=\"-C linker=rust-lld\" cargo build \
             --target aarch64-unknown-linux-musl --release\n  \
             then copy it to {}",
            guest_bin_dir().join("exec-agent").display(),
            guest_bin_dir().display()
        )
    })?;
    std::fs::create_dir_all(dest)?;
    let target = dest.join("exec-agent");
    std::fs::copy(&src, &target)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&target, std::fs::Permissions::from_mode(0o755));
    }
    Ok("/agent/exec-agent".to_string())
}

/// Where a sandbox's env/secrets came from, recorded so `restart` can
/// re-resolve them without persisting any secret values.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, Default)]
pub struct Origin {
    /// `"manifest"` (declared in sandbox.yml) or `"cli"` (`nanosb run` flags).
    pub source: String,
    /// Env **key names** only (never values) to re-resolve on restart.
    #[serde(default)]
    pub env_keys: Vec<String>,
    /// `--env-file` path(s) to re-read on restart.
    #[serde(default)]
    pub env_files: Vec<String>,
    /// Path to the declaring `sandbox.yml`, when `source == "manifest"`.
    #[serde(default)]
    pub manifest_path: Option<String>,
}

impl Origin {
    pub fn cli(env_keys: Vec<String>, env_files: Vec<String>) -> Self {
        Self {
            source: "cli".to_string(),
            env_keys,
            env_files,
            manifest_path: None,
        }
    }

    pub fn manifest(manifest_path: Option<String>, env_keys: Vec<String>) -> Self {
        Self {
            source: "manifest".to_string(),
            env_keys,
            env_files: Vec::new(),
            manifest_path,
        }
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| "{}".to_string())
    }
}

/// Split a serialized sandbox config into (config without env, env JSON object).
///
/// Secrets must not be persisted to disk nor placed on the supervisor command
/// line; the env is delivered separately via the supervisor's process environment.
pub fn extract_boot_env(config_json: &str) -> anyhow::Result<(String, String)> {
    let mut cfg: runtime_config::SandboxConfig = serde_json::from_str(config_json)?;
    let env = std::mem::take(&mut cfg.env);
    Ok((serde_json::to_string(&cfg)?, serde_json::to_string(&env)?))
}
