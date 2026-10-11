# Decision — Snapshots shipped in Epic 1

Status: accepted (2026-10-11)
Related: `docs/epics/epic-1-multi-language-sdk.md` §WS6 / AC6, risk R3.

## Context

Epic 1 (D8) places **full snapshots** (writable layer + manifest; `restore` +
`fork`) in scope, with `pause`/`resume`. R3 warns that full writable-layer
capture on libkrun may prove disproportionate and permits a **disk-only
fallback** (memory/process state out of scope).

The protocol and every SDK already expose `snapshot_create`/`list`/`restore`/
`fork`/`remove`; the helper previously answered `unsupported`.

## Decision

Ship a **disk-only snapshot store** (`src/supervisor/snapshots.rs`), served
directly by the helper daemon:

- A snapshot captures the sandbox's **on-disk writable state** (its config plus
  any persisted files/dirs under the sandbox directory) into
  `$NANOSB_HOME/snapshots/<id>/state/` plus a `manifest.json` (id, sandbox,
  base image, timestamp, `includes_memory: false`) and a content hash.
- `snapshot_list` / `get` / `remove` manage the store.
- `snapshot_restore` / `snapshot_fork` **materialise a new, independent sandbox
  directory** from a snapshot's captured state.
- Memory/process state is **out of scope** (`includes_memory` is always false) —
  the R3 disk-only fallback.

`pause`/`resume` (execution state via SIGSTOP/SIGCONT) are implemented separately
in the supervisor.

The helper advertises `Capability::Snapshots`.

## Consequences

- SDK snapshot methods round-trip end-to-end through the helper socket (create →
  list → restore → remove), verified live.
- A restored sandbox directory is materialised from the snapshot; booting a VM
  **on** the restored writable layer (continuous execution state) remains a
  runtime-integration step and is not part of this disk-only cut.
- No partial resources: `create` validates the id and captures atomically into a
  fresh directory; unsupported operations return typed errors.