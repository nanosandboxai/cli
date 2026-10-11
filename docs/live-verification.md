# Live-VM verification — Epic 1 Multi-language Sandbox SDK

**Date:** 2026-10-11
**Branch:** `feat/epic-1-sdk`
**Commit:** `07cd43a`
**Test:** `crates/client/tests/live_conformance.rs` (new, `#[ignore]`-gated)
**Result:** ✅ **PASS** — volumes and disk-only snapshots are served through the
helper socket.

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
live_conformance: exec ok; snapshots create/list/restore/remove ok
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

## Per-SDK live E2E

Every language SDK ships a `ManagedRuntime` (locate + spawn `nanosb-runtime
serve` on a private socket) and an opt-in live test that drives a **real
microVM** — the same operations as the Rust reference above. Requires macOS
arm64 + libkrun/gvproxy + a cached image; each test is skipped with a clear
reason otherwise.

| SDK | Command | Result |
|---|---|---|
| Rust (reference) | `cargo test -p nanosb-client --test live_conformance -- --ignored` | ✅ PASS |
| Python | `NANOSB_E2E=1 python3 sdk/python/tests/test_e2e.py` | ✅ PASS |
| TypeScript/Node | `NANOSB_E2E=1 node --test sdk/typescript/tests/e2e.test.mjs` | ✅ PASS |
| Go | `NANOSB_E2E=1 go test ./sdk/go/e2e -run TestLiveMicroVMSmoke` | ✅ PASS |
| Ruby | `NANOSB_E2E=1 ruby -I sdk/ruby/lib sdk/ruby/test/test_e2e.rb` | ✅ PASS |
| Java | `NANOSB_E2E=1 mvn -f sdk/java/pom.xml test -Dtest=E2ETest` | ✅ PASS |
| Kotlin | `NANOSB_E2E=1 java -cp sdk/kotlin/nanosandbox-kotlin.jar nanosandbox.kt.E2EKt` | ✅ PASS |
| C#/.NET | `NANOSB_E2E=1 dotnet test sdk/dotnet --filter E2ETest` | ✅ PASS |

Each test boots a real microVM and asserts: create→running, get, exec stdout,
fs write/read/exists/mkdir/stat, logs non-empty, metrics disk>0, list contains,
secret set/list (value redacted)/remove, pause→running→resume→exec, volume
create/list/remove, snapshot create/list/restore/remove, stop, remove. See
`docs/plans/2026-10-11-sdk-live-e2e-plan.md`.

## Blockers (precise)

### 1. Volumes — FIXED

The helper daemon now proxies `VolumeCreate`/`VolumeList`/`VolumeGet`/
`VolumeRemove`/`MountAdd` to the supervisor (mirroring the secret verbs) and
advertises `Capability::Volumes`. `volume_create` → `volume_list` →
`volume_get` → `volume_remove` round-trips cleanly through the helper socket.
(Fixed in `src/bin/nanosb_runtime.rs`; the supervisor already implemented the
registry.)

### 2. Snapshots — disk-only (AC6)

The helper daemon now serves the snapshot verbs from a disk-only store
(`src/supervisor/snapshots.rs`; see `docs/decisions/snapshots.md`) and
advertises `Capability::Snapshots`: `snapshot_create` → `snapshot_list` →
`snapshot_restore` (materialises a new, independent sandbox directory) →
`snapshot_remove` round-trips through the helper socket. Memory/process capture
and booting a VM on the restored writable layer are out of scope (epic R3).

## AC mapping

| AC | Evidence |
|---|---|
| AC5 (exec/fs/logs/metrics/volumes in every binding) | exec/fs/logs/metrics ✅ live; volumes ✅ live (helper proxies volume verbs) |
| AC6 (snapshot + restore, pause + resume) | pause/resume ✅ live; disk-only snapshot create/list/restore/remove ✅ live (memory capture deferred) |
| AC9 (bundled macOS arm64, `NANOSB_HOME`) | ✅ `nanosb doctor` clean; helper + client run with zero extra setup; `NANOSB_HOME`-relative paths (`sandbox_dir`, `volumes_root`) resolve correctly |

## Re-running

The test is `#[ignore]`-gated so CI stays green without a VM. Re-run with the
exact command above. When blockers #1/#2 are fixed, the corresponding
`assert!(...contains("helper does not serve"))` assertions will fail — that is
the signal to update this document and flip the assertions to expect success.