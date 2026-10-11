//! Live-VM conformance for the protocol client against a real microVM.
//!
//! This is the AC5/AC6/AC9 evidence harness for Epic 1: it builds/spawns the
//! real `nanosb-runtime` helper (`serve`), connects `nanosb-client`, and drives
//! the operations that require a real microVM — lifecycle (create/get/exec/fs/
//! logs/metrics/list/stop/remove), secrets, pause/resume, plus volumes and
//! snapshot create/restore (which are blocked in this build; the exact blocker
//! is asserted so a change in behaviour is caught).
//!
//! Opt-in: requires the `nanosb-runtime` binary, libkrun/gvproxy, and a cached
//! image. Run with:
//!
//!   cargo build -p nanosb-cli --bin nanosb-runtime --no-default-features --features runtime-host
//!   cargo test -p nanosb-client --test live_conformance -- --ignored --nocapture
//!
//! Override the binary with `NANOSB_RUNTIME_BIN` and the image with
//! `NANOSB_TEST_IMAGE` (default `library/alpine:latest`). See
//! `docs/live-verification.md` for the recorded outcome.

use std::path::PathBuf;
use std::process::{Child, Command};
use std::time::{Duration, Instant};

use nanosb_client::{SandboxBuilder, SandboxClient, VolumeBuilder};
use nanosb_protocol::{Capability, SandboxState};

struct Daemon {
    child: Child,
    socket: PathBuf,
    dir: PathBuf,
    name: String,
    sandbox_dir: PathBuf,
}

impl Drop for Daemon {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_dir_all(&self.dir);
        let _ = std::fs::remove_dir_all(&self.sandbox_dir);
    }
}

fn runtime_bin() -> PathBuf {
    if let Ok(p) = std::env::var("NANOSB_RUNTIME_BIN") {
        return PathBuf::from(p);
    }
    let workspace = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../");
    workspace.join("target/debug/nanosb-runtime")
}

fn start_daemon() -> Daemon {
    let dir = std::env::temp_dir().join(format!("nsb-live-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let socket = dir.join("helper.sock");
    let child = Command::new(runtime_bin())
        .arg("serve")
        .arg("--socket")
        .arg(&socket)
        .spawn()
        .expect("spawn nanosb-runtime");
    let deadline = Instant::now() + Duration::from_secs(10);
    while !socket.exists() {
        assert!(Instant::now() < deadline, "helper socket never appeared");
        std::thread::sleep(Duration::from_millis(50));
    }
    let name = format!("sdk-live-{}", std::process::id());
    Daemon {
        child,
        socket,
        dir,
        name: name.clone(),
        sandbox_dir: nanosb_client::sandbox_dir(&name),
    }
}

#[test]
#[ignore = "requires nanosb-runtime + libkrun + a cached image"]
fn live_conformance_smoke() {
    let daemon = start_daemon();
    let client = SandboxClient::connect(&daemon.socket).expect("connect");
    assert!(!client.capabilities().is_empty());

    let image = std::env::var("NANOSB_TEST_IMAGE").unwrap_or_else(|_| "library/alpine:latest".into());
    let name = daemon.name.clone();

    // ── lifecycle: create boots a real microVM ─────────────────────────
    let sandbox = client
        .create_with(SandboxBuilder::new(&image).name(&name).cpus(2).memory_mb(1024))
        .expect("create");
    assert_eq!(sandbox.state().unwrap(), SandboxState::Running);

    // get
    let info = client.get(&name).expect("get");
    assert_eq!(info.name, name);
    assert_eq!(info.state, SandboxState::Running);
    assert_eq!(info.image, image);

    // exec
    let out = sandbox.exec("echo", &["hello-from-live"]).expect("exec");
    assert_eq!(out.exit_code, 0);
    assert_eq!(out.stdout.trim(), "hello-from-live");

    // fs
    sandbox.fs_write("/tmp/live-conformance", b"written-by-live").expect("fs_write");
    assert_eq!(
        sandbox.fs_read_to_string("/tmp/live-conformance").unwrap(),
        "written-by-live"
    );
    assert!(sandbox.fs_exists("/tmp/live-conformance").unwrap());
    sandbox.fs_mkdir("/tmp/live-conformance-dir", true).unwrap();
    assert!(sandbox.fs_stat("/tmp/live-conformance-dir").unwrap().is_dir);

    // logs + metrics
    assert!(!sandbox.logs(Some(10)).unwrap().is_empty());
    let metrics = sandbox.metrics().unwrap();
    assert!(metrics.disk_used_bytes > 0);

    // list
    assert!(client.list(true).unwrap().iter().any(|s| s.name == name));

    // ── secrets (AC7: values are never returned) ───────────────────────
    sandbox.secret_set("LIVE_TOKEN", "s3cr3t").expect("secret_set");
    let secrets = sandbox.secret_list().unwrap();
    assert!(secrets.iter().any(|s| s.key == "LIVE_TOKEN"));
    assert!(secrets.iter().all(|s| s.value.is_none()));
    sandbox.secret_remove("LIVE_TOKEN").expect("secret_remove");
    assert!(sandbox.secret_list().unwrap().iter().all(|s| s.key != "LIVE_TOKEN"));

    // ── pause / resume (SIGSTOP / SIGCONT on the VM process) ───────────
    sandbox.pause().expect("pause");
    assert_eq!(sandbox.state().unwrap(), SandboxState::Running);
    sandbox.resume().expect("resume");
    let after = sandbox.exec("echo", &["after-resume"]).expect("exec after resume");
    assert_eq!(after.exit_code, 0);
    assert_eq!(after.stdout.trim(), "after-resume");

    // ── volumes (AC5): served through the helper socket ────────────────
    let vol_name = format!("vol-{}", std::process::id());
    let vol_dir = daemon.dir.join("vol-data");
    assert!(
        client.supports(Capability::Volumes),
        "the helper must advertise the Volumes capability"
    );
    let vol = sandbox
        .volume_create(VolumeBuilder::new(&vol_name).dir(vol_dir.to_string_lossy().to_string()).build())
        .expect("volume_create via helper socket");
    assert_eq!(vol.name, vol_name);
    assert!(sandbox.volume_list().unwrap().iter().any(|v| v.name == vol_name));
    assert_eq!(sandbox.volume_get(&vol_name).unwrap().name, vol_name);
    sandbox.volume_remove(&vol_name).expect("volume_remove");
    assert!(sandbox.volume_list().unwrap().iter().all(|v| v.name != vol_name));

    // ── snapshots: blocked (AC6) ───────────────────────────────────────
    // The helper does not advertise `Snapshots` and does not dispatch the
    // snapshot verbs; the supervisor also answers `unsupported` for them.
    assert!(
        !client.supports(Capability::Snapshots),
        "this build must not advertise snapshots (AC6 snapshots are blocked)"
    );
    let snap_err = sandbox
        .snapshot_create(None)
        .err()
        .map(|e| format!("{e}"))
        .unwrap_or_default();
    eprintln!("live_conformance: snapshot_create via helper socket -> {snap_err}");
    assert!(
        snap_err.contains("helper does not serve"),
        "snapshot_create should be blocked at the helper daemon, got: {snap_err}"
    );
    let restore_err = sandbox
        .snapshot_restore("snap-live", &format!("{}-restored", name))
        .err()
        .map(|e| format!("{e}"))
        .unwrap_or_default();
    assert!(
        restore_err.contains("helper does not serve"),
        "snapshot_restore should be blocked at the helper daemon, got: {restore_err}"
    );

    // ── lifecycle teardown ─────────────────────────────────────────────
    sandbox.stop(true).expect("stop");
    client.sandbox(&name).remove(true).expect("remove");
    assert!(client.list(true).unwrap().iter().all(|s| s.name != name));
}