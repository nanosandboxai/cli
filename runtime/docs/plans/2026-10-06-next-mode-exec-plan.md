# Plan: Host-side exec for next mode (microsandbox-style)

Status: reviewed (Momus APPROVE, 2026-10-06) — vsock feasibility confirmed
(libkrun-sys + kernel config); refinements folded: SDK exec built new (not wired
to runtime), supervisor Exec protocol shape, AC4 conditional on D4, QA scenarios.

## Phase 1 SPIKE: PASSED (2026-10-06)

Proven end-to-end: host connects to a unix socket → libkrun → guest vsock
listener → `echo VSOCK_EXEC_OK` → streamed `started/stdout/exit` → exit 0.
Artifacts: `runtime/crates/runtime/examples/spike-vsock-exec.rs`,
`guest/crates/exec-agent/`.

### Working recipe (mirrors smolvm; the non-obvious parts)
1. `krun_add_vsock(ctx, 0)` — enable the device. Our libkrun v1.19.5 defaults
   vsock to `Implicit` (already enabled), so this returns **EEXIST (-17)**; treat
   that as OK. (smolvm's newer libkrun disables implicit, so it doesn't hit this.)
2. `krun_add_vsock_port2(ctx, port, host_unix_socket, listen=true)` — **the key**:
   `listen=true` means the **guest serves** a vsock listener and the **host
   connects in** through libkrun's `UnixAcceptorProxy`. (`listen=false` inverts
   it: guest dials out — this is what caused the original hang.)
3. Guest agent: `socket(AF_VSOCK) → bind(VMADDR_CID_ANY, port) → listen() →
   accept()`; the host app connects to the unix socket path.
4. The child `internal-boot-vm` runs inside the `nanosb` binary — **rebuild and
   re-sign `nanosb`** after changing runtime vsock code, or the changes are
   invisible.
5. Cross-compile the guest agent:
   `PATH=~/.cargo/bin:$PATH RUSTFLAGS="-C linker=rust-lld" cargo build -p
   exec-agent --target aarch64-unknown-linux-musl --release`.

Date: 2026-10-06
Branch: feat/zero-image-customization
Supersedes: the "do NOT build exec" verdict (Phase 7) in
            runtime/docs/plans/2026-10-06-close-remaining-gaps-plan.md
Related: runtime/docs/plans/2026-10-06-remove-agent-gateway-plan.md

## Goal
Provide first-class host-side command execution for next-mode sandboxes —
`exec`, `exec_stream`, and interactive `attach` — matching the industry-standard
model used by microsandbox / Modal / E2B. This makes nanosandbox a peer of those
platforms rather than the outlier.

## Reference model (microsandbox) — verified from their docs
> "Command execution doesn't use SSH or the network. There's a **dedicated
> channel between the host and a guest agent** running inside the VM, completely
> separate from the sandbox's network stack. The agent spawns processes, streams
> output back, and reports exit codes."

API surface they expose (we should match the shape):
- `exec(cmd, args, {cwd, env, user, timeout, rlimits, stdin, tty}) -> {stdout, stderr, exit}`
- `shell(script, ...)` — via configured shell (`sh -c`)
- `exec_stream(...) -> ExecHandle` — streaming stdout/stderr/exit events, `stdin_pipe`, `tty`
- `attach(cmd, args, ...)` — interactive PTY, detach keys
- Works with networking fully disabled.

## Why this reverses the earlier verdict
The prior security review rejected an **init-blob relay** (root, PID-1-spawned,
image-independent) as net-negative. A **minimal, dedicated exec agent** is a
different design with a materially smaller surface than the old general
agent-gateway (which also did HTTP config CRUD, secrets, MCP translation, SSH).
The industry has validated the dedicated-channel + minimal-agent pattern; we
adopt it deliberately, scoped to exec only.

## Two viable transports (decision D1)

- **Option A — virtio-vsock** (microsandbox-style "not the network").
  Host↔guest over AF_VSOCK; independent of gvproxy/TSI; works with networking
  off. Requires libkrun vsock support (`krun_add_vsock_port` / TSI vsock) and an
  in-guest listener bound to a vsock port.
- **Option B — loopback TCP via gvproxy** (what the old gateway did).
  Guest agent binds `127.0.0.1:PORT`; host reaches it via a gvproxy port
  mapping. Simpler, reuses the existing port-forward machinery, but is
  network-stack dependent (fails when networking is off — the exact thing
  microsandbox advertises as working).

Recommended: **Option A (vsock)** for parity with the reference and the
"works without networking" property; fall back to B only if libkrun vsock proves
unavailable. **Feasibility confirmed:** `krun_add_vsock`/`krun_add_vsock_port`/`_port2`
exist in `runtime/crates/libkrun-sys/src/lib.rs` (safe wrappers included), and the
libkrunfw kernel config has `CONFIG_VSOCKETS=y`, `CONFIG_VIRTIO_VSOCKETS=y`,
`CONFIG_VSOCKETS_LOOPBACK=y` (all arches). Note: `krun_add_vsock` takes a
`tsi_features` flag — that is vsock's own TSI knob, not gvproxy; A does not need
gvproxy's port-map machinery. Phase 1 still validates the end-to-end path.

## The in-guest agent (scope: exec only)

A **new, minimal agent** — not a resurrection of the old gateway. Responsibilities:
- Listen on the chosen transport (vsock port, or loopback TCP).
- Accept a request: `{command, args, cwd, env, user, timeout, tty, rlimits}`.
- Spawn the process (`fork`/`exec`, optional PTY), own stdin/stdout/stderr.
- Stream tagged events: `stdout`, `stderr`, `exit`, `error`, `started`.
- Report exit code; support `stdin` writes, `signal`/`kill`, `resize`.
- Optional session IDs for reattach (later).

Explicitly **NOT** in scope (what made the old gateway large/risky): HTTP config
CRUD, MCP/skills generation, secrets store, SSH server, agent command building.
Those all live host-side now (`deploy` module).

Language: a small Rust binary (static, same toolchain) — avoids reintroducing Go
toolchain/CI. Decision D2.

## Where the agent lives (decision D3)

- **D3a — baked into a thin base image** (`agents-registry/docker/Dockerfile.base`).
  Simple; but violates zero-image-customization for arbitrary images.
- **D3b — injected at boot** (host writes the static binary into the rootfs, or
  mounts it RO via virtiofs). Keeps vanilla images working — consistent with the
  init patch approach. Recommended.

Note: any in-guest agent reintroduces *some* image/runtime coupling. This is the
accepted cost of the feature; document it clearly.

## Host-side work

### 1. Transport client (new `crates/exec-client` or revive `gateway` crate, trimmed)
- Keep the proven pieces: transport (vsock/TCP), request/response framing,
  SSE/event streaming, health check.
- Drop: SSH key management, secrets crypto, config CRUD from the old crate.
- Public types: `ExecOptions`, `ExecResult`, `OutputChunk`, `Stream`, `ExecHandle`.

### 2. SDK wiring (`sandbox/crates/sandbox`)
- `Sandbox::exec / exec_stream / exec_with / shell / attach` — **new methods built
  on the exec client.** Note: `runtime::Sandbox` (the VM lifecycle type) has **no
  exec method today**; the current `sandbox::Sandbox::exec` was a thin wrapper over
  `gateway()` (now removed). Exec is constructed fresh in the SDK crate against
  the new client — it is *not* wired into the runtime crate.
- Backend selection by runtime mode: next → exec agent; (legacy removed later).
- `agent_sandbox.rs::send_message` reimplemented over exec (or dropped).

### 3. FFI surface (`sandbox/src/ffi.rs`)
- Keep `sandbox_exec`, `sandbox_exec_stream` (they will now work in next mode).
- Add `sandbox_shell`, `sandbox_attach` (optional, phase 2) to match peers.
- Keep ABI signatures stable.

### 4. Supervisor / control socket
- Add a `ControlRequest::Exec { cmd, args, cwd, env, user, timeout, tty }` variant
  (current enum has only `Status`, `Stop`, `Attach`, `LogsFollow`, `Ping`), with a
  streamed response: `ExecFrame::{Started, Stdout, Stderr, Exit, Error}` — mirror
  the existing `Attach`/`AttachFrame` framing (`src/supervisor/mod.rs`). Add the
  handler in the supervisor request loop so `nanosb exec` and detached sandboxes
  can exec without the caller owning the VM fds.

### 5. CLI
- Revive `nanosb exec <sandbox> <cmd>` (was removed) backed by the new agent.
- `nanosb attach` already exists (console); add process-attach later if desired.

## Phases

1. **Spike (1 day):** prove vsock host↔guest works in a next-mode vanilla alpine
   (smallest possible echo agent). If not, decide B.
2. **Agent v1:** minimal exec agent (buffered exec + streaming) + transport.
   AC: agent runs `echo hi`, returns exit code; streaming delivers chunks.
3. **Client v1:** trimmed Rust client; `ExecResult`/`OutputChunk` types.
4. **SDK + FFI:** `exec`/`exec_stream` work for next mode; ABI stable.
5. **CLI:** revive `nanosb exec`; `-f`-style streaming.
6. **PTY/attach + stdin + signals:** `attach`, `stdin_pipe`, `resize`, `kill`.
7. **Agent packaging:** inject at boot (D3b) or bake into base (D3a).
8. **Docs + security:** update security checklist; scope the agent's surface.

## Acceptance criteria
- AC1 `exec("echo",["hi"])` returns `hi`, exit 0, for a next-mode sandbox.
- AC2 `exec_stream` yields stdout/stderr/exit events live.
- AC3 `shell("a && b")` works via `sh -c`.
- AC4 **(v1 only if D4 = include-PTY)** `attach` gives an interactive PTY; detach
  keys work. If D4 defers PTY, AC4 becomes a v2 criterion.
- AC5 Works with networking disabled (vsock path).
- AC6 FFI signatures unchanged; SDK bindings can call exec.
- AC7 Agent surface is exec-only (no config/secrets/SSH endpoints).

### QA scenarios (per phase)
- **Phase 1 (spike):** boot next-mode `alpine:latest` with a tiny echo agent;
  from the host, connect over the chosen transport, send `ping`, expect `pong`
  within N seconds. Pass/fail is binary. If vsock: also boot with networking
  disabled and repeat.
- **Phase 2 (agent):** run the agent in-guest; host sends
  `{command:"echo",args:["hi"]}`; assert exit `0` and stdout `hi\n`. Stream test:
  run `sh -c 'echo a; sleep 0.2; echo b'`; assert two stdout events in order.
- **Phase 4 (SDK/FFI):** call `sandbox_exec` via the FFI against a next-mode
  sandbox; assert JSON `{exit_code:0,stdout:"hi\n"}`.
- **Phase 5 (CLI):** `nanosb exec <name> -- echo hi` prints `hi`; `-f` streams.

## Security considerations (must be explicit)
- This **reintroduces an in-guest listener** — the deliberate tradeoff. Mitigate:
  - Bind only to vsock / `127.0.0.1` (never routable), gate by the control socket
    permissions (0600, same-UID) for host access.
  - Exec runs as the configured guest user (already supported via `--user`), not
    root by default.
  - Minimal attack surface: exec verbs only; no unauthenticated CRUD.
  - Document as a capability in `zero-image-customization-security.md`.
- Update the checklist row that currently says "no privileged in-guest control
  server" to reflect the scoped exec agent and its mitigations.

## Risks
- R1. **vsock availability in libkrun/pinned version** — spike-gated; fallback B.
- R2. **Reintroduces image coupling** if D3a — prefer D3b injection.
- R3. **Security regression vs. the zero-in-guest ideal** — accepted, scoped,
  documented.
- R4. **ABI/consumer expectations** — SDK not built yet; low risk if the FFI
  signatures are kept.
- R5. **Scope creep back into a full gateway** — freeze the agent at exec-only;
  reject config/secrets/MCP endpoints.

## Sign-off items
- **D1:** transport — vsock (recommended) vs loopback TCP.
- **D2:** agent language — Rust static (recommended) vs Go (old stack) vs other.
- **D3:** agent delivery — inject at boot (recommended) vs bake into base image.
- **D4:** include PTY `attach`/`stdin`/signals in v1, or exec+stream only first?
- **D5:** revive `nanosb exec` in the CLI now, or SDK-only first?

## Relationship to the removal plan
The `2026-10-06-remove-agent-gateway-plan.md` removes the *old general gateway*.
This plan adds a *new, minimal exec agent*. They are sequential: remove the old
(large, risky, dead-in-repo) surface, then build the small, well-scoped feature
the industry expects. Do not conflate them.
