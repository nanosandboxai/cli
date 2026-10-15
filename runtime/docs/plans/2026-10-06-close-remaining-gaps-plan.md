# Plan: Close Remaining Gaps (post user-env / secret-splitting work)

Status: reviewed (Momus APPROVE, 2026-10-06). Decisions resolved 2026-10-06:
D1 = re-source (manifest or recorded CLI recipe), D2 = warn-and-buffer,
D3 = REVISED: do NOT build the exec side-channel (security verdict); gateway stays legacy-scoped.
D4 = G1 -> G8 -> G4 -> G2 -> G3 -> G7 -> (G5/G6 closed by verdict) -> G9.
Date: 2026-10-06
Branch: feat/zero-image-customization
Related: runtime/docs/plans/2026-10-05-tui-supervisor-migration-plan.md,
         runtime/docs/zero-image-customization-security.md

## Context

Recent work added: `--user`/`--home` (guest privilege drop), `--run-as-root`
collapsed into `user`, agent sandboxes defaulting to `developer`, `--format json`
for `nanosb run`, `-f` console streaming, and secret env splitting (secrets no
longer persisted to `config.json`/`deploy.json`/argv).

That work left gaps. This plan closes them, ordered by risk.

## Gap inventory (verified against source)

| # | Gap | Severity | Evidence |
|---|-----|----------|----------|
| G8 | No automated tests for new work | High | `--user`/`--home` resolution, `extract_boot_env`, JSON output have zero CI-runnable tests; verified by hand only |
| G1 | `nanosb restart` drops secrets | High | `cmd_restart` reads persisted `config.json` (env now `{}`) and spawns with `"{}"` boot env → restarted guest has no API keys |
| G4 | `--home` not validated / not created | Medium | `configure_and_start_vm_next` sets `KRUN_HOME` but never creates the dir or checks it |
| G2 | `--format json` + `-f` silently buffers | Medium | JSON mode ignores `follow`; undocumented |
| G3 | Name lookup needs guest `/etc/passwd`; error path untested | Medium | `resolve_guest_user` reads `rootfs/etc/passwd`; missing-file branch untested |
| G5 | SDK/FFI legacy gateway surface inconsistent | In scope | `sandbox_exec`/`_stream`/`send_message` still gateway-based; public ABI |
| G6 | `gateway` crate still a workspace member | In scope | removed once G5 lands |
| G7 | `run_as_root` config field redundant | Low | kept for sandbox.yml/ABI compat; deprecation not bug |
| G10 | Secret in caller's own `-e` argv | Accepted | inherent to CLI; documented |
| G11 | Secret printed by guest lands in `console.log` | Accepted | unavoidable; documented |
| G9 | TUI attach never opened on a real terminal | Deferred | compiled + unit-tested only |

---

## Phase 1 — G1: restart without losing secrets

**Problem.** `restart` has no source for secrets. `start` (from `apply`/`run`)
does, because it re-reads `sandbox.yml`/`--env`. `restart` only has `deploy.json`.

**Decision (D1, resolved).** Restart must **re-source** secrets, never persist
their values. Two origins:

- **Case A — created by `apply`:** the declared `sandbox.yml` is the source;
  restart re-reads it and re-resolves env against the current host env / `.env`.
- **Case B — created by `nanosb run --name X -e KEY` (no manifest):** there is
  no manifest, so persist the **recipe, not the value**: record origin metadata
  (arg names, `--env-file` path, image/command/user) in `state.json`; restart
  re-reads those keys from the current host env / recorded env-file.

Values are never written to disk (preserves R4). This mirrors Docker/Compose:
config carries the reference, the host holds the value, each start re-reads it.

### Steps
1. Record origin metadata in `state.json` at spawn time (both `apply` and `run`):
   `source: "manifest" | "cli"`, env **key names**, `env_file` path(s), and the
   config already stored. Extend `SupervisorState` (or a sibling `origin.json`,
   0600) — no secret values.
2. `cmd_restart`:
   - Case A: locate the declaring `sandbox.yml` (discovery as `apply`:
     `--project`/CWD/`--config`), rebuild via `deploy_plan_for`, re-derive
     `rc` + `boot_env_json`.
   - Case B: re-resolve the recorded key names from the current host env /
     recorded `--env-file`.
3. Missing source or missing key at restart → clear non-zero error naming the
   key; `--allow-no-env` proceeds keyless (explicit opt-in).
4. Update `runtime/docs/zero-image-customization-security.md` with restart
   semantics.

### Explicit consequence (accepted)
`restart` of a `run`-created sandbox now depends on the host still providing the
env keys (or the recorded `--env-file`). Inline `-e KEY=<literal>` values cannot
be recovered — same sharp edge as Docker `${VAR}` — surfaced as a named error.

### Acceptance
- AC1.1 `apply` → run agent with key → `restart` → guest still has the key
  (check: `restart`, then `logs`/`attach` and `env | grep ANTHROPIC_API_KEY`).
- AC1.2 `run -e KEY` (host env has KEY) → `restart` → guest still has KEY.
- AC1.3 `restart` with no recoverable source/key → non-zero exit + names the key.
- AC1.4 `restart --allow-no-env` → boots, guest env empty.
- AC1.5 no secret value appears in `config.json`, `deploy.json`, `state.json`,
  `origin.json`, or supervisor argv after any of the above.

---

## Phase 2 — G8: tests for the new behavior

**Problem.** Everything added was verified by hand against a live VM + API key;
nothing runs in CI.

Two tiers:

### 2a. Pure/unit tests (CI-runnable, fast)
Make these functions testable without a rootfs:
- `resolve_guest_user(rootfs_path, spec, home_override)` — refactor to take a
  `&Path` rootfs and test against a temp dir with a fixture `etc/passwd` +
  `etc/group` (this is an **in-place refactor of the existing function**, not a
  new one; the colon/empty spec parsing currently inline in it is extracted —
  there is no existing `parse_user_spec`).
  - name → uid/gid/home from passwd
  - `uid:gid` numeric passthrough
  - `name:groupname` → group name resolved via `/etc/group`
  - uid-only numeric → gid/home backfilled from passwd
  - unknown name → error
  - empty / malformed spec → error
- `extract_boot_env(config_json)` (`src/deploy.rs`)
  - env removed from config; env returned separately
  - config with no env → `{}`
  - round-trip: config parses without env, env parses as map
- `deploy_plan_for` agent default
  - agent config, no `user`/`run_as_root` → `user=developer`, `home=/home/developer`
  - explicit `user` preserved
  - `run_as_root=true` → not overridden to developer
- JSON output shape: only if the JSON object construction is **extracted into a
  testable helper** (e.g. `fn run_result_json(...) -> serde_json::Value`) in
  `src/main.rs` or `src/deploy.rs`; otherwise it is not covered (the 2b tests do
  not assert JSON) — decide during Phase 2.

### 2b. Integration tests (ignored, require VM)
Extend `runtime/crates/runtime/tests/next_mode_test.rs` (uses the in-process
`handle_boot_vm_subprocess` pattern + `#[ignore]`; run via
`cargo test -p runtime --test next_mode_test -- --ignored`):
- `test_next_mode_user_drop`: boot alpine with `user=1000`, assert `id` output
  shows uid 1000 and `HOME` is set.
- `test_next_mode_user_name_resolution`: image with a passwd entry; assert
  resolved uid.
- `test_next_mode_bad_home`: `--home /nonexistent` → defined, tested behavior
  (see G4) — **finalize this test after Phase 3 defines the behavior**.

### Acceptance
- AC2.1 `cargo test -p runtime` (unit) covers the runtime-crate §2a cases
  (`resolve_guest_user`), green, no VM.
- AC2.2 `cargo test -p nanosb-cli` covers `extract_boot_env` + `deploy_plan_for`
  defaults (+ JSON helper if extracted).
- AC2.3 `cargo test -p runtime --test next_mode_test -- --ignored` passes with VM.

---

## Phase 3 — G4: validate/create `--home`

**Problem.** `--home /nope` sets `KRUN_HOME=/nope`; nothing creates it; agent
fails obscurely.

### Steps
1. In `configure_and_start_vm_next`, when `KRUN_HOME` is set and the dir does not
   exist under the rootfs, create it (`rootfs/<home>`, mode 0755) and, when a
   uid is set, best-effort `chown` is unnecessary on macOS virtiofs — instead
   rely on the dir being world-readable/executable.
2. Validate `--home` is absolute; reject relative paths at config build time
   with a clear error.
3. Document `--home` semantics (default `/home/<user>` for names; passwd home for
   numerics when available).

### Acceptance
- AC3.1 `--user developer --home /custom/home` boots; `HOME=/custom/home` and the
  dir exists in guest.
- AC3.2 `--home relative/path` → error before spawning.
- AC3.3 no `--home` + `--user 1000` (passwd has `/home/developer`) → that home.

---

## Phase 4 — G2: document/align `--format json` + `-f`

**Problem.** In JSON mode `-f` is ignored; output is buffered into `output`.

### Steps (pick per §Sign-off D2)
- **Option A (recommended):** keep buffering, but emit a one-line warning to
  stderr when `--format json` and `-f` are both given:
  `warning: --follow is ignored in json mode (output captured in "output")`.
- Option B: stream `output` as NDJSON events and a final summary object (larger,
  changes the contract).

### Acceptance
- AC4.1 `run --format json -f` → warning on stderr, single JSON object on stdout.
- AC4.2 `run --format json` (no `-f`) → unchanged.

---

## Phase 5 — G3: harden name resolution errors

### Steps
1. When `--user <name>` is given and `rootfs/etc/passwd` is missing/unreadable,
   return a specific error: `cannot resolve user 'x': guest has no /etc/passwd
   (use a numeric uid, e.g. --user 1000)`.
2. Unit tests for that branch (Phase 2a).

### Acceptance
- AC5.1 `--user alice` against a rootfs without passwd → actionable error.
- AC5.2 numeric `--user 1000` on the same rootfs → still works (no passwd needed).

---

## Phase 6 — G7: deprecate `run_as_root`

### Steps
1. Mark `SandboxConfig.run_as_root` deprecated in rustdoc and `sandbox.yml`
   docs; keep deserialization for ABI/back-compat.
2. Emit a one-time `warn!` when `run_as_root=true` is seen, pointing to `user`.

### Acceptance
- AC6.1 `sandbox.yml` with `run_as_root: true` still boots as root + logs a
  deprecation warning.

---

## Phase 7 — G5/G6: FFI exec side-channel — REVISED (security verdict: do NOT build)

**Superseded.** A spike + architecture review concluded that adding a next-mode
exec channel is **net-negative for security** and should not be implemented.
See "Security verdict" below. The original steps (an in-guest exec relay on a
virtio-console port, or console multiplexing) would have reintroduced a
privileged in-guest server — the exact thing zero-image-customization removed.

### Security verdict (2026-10-06)
`sandbox_exec` is arbitrary guest-side command execution **inside the VM** — it
does not cross the boundary. The agent can already run everything exec would.
So exec adds no capability; it only adds **a new host→guest root-execution
channel** plus **a standing in-guest listener**. Both are inside the blast radius
yet widen the privileged attack surface and re-introduce the agent-gateway shape
the migration deliberately deleted. Benefit is SDK convenience only; the CLI/TUI
do not need it.

### What to do instead (the accepted scope of this phase)
1. **Do not add an exec relay.** No new in-guest listener, no console muxing.
2. **Leave the SDK exec on the legacy gateway path**; legacy images still need
   it. `gateway` stays a dependency (deletion is not justified while legacy mode
   exists and its consumers are public ABI).
3. **If exec is ever needed for next mode**, it must be an explicit,
   off-by-default per-sandbox opt-in (`--enable-exec`) that installs a
   least-privileged, per-call mechanism — never a default standing channel.
4. Record this rationale so the direction is not silently reversed later.

### Acceptance (revised)
- AC7.1 No in-guest exec listener is added; default next-mode posture remains
  "one console stream, no in-guest server".
- AC7.2 `gateway` remains feature-scoped for legacy; no ABI change.
- AC7.3 This rationale is captured in the plan + security checklist.
- ~~AC7.1–7.4 (original exec implementation)~~ withdrawn.

### Original plan (kept for reference, NOT executed)
1. Side-channel via supervisor `ControlRequest::Exec` + streamed frames.
2. In-guest delivery (console marker framing, or dedicated virtio-console port
   with an init-side relay).
3. Rewire `sandbox_exec`/`sandbox_exec_stream` off `gateway().exec*`.
4. `agent_sandbox.rs::send_message` over the new path.
5. Remove the `gateway` crate.

---

## Phase 8 — G9: TUI manual verification

### Steps
1. Script/manual checklist for opening the TUI against a supervised sandbox and
   confirming console attach, reconnect, kill-stops-supervisor (AC3/4/7 of the
   migration plan).
2. Record result in the migration plan's status.

---

## Risks

- R1. **G1 re-source may pick up a *changed* secret** — restart after editing
  `.env` boots with the new value. Acceptable and arguably correct; document it.
- R2. **Refactoring `resolve_guest_user` for tests** touches the boot path —
  keep signature stable; add a thin `rootfs: &Path` core the caller already has.
- R3. **G4 creating dirs in rootfs** mutates the image cache rootfs — scope it to
  the per-sandbox rootfs copy, never a shared layer.
- R4. **Integration tests need a VM + entitlement**; keep them `#[ignore]` so CI
  stays green without one.

## Out of scope
- Rotating credentials (user action).
- Windows/archived track.
- Nested container runtimes (podman/kubectl) — separate track; noted at the
  bottom of this document.

## Sign-off items (resolved 2026-10-06)
- **D1 — RESOLVED:** restart re-sources secrets (manifest for `apply`; recorded
  key-names/env-file for `run`); never persists values; errors if unresolved.
- **D2 — RESOLVED:** warn-and-buffer. Emit a stderr warning when `--format json`
  and `-f` are both set; keep single-object output.
- **D3 — REVISED (2026-10-06):** do **not** implement the FFI exec side-channel.
  A security review concluded it is net-negative (adds a privileged host→guest
  root-exec channel + a standing in-guest listener for SDK convenience only).
  `gateway` stays legacy-scoped; no new in-guest server. See Phase 7.
- **D4 — RESOLVED:** order = G1 → G8 → G4 → G2 → G3 → G7 → G5/G6 → G9.

## Appendix — future track: tool runtime (not in this plan)

Discussed but explicitly deferred. Summary of findings for the follow-up:

- **Tier 0 (works now):** run container *clients* (kubectl, helm, terraform) as
  workloads — no runtime change; kubeconfig/creds are files → the secrets/mount
  model. Document-only.
- **Tier 1+ (needs libkrunfw fork):** running podman/Docker *inside* the guest
  requires kernel features that are currently **off** in
  `runtime/deps/libkrunfw/config-libkrunfw_aarch64`:
  `# CONFIG_NETFILTER is not set`, `# CONFIG_BRIDGE is not set` (cgroups,
  namespaces, overlayfs, seccomp, veth **are** enabled).
- Hence nested containers = rebuild firmware (netfilter/nftables/conntrack/
  bridge) + writable disk for overlay storage + CNI/port-forward work. Multi-
  week, diverges from the thin-runtime philosophy. Decide demand first.
- **Shared dependency:** file-based Docker/Compose-style `secrets:` mounts at
  `/run/secrets` benefit both the agent track and any tool track — worth doing
  before tool work, not as part of it.
