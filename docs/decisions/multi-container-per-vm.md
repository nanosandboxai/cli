# Decision — Multi-container-per-VM (C5)

Status: accepted (2026-10-14)
Related: GitHub issue #161, Epic #156. See `docs/epics/epic-3-runtime-networking.md`
for the networking enforcement that multi-container pods will eventually need.

## Context

Today the runtime is strictly **1 VM per sandbox**: one sandbox maps to one
process, and one process boots one microVM via libkrun. There is no notion of a
pod, and no way to run two application workloads inside a single VM.

The containerd CRI pod model is different. A pod is a **pause/sandbox
container** plus N application containers that share the sandbox's network
namespace and localhost. Containers in a pod reach each other over `localhost`
and share lifecycle with the sandbox container. That is the shape a
multi-container runtime must reproduce.

## Decision

**v1 stays 1-container = 1-VM.** A sandbox is one VM, one process, one
container. We do not build a multi-container pod model in this epic.

True CRI multi-container pods require a **nanosandbox in-guest container
manager** — a process inside the VM that spawns and supervises multiple
containers against a shared kernel and shared namespaces. That is not a shim
feature and not something the host-side helper can fake. It is a distinct piece
of runtime work, scoped below.

## Consequences

- The protocol and SDK surface remain 1:1 with the VM: one `SandboxSpec`, one
  boot, one container. No pod-shaped API is introduced.
- `localhost` semantics are unchanged: a sandbox's own services listen on
  localhost inside its single VM. Cross-container localhost is not available.
- No silent partial support: nothing advertises multi-container capability, so
  callers cannot request a pod and get a degraded result.
- The in-guest container manager, when it lands, is additive: it does not change
  the single-container path.

## Rejected alternatives

- **One VM per container with reconstructed pod networking.** Boot N VMs and
  stitch them into a shared network namespace / localhost bridge on the host.
  Rejected: it multiplies VM overhead per container, and reconstructing a shared
  netns across separate VMs is a host-side hack that does not match CRI pod
  semantics. It also fights the isolation model rather than extending it.
- **Extend to a first-class multi-container runtime now.** Rejected: it is a
  large, separate workstream (in-guest manager, shared namespaces, volume
  sharing, pod lifecycle) that would block the single-container surface this
  epic must deliver. Deferring keeps v1 shippable and the pod model coherent.

## Scoped future work

When multi-container pods are pursued, the work is:

- **In-guest container manager** — a crun/container-manager process inside the
  VM that spawns and supervises N containers against the shared kernel.
- **Shared namespaces** — netns / IPC / UTS shared across the pod's containers,
  so they reach each other over `localhost`.
- **Volume sharing** — a shared writable layer or shared mounts visible to all
  containers in the pod.
- **Live E2E** — two containers in one VM communicating over `localhost`,
  verified against a real boot.
