# Plan: Remove the in-VM agent-gateway entirely

Status: reviewed (Momus APPROVE, 2026-10-06) — minor notes folded: secrets/mod.rs
re-export, ignored gateway integration tests, PanelBackend::Legacy scoped out.
Date: 2026-10-06
Branch: feat/zero-image-customization
Related: runtime/docs/plans/2026-10-06-close-remaining-gaps-plan.md (Phase 7),
         runtime/docs/plans/2026-10-05-tui-supervisor-migration-plan.md

## Goal
Delete the agent-gateway subsystem completely: the `gateway` Rust crate, every
consumer in the `sandbox` SDK, the legacy (non-next) boot path that exists only
to talk to the gateway, and the FFI exec/message surface built on it. After this,
nanosandbox has exactly one runtime mode (next/console) and no in-guest server.

## Decisive finding (verified 2026-10-06)
**No in-repo code boots legacy mode.** `src/main.rs`, `src/tui/**`, and
`src/supervisor/mod.rs` all force `RuntimeMode::Next`. `Sandbox::start()`
(`sandbox/crates/sandbox/src/sandbox.rs:170`) enters the gateway path only when
`runtime_mode != Next` — i.e. only the `Default` (`Legacy`) value, which nothing
in-repo sets. The gateway is therefore **dead in this repo**, kept alive only by:
- the SDK/FFI public surface (external consumers), and
- `RuntimeMode::Legacy` remaining the `Default`.

So this is "delete dead subsystem + public ABI," not "migrate live code."

## Blast radius (verified)

| Site | What it uses | Action |
|---|---|---|
| `sandbox/crates/gateway/**` (1211 LOC, 7 files) | the crate itself | **delete** |
| `Cargo.toml:8` | workspace member | remove |
| `sandbox/crates/sandbox/Cargo.toml:24` | `gateway = {path}` | remove |
| `sandbox/src/lib.rs:39-40` | re-exports (`GatewayClient`, `ExecOptions`, `ExecResult`, `OutputChunk`, `Stream`, `encrypt_payload`, `EncryptedPayload`, `SecretManifest`) | remove |
| `sandbox/src/sandbox.rs` | `gateway` field, `gateway()`, `gateway_mut()`, gateway detection/setup/health/secrets keypair, `ssh_key_path`, `ssh_port/host`, `cleanup_ssh_keys` | delete gateway; keep next path |
| `sandbox/src/ffi.rs:224,298` | `sandbox_exec`, `sandbox_exec_stream` → `gateway().exec*` | **remove the two FFI functions** (see D2) |
| `sandbox/src/ffi.rs:337-338` | `gateway::OutputChunk`/`Stream` in stream callback | remove with the fn |
| `sandbox/src/agent_sandbox.rs:74` | `send_message` → `gateway().http_post_sse` | **remove method** (see D2) |
| `sandbox/src/secrets/crypto.rs` | `pub use gateway::secrets::{…}` | reimplement locally or delete (see D3) |
| `sandbox/src/secrets/mod.rs:5` | `pub use crypto::encrypt_payload;` | update/remove with crypto.rs |
| `runtime/crates/runtime/tests/integration_test.rs` (~1280-1840) | `test_cursor_ssh_and_gateway`, `e2e-gateway-test` (`#[ignore]`) | delete/update these ignored tests |
| `src/tui/app.rs` `PanelBackend::Legacy` | holds a `Sandbox` | follow-up in the TUI migration plan (not this one) |
| `sandbox/src/secrets/*` | `SecretPayload`, `SecretManifest` | keep payload; drop crypto if unused |
| `runtime` config `RuntimeMode` | `Legacy` is `Default` | flip `Default` to `Next` (see D1) |
| docs | `agents-registry/docs/.../agents-registry-design.md`, old plans | add "superseded" notes; don't rewrite history |

No `.py`/`.js`/`.go`/`.ts` SDK bindings exist in this repo — external bindings
are out of tree (see D2/§External impact).

## Phases

### Phase 1 — Make next mode the only mode (runtime)
- `runtime/crates/runtime/src/config/mod.rs`: change `RuntimeMode` `Default`
  from `Legacy` to `Next`; keep the enum (serialized configs reference it) but
  mark `Legacy` deprecated.
- Remove `Sandbox::start()`'s legacy branch: the whole `has_gateway` detection,
  port 8080/22 mapping, `nanosb-init.sh`/`agent-gateway` rootfs probing
  (`sandbox.rs:170-360`). `start()` becomes a thin wrapper over `start_next()`.
- Delete now-unused fields: `gateway`, `ssh_port`, `ssh_host`, `ssh_key_path`
  and their methods.
- AC1.1 `Sandbox::start()` no longer references gateway; next boot unchanged.
- AC1.2 No `RuntimeMode::Legacy` path remains reachable in-repo.

### Phase 2 — Remove gateway from the SDK crate
- Delete `sandbox/src/secrets/crypto.rs` re-export; either inline a minimal
  `encrypt_payload`/types or delete if no next-mode consumer (verify first).
- Remove `sandbox.rs` gateway field/accessors and all gateway calls
  (`generate_ssh_keys`, `inject_pubkey_into_rootfs`, `GatewayClient::new`,
  `cleanup_ssh_keys`, `wait_for_health`).
- Remove `lib.rs` gateway re-exports.
- AC2.1 `grep -r "gateway" sandbox/crates/sandbox/src` → only comments/none.
- AC2.2 `cargo build -p sandbox` + `--features ffi` clean.

### Phase 3 — Remove the gateway-dependent FFI + SDK methods (ABI decision D2)
- Remove `sandbox_exec`, `sandbox_exec_stream`, `ExecStreamCallback`.
- Remove `agent_sandbox.rs::send_message`.
- Update `lib.rs` re-exports (`ExecOptions`/`ExecResult`/`Stream`/`OutputChunk`).
- AC3.1 FFI still exports the lifecycle set (`sandbox_create/start/stop/destroy/
  status/free`, `image_*`, `free_string`, `version`, `validate_runtime`).
- AC3.2 No remaining symbol references gateway types.

### Phase 4 — Delete the crate + workspace wiring
- Delete `sandbox/crates/gateway/`.
- Remove workspace member (`Cargo.toml:8`) and dep (`sandbox/Cargo.toml:24`).
- AC4.1 `cargo build --workspace` clean; `cargo tree` shows no `gateway`.
- AC4.2 `cargo test -p sandbox -p runtime -p nanosb-cli` green.

### Phase 5 — Header/docs/examples
- Remove `//! Gateway crate` docs; note removal here and in
  `zero-image-customization-security.md`.
- Mark `agents-registry-design.md` agent-gateway sections as superseded.
- AC5.1 No live doc describes the gateway as current.

## Decisions required (sign-off)

- **D1 — Flip `RuntimeMode::default()` to `Next`.**
  Recommended: yes. It makes the removal complete and matches all in-repo
  callers. Risk: any external tool that omits `runtime_mode` currently gets
  legacy; after the flip it gets next. Since legacy is being deleted, this is
  the intended direction — but it is a behavior change for external callers.

- **D2 — FFI/ABI break: remove `sandbox_exec` and `sandbox_exec_stream`.**
  This is the crux. They are **public C ABI** used by out-of-tree SDKs
  (Python/Node/Go). Removing them is a **breaking change**. Options:
  - **(a) Remove them** (recommended if no shipping external consumers).
    Cleanest; the security review already concluded a next-mode exec channel is
    net-negative, so there is no replacement to offer.
  - **(b) Keep the symbols but make them return a clear error**
    ("exec is not supported in next mode") — preserves ABI, no gateway needed.
    Zero-in-guest. Non-breaking.
  - **(c) Keep the symbols backed by a stub** that errors; deprecate in docs.
  Need the user to choose; (b) is the safe default if external consumers exist.

- **D3 — Secrets crypto re-export.**
  `secrets/crypto.rs` re-exports `gateway::secrets::{encrypt_payload,…}`.
  Recommended: delete it if nothing in next mode uses encryption (secrets now
  travel via the supervisor process env, not encrypted payloads). Verify with
  `grep` before deleting; otherwise inline the two functions.

- **D4 — `SecretManifest`/secrets surface.**
  `lib.rs` re-exports `encrypt_payload`, `EncryptedPayload`, `SecretManifest`.
  Confirm none are part of a documented external SDK contract before removal.

## Risks
- R1. **External SDK breakage** — the real risk. Mitigate per D2(b) if any
  consumer exists. Cannot be verified from this repo.
- R2. **Hidden legacy usage via serialized configs** — a stored `config.json`
  with `"runtime_mode":"legacy"` would now hit a deleted path. Mitigate: keep
  deserializing `Legacy` but map it to `Next` with a `warn!`, rather than error.
- R3. **Secrets crypto used elsewhere** — verify before deleting (D3).
- R4. **Docs elsewhere reference the gateway** — sweep at the end.

## Out of scope
- Building any next-mode exec replacement (rejected in the prior plan on
  security grounds; see Phase 7 of the gap-closure plan).
- Rewriting old plan documents (annotate, don't rewrite).

## External impact (must confirm before Phase 3)
The published multi-language SDK bindings may call `sandbox_exec`. This repo
cannot see them. **Before deleting the ABI, confirm with the user whether any
external SDK ships today.** If yes → D2(b). If no → D2(a).

## Verification (end state)
- `cargo build --workspace` clean; no `gateway` anywhere (`grep`, `cargo tree`).
- `cargo test -p sandbox -p runtime -p nanosb-cli` green.
- E2E: `apply`/`run --next`/`restart`/`logs`/`attach` still work.
- FFI exports: lifecycle intact; exec either gone (D2a) or erroring (D2b).
- Security checklist updated: no in-guest server remains.
