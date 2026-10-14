# TUI Supervisor Migration Plan

Status: reviewed (Momus APPROVE, 2026-10-05) — refinements folded: extraction step,
supervisor-aware kill, write_secrets_bootstrap, env-var parity, upload call sites.
Date: 2026-10-05
Branch: feat/zero-image-customization
Parent plan: runtime/docs/plans/2026-10-05-zero-image-customization-plan.md

## 1. Goal

Make the TUI supervisor-only for sandbox lifecycle and interactive access, so that
the in-VM agent-gateway (HTTP/SSE/SSH) is no longer reachable from the TUI. After
this migration, every TUI panel is backed by exactly one of:

- a **supervisor-managed sandbox** (detached supervisor process + console stream), or
- a **resumed/session panel** that reconnects to an existing supervisor.

The gateway client crate (`sandbox/crates/gateway`) remains only for the SDK/FFI
surface (see §8 Non-Goals) but is no longer consumed by `src/tui/**`.

## 2. Current State (verified 2026-10-05)

### 2.1 Two panel backends coexist

`src/tui/app.rs` `Panel` (line ~278+) holds BOTH:

| Field | Backend | Line |
|---|---|---|
| `sandbox: Option<Arc<Mutex<Sandbox>>>` | legacy gateway/SSH | 278 |
| `sandbox_id_short` | both | 284 |
| `terminal: Option<SshTerminal>` | shared renderer | 296 |
| `terminal_handle: Option<SshTerminalHandle>` | shared | 298 |
| `project_mount: Option<sandbox::ProjectMount>` | legacy SDK | 308 |
| `sync_override: Option<bool>` | legacy | 315 |
| `ssh_host_port/ssh_host/ssh_key_path` | legacy SSH/ssh -L/upload | 317-321 |
| `supervisor_name: Option<String>` | next-mode | 323 |

### 2.2 Spawn paths (three sites, all in `run.rs`)

1. **Initial spawn** — `AppEvent::SandboxReady` (379-497): sets `panel.sandbox`,
   then either `spawn_gateway_exec` (auto-mode, 424) or `connect_ssh` (interactive, 467).
   `AppEvent::SupervisorReady` (498-552) sets `panel.supervisor_name`, `panel.sandbox=None`,
   then `connect_console`.
2. **Reconnect** — `Command::Reconnect` ≈2150-2248: branches on `panel.sandbox.is_none()`
   → `connect_console`, else SSH `connect_ssh`; falls through to an error if neither.
3. **Headless/auto spawn** — `spawn_gateway_exec` def at 1126; `send_encrypted_env` def at 5362
   (calls `sandbox.gateway().crypto_public_key()` and `gateway().set_env`).

### 2.3 Gateway/SSH consumers in `src/tui/**`

- `run.rs`: `sb.gateway()` at 1004, 1204, 5382, 5458, 5473; `spawn_gateway_exec` 424/1126;
  `send_encrypted_env` 4251/4433/4843/5362; `sb.ssh_port()/ssh_host()/ssh_key_path()` 383, 2202-2204;
  `connect_ssh` 467, 2227; `ssh -L` port-forward 774, 2165; OAuth `ssh -L` 787.
- `terminal.rs`: `russh` client `connect_ssh` 173; `SshHandler` 151; `SshTerminalHandle::noop` 434
  ("headless gateway exec"); `agent_env_vars` docstring references "SSH and gateway exec paths" 537.
- `upload.rs`: `UploadSshHandler` 85; `ssh_upload` 104; callers `spawn_upload`/`spawn_bytes_upload` 252/302.
- `app.rs`: SSH fields 317-321; `ssh_key_path` init 387.

### 2.4 What already works for next-mode

- Supervisor process, control socket (NDJSON), console attach, reconnect, log tail:
  `src/supervisor/{mod.rs,client.rs}`. `AttachFrame::{Output,Exit}`, `AttachInput::{Input,Resize}`.
- `connect_console` (`terminal.rs` 446-533) returns an `SshTerminalHandle` whose channels are
  translated to attach input/resize frames and whose reader emits `AppEvent::TerminalData`.
- CLI: `cmd_run_next` (main.rs 1367) runs supervisor-only via `spawn_supervisor` + `SupervisorClient`.
- Exit-code propagation verified E2E (`exit 3` → CLI exit 3).

### 2.5 Constraints discovered

- **No exec channel in next-mode.** The supervisor console is a single interactive stream;
  there is no side-channel to run `sync`, env injection, or one-off commands. Any TUI action
  that assumed `gateway().exec(...)` must be re-expressed against the console or deferred.
- **`SshTerminalHandle` is transport-agnostic** (just `write_tx`/`resize_tx`), so console-backed
  panels already render through the existing terminal path. Renaming it would be cosmetic risk.
- **`SshDisconnected` event** is reused for console exit — an intentional naming leak but harmless.
- **`panel.project_mount` is produced host-side by the SDK** (`Sandbox::create` → `setup_project_mount`)
  and is needed for gitsync status, upload remote paths, and `Command::Edit`. In next-mode the
  project mount is planned by `sandbox/crates/sandbox/src/deploy/` (`MountPlanner`) at supervisor
  spawn time in `main.rs`, but the TUI does not currently construct a `ProjectMount` for
  supervisor panels. **This is the migration's central blocker.**

## 3. Decisions Required (proposed defaults)

These were flagged as product-decision-gated. Proposed defaults let implementation proceed;
each is called out again in §8 as an explicit sign-off item.

| # | Question | Proposed default |
|---|---|---|
| D1 | Project clone/sync behavior for supervisor panels | Keep host-side SDK `ProjectMount` setup; feed its mounts into the supervisor deploy plan (same virtiofs path as CLI). No in-guest git. |
| D2 | Upload replacement (no SSH) | Replace `ssh_upload` with a virtiofs write into the project mount (or a shared uploads dir) via the host filesystem. If no mount → upload disabled with a clear message. |
| D3 | OAuth `ssh -L` removal | Drop TUI-driven `ssh -L`; rely on gvproxy port mappings (`--port`) in the deploy plan. Document that OAuth callback must be mapped at spawn. |
| D4 | auto-mode / headless behavior | auto-mode = supervisor console with the agent command as the boot command (via `config.command`), not a gateway exec. Output still rendered in the panel. |
| D5 | `Command::Edit` tool | Use `project_mount.worktree_base` (already read at 2455 area) — host-side edit, no SSH. |
| D6 | Rename `SshTerminal*` / `SshConnected`/`SshDisconnected` | Defer. Keep names; add doc note. Renaming touches renderer/event surface broadly for no functional gain. |

## 4. Work Breakdown

Phases are ordered by dependency. Each phase ends green (`cargo test -p nanosb-cli`) and is
one atomic commit.

### Phase T1 — Panel model unification (no behavior change yet)

- `src/tui/app.rs`: add `PanelBackend` enum:
  ```rust
  pub enum PanelBackend {
      Supervisor { name: String },
      Legacy { sandbox: Arc<Mutex<Sandbox>> },
  }
  ```
  Replace the pair (`sandbox: Option`, `supervisor_name: Option`) with a single
  `backend: Option<PanelBackend>`. Keep the old accessors as thin helpers during migration
  (`panel.sandbox()` → `match backend { Legacy{..} => Some, _ => None }`) so the tree compiles
  incrementally.
- Files: `app.rs` only. No callers change in this phase (helpers preserve API).
- Verify: `cargo build -p nanosb-cli`; existing TUI unit tests pass.

### Phase T2 — Route all spawns through supervisor

- **Extraction step first**: `deploy_plan_for` (main.rs 928), `materialize_plan` (1036), and
  `spawn_supervisor` (1077) are currently **nested inside `impl Cli`** — extract each into
  free functions (or move to a new `src/supervisor/deploy.rs`) before reuse. Keep behavior
  byte-identical; this is a pure move.
- New helper `spawn_supervisor_panel(...)` in `run.rs` that mirrors `cmd_run_next`'s
  config-building (reuse the extracted `deploy_plan_for` / `materialize_plan` / `spawn_supervisor`).
- `AppEvent::SandboxReady` handling: replace `spawn_gateway_exec` + `connect_ssh` branches with
  `spawn_supervisor_panel` → emits `AppEvent::SupervisorReady`.
- `AppEvent::SupervisorReady`: set `backend = Supervisor`, keep `connect_console`.
- `Command::Reconnect`: collapse to the console branch only; delete the SSH branch.
- **Panel kill must be supervisor-aware**: `kill_panel_at` (run.rs 1293) currently calls
  `spawn_sandbox_destroy` only when `sandbox_arc` is `Some`. After T1, supervisor panels have
  `sandbox == None`, so kill would orphan the process. Add a `SupervisorClient::stop()` branch
  for `PanelBackend::Supervisor` (this is required for AC7, not a follow-up).
- Delete `spawn_gateway_exec` (1126) and its call site (424).
- Delete `send_encrypted_env` (5362) and call sites (4251/4433/4843), **including
  `write_secrets_bootstrap` (5445)** which is only reachable from those sites — env is delivered
  via `config.env` in the deploy plan instead.
- **Env-var parity**: `agent_env_vars` (terminal.rs 539) currently feeds both SSH and gateway
  paths. Ensure the vars it produces (GOOSE_MODE, GOOSE_MODEL, NANOSB_PROMPT, …) are present in
  the deploy plan's `config.env`. `deploy_plan_for` already routes through
  `AgentCommandBuilder::build_env`, so verify parity rather than re-implementing.
- Remove the SYNC probe `sb.gateway().exec("sync",...)` (1004) — replace with a no-op or
  drop the health check (supervisor `client.is_running()` already gates attach).
- Verify: `cargo test -p nanosb-cli`; manual TUI launch with a supervisor sandbox attaches
  and streams (see §6).

### Phase T3 — Project mount + deploy-plan wiring for TUI panels

- Reuse the host-side SDK `setup_project_mount` (in `sandbox/crates/sandbox/src/sandbox.rs` 428)
  to obtain mounts for a TUI panel when `--project`/`sandbox.yml project` is set.
- Feed the resulting `ProjectMount.mount_config("/workspace")` into the supervisor deploy plan
  so the same virtiofs share the CLI uses is present. Persist the `ProjectMount` on the panel
  (keep field) so gitsync status/Edit keep working.
- `Command::GitSync` (2351 area): works unchanged once `panel.project_mount` is populated.
- Verify: gitsync status prints branch; `/edit` resolves `worktree_base`.

### Phase T4 — Upload via virtiofs

- `src/tui/upload.rs`: add `fs_upload(mount_root: &Path, remote_path: &str, data: &[u8])`
  writing host-side with `create_dir_all` + `fs::write`.
- `spawn_upload`/`spawn_bytes_upload`: replace `(ssh_host, ssh_port, key_path)` params with
  `mount_root: Option<PathBuf>`; when `None`, emit `UploadFailed` with "no project mount".
- Delete `UploadSshHandler` + `ssh_upload` + `russh` import in `upload.rs`.
- Update all call sites: `spawn_file_upload` (run.rs 2803, call 2828), bytes upload (run.rs 2892),
  and `panel_ssh_info` (run.rs 2729) which becomes `panel_mount_root`.
- Verify: upload a file to a supervisor panel; assert file appears under the mount.

### Phase T5 — Remove remaining SSH from terminal.rs

- Delete `connect_ssh` (173), `SshHandler` (151), `SshTerminalHandle::noop` (434) if unused.
- Update `agent_env_vars` docstring (537) to reflect console-only.
- Remove `ssh -L` port-forward machinery: `port_forward_children`, `forwarded_ports`,
  `ssh -L` spawning (774, 2165), OAuth `ssh -L` (787). Replace OAuth with gvproxy port note.
- Delete `ssh_host_port`/`ssh_host`/`ssh_key_path` fields from `Panel` (app.rs 317-321, init 387).
- Move `agent_env_vars` application into the supervisor boot command/env (already partly there
  via `config.command`/`config.env`).
- Verify: `grep -rn "russh\|connect_ssh\|ssh -L" src/tui/` returns nothing.

### Phase T6 — Cleanup + docs

- Root `Cargo.toml`: remove `russh` + `ssh-key` **only if no other crate uses them**
  (verify with `cargo tree`/grep; `sandbox` may).
- Update README TUI notes (SSH references) and `runtime/docs/zero-image-customization-security.md`.
- Run `cargo fmt`, `cargo clippy`, full test suite.

## 5. Out of Scope (this plan)

- Deleting `sandbox/crates/gateway` (still consumed by ffi.rs, agent_sandbox.rs, sandbox.rs).
- SDK/FFI `sandbox_exec` semantics change.
- `nanosb exec` for supervised sandboxes (tracked separately; needs an exec side-channel).
- Renaming `SshTerminal*` / `SshConnected` / `SshDisconnected`.
- The three original open questions (APFS virtiofs volume; image digest pinning + cosign;
  secret delivery SSH-post-boot vs vsock-at-boot).

## 6. Acceptance Criteria (evidence-based)

- AC1: `cargo test -p nanosb-cli` and `-p sandbox` pass; `cargo build -p nanosb-cli` clean.
- AC2: `grep -rn "gateway()\|russh\|connect_ssh" src/tui/` returns zero hits.
- AC3: Launch TUI, spawn a panel: `panel.backend == Supervisor`, console output streams into
  the panel (visible text), input echoes back.
- AC4: Reconnect (`Command::Reconnect`) re-attaches console without SSH; no "No sandbox running"
  error for a live supervisor.
- AC5: With `--project`, `Command::GitSync` prints a branch; `/edit` opens `worktree_base`.
- AC6: Upload a file to a supervisor panel: file exists under the mount; oversized file →
  `UploadFailed` with the size message.
- AC7: Kill a panel: supervisor is stopped (no orphan process in `nanosb ps`).
- AC8: Exit code from the sandbox propagates to panel disconnect reason.

## 7. Risks

- R1 (high): Project mount wiring for TUI panels is the blocker; if `setup_project_mount`
  cannot run before the supervisor (VM) exists, D1 default fails and we must spawn the
  supervisor first, then materialize mounts — sequencing must be validated in T3 before T2
  lands. **Mitigation: prototype T3 mount acquisition first; if it needs the VM, fold mount
  planning into `spawn_supervisor` as the CLI already does.**
- R2 (med): Losing SSH removes the only current upload + OAuth path. T4/T5 must land together
  or uploads break silently.
- R3 (med): `SshDisconnected` naming reuse may confuse future readers — accept (D6).
- R4 (low): `russh` may still be needed by the `sandbox` crate, so root dep removal (T6) may
  be a no-op.

## 8. Sign-off Items (user)

- D1 project mount behavior
- D2 upload replacement
- D3 OAuth degradation
- D4 auto-mode semantics
- Confirmation that gateway-crate deletion + `nanosb exec` are correctly deferred.

## 9. Manual TUI verification (Phase 8 / G9) — pending human run

The TUI console-attach path is compiled and unit-tested, but has **not** been
opened against a live supervised sandbox on a real terminal. Run the checklist
below and record pass/fail. Requires an interactive terminal (macOS) and a
supervised sandbox image.

### Prerequisites
```bash
cargo build -p nanosb-cli
docker compose -f agents-registry/docker/docker-compose.yml up -d
./target/debug/nanosb pull localhost:5050/claude:latest
```

### Checklist
1. **Attach (AC3)** — launch `./target/debug/nanosb` (TUI); spawn a panel.
   Expect: panel shows `Supervisor` backend, console output streams live,
   keystrokes echo back.
2. **Reconnect (AC4)** — `/reconnect`. Expect: re-attaches console, no
   "No sandbox running" error for a live supervisor.
3. **Kill stops supervisor (AC7)** — `/kill`. Expect: supervisor stops; the
   sandbox disappears from `./target/debug/nanosb ps -a` (no orphan).
4. **Project mount / gitsync (AC5)** — launch with `--project <dir>`; `/gitsync`
   prints a branch; `/edit` resolves the clone dir.
5. **Upload (AC6)** — `/upload <file>`. Expect: file appears under the mounted
   workspace; oversized file → `UploadFailed` with the size message.
6. **Exit code (AC8)** — run a command that exits non-zero; expect the panel's
   disconnect reason to carry the code.

### Result
- Status: **NOT RUN** (requires human at a terminal).
- Recorded by / date: _pending_.
- Failures: _none recorded yet_.

