# Decision — Networking dynamic-publish scope (C7)

Status: accepted (2026-10-14)
Related: GitHub issue #163, Epic #156. Enforcement ownership:
`docs/epics/epic-3-runtime-networking.md` and Epic 8 task T9.

## Context

Dynamic runtime port publish/unpublish — changing which ports a running sandbox
exposes after it has booted — plus the host-side policy enforcement that gates
those ports is owned by **Epic 3** (`docs/epics/epic-3-runtime-networking.md`)
and **Epic 8 T9**. The protocol carries only the **create-time config surface**:
`NetworkSpec.publish` (see `docs/protocol/protocol.md` §5) is set at sandbox
creation and applied at boot. There is no runtime verb to mutate published
ports after boot.

## Decision

**Do not build an enforcement engine here.** Dynamic publish/unpublish and the
host-side policy that would authorize it are Epic 3 / Epic 8 T9 work. This epic
does not implement them.

Instead, expose a **typed fail-closed gate** so callers get `unsupported` —
never a silent drop — when they attempt dynamic publish/unpublish before Epic 3
lands. The gate makes the missing capability explicit and testable rather than
letting a request vanish.

## Interfaces

The intended verbs, gated by the `networking` capability:

- `network_publish` — publish a port on a running sandbox.
- `network_unpublish` — remove a published port from a running sandbox.

Until Epic 3 implements them, both return a typed `unsupported` error (protocol
code `unsupported`, `docs/protocol/protocol.md` §7). The verbs exist so the
surface is stable and callers can branch on the error; they do not silently
succeed or no-op.

## Boundaries

- **Multi-tenant isolation floor** is deferred to Epic 3
  (`docs/epics/epic-3-runtime-networking.md` §WS8). This epic does not define or
  enforce it.
- Create-time `NetworkSpec.publish` remains the only supported way to expose
  ports in this build.

## De-dup note

Dynamic publish/unpublish overlaps **Epic 8 T9**. This decision records the
scope split: the protocol surface and the fail-closed gate live here; the
enforcement engine and the multi-tenant floor live in Epic 3 / Epic 8 T9. Do not
implement the engine in both.
