# Epic 1 — Conformance & status report

Date: 2026-10-11 · Branch: `feat/epic-1-sdk`

## Conformance matrix (all green)

| Binding | Driver | Result |
|---|---|---|
| Rust (reference client) | `crates/conformance/tests/driver_test.rs` | **35/35** |
| Python | `python3 sdk/python/conformance/run.py` | **35/35** |
| TypeScript/Node | `node sdk/typescript/conformance/run.mjs` | **35/35** |
| Go | `go run ./sdk/go/conformance/run.go` | **35/35** |
| Ruby | `ruby -I sdk/ruby/lib sdk/ruby/conformance/run.rb` | **35/35** |
| Java | `java -cp <build> Run` (`sdk/java/conformance/Run.java`) | **35/35** |
| C#/.NET | `dotnet run --project sdk/dotnet/conformance` | **35/35** |

The corpus (`sdk/conformance/scenarios/`, 35 scenarios) exercises lifecycle,
exec/exec_stream/shell/attach(+input/resize), the full `fs` v1 set including
streamed write, logs (tail/follow/cursor/source), metrics(+stream), volumes,
secrets, snapshots, error codes, per-step timeouts, and capability gating. Each
scenario is scripted against the standalone `nanosb-conformance` harness
(`crates/conformance`) and each binding drives its own client API.

Rust workspace suites (green): `nanosb-protocol` 18, `nanosb-client` 21,
`nanosb-conformance` 15, `gateway` 7, `runtime` 76, `nanosb-cli` 351.

## Acceptance criteria

| AC | Status | Evidence |
|---|---|---|
| AC1 `nanosb-runtime` builds from features; boots + controls a sandbox | ✅ | `runtime-host` build; helper daemon + supervisor serve the verb set; live-VM e2e (helper_e2e) passed during W1 |
| AC2 Protocol spec published; reference client passes every verb | ✅ | `docs/protocol/*`; Rust driver 35/35 |
| AC3 Rust/Python/TS/Go/Ruby pass conformance | ✅ | 5/5 drivers 35/35 |
| AC4 Java/Kotlin + C# pass conformance | ✅ | Java 35/35, C# 35/35, Kotlin (facade over the Java SDK) 35/35 |
| AC5 exec/stream/shell/attach/fs/logs/metrics/volumes in every binding | ✅ | scripted harness 35/35 in all 8 bindings; **live** on a next-mode vanilla image: Rust reference + Python/TS/Go/Ruby/Java/Kotlin/C# each boot a real microVM and assert `exec`/`exec_stream`/`shell`/`attach` + fs/logs/metrics/volumes (see `docs/live-verification.md`) |
| AC6 snapshot+restore and pause+resume (local) | ✅ | `pause`/`resume` live in all 8; disk-only snapshot create/list/restore/remove live in all 8. Memory/process capture + boot-from-snapshot deferred under R3 (`docs/decisions/snapshots.md`) |
| AC7 no binding persists secret values | ✅ | in-memory store; `list` returns redacted values; regression test greps the sandbox dir |
| AC8 C FFI fully removed | ✅ | zero `extern "C" fn sandbox_`, no `cbindgen`, no `ffi` feature/cdylib |
| AC9 bundled macOS arm64 install, zero setup, `NANOSB_HOME` works | ✅ | `scripts/test-packaged-boot.sh`: `package-sdk.sh` → bundle `install.sh` into a fresh `NANOSB_HOME` → the installed helper (helper + gvproxy + libkrunfw + guest `exec-agent`) boots a real microVM; pre-sign + lazy re-sign verified |

Legend: ✅ done · ◑ partial · ✗ not done.

## What landed (commits on `feat/epic-1-sdk`)

- `nanosb-protocol` + `nanosb-client` foundation (W0).
- Helper `nanosb-runtime` + supervisor protocol serving; guest `fs` verbs over
  vsock; C FFI retired (W1).
- Reference-client surface closure; `hostname`/`secret_env` spec fields.
- Runtime: secrets store (AC7), Start/Modify, attach input/resize, ephemeral
  auto-remove, `pullPolicy`, `bind_address`; streamed `fs` write.
- Storage: dir-backed volume registry + decision doc.
- `nanosb-conformance` harness + 35-scenario corpus + SPEC.
- `docs/protocol` (AC2).
- Rust driver + 6 language SDKs (Python, TypeScript, Go, Ruby, Java, C#), each
  with a conformance driver and unit tests.

## Remaining (deferred, not AC blockers)

- **WS6 / M5 — snapshots beyond disk-only**: memory/process capture and booting a
  VM *on* a restored writable layer are out of scope under R3
  (`docs/decisions/snapshots.md`). The disk-only store ships and is verified live.
- **§4 advanced surface (non-AC)**: **closed by Epic 5**
  (`docs/epics/epic-5-advanced-sandbox-surface.md`). Per-exec `rlimits`,
  tmpfs/file/disk-image mounts, mount options/owner, `quota`, named scripts,
  `secretEnv` substitution, `hostname`, `NetworkConfig` policy passthrough, and
  log-source separation are now threaded end-to-end with live assertions in
  `crates/client/tests/epic5_live.rs`. Still deferred: live `mount_add` (no
  virtiofs hotplug), `stat virtualization` and `securityProfile` enforcement
  (undefined semantics). The **AC5 verb set itself is complete and live-verified**.
- **Kotlin**: shipped (facade over the Java SDK) — a fully standalone Kotlin
  client is an optional refinement.
- **WS5 networking enforcement**: deliberately Epic 3 (config surface ships here).