# Decision — In-guest OCI security-context contract

Status: accepted (2026-10-14)
Related: #162, #156.

## Context

Epic 9's security-context surface lets callers request OCI-style in-guest
confinement: Linux capabilities, a seccomp profile, an AppArmor profile, and
`no_new_privileges`. The guest applies **none** of these today:

- The guest kernel is libkrunfw's bundled kernel; it boots with its own default
  capability set and no per-process seccomp/AppArmor policy is installed.
- The host trusts nothing from the guest (the guest is untrusted code running
  in a microVM), but that is a host-side boundary property, not an in-guest
  enforcement of the requested OCI fields.
- seccomp, capabilities, and AppArmor are Linux-kernel features; the guest
  runtime does not apply them in-guest in this build.

Silently accepting a `security` block and booting without enforcing it would
violate the caller's security expectation. The honest, fail-closed deliverable
is a **validation layer**: every security-sensitive OCI field this build cannot
enforce is rejected with a typed `unsupported` error at create, and the
remaining surface is documented as the contract.

## Decision

`SandboxSpec.security` (`SecurityContext`) is carried on the wire and validated
at create. `SecurityContext::unenforced_field()` returns the first field this
build cannot enforce in-guest; the helper-daemon create path rejects the create
with `ErrorCode::Unsupported` when it is `Some`.

| OCI security field | Disposition | Notes |
|---|---|---|
| `capabilities` (non-empty) | **rejected** (`unsupported`) | No in-guest capability drop/add is applied. |
| `seccomp_profile` (non-empty) | **rejected** (`unsupported`) | No seccomp filter is installed in-guest. |
| `apparmor_profile` (non-empty) | **rejected** (`unsupported`) | No AppArmor profile is loaded in-guest. |
| `no_new_privileges == true` | **rejected** (`unsupported`) | The `no_new_privileges` bit is not set in-guest. |
| `run_as_user` | **allowed** | The guest supports dropping to a user; the value is carried through. |
| empty / default context | **allowed** | No confinement requested; nothing to enforce. |

Empty profile strings (`Some("")`) and `no_new_privileges == Some(false)` are
treated as "not requested" and accepted — they request no confinement.

## Host ↔ guest boundary threat model

The host trusts nothing from the guest. The guest runs untrusted code in a
microVM whose kernel is libkrunfw; the host boundary (hypervisor, virtio
devices, gvproxy networking) is the actual isolation mechanism. In-guest
seccomp/capabilities/AppArmor would be a second, in-guest layer — useful for
defense-in-depth but **not present in this build**. This decision does not
change the host boundary; it only prevents callers from believing an in-guest
layer exists when it does not.

## Fail-closed principle

"Accepted ⇒ enforced" holds only because everything unenforced is rejected.
The validation layer is the enforcement: a create that names a security field
this build cannot apply is refused before any sandbox state is created, so no
sandbox ever boots with a silently-ignored security request.

## Consequences

- SDKs that send a `security` block with an unenforced field receive a typed
  `unsupported` error naming the field; they can surface it to the caller.
- Legacy specs without `security` parse unchanged (`#[serde(default)]`).
- Future in-guest enforcement (Linux-guest-only) can flip fields from
  `rejected` to `enforced` without changing the wire type.
