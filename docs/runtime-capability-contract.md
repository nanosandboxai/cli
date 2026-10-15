# Runtime & Capability Contract (for host-side consumers / shim authors)

This document is the contract a host-side consumer (e.g. the containerd shim)
relies on when talking to the Nanosandbox runtime helper. It is part of
Epic 10 (#168).

## 1. Protocol version

The wire protocol is versioned and implemented by the `nanosb-protocol` crate:

- **Current version:** `1.0.0` (`nanosb_protocol::PROTOCOL_VERSION`).
- Every connection begins with a **`hello`** handshake. The helper replies with
  its agreed protocol version and the capability list it implements.
- Version compatibility helpers: `nanosb_protocol::{cmp_version, version_in_range}`.

Clients **must** negotiate before issuing any optional verb.

## 2. Capabilities

Capabilities are declared in `nanosb_protocol::hello::Capability`. A consumer
must check that a capability is present before calling the verbs it gates
("no half-implemented verb set").

| Capability | Gates |
|-----------|-------|
| `lifecycle` | create/start/stop/kill/remove/get/list/modify/drain/touch/ping |
| `exec` | exec / exec_stream / shell / attach |
| `fs` | `fs/*` verbs |
| `logs` | logs (+ follow + cursor) |
| `metrics` | metrics / metrics_stream |
| `volumes` | `volumes/*` verbs |
| `secrets` | `secrets/*` verbs |
| `snapshots` | `snapshot/*` + pause/resume |
| `networking` | publish TCP/UDP ports + policy passthrough |
| `handles` | labels + handles |
| `ephemeral` | ephemeral sandboxes |
| `signal` | `kill` with an explicit signal (SIGTERM/SIGKILL) |
| `wait` | blocking `wait` verb (returns exit code) |
| `exec_pty` | `exec_stream` with a PTY + live stdin/resize frames |

`ExecPty`, `Signal`, and `Wait` are the shim-facing surface used by
containerd/CRI integration on Linux/KVM.

## 3. Process contract

- The runtime helper binary is **`nanosb-runtime`** (`src/bin/nanosb_runtime.rs`).
  It serves the protocol on a local socket and is the only process a consumer
  needs to speak to.
- The **supervisor** for a sandbox is a separate process; control flows over
  `$NANOSB_HOME/<sandbox>/control.sock` (see `supervisor::client`).

## 4. Dependency contract (layering)

A host-side consumer must be able to depend on the **thin host layer** without
pulling in the TUI or the VM engine (libkrun FFI):

```
nanosb-protocol  (pure wire types)
  └─ nanosb-host (spec→config, deploy, supervisor client/state; no TUI, no FFI)
       └─ nanosb-cli (adds TUI)   ·   runtime (engine, libkrun FFI)
```

Target consumer dependencies: **`nanosb-protocol` + `nanosb-host` only**.
`nanosb-cli` must not be a dependency (it drags in ratatui/tui-term/arboard and
`runtime → libkrun-sys → krun.a`).

### Status (Epic 10 progress)

- ✅ **H1** — `runtime::config` types extracted into the FFI-free
  `runtime-config` crate (`runtime/crates/runtime-config`); `runtime` re-exports
  it as `runtime::config`. Image normalization (`normalize_image`) also moved there.
- ✅ **H2/H3** — `nanosb-host` (`crates/host`) provides the supervisor client +
  state, `spec::spec_to_config` (+ `mount_spec_to_mount`), and the FFI-free
  `deploy` helpers (`EXEC_VSOCK_PORT`, `stage_exec_agent`, `Origin`,
  `extract_boot_env`). `nanosb-cli` re-exports them for compatibility. The
  engine-coupled `sandbox` (`AgentSandbox`, `runtime::Sandbox`) stays in the CLI.
- ✅ **H4** — TUI deps gated behind the optional `tui` feature; the `runtime-host`
  profile builds with no TUI dependencies.
- ✅ **H5** — `nanosb supervise --foreground --name <n> --spec <file|->` spawns the
  supervisor in the caller's process tree and prints the child pid.
- ✅ **H7** — CI (`host-layer` job) asserts `nanosb-host` and the slim helper build
  without the engine or TUI dependencies.

A host-side consumer (the shim) can depend on **`nanosb-protocol` +
`nanosb-host` only** — for spec→config conversion, exec-agent staging, and
supervisor control — with no TUI and no libkrun.

## 5. Where the source of truth lives

| Concern | Source |
|---------|--------|
| Wire protocol | `docs/protocol/protocol.md`, `crates/protocol` |
| Capabilities / handshake | `crates/protocol/src/hello.rs` |
| Config types (FFI-free) | `runtime/crates/runtime-config/src/lib.rs` |
| Host layer (client/state/spec/deploy) | `crates/host/src/` |
