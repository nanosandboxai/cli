//! Volume registry: named, dir-backed volumes under `$NANOSB_HOME/volumes`.
//!
//! Backing decision (see `docs/decisions/volume-backings.md`): only dir-backed
//! volumes ship in this build. Disk-image volumes (`raw`/`qcow2`/`vmdk`) and
//! quota are deferred — the libkrun attach path has no block-device API and
//! APFS has no per-directory quota. Unsupported backings return a typed
//! [`VolumeError`] that the verb boundary maps to the protocol `unsupported`
//! code — never a half-created volume.

use std::path::{Path, PathBuf};

use nanosb_protocol::{VolumeInfo, VolumeSpec};

/// Default size of an owned raw disk-image volume when no quota is given.
const DEFAULT_DISK_IMAGE_BYTES: u64 = 64 * 1024 * 1024;

/// Root directory for volumes: `$NANOSB_HOME/volumes` (default
/// `~/.nanosandbox/volumes`).
pub fn volumes_root() -> PathBuf {
    if let Ok(dir) = std::env::var("NANOSB_HOME") {
        return PathBuf::from(dir).join("volumes");
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    PathBuf::from(home).join(".nanosandbox").join("volumes")
}

/// Typed volume error, mapped to a protocol `ErrorCode` at the verb boundary.
#[derive(Debug)]
pub enum VolumeError {
    NotFound(String),
    AlreadyExists(String),
    Invalid(String),
    Unsupported(String),
    Io(std::io::Error),
}

impl std::fmt::Display for VolumeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            VolumeError::NotFound(name) => write!(f, "volume '{name}' not found"),
            VolumeError::AlreadyExists(name) => write!(f, "volume '{name}' already exists"),
            VolumeError::Invalid(msg) => write!(f, "invalid volume: {msg}"),
            VolumeError::Unsupported(msg) => write!(f, "unsupported volume backing: {msg}"),
            VolumeError::Io(e) => write!(f, "volume io error: {e}"),
        }
    }
}

impl std::error::Error for VolumeError {}

impl VolumeError {
    /// Map to the protocol error the verb boundary should emit.
    pub fn to_protocol(&self) -> nanosb_protocol::ProtocolError {
        match self {
            VolumeError::NotFound(name) => {
                nanosb_protocol::ProtocolError::not_found(format!("volume '{name}' not found"))
            }
            VolumeError::AlreadyExists(name) => nanosb_protocol::ProtocolError::invalid_state(
                format!("volume '{name}' already exists"),
            ),
            VolumeError::Invalid(msg) => nanosb_protocol::ProtocolError::bad_request(msg.clone()),
            VolumeError::Unsupported(msg) => {
                nanosb_protocol::ProtocolError::unsupported(msg.clone())
            }
            VolumeError::Io(e) => nanosb_protocol::ProtocolError::io(e.to_string()),
        }
    }
}

/// Named, dir-backed volume registry.
///
/// Layout under the root:
///
/// ```text
/// volumes/<name>/volume.json   # metadata: {"dir": "<backing dir>"}
/// volumes/<name>/data/         # backing dir when the spec did not pin one
/// ```
///
/// A volume pinned to an external host dir (`VolumeSpec.dir`) records that dir
/// in `volume.json`; `remove` deletes only the marker, never the external dir
/// (the registry does not own it).
pub struct VolumeRegistry {
    root: PathBuf,
}

impl VolumeRegistry {
    pub fn new() -> Self {
        Self::with_root(volumes_root())
    }

    pub fn with_root(root: PathBuf) -> Self {
        Self { root }
    }

    /// The registry root directory.
    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Create a volume. Only dir-backed volumes are supported; disk-image and
    /// quota requests return [`VolumeError::Unsupported`].
    pub fn create(&self, spec: &VolumeSpec) -> Result<VolumeInfo, VolumeError> {
        let name = validate_name(&spec.name)?;
        let marker = self.root.join(&name);
        if marker.exists() {
            return Err(VolumeError::AlreadyExists(name));
        }
        if let Some(format) = &spec.disk_image {
            return self.create_disk_image(spec, &name, &marker, format);
        }
        let backing = match &spec.dir {
            Some(dir) => {
                let p = PathBuf::from(dir);
                if p.exists() && !p.is_dir() {
                    return Err(VolumeError::Invalid(format!(
                        "backing path '{}' exists and is not a directory",
                        p.display()
                    )));
                }
                std::fs::create_dir_all(&p).map_err(VolumeError::Io)?;
                p
            }
            None => {
                let p = marker.join("data");
                std::fs::create_dir_all(&p).map_err(VolumeError::Io)?;
                p
            }
        };
        std::fs::create_dir_all(&marker).map_err(VolumeError::Io)?;
        let meta = serde_json::json!({
            "dir": backing.to_string_lossy(),
            "quota_bytes": spec.quota_bytes,
        });
        std::fs::write(
            marker.join("volume.json"),
            serde_json::to_string_pretty(&meta).unwrap_or_default(),
        )
        .map_err(VolumeError::Io)?;
        Ok(VolumeInfo {
            name,
            dir: Some(backing.to_string_lossy().to_string()),
            disk_image: None,
            fstype: None,
            quota_bytes: spec.quota_bytes,
            used_bytes: dir_size(&backing),
        })
    }

    fn create_disk_image(
        &self,
        spec: &VolumeSpec,
        name: &str,
        marker: &Path,
        format: &str,
    ) -> Result<VolumeInfo, VolumeError> {
        let format = format.to_ascii_lowercase();
        if !matches!(format.as_str(), "raw" | "qcow2" | "vmdk") {
            return Err(VolumeError::Unsupported(format!(
                "unknown disk-image format '{format}'"
            )));
        }
        let extension = match format.as_str() {
            "qcow2" => "qcow2",
            "vmdk" => "vmdk",
            _ => "raw",
        };
        std::fs::create_dir_all(marker).map_err(VolumeError::Io)?;
        let backing = match &spec.dir {
            Some(dir) => {
                let p = PathBuf::from(dir);
                if !p.is_file() {
                    return Err(VolumeError::Invalid(format!(
                        "disk-image backing '{}' must be an existing file",
                        p.display()
                    )));
                }
                p
            }
            None => {
                if format != "raw" {
                    return Err(VolumeError::Unsupported(format!(
                        "'{format}' volumes require a pre-built image (set VolumeSpec.dir)"
                    )));
                }
                let owned = marker.join(format!("disk.{extension}"));
                let size = spec.quota_bytes.unwrap_or(DEFAULT_DISK_IMAGE_BYTES);
                let file = std::fs::File::create(&owned).map_err(VolumeError::Io)?;
                file.set_len(size).map_err(VolumeError::Io)?;
                owned
            }
        };
        let used_bytes = std::fs::metadata(&backing).map(|m| m.len()).unwrap_or(0);
        let quota = spec.quota_bytes.or(Some(used_bytes));
        let meta = serde_json::json!({
            "disk_image": backing.to_string_lossy(),
            "format": format,
            "fstype": spec.fstype,
            "quota_bytes": quota,
        });
        std::fs::write(
            marker.join("volume.json"),
            serde_json::to_string_pretty(&meta).unwrap_or_default(),
        )
        .map_err(VolumeError::Io)?;
        Ok(VolumeInfo {
            name: name.to_string(),
            dir: None,
            disk_image: Some(backing.to_string_lossy().to_string()),
            fstype: spec.fstype.clone(),
            quota_bytes: quota,
            used_bytes,
        })
    }

    /// List all volumes, sorted by name.
    pub fn list(&self) -> Vec<VolumeInfo> {
        let mut out = Vec::new();
        if let Ok(entries) = std::fs::read_dir(&self.root) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                if let Ok(info) = self.get(&name) {
                    out.push(info);
                }
            }
        }
        out.sort_by(|a, b| a.name.cmp(&b.name));
        out
    }

    /// Get a volume by name.
    pub fn get(&self, name: &str) -> Result<VolumeInfo, VolumeError> {
        let name = validate_name(name)?;
        let marker = self.root.join(&name);
        let meta: serde_json::Value = std::fs::read_to_string(marker.join("volume.json"))
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .ok_or_else(|| VolumeError::NotFound(name.clone()))?;
        let quota_bytes = meta.get("quota_bytes").and_then(|v| v.as_u64());
        if let Some(img) = meta.get("disk_image").and_then(|v| v.as_str()) {
            return Ok(VolumeInfo {
                name,
                dir: None,
                disk_image: Some(img.to_string()),
                fstype: meta
                    .get("fstype")
                    .and_then(|v| v.as_str())
                    .map(String::from),
                quota_bytes,
                used_bytes: std::fs::metadata(img).map(|m| m.len()).unwrap_or(0),
            });
        }
        let dir = meta
            .get("dir")
            .and_then(|v| v.as_str())
            .map(String::from)
            .ok_or_else(|| VolumeError::NotFound(name.clone()))?;
        Ok(VolumeInfo {
            name,
            dir: Some(dir.clone()),
            disk_image: None,
            fstype: None,
            quota_bytes,
            used_bytes: dir_size(Path::new(&dir)),
        })
    }

    /// Resolve a volume name to its host backing directory.
    pub fn resolve(&self, name: &str) -> Result<PathBuf, VolumeError> {
        self.get(name)
            .map(|info| PathBuf::from(info.dir.unwrap_or_default()))
    }

    /// Remove a volume. External backing dirs (pinned via `spec.dir`) are not
    /// deleted — the registry only owns the marker under its root.
    pub fn remove(&self, name: &str) -> Result<(), VolumeError> {
        let name = validate_name(name)?;
        let marker = self.root.join(&name);
        if !marker.exists() {
            return Err(VolumeError::NotFound(name));
        }
        std::fs::remove_dir_all(&marker).map_err(VolumeError::Io)
    }
}

impl Default for VolumeRegistry {
    fn default() -> Self {
        Self::new()
    }
}

fn validate_name(name: &str) -> Result<String, VolumeError> {
    let name = name.trim();
    if name.is_empty() {
        return Err(VolumeError::Invalid("volume name is required".to_string()));
    }
    if name == "."
        || name == ".."
        || name.contains('/')
        || name.contains('\\')
        || name.contains('\0')
    {
        return Err(VolumeError::Invalid(format!(
            "invalid volume name '{name}'"
        )));
    }
    Ok(name.to_string())
}

fn dir_size(path: &Path) -> u64 {
    let mut total = 0;
    if let Ok(entries) = std::fs::read_dir(path) {
        for entry in entries.flatten() {
            let p = entry.path();
            if let Ok(meta) = entry.metadata() {
                if meta.is_dir() {
                    total += dir_size(&p);
                } else {
                    total += meta.len();
                }
            }
        }
    }
    total
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_registry() -> (tempfile::TempDir, VolumeRegistry) {
        let dir = tempfile::tempdir().unwrap();
        let reg = VolumeRegistry::with_root(dir.path().join("volumes"));
        (dir, reg)
    }

    fn spec(name: &str) -> VolumeSpec {
        VolumeSpec {
            name: name.to_string(),
            dir: None,
            disk_image: None,
            fstype: None,
            quota_bytes: None,
        }
    }

    #[test]
    fn create_dir_backed_volume_materializes_data_dir() {
        let (_tmp, reg) = temp_registry();
        let info = reg.create(&spec("data")).unwrap();
        assert_eq!(info.name, "data");
        assert_eq!(info.disk_image, None);
        let dir = PathBuf::from(info.dir.unwrap());
        assert!(dir.is_dir());
        assert!(reg.root().join("data").join("volume.json").is_file());
    }

    #[test]
    fn create_with_external_dir_records_backing() {
        let (_tmp, reg) = temp_registry();
        let external = std::env::temp_dir().join(format!("nsb-vol-ext-{}", std::process::id()));
        let mut s = spec("ext");
        s.dir = Some(external.to_string_lossy().to_string());
        let info = reg.create(&s).unwrap();
        assert_eq!(
            info.dir.as_deref(),
            Some(external.to_string_lossy().as_ref())
        );
        assert!(external.is_dir());
        // get() resolves the same backing
        assert_eq!(
            reg.get("ext").unwrap().dir.as_deref(),
            Some(external.to_string_lossy().as_ref())
        );
        let _ = std::fs::remove_dir_all(&external);
    }

    #[test]
    fn create_disk_image_is_unsupported() {
        let (_tmp, reg) = temp_registry();
        let mut s = spec("img");
        s.disk_image = Some("qcow2".to_string());
        let err = reg.create(&s).unwrap_err();
        assert!(matches!(err, VolumeError::Unsupported(_)), "{err}");
        assert_eq!(
            err.to_protocol().code,
            nanosb_protocol::ErrorCode::Unsupported
        );
    }

    #[test]
    fn create_with_quota_is_recorded() {
        let (_tmp, reg) = temp_registry();
        let mut s = spec("quota");
        s.quota_bytes = Some(1024 * 1024);
        let info = reg.create(&s).unwrap();
        assert_eq!(info.quota_bytes, Some(1024 * 1024));
        assert_eq!(reg.get("quota").unwrap().quota_bytes, Some(1024 * 1024));
    }

    #[test]
    fn create_raw_disk_image_volume_allocates_quota_sized_file() {
        let (_tmp, reg) = temp_registry();
        let mut s = spec("img");
        s.disk_image = Some("raw".to_string());
        s.fstype = Some("ext4".to_string());
        s.quota_bytes = Some(4 * 1024 * 1024);
        let info = reg.create(&s).unwrap();
        assert_eq!(info.fstype.as_deref(), Some("ext4"));
        assert_eq!(info.quota_bytes, Some(4 * 1024 * 1024));
        let path = PathBuf::from(info.disk_image.unwrap());
        assert!(path.is_file());
        assert_eq!(std::fs::metadata(&path).unwrap().len(), 4 * 1024 * 1024);
        reg.remove("img").unwrap();
        assert!(!path.exists());
    }

    #[test]
    fn create_qcow2_without_prebuilt_image_is_unsupported() {
        let (_tmp, reg) = temp_registry();
        let mut s = spec("qcow");
        s.disk_image = Some("qcow2".to_string());
        assert!(matches!(reg.create(&s), Err(VolumeError::Unsupported(_))));
    }

    #[test]
    fn duplicate_create_is_already_exists() {
        let (_tmp, reg) = temp_registry();
        reg.create(&spec("dup")).unwrap();
        let err = reg.create(&spec("dup")).unwrap_err();
        assert!(matches!(err, VolumeError::AlreadyExists(_)), "{err}");
    }

    #[test]
    fn get_missing_is_not_found() {
        let (_tmp, reg) = temp_registry();
        let err = reg.get("nope").unwrap_err();
        assert!(matches!(err, VolumeError::NotFound(_)), "{err}");
        assert_eq!(err.to_protocol().code, nanosb_protocol::ErrorCode::NotFound);
    }

    #[test]
    fn list_sorts_and_remove_roundtrip() {
        let (_tmp, reg) = temp_registry();
        reg.create(&spec("b")).unwrap();
        reg.create(&spec("a")).unwrap();
        let names: Vec<String> = reg.list().iter().map(|v| v.name.clone()).collect();
        assert_eq!(names, vec!["a".to_string(), "b".to_string()]);
        reg.remove("a").unwrap();
        assert!(matches!(reg.get("a"), Err(VolumeError::NotFound(_))));
        assert_eq!(reg.list().len(), 1);
        assert!(matches!(reg.remove("a"), Err(VolumeError::NotFound(_))));
    }

    #[test]
    fn remove_external_backing_keeps_external_dir() {
        let (_tmp, reg) = temp_registry();
        let external = std::env::temp_dir().join(format!("nsb-vol-ext2-{}", std::process::id()));
        let mut s = spec("ext");
        s.dir = Some(external.to_string_lossy().to_string());
        reg.create(&s).unwrap();
        reg.remove("ext").unwrap();
        assert!(external.is_dir(), "external backing must not be deleted");
        let _ = std::fs::remove_dir_all(&external);
    }

    #[test]
    fn invalid_names_rejected() {
        let (_tmp, reg) = temp_registry();
        for bad in ["", "..", ".", "a/b", "a\\b", "a\0b"] {
            let err = reg.create(&spec(bad)).unwrap_err();
            assert!(
                matches!(err, VolumeError::Invalid(_)),
                "name '{bad}': {err}"
            );
        }
    }

    #[test]
    fn used_bytes_counts_backing_contents() {
        let (_tmp, reg) = temp_registry();
        let info = reg.create(&spec("data")).unwrap();
        let dir = PathBuf::from(info.dir.unwrap());
        std::fs::write(dir.join("f.bin"), vec![0u8; 4096]).unwrap();
        assert_eq!(reg.get("data").unwrap().used_bytes, 4096);
    }
}
