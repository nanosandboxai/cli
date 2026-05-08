pub mod tui;

/// Collect secrets from the SecretSource configuration.
/// Returns a SecretPayload ready for encryption.
pub fn collect_secrets(
    secrets_config: &sandbox::SecretSource,
    config_dir: &std::path::Path,
) -> anyhow::Result<sandbox::secrets::payload::SecretPayload> {
    use tracing::{info, warn};

    let mut payload = sandbox::secrets::payload::SecretPayload::new();

    // 1. Load from SOPS-encrypted file if specified
    if let Some(ref file) = secrets_config.file {
        let file_path = std::path::Path::new(file);
        match sandbox::secrets::sops::decrypt_sops_file(file_path, config_dir) {
            Ok(secrets) => {
                for (key, value) in secrets {
                    payload.add_secret(key, value);
                }
                info!("Loaded {} secrets from SOPS file: {}", payload.secrets.len(), file);
            }
            Err(e) => {
                return Err(anyhow::anyhow!("Failed to decrypt SOPS file '{}': {}", file, e));
            }
        }
    }

    // 2. Read explicit keys from host environment (without set_var!)
    for key in &secrets_config.keys {
        match std::env::var(key) {
            Ok(value) => {
                payload.add_secret(key.clone(), value);
            }
            Err(_) => {
                warn!("Secret key '{}' not found in host environment", key);
            }
        }
    }

    Ok(payload)
}
