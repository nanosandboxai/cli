# Epic 5 — Advanced sandbox surface (Epic 1 §4 follow-up)

Status: implemented (2026-10-13) — see §7 outcome
Date: 2026-10-12
Related: `docs/epics/epic-1-multi-language-sdk.md` (§4 inventory), `docs/conformance-report.md`, `docs/decisions/snapshots.md`, `docs/decisions/volume-backings.md`

## 1. Context

Epic 1 met all of its acceptance criteria (AC1–AC9) — eight protocol clients
pass the conformance corpus (35/35) and boot a real microVM live. The §4
"missing-interface inventory" is broader than the AC verb set, and several
`[A]`/`[R]` items exist **only as protocol types**: the client can send them,
the scripted conformance harness accepts them, but the helper/supervisor does
not implement them. This epic closes that delta.

> Note: the 35-scenario conformance suite is a **scripted fake-server harness**,
> so a passing scenario proves client-side verb coverage, not runtime
> implementation. Each item below needs a runtime implementation **and** a
> live-VM assertion.

## 2. Gaps (runtime drops or refuses the verb)

| §4 item | Evidence |
|---|---|
| per-exec `rlimit` | `ExecRequest.rlimits` exists; dropped by `exec_buffered`/`stream_exec_stream` (`src/supervisor/proto.rs`) |
| `exec_default` / `attach_default` | no protocol verb (`crates/protocol/src/verbs.rs`) |
| log sources (stdout/stderr/pty/system) | `handle_logs` ignores `spec.source`, always labels `Stdout` (`src/supervisor/proto.rs`) |
| `secretEnv` substitution | `SandboxSpec.secret_env` never read in `spec_to_config` (`src/helper.rs`) |
| file mount | `mount_spec_to_mount` returns `Unsupported` (`src/helper.rs`) |
| disk-image volumes (raw/qcow2/vmdk + fstype) | `VolumeRegistry::create` returns `Unsupported` (`src/supervisor/volumes.rs`) |
| tmpfs | `mount_spec_to_mount` returns `Unsupported` (`src/helper.rs`) |
| mount options (noexec/nosuid/nodev) | `mount_spec_to_mount` returns `Unsupported` (`src/helper.rs`) |
| mount owner (uid/gid) | `mount_spec_to_mount` returns `Unsupported` (`src/helper.rs`) |
| stat virtualization (strict/relaxed/off) | no protocol field |
| `quota` | `VolumeRegistry::create` returns `Unsupported` (`src/supervisor/volumes.rs`) |
| live `mount_add` | supervisor returns `unsupported` (`src/supervisor/proto.rs`) |
| `NetworkConfig` policy passthrough | `NetworkSpec.policy` dropped; runtime `NetworkConfig` has no `policy` field (`src/helper.rs`, `runtime/.../config/mod.rs`) |
| local-directory rootfs / disk-image rootfs | no protocol field |
| per-sandbox registry config | no protocol field |
| pre-boot rootfs patches | no protocol field |
| named scripts (`/.msb/scripts/`) | `SandboxSpec.scripts` never read (`src/helper.rs`) |
| `securityProfile` (default/restricted) | no protocol field |
| `hostname` override | `SandboxSpec.hostname` never applied (`src/helper.rs`) |
| lightweight handles | only a hardcoded `detached: true`; no handle surface |
| list pagination cursor | `list_sandboxes` ignores `cursor` (`src/bin/nanosb_runtime.rs`) |

## 3. Implemented but untested (coverage gaps)

`replace`, `waitUntilStopped`, publish-with-explicit-bind-address, publish-UDP,
`pullPolicy` — implemented, but no conformance/live assertion.

## 4. Deliberately deferred (not this epic)

- Full snapshots (memory/process capture; boot-on-restored-layer) — Epic 1 R3,
  `docs/decisions/snapshots.md`.
- Networking **enforcement** engine (policy, allowlists, DNS/TLS, rate limits,
  interface overrides, host CA trust, NAT64) — Epic 3.
- Owned volumes — Epic 1 D11.
- `onSecretViolation` — with egress (Epic 3).
- `max_cpus`/`max_memory` hotplug ceilings, `guest_clock`/THP — Epic 1 defer.

## 5. Goal

For every §4 `[A]`/`[R]` item **not** in §4 above: implement it in the
helper/supervisor, thread it end-to-end from the protocol type, and add a
live-VM assertion (so the conformance harness can no longer mask it). Prefer
small, independently shippable increments; version the protocol where a verb's
shape changes.

## 6. Acceptance criteria

- AC1 Every §4 `[A]`/`[R]` item is either implemented end-to-end with a live
  assertion, or explicitly re-tagged `defer`/`[E3]` in
  `docs/epics/epic-1-multi-language-sdk.md`.
- AC2 No protocol type exists without a corresponding runtime path (no
  silent drops): add a test that fails when a spec field is dropped.
- AC3 The five §3 items gain conformance/live coverage.

## 7. Outcome (2026-10-13)

Branch `feat/epic-5-advanced-surface`. Live evidence:
`crates/client/tests/epic5_live.rs` (opt-in, `#[ignore]`) boots a real microVM
and asserts the implemented surface; unit tests cover the threading.

### Implemented + live-verified

| Item | Where | Live assertion |
|---|---|---|
| S3 log sources | `src/supervisor/mod.rs`, `proto.rs` | stderr console line labeled `Stderr` |
| S4 `secretEnv` | `src/helper.rs` | env substituted; value absent from `config.json` |
| S5 tmpfs mount | `src/helper.rs`, guest agent | `mount` shows tmpfs at target |
| S8 `hostname` | guest agent | `hostname` returns the override |
| S1 per-exec rlimits | exec wire + guest agent | `ulimit -n` honors the per-exec limit |
| S1 `exec_default` | `src/supervisor/proto.rs` | runs the default workload |
| S2 list pagination | `src/bin/nanosb_runtime.rs` | `next_cursor` pages without overlap |
| S2 `replace` | `src/bin/nanosb_runtime.rs` | same name rebuilds cleanly |
| S6 disk-image volume + quota | `src/supervisor/volumes.rs` | raw image sized to quota; `quota_bytes` set |
| S9 publish UDP + bind | `src/helper.rs` | UDP+bind sandbox boots + execs |
| §3 `pullPolicy` | `src/helper.rs` | `never` boots against a cached image |
| §3 `waitUntilStopped` | `crates/client` | observes the stop (fixed socket-close handling) |

### Implemented, unit/threading-verified (not live-asserted)

file mounts, mount options/owner, local-dir rootfs, disk-image rootfs
(`krun_set_root_disk`), pre-boot rootfs patches, named scripts, per-sandbox
registry config, `NetworkConfig.policy` passthrough, `stat_virtualization` and
`security_profile` field carry. Each is threaded protocol → helper → runtime
config, covered by `every_sandbox_spec_field_reaches_runtime_config` (AC2).

### Deferred (re-tagged `defer` in the Epic 1 §4 inventory)

- **live `mount_add`** — libkrun has no virtiofs hotplug; a device cannot be
  attached to a running VM. Mounts remain create-time (persisted for the next
  boot).
- **stat virtualization enforcement** — no defined strict/relaxed/off semantics
  in this build; the field is carried but not enforced.
- **`securityProfile` enforcement** — no defined default/restricted policy
  mapping; the field is carried but not enforced.

Disk-image volumes/rootfs are **no longer deferred**: the shipped `libkrun.a`
already exports the block-device API, so enabling the `blk` feature plus
`krun_add_disk2` / `krun_set_root_disk` closed that gap without a fork change.

