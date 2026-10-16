# Linux/KVM live verification (Epic 9 · C1)

Status: **live-verified on Linux x86_64 (KVM)** — see §3 for the captured
evidence. `aarch64` has the same code path but was not exercised (no ARM+KVM
host available); it is tracked by the same harness.

This document records how the nanosandbox runtime is verified on Linux/KVM,
the baseline footprint, and the harness used by Epic 9's C1 gate and C9 live
matrix. The macOS verification story is in [`live-verification.md`](live-verification.md).

## 1. Requirements

- Linux host with KVM enabled and `/dev/kvm` accessible to the running user
  (add the user to the `kvm` group: `sudo usermod -aG kvm "$USER"`, then
  re-login).
- Runtime dependencies: `libkrunfw` firmware, `libkrun` static lib, `gvproxy`.
  Build them with `runtime/scripts/build-all.sh` (or install the release bundle
  with `install-deps/install.sh`).
- `nanosb` binary built with `LIBKRUN_LIB_DIR` pointing at the directory
  holding `libkrun.a`.

### Build from source (Linux)

```bash
runtime/scripts/ci/install-deps-apt.sh                       # toolchain + libs
LIBKRUN_OUTPUT_DIR="$HOME/.nanosandbox/lib" runtime/scripts/build-libkrun.sh
( cd runtime/deps/libkrunfw && make )
sudo cp runtime/deps/libkrunfw/libkrunfw.so.5.* /usr/local/lib/ && sudo ldconfig
( cd runtime/deps/gvproxy && GOWORK=off go build -o "$HOME/.nanosandbox/bin/gvproxy" ./cmd/gvproxy )
LIBKRUN_LIB_DIR="$HOME/.nanosandbox/lib" cargo build --release -p nanosb-cli
```

`nanosb doctor` must report all checks green:

```
[✓] libkrunfw Kernel Firmware: found
[✓] KVM Device: /dev/kvm accessible
[✓] gvproxy: available (full outbound networking)
```

> Note: `/dev/kvm` being present is not sufficient — the user must be in the
> `kvm` group. Without it, libkrun aborts with
> `Error creating the Kvm object: Error(13)` (EACCES).

## 2. The harness

[`runtime/scripts/linux-kvm-e2e.sh`](../runtime/scripts/linux-kvm-e2e.sh) boots a
real microVM, runs a workload, and asserts stdout + exit code propagation. It
**self-skips with exit 0** on a non-Linux host or when `/dev/kvm` is
unavailable, so it is safe to wire into CI as a gate.

```bash
NANOSB_BINARY="$PWD/target/release/nanosb" runtime/scripts/linux-kvm-e2e.sh
```

CI: [`.github/workflows/linux-kvm.yml`](../.github/workflows/linux-kvm.yml) runs
the harness on a self-hosted runner labelled `linux-kvm` (GitHub-hosted runners
do not expose `/dev/kvm`). It is manual/scheduled only, so it never queues on
pull requests for repos without such a runner.

### Shim-facing verbs E2E (C2/C3/C4)

[`runtime/scripts/linux-kvm-verbs-e2e.py`](../runtime/scripts/linux-kvm-verbs-e2e.py)
drives the per-sandbox control socket of a live VM and asserts the Epic 9
shim-facing verbs: tty `exec_stream` with live `exec_input`/`exec_resize`,
blocking `wait` returning the real exit code, and signal `kill` (unsupported
signal → typed `unsupported`; `SIGTERM` stops). It needs the guest exec-agent
staged for the host arch:

```bash
rustup target add x86_64-unknown-linux-musl --toolchain 1.94.0
( cd guest/crates/exec-agent && RUSTFLAGS="-C linker=rust-lld" \
    cargo build --target x86_64-unknown-linux-musl --release )
mkdir -p ~/.nanosandbox/guest-bin
cp guest/crates/exec-agent/target/x86_64-unknown-linux-musl/release/exec-agent \
   ~/.nanosandbox/guest-bin/exec-agent
python3 runtime/scripts/linux-kvm-verbs-e2e.py
```


### Epic 11 · M4 — non-OCI rootfs + ownable entrypoint

The harness additionally covers the Epic 11 surfaces:

- a **`local_dir` rootfs** sandbox booted via `nanosb supervise --foreground`
  (no OCI bundle), asserting the real exit code (a static `/init` returning 42)
  and that `<sandbox_dir>/supervisor.pid` is written;
- the exec channel (`exec.sock`) being wired through `nanosb supervise` (needs a
  host-arch guest `exec-agent`; otherwise covered by unit tests).

Both self-skip (exit 0) when `gcc -static` or the exec-agent is unavailable.

## 3. Captured evidence (Linux x86_64, Ubuntu 24.04, kernel 6.17, `/dev/kvm`)

```
$ nanosb doctor
  [✓] libkrunfw Kernel Firmware: found (libkrunfw.so.5)
  [✓] KVM Device: /dev/kvm accessible
  [✓] gvproxy: available (full outbound networking)
  3 checks passed, 0 errors, 0 warnings

$ nanosb run --name c1test docker.io/library/alpine:latest /bin/echo hello-from-linux-kvm
✓ Sandbox c1test started                                       # exit 0

$ cat ~/.nanosandbox/sandboxes/c1test/logs/console.log
hello-from-linux-kvm

$ cat ~/.nanosandbox/sandboxes/c1test/state.json
{"state":"stopped","exit_code":0, ...}
```

A live VM booted, ran the workload, and both stdout and the exit code
propagated. First-attempt failure was `Error creating the Kvm object: Error(13)`
(EACCES) until the user was added to the `kvm` group.

## 4. Baseline footprint (Linux x86_64, **debug** build)

Measured on a 2-vCPU / 7.7 GB Azure VM, 4 GB guest RAM, `alpine` image:

| Metric | Value |
|---|---|
| Boot + exec + teardown (`/bin/echo`) | ~2.4 s |
| Live VM process RSS (`internal-boot-vm`, debug) | ~211 MB |
| Live VM process virtual size | ~5.3 GB (dominant term = 4 GB guest RAM mapping) |
| Supervisor process RSS (`__supervise`) | ~43 MB |
| Host `Mem used` delta while running | ~190 MB |

A release build reduces the process RSS (debug symbols dominate); treat the
above as an upper-bound development baseline, not a production figure.
