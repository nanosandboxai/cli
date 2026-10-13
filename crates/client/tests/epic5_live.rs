//! Live-VM assertions for Epic 5 (advanced sandbox surface, S1–S9).
//!
//! Boots a real microVM through the `nanosb-runtime` helper and proves the
//! surface that previously existed only as protocol types now reaches the
//! runtime: hostname, secretEnv substitution, log-source separation, tmpfs
//! mounts, per-exec rlimits, `exec_default`, list pagination, `replace`,
//! disk-image volumes, and published UDP ports with an explicit bind address.
//!
//! Opt-in (needs the helper, libkrun/gvproxy, a cached image):
//!
//!   cargo build -p nanosb-cli --bin nanosb-runtime --no-default-features --features runtime-host
//!   cargo test -p nanosb-client --test epic5_live -- --ignored --nocapture

use std::path::PathBuf;
use std::process::{Child, Command};
use std::time::{Duration, Instant};

use nanosb_client::{SandboxBuilder, SandboxClient, VolumeBuilder};
use nanosb_protocol::{
    ExecDefaultRequest, ExecRequest, LogSource, PortPublish, PullPolicy, SandboxState,
};

struct Daemon {
    child: Child,
    socket: PathBuf,
    dir: PathBuf,
}

impl Drop for Daemon {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn runtime_bin() -> PathBuf {
    if let Ok(p) = std::env::var("NANOSB_RUNTIME_BIN") {
        return PathBuf::from(p);
    }
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../target/debug/nanosb-runtime")
}

fn start_daemon() -> Daemon {
    let dir = std::env::temp_dir().join(format!("nsb-e5-{}", std::process::id()));
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
    Daemon { child, socket, dir }
}

fn cleanup(name: &str) {
    let _ = std::fs::remove_dir_all(nanosb_client::sandbox_dir(name));
}

#[test]
#[ignore = "requires nanosb-runtime + libkrun + a cached image"]
fn epic5_advanced_surface_live() {
    let daemon = start_daemon();
    let client = SandboxClient::connect(&daemon.socket).expect("connect");
    let image =
        std::env::var("NANOSB_TEST_IMAGE").unwrap_or_else(|_| "library/alpine:latest".into());
    let pid = std::process::id();
    let name = format!("e5-{pid}");

    // ── S8 hostname + S4 secretEnv + S5 tmpfs + S1 rlimit in one boot ──
    let sandbox = client
        .create_with(
            SandboxBuilder::new(&image)
                .name(&name)
                .cpus(2)
                .memory_mb(1024)
                .hostname("e5box")
                .secret("api-key", "s3cr3t-value")
                .secret_env("API_KEY", "api-key")
                .mount_tmpfs("/mnt/scratch")
                .rlimit("nofile", 256, 256),
        )
        .expect("create");
    assert_eq!(sandbox.state().unwrap(), SandboxState::Running);

    // S8: hostname is applied in the guest.
    let host = sandbox.exec("hostname", &[]).expect("hostname");
    assert_eq!(host.stdout.trim(), "e5box", "hostname not applied");

    // S4: secretEnv substituted into the guest environment.
    let secret = sandbox
        .exec("sh", &["-c", "printf %s \"$API_KEY\""])
        .expect("secret exec");
    assert_eq!(
        secret.stdout.trim(),
        "s3cr3t-value",
        "secretEnv not substituted"
    );

    // S4 invariant: the secret value is never written to disk.
    let config = std::fs::read_to_string(nanosb_client::sandbox_dir(&name).join("config.json"))
        .unwrap_or_default();
    assert!(
        !config.contains("s3cr3t-value"),
        "secret value persisted to config.json"
    );

    // S5: tmpfs mount appears in the guest mount table.
    let mounts = sandbox.exec("sh", &["-c", "mount"]).expect("mount");
    assert!(
        mounts.stdout.contains("/mnt/scratch") && mounts.stdout.contains("tmpfs"),
        "tmpfs mount missing: {}",
        mounts.stdout
    );

    // S1: per-exec rlimit is honored by the guest process.
    let mut rl = ExecRequest::new("sh");
    rl.name = Some(name.clone());
    rl.args = vec!["-c".into(), "ulimit -n".into()];
    rl.rlimits = vec![nanosb_protocol::Rlimit {
        resource: "nofile".into(),
        soft: Some(256),
        hard: Some(256),
    }];
    let ulimit = sandbox.exec_with(rl).expect("ulimit exec");
    assert_eq!(ulimit.stdout.trim(), "256", "per-exec rlimit not applied");

    // S1: exec_default runs the default workload (a shell here).
    let mut def = ExecDefaultRequest::default();
    def.args = vec!["-c".into(), "printf default-ok".into()];
    let default = client
        .sandbox(&name)
        .exec_default(def)
        .expect("exec_default");
    assert_eq!(default.stdout.trim(), "default-ok", "exec_default failed");

    // S3: stderr console output is labeled Stderr (the agent logs to fd 2).
    let stderr_lines = sandbox
        .logs_with(None, None, Some(LogSource::Stderr))
        .expect("stderr logs");
    assert!(!stderr_lines.is_empty(), "no stderr log lines");
    assert!(
        stderr_lines.iter().all(|l| l.source == LogSource::Stderr),
        "stderr logs mislabeled"
    );
    let merged = sandbox.logs_with(None, None, None).expect("merged logs");
    assert!(
        merged.iter().any(|l| l.source == LogSource::Stderr),
        "merged logs lost the stderr source"
    );

    // ── S9: published UDP port with an explicit bind address boots ──────
    let net_name = format!("e5net-{pid}");
    let net = client
        .create_with(
            SandboxBuilder::new(&image)
                .name(&net_name)
                .memory_mb(1024)
                .publish(PortPublish {
                    host_port: 15353,
                    container_port: 53,
                    protocol: "udp".into(),
                    bind_address: Some("127.0.0.1".into()),
                }),
        )
        .expect("create with udp publish");
    assert_eq!(net.state().unwrap(), SandboxState::Running);
    assert!(
        net.exec("true", &[]).is_ok(),
        "udp-published guest not execable"
    );

    // ── S2: list pagination cursor ──────────────────────────────────────
    let page = client.list_page(Some(1), None, None).expect("list page 1");
    assert_eq!(page.sandboxes.len(), 1, "page should hold one sandbox");
    let cursor = page.next_cursor.expect("next_cursor missing");
    let page2 = client
        .list_page(Some(1), Some(cursor), None)
        .expect("list page 2");
    assert!(
        !page2.sandboxes.is_empty(),
        "second page empty; pagination did not advance"
    );

    // ── S2: replace stops and rebuilds the same name ────────────────────
    let replaced = client
        .create_with(
            SandboxBuilder::new(&image)
                .name(&net_name)
                .memory_mb(1024)
                .replace(true),
        )
        .expect("replace create");
    assert_eq!(replaced.state().unwrap(), SandboxState::Running);

    // ── S6: disk-image volume with an enforced quota ────────────────────
    let vol = sandbox
        .volume_create(
            VolumeBuilder::new("e5vol")
                .disk_image("raw")
                .fstype("ext4")
                .volume_quota(4 * 1024 * 1024)
                .build(),
        )
        .expect("disk volume create");
    assert_eq!(vol.quota_bytes, Some(4 * 1024 * 1024), "quota not recorded");
    assert_eq!(vol.fstype.as_deref(), Some("ext4"));
    let _ = sandbox.volume_remove("e5vol");

    // ── §3: pullPolicy=never succeeds against a cached image, and
    //       waitUntilStopped observes the stop ──────────────────────────
    let pull_name = format!("e5pull-{pid}");
    let pull = client
        .create_with(
            SandboxBuilder::new(&image)
                .name(&pull_name)
                .memory_mb(1024)
                .pull_policy(PullPolicy::Never),
        )
        .expect("pull_policy=never with cached image");
    assert_eq!(pull.state().unwrap(), SandboxState::Running);
    pull.stop(true).expect("stop");
    let stopped = pull
        .wait_until_stopped(Duration::from_secs(20))
        .expect("wait");
    assert_eq!(
        stopped,
        SandboxState::Stopped,
        "waitUntilStopped did not observe stop"
    );
    let _ = pull.remove(true);
    cleanup(&pull_name);

    // ── teardown ────────────────────────────────────────────────────────
    for n in [&name, &net_name] {
        let _ = client.sandbox(n).stop(true);
        let _ = client.sandbox(n).remove(true);
        cleanup(n);
    }
}
