# Decision — Volume backings shipped in Epic 1

Status: accepted (2026-10-11)
Related: `docs/epics/epic-1-multi-language-sdk.md` §4.6, WS4.

## Context

Epic 1's `§4.6 Storage / volumes` inventory lists dir-backed volumes,
disk-image volumes (`raw`/`qcow2`/`vmdk` + `fstype`), `tmpfs` mounts, mount
options, and `quota`. microsandbox supports dir-backed and disk-backed volumes.

The helper/supervisor path attaches guest storage through libkrun's virtio-fs
(host directory) and virtio-blk (block device) devices. The runtime exposes a
host-directory mount path (`MountType::Bind` / `VirtioFs`) but no block-device
attach API, and APFS provides no per-directory quota facility.

## Decision

**Ship dir-backed volumes only** in this build:

- `VolumeCreate` / `VolumeList` / `VolumeGet` / `VolumeRemove` operate on a
  registry under `$NANOSB_HOME/volumes/<name>/` (metadata in `volume.json`,
  backing dir at `volume.json.dir`, defaulting to `volumes/<name>/data`).
- A volume may pin an external host directory via `VolumeSpec.dir`; the registry
  records it but never deletes it on `remove`.
- `VolumeSpec.disk_image` (raw/qcow2/vmdk) and `VolumeSpec.quota_bytes` return a
  typed `unsupported` error — never a half-created volume.

**Deferred** (return clean `unsupported`, not implemented):

| Backing | Why deferred |
|---|---|
| Disk-image volumes (`raw`/`qcow2`/`vmdk`) | libkrun attach path has no block-device API in this build; virtio-blk wiring is separate runtime work. |
| `quota` | No per-directory quota on APFS; enforcing it needs a filesystem/project-quota mechanism that does not exist on the target. |

`MountAdd` and the `MountSpec` surface (bind/virtiofs, and the wire fields
`file`/`tmpfs`/`options`/`uid`/`gid`) are carried through protocol → helper →
runtime; backings the VM cannot attach are rejected with a typed error at the
helper boundary.

## Consequences

- SDK volume methods work end-to-end for dir-backed volumes; callers requesting
  disk-image/quota receive `unsupported` with a clear message.
- No partial resources: `create` validates everything before touching disk.
- Future block-device support can extend `VolumeRegistry` and the runtime
  `Mount`/`MountType` without changing the protocol surface.