# Live-VM verification — Epic 1 Multi-language Sandbox SDK

**Date:** 2026-10-11
**Branch:** `feat/epic-1-sdk`
**Commit:** `07cd43a`
**Test:** `crates/client/tests/live_conformance.rs` (new, `#[ignore]`-gated)
**Result:** ✅ **PASS** — volumes now served through the helper socket; one
remaining blocker (snapshots) documented below.

This run is the AC5 / AC6 / AC9 evidence for Epic 1 that requires a **real
microVM** (libkrun + gvproxy + a cached image). It builds/spawns the real
`nanosb-runtime` helper (`serve`), connects `nanosb-client`, and drives the
operations that cannot be faked by the CI conformance harness.

## Prerequisites

| Requirement | Checked | Notes |
|---|---|---|
| macOS Apple Silicon (arm64) | ✅ | `uname -m` → `arm64` |
| `nanosb-runtime` binary | ✅ | `target/debug/nanosb-runtime` (built via `cargo build -p nanosb-cli --bin nanosb-runtime`) |
| libkrun | ✅ | `~/.nanosandbox/lib/libkrun.a` |
| libkrunfw | ✅ | `~/.nanosandbox/libs/libkrunfw.5.dylib` |
| gvproxy | ✅ | `~/.nanosandbox/bin/gvproxy` |
| Hypervisor.framework | ✅ | `nanosb doctor` → 4/4 checks passed |
| Cached image | ✅ | `library/alpine:latest` (4.0 MB, pulled 16 h before run) |

`nanosb doctor` output before the run:

```
[✓] Architecture: Apple Silicon (aarch64)
[✓] libkrunfw Kernel Firmware: found (libkrunfw.5.dylib)
[✓] Hypervisor.framework: available
[✓] gvproxy: available (full outbound networking)
4 checks passed, 0 errors, 0 warnings
```

## Exact command

```bash
cargo build -p nanosb-cli --bin nanosb-runtime --no-default-features --features runtime-host
cargo test -p nanosb-client --test live_conformance -- --ignored --nocapture
```

Optional overrides:

```bash
NANOSB_RUNTIME_BIN=/path/to/nanosb-runtime \
NANOSB_TEST_IMAGE=library/alpine:latest \
  cargo test -p nanosb-client --test live_conformance -- --ignored --nocapture
```

## Result

```
running 1 test
nanosb-runtime: listening on /var/folders/.../nsb-live-51401/helper.sock
live_conformance: snapshot_create via helper socket -> unsupported: helper does not serve SnapshotCreate(...)
test live_conformance_smoke ... ok

test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 5.41s
```

A real microVM booted (create returned `Running`, `exec` returned
`hello-from-live`, `metrics.disk_used_bytes > 0`). Cleanup verified: no leftover
sandbox dirs under `~/.nanosandbox/sandboxes/`, no leftover temp dirs, no
leftover volumes.

## What passed (verified against a live VM)

| Area | Verbs exercised | Outcome |
|---|---|---|
| Lifecycle | `create` (boots VM) → `get` → `exec` → `stop` → `remove` → `list` | ✅ |
| Filesystem | `fs_write` / `fs_read_to_string` / `fs_exists` / `fs_mkdir` / `fs_stat` | ✅ |
| Observability | `logs` (non-empty), `metrics` (disk used > 0) | ✅ |
| Secrets (AC7) | `secret_set` / `secret_list` / `secret_remove`; values never returned (`value: None`) | ✅ |
| Pause / resume (AC6) | `pause` (SIGSTOP) → state still `Running` → `resume` (SIGCONT) → `exec` succeeds | ✅ |
| Volumes (AC5) | `volume_create` / `volume_list` / `volume_get` / `volume_remove` **via the sandbox control socket** | ✅ |

## Blockers (precise)

### 1. Volumes — FIXED

The helper daemon now proxies `VolumeCreate`/`VolumeList`/`VolumeGet`/
`VolumeRemove`/`MountAdd` to the supervisor (mirroring the secret verbs) and
advertises `Capability::Volumes`. `volume_create` → `volume_list` →
`volume_get` → `volume_remove` round-trips cleanly through the helper socket.
(Fixed in `src/bin/nanosb_runtime.rs`; the supervisor already implemented the
registry.)

### 2. Snapshots are not implemented (AC6)

The helper daemon does not advertise `Snapshots` and does not dispatch the
snapshot verbs; the supervisor also answers `unsupported` for them. Both
`snapshot_create` and `snapshot_restore` through the helper socket return:

```
unsupported: helper does not serve SnapshotCreate(SnapshotCreateSpec { ... })
```

Even if the helper proxied them, the supervisor returns
`unsupported: snapshots are not available in this build`
(`src/supervisor/proto.rs`). This matches the epic's R3 risk (full snapshots on
libkrun deferred; disk-only fallback not yet landed). Fix: implement snapshot
create/restore in the supervisor, then add the proxy arms + capability in the
helper daemon.

## AC mapping

| AC | Evidence |
|---|---|
| AC5 (exec/fs/logs/metrics/volumes in every binding) | exec/fs/logs/metrics ✅ live; volumes ✅ at supervisor level, ⛔ blocked at helper socket (blocker #1) |
| AC6 (snapshot + restore, pause + resume) | pause/resume ✅ live; snapshot create/restore ⛔ not implemented (blocker #2) |
| AC9 (bundled macOS arm64, `NANOSB_HOME`) | ✅ `nanosb doctor` clean; helper + client run with zero extra setup; `NANOSB_HOME`-relative paths (`sandbox_dir`, `volumes_root`) resolve correctly |

## Re-running

The test is `#[ignore]`-gated so CI stays green without a VM. Re-run with the
exact command above. When blockers #1/#2 are fixed, the corresponding
`assert!(...contains("helper does not serve"))` assertions will fail — that is
the signal to update this document and flip the assertions to expect success.