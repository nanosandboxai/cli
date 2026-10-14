# Zero Image Customization Redesign — Final Plan

**Goal:** Remove the in-VM agent-gateway and every nanosb-specific artifact from OCI images. Any vanilla Docker/OCI image must run unmodified, with all setup performed by the microVM layer (libkrun init/kernel/console) and the host runtime. Replace HTTP/SSE/SSH control with an out-of-band virtio-console channel. Make configuration deployment-only (`sandbox.yml` + `apply`), with security as the highest priority.

**Architecture:** Host CLI + detached per-sandbox supervisor own the VM lifecycle, console I/O, logs, and networking. Guest-side setup is entirely libkrun's own init layer (injected by the VMM, not the image): mounts, TTY/session, network, env, workdir, then `execvp` of the image entrypoint. Control channels are hypervisor-mediated virtio devices only — console (I/O + logs), virtiofs (workspace/state/config mounts), virtio-net (gvproxy, agent internet). No in-guest servers, no HTTP, no SSH, no exec.

**Non-Goals (explicit):**
- No containerd integration now; no daemon. containerd is Linux/Windows-only, unavailable on the macOS-first target, and its ecosystem value (CRI/Kubernetes) is a non-goal.
- No podman integration now (future path: crun + libkrun handler).
- No in-guest agent of any kind — not injected, not baked. Exec/attach beyond console is intentionally not supported.
- No hot reload of any config. All changes go through redeploy.

**Tech Stack:** Rust (runtime, sandbox SDK, CLI/TUI), libkrun (macOS HVF, Linux KVM later), gvproxy, virtio-console/virtiofs/virtio-net, OCI images (vanilla), `sandbox.yml`.

---

## 1. Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Images are 100% vanilla; no nanosb binaries, scripts, keys, or config baked or injected into image content | Removes build complexity; enables any image; image artifact stays immutable/verifiable |
| D2 | Image ENTRYPOINT/CMD runs as the workload via libkrun exec config; no wrapper scripts | Same contract as `docker run`; argv/env overridable at runtime (not an image edit) |
| D3 | Console is the only I/O channel: host fds wired to virtio-console; host writes = stdin; guest output = logs + live stream | TTY + raw mode + SIGWINCH resize supported by libkrun console; out-of-band, not network-reachable |
| D4 | SSH is removed entirely; `exec` is removed | No in-guest server allowed by constraint; both required an in-guest agent. Honest capability cut |
| D5 | Config/state/skills/MCP delivered as virtiofs mounts (RO config, RW state) + boot-time env; no in-guest config generation | MicroVM-layer setup only; survives redeploys; no hot reload |
| D6 | Secrets delivered only via in-memory boot env (`krun_set_env`); never disk, never cmdline | Standard, no persistence, no leakage to host files |
| D7 | Detached per-sandbox host supervisor owns VM + console + gvproxy + logs; CLI/TUI are clients | VM and logs survive client restarts; no central daemon |
| D8 | Deployment model: `sandbox.yml` + `apply` with config hash recreate-only; no CRUD APIs, no hot reload | kubectl-like, deterministic, immutable at boot |
| D9 | Security defaults: dedicated volume for shares, dedicated unprivileged UID, RO config mounts, TSI off, opt-in loopback-only forwards, digest/cosign verification, console sanitization | Threat model: untrusted agent code; virtiofs is the top host-facing surface |
| D10 | Keep the lean custom runtime; design seams (shim-v2-shaped supervisor API, OCI bundle generation, stdio/log streams) for a future containerd shim. Podman later via crun + libkrun | containerd adds a daemon + Linux assumptions without simplifying the hard parts; podman needs crun, not containerd |
| D11 | Prefer upgrading to `containers/libkrun` v2 (init-blob, console tty ports, DHCP) over backporting into pinned v1.19.5; fallback is backport | v2's init-blob is exactly the microVM-layer setup engine this design needs |

---

## 2. Target Architecture

```
HOST (CLI/TUI + per-sandbox supervisor, unprivileged)        GUEST (vanilla image, untouched)
┌───────────────────────────────────────────────┐           ┌───────────────────────────────────────┐
│ nanosb apply/get/logs/attach/restart/delete   │           │ libkrun init (microVM layer):         │
│                                               │           │   mount rootfs + extra virtiofs tags   │
│ supervisor (detached, setsid):                │           │   setsid + TIOCSCTTY (TTY)             │
│   spawns VM + gvproxy                         │           │   network (DHCP/static)                │
│   owns console fds (input pipe, out/err tee)  │           │   env / workdir / hostname / rlimits   │
│   writes logs, enforces timeout, cleans up    │           │   execvp(image ENTRYPOINT/CMD)         │
│   control.sock (0700/0600) for clients        │           │                                       │
│                                               │           │ workload = image entrypoint (PID1 child│
│   console.log (raw, append)  ◀─virtio-console─┼───────────┤   stdin/stdout/stderr = console TTY)  │
│   workspace/state/config     ──virtiofs──────▶│           │                                       │
│   gvproxy (internet, opt-in forwards) ─virtio-net─▶       │                                       │
└───────────────────────────────────────────────┘           └───────────────────────────────────────┘
```

**Component responsibilities:**

| Component | Owns | Never does |
|---|---|---|
| CLI/TUI | manifest, apply, log reading, console attach | hold VM/session lifetime |
| Supervisor (host) | VM spawn, console fds, gvproxy, timeout, cleanup, state files | implement guest protocols |
| libkrun init (microVM layer) | mounts, TTY, network, env, workdir, exec | anything nanosb-specific, HTTP, SSH |
| Image | its own entrypoint and tools | nanosb code, configs, keys |

---

## 3. Capability Matrix (before → after)

| Feature | Before (gateway) | After (zero in-guest) |
|---|---|---|
| Any vanilla image | Requires gateway detection / plain fallback | ✅ Unmodified, first-class |
| Logs | Only inside SSE response of the owning client | ✅ Per-sandbox console log file, client-independent, `logs -f` |
| Interactive agent TUI | SSH PTY (russh) | ✅ Console TTY attach (raw mode, resize) |
| Multi-agent panels | SSH per panel | ✅ One VM + console per agent |
| `exec` | HTTP SSE `/api/v1/exec` | ❌ Removed (no in-guest agent by design) |
| SSH | Embedded charm server :22 | ❌ Removed |
| Upload | SSH exec channel | ✅ Host copies into workspace virtiofs mount |
| MCP/skills | In-guest CRUD + config generation | ✅ RO virtiofs mounts + env; redeploy-only |
| Secrets | Encrypted payload → plaintext over loopback TCP | ✅ In-memory boot env only |
| State persistence | Symlinks into `/workspace/.nanosb-state` | ✅ Dedicated RW state mounts per sandbox |
| Timeout/lifecycle | CLI child process | ✅ Detached supervisor, VM survives CLI exit |
| Port exposure | gvproxy auto mapping | ✅ Opt-in, loopback-only |
| OAuth loopback | `ssh -L` | ⚠️ Requires workload to bind `0.0.0.0`; else degraded (documented) |

---

## 4. Workstreams

Each phase ends with a hard verification gate. Do not start the next phase until the gate passes.

### Phase 0 — Spikes and Decision Gates (no production changes)

**Task 0.1 — Console I/O spike**
- Files: throwaway spike under `runtime/crates/runtime/examples/` (or a scratch bin), using `ffi`/`libkrun-sys`.
- Work: boot a vanilla Alpine rootfs; wire console with host fds (input pipe; output/err pipes); write bytes to stdin; read output; verify raw-mode TUI behavior and window resize (PTY + SIGWINCH or `krun_add_console_port_tty`); verify behavior on macOS HVF.
- Verify: interactive `sh` over console works; `stty size` reflects resize; output tees to file + live reader without loss.

**Task 0.2 — Extra virtiofs mount spike (microVM layer)**
- Files: libkrun init layer (upgrade branch or `runtime/deps` patch series).
- Work: boot with an extra virtiofs tag; confirm current init does not mount it; add mount support (create target dir if missing, RO/RW) driven by boot config; no image involvement.
- Verify: file written on host appears in guest at target; RO mount rejects writes.

**Task 0.3 — Network bring-up spike**
- Files: libkrun init layer / kernel cmdline config.
- Work: configure `eth0` at boot (DHCP via gvproxy, or static 192.168.127.2/24 + gw + resolv.conf) without any image-side client.
- Verify: `wget`/`curl` from a vanilla image works; DNS resolves; no DHCP binary present in image.

**Task 0.4 — libkrun version decision**
- Work: evaluate `containers/libkrun` v2 upgrade vs backport of init-blob/console pieces into pinned v1.19.5 fork. Criteria: console tty + resize, init mounts, DHCP, exit-code propagation, patch-series conflicts, macOS support.
- Verify: written decision (v2 upgrade preferred unless blocked) + branch created.

**Gate G0:** all four spikes pass on macOS; version decision recorded.

---

### Phase 1 — MicroVM Layer Implementation

**Task 1.1 — Console fds through runtime config**
- Files: `runtime/crates/libkrun-sys/src/lib.rs`, `runtime/crates/runtime/src/runtime/ffi.rs`, `runtime/crates/runtime/src/runtime/libkrun.rs`, `runtime/crates/runtime/src/config/mod.rs`, `runtime/crates/runtime/src/sandbox.rs`.
- Work: extend the VM boot request/config with console descriptor setup (input fd, output fd, err fd, tty flag); wire `krun_add_virtio_console_default` / tty port; replace implicit-console-to-stdout usage.
- Verify: unit/integration test boots rootfs, writes stdin, asserts echo on stdout.

**Task 1.2 — Extra mounts in init**
- Files: libkrun init layer + boot config schema in runtime.
- Work: accept list of `{tag, target, readonly}`; mount at boot; create targets; fail boot loudly on error.
- Verify: integration test with RW + RO mounts.

**Task 1.3 — Network bring-up in init**
- Files: libkrun init layer; `runtime/crates/runtime/src/runtime/gvproxy.rs` for addressing.
- Work: DHCP or static config at boot; resolv.conf; keep gvproxy as the userspace network.
- Verify: integration test with outbound HTTP + DNS.

**Task 1.4 — Entry point without wrapper**
- Files: `runtime/crates/runtime/src/runtime/libkrun.rs`, `runtime/crates/runtime/src/sandbox.rs`, `runtime/crates/runtime/src/oci.rs`.
- Work: stop setting PID1 to `/usr/local/bin/nanosb-init.sh`; resolve image ENTRYPOINT/CMD (and optional manifest override) into exec argv; keep env/workdir from config; ensure init remains PID1 above the workload and reaps (do not set `KRUN_INIT_PID1`); propagate workload exit code.
- Verify: vanilla `alpine` runs its entrypoint; exit code observed host-side; zombies reaped.

**Task 1.5 — Timeout + abrupt stop semantics**
- Files: `runtime/crates/runtime/src/runtime/libkrun.rs`, supervisor (Phase 2).
- Work: document v1 stop = SIGTERM process group → SIGKILL after grace (no guest signal possible); ensure logs/state are append-only/fsync-friendly; note vsock graceful shutdown as future work.
- Verify: kill during write loses at most tail bytes; logs remain readable.

**Gate G1:** vanilla image boots with console I/O, mounts, network, entrypoint, exit code — no nanosb artifacts anywhere in the rootfs.

---

### Phase 2 — Host Supervisor

**Task 2.1 — Supervisor process**
- Files: `src/main.rs` (hidden `__supervise` subcommand), new module `src/supervisor/` (or `sandbox/crates/supervisor/`), `runtime/crates/runtime/src/config/mod.rs`.
- Work: `setsid`-detached process per sandbox; spawns VM with console fds; starts/stops gvproxy; writes state (`~/.nanosandbox/sandboxes/{id}/…`); enforces timeout; cleans up on exit; updates registry.
- Verify: VM survives CLI exit; `nanosb ps` shows it; timeout kills it; no orphan gvproxy/sockets after `nanosb rm`.

**Task 2.2 — Control socket**
- Files: supervisor module.
- Work: unix socket `{sandbox}/control.sock` (dir 0700, sock 0600, peer same-UID); verbs: `status`, `stop`, `attach` (stream out + input + resize), `logs-follow`, `ping`. Version the protocol.
- Verify: two clients attach; single input writer enforced; resize forwarded; protocol errors handled.

**Task 2.3 — Lazy GC + crash tolerance**
- Files: supervisor module, `src/main.rs` (`ps`, `cleanup`).
- Work: if supervisor dies, VM remains (console output goes to file); CLI can operate via pid/socket when present; dead VMs detected and cleaned on next command; stale socket/pid cleanup.
- Verify: kill -9 supervisor; VM continues; subsequent CLI commands detect and recover/cleanup.

**Gate G2:** sandbox lifecycle fully host-owned, crash-tolerant, no daemon.

---

### Phase 3 — Console Streaming Layer (CLI + TUI)

**Task 3.1 — Log files + live fan-out**
- Files: supervisor + `src/main.rs`.
- Work: raw append log `{sandbox}/logs/console.log`; bounded in-memory ring for attach replay; fan-out to subscribers; backpressure policy (never block guest; drop live frames if a slow client, file always complete); 0600 perms; size rotation (e.g. 50 MB × 3).
- Verify: `nanosb logs <id> -f` streams; client disconnect does not affect VM; log matches output after VM stop.

**Task 3.2 — `nanosb logs`**
- Files: `src/main.rs`.
- Work: `logs <name> [-f] [--tail N] [--timestamps]`; read from files directly (works for stopped sandboxes).
- Verify: logs available while running and after stop; no supervisor required to read.

**Task 3.3 — `nanosb attach` + TUI migration**
- Files: `src/tui/run.rs`, `src/tui/terminal.rs`, `src/tui/app.rs`, `src/tui/event.rs`, `src/main.rs`.
- Work: replace russh connection with supervisor attach; render through existing vt100; forward keystrokes + resize; headless panels consume the console stream (PTY/NDJSON handling preserved from the `script -qfc` behavior); remove SSH retry logic.
- Verify: interactive Claude/Codex TUI usable; resize works; TUI restart reattaches; NDJSON headless parsing still correct.

**Task 3.4 — Upload without SSH**
- Files: `src/tui/upload.rs`.
- Work: copy files into the workspace mount host-side; surface in guest at the workspace path.
- Verify: uploaded file appears in guest; no SSH client used.

**Task 3.5 — Remove gateway client**
- Files: `sandbox/crates/gateway/src/http.rs`, `client.rs`, `transport.rs`, `ssh.rs`; `sandbox/crates/sandbox/src/sandbox.rs` (SSH keys, port 8080/22 mappings, health polling); TUI suspend `sync` call in `src/tui/run.rs`.
- Work: new console/supervisor client replaces `GatewayClient`; delete SSH key generation/injection and gateway port mappings; remove `gw.exec("sync")`.
- Verify: no references to `gateway_http_*`, `wait_for_health`, `ssh_port` in the CLI/TUI paths.

**Gate G3:** full interactive + headless flow on console only; logs client-independent; no SSH/HTTP anywhere.

---

### Phase 4 — Config Delivery, State, Secrets (Redefine SDK)

**Task 4.1 — Mount planner**
- Files: new `sandbox/crates/sandbox/src/deploy/` (planner), `sandbox/crates/sandbox/src/config/file.rs`.
- Work: compute mounts per sandbox from manifest + agent type: workspace RW, state dirs RW (e.g. `~/.claude`, `~/.codex`, `~/.cursor`, `~/.config/goose`, `~/.local/share/goose`, `~/.agents`), config dirs RO; host dirs under `~/.nanosandbox/sandboxes/{name}/state/…` and `…/config/…`.
- Verify: unit tests for the mount plan; integration test shows state survives recreate.

**Task 4.2 — Port MCP/skills config generation to host**
- Files: new Rust modules ported from `agents-registry/agent-gateway/mcp/config_gen.go`, `skills/config_gen.go`, and agent command building from `agent-gateway/main.go` (`buildAgentCommand`); also consolidate `src/tui/terminal.rs` agent command logic.
- Work: generate per-agent config files (Claude JSON, Goose YAML, Codex TOML, Cursor JSON) into `…/config/…`; skills files into config dirs; env pointers/argv per agent.
- Verify: per-agent matrix test (claude, codex, goose, cursor) — config visible in guest at expected paths; MCP servers spawn from the agent CLI.

**Task 4.3 — Secrets via boot env**
- Files: `runtime/crates/runtime/src/runtime/libkrun.rs` (env path), `sandbox/crates/sandbox/src/sandbox.rs`.
- Work: pass resolved secrets into `krun_set_env`; never write to rootfs; document guest-process visibility.
- Verify: env visible to workload; nothing persisted under `~/.nanosandbox/sandboxes/{name}` (except non-secret manifest state).

**Task 4.4 — Remove CRUD from SDK**
- Files: `sandbox/crates/sandbox/src/agent_sandbox.rs`, `sandbox/crates/sandbox/src/ffi.rs`, `sandbox/docs/sdk-bindings.md`.
- Work: delete `bootstrap_agent`, `set_agent`, `restart_agent`, MCP CRUD, skills CRUD; add `apply`-shaped create/update; update FFI exports and docs.
- Verify: SDK compiles; FFI header docs updated; no server API types remain.

**Gate G4:** agents work with host-delivered config; no in-guest config generation remains; secrets never touch disk.

---

### Phase 5 — Deployment Surface

**Task 5.1 — Manifest schema**
- Files: `sandbox/crates/sandbox/src/config/file.rs`, `sandbox/crates/sandbox/src/config/mod.rs`, README.
- Work: finalize `sandbox.yml` (existing fields retained; optional `command` override; no new hot-reload fields); document that all config is boot-immutable.
- Verify: schema tests; docs updated.

**Task 5.2 — `apply` semantics**
- Files: `src/main.rs`, `sandbox/crates/sandbox/src/deploy/`.
- Work: per-sandbox config hash (boot-affecting fields only); create/recreate/no-op/start; `--prune` with ownership marker; `--force`; `--dry-run`; registry file lock; per-resource results and non-zero exit on error.
- Verify: integration tests for each transition; concurrent `apply` serialized; prune never removes unrelated sandboxes.

**Task 5.3 — CLI surface**
- Files: `src/main.rs`.
- Work: `apply`, `get`/`ps`, `describe`, `logs`, `attach`, `restart`, `delete`/`rm`; remove `exec`, `ssh`, `run` as gateway-based flows (redefine `run` as one-shot apply+attach).
- Verify: command help matches README; old commands removed.

**Gate G5:** full redeploy workflow from manifest; no hot reload paths exist.

---

### Phase 6 — Image Cleanup

**Task 6.1 — Clean Dockerfiles**
- Files: `agents-registry/docker/Dockerfile.base`, `Dockerfile.claude|codex|goose|cursor`, delete `nanosb-init.sh`, `rootless-apt-wrapper.sh`.
- Work: remove Go builder stage + gateway copy + init script + apt wrapper; remove any nanosb-specific dirs; keep agent CLIs and standard tooling only; ensure ENTRYPOINT/CMD is the agent CLI (image content, not nanosb customization).
- Verify: image contains no `nanosb`/`agent-gateway` strings; `docker build` succeeds without Go.

**Task 6.2 — CI cleanup**
- Files: `.github/workflows/*` (gateway build steps, release artifacts).
- Work: delete gateway build/release jobs; keep image builds.
- Verify: CI green; release artifacts no longer include agent-gateway.

**Task 6.3 — E2E on new images**
- Files: `test/` scripts.
- Work: apply → boot → attach → logs → redeploy-preserving-state on claude/codex/goose/cursor; plus a vanilla `alpine` image.
- Verify: all pass on macOS.

**Gate G6:** default builds ship zero nanosb artifacts in images; E2E green with legacy path no longer required for new images.

---

### Phase 7 — Deletion, Cleanup, Security Validation

**Task 7.1 — Delete gateway and dead code**
- Files: `agents-registry/agent-gateway/**` (delete), `sandbox/crates/gateway/**` (delete or reduce to console client), charm/SSH deps in `Cargo.toml`, `sandbox/README.md`, `runtime/README.md`, `runtime/docs/ARCHITECTURE.md`.
- Work: remove all references; update architecture docs to the new model.
- Verify: `rg -i "agent-gateway|nanosb-init|gateway_http"` returns only docs referencing the removal.

**Task 7.2 — Security validation**
- Work: run the checklist below; fix or explicitly accept every item; record results in a security sign-off section (append to this plan or a follow-up doc).
- Verify: checklist signed; residual risks documented.

**Gate G7:** codebase clean; security checklist complete.

---

## 5. Interfaces (contract sketches)

**Supervisor control socket (newline-delimited JSON over unix socket):**

| Verb | Request | Response |
|---|---|---|
| `status` | `{}` | `{state, pid, exit_code?, started_at, config_hash}` |
| `stop` | `{force?}` | `{ok}` |
| `attach` | `{}` | stream: `{type:"output", data}` / `{type:"exit", code}`; client sends `{type:"input", data}` and `{type:"resize", cols, rows}` |
| `logs-follow` | `{tail?}` | stream of output frames (no input) |
| `ping` | `{}` | `{ok, version}` |

**Log file:** raw console bytes, append-only, 0600, `{sandbox}/logs/console.log`, rotation 50 MB × 3.

**State on host:**
```
~/.nanosandbox/sandboxes/{name}/
├── state.json          # status, pid, exit code, config hash, generation
├── applied.json        # manifest slice + hash + owner path
├── control.sock        # 0600
├── logs/console.log
├── config/             # RO-mounted agent config dirs (MCP/skills)
└── state/              # RW-mounted agent state dirs (persisted across redeploys)
```

**Manifest (unchanged fields + one addition):** `command` (optional argv override). Everything else stays: `image`, `cpus`, `memory`, `timeout`, `env`, `mounts`, `network`, `run_as_root` (redefined as image-user passthrough — see risk R6), `agent`, `prompt`, `model`, `permissions`, `auto_mode`, `mcp`, `skills`.

---

## 6. Security Plan

**Threat model:** agent workload is untrusted; images are semi-trusted (supply chain); the hypervisor is the boundary; the VMM is a proxy (virtiofs/net) and therefore the top host-facing surface.

**Required defaults:**

- [ ] VMM + supervisor run as a dedicated unprivileged UID; control dir 0700, sockets 0600, peer same-UID.
- [ ] All virtiofs shares live under a dedicated directory on a **dedicated APFS volume** (`nanosb volume init` helper); never share `$HOME` or the project parent.
- [ ] Config mounts read-only; workspace/state mounts scoped per sandbox; no undeclared shares.
- [ ] Image pull: digest pinning; `cosign` verification (fail-closed in secure mode); no `:latest`.
- [ ] Console output rendered through a VT parser; strip OSC 8/52 and unsafe sequences; never pipe raw guest bytes to the host TTY.
- [ ] Secrets only in boot env; never persisted; never in cmdline; documented as visible to the agent's child processes.
- [ ] Network: TSI disabled; gvproxy only; port forwards opt-in, loopback-only, ephemeral.
- [ ] Guest hardening: rlimits, PID limits, no devices by default, minimal kernel cmdline, rootfs treated as ephemeral (no host persistence).
- [ ] Logs 0600; no world-readable state.
- [ ] CI: `cargo audit`; optional image scan.

**Residual risks (ranked):**
1. virtiofs host-path exposure — libkrun does not confine the guest to the shared dir; mitigated (not eliminated) by dedicated volume + unprivileged VMM.
2. Untrusted image as workload with network + workspace — mitigated by image verification and VM boundary.
3. Terminal escape injection — mitigated by VT sanitization.
4. Secret visibility inside guest — accepted, single-tenant.
5. Forwarded-port local reachability — mitigated by loopback-only opt-in.
6. Supervisor fd/socket handling bugs — mitigated by tests + fuzzing the attach protocol.

---

## 7. Migration & Rollback

- Keep the legacy gateway path functional behind `NANOSB_LEGACY_GATEWAY=1` (auto-off after Phase 6). Old gateway images remain pullable by digest for rollback.
- Phases 1–5 can land behind a `next` runtime flag while the default remains legacy; after G3 the console path becomes default on developer machines; after G6 it is the only path for new images.
- Rollback = set legacy flag + pin the last gateway image digests; no host state migration required (state dirs are new paths; legacy state is untouched).
- Remove the flag and legacy code in Phase 7.

## 8. Testing Strategy

| Level | Coverage |
|---|---|
| Unit | mount planner, config hash, log ring/fan-out, VT sanitizer, supervisor protocol parsing |
| Integration (runtime) | console stdin→stdout, resize, extra mounts RW/RO, network + DNS, entrypoint + exit code, timeout, reaping |
| Integration (sandbox) | apply transitions (create/no-op/recreate/prune/force), state persistence across recreate, secrets in env, per-agent config materialization |
| E2E (macOS) | vanilla alpine; claude/codex/goose/cursor; TUI attach/resize; logs while running/stopped; upload; crash-recovery; security smoke (no listening services, RO configs) |
| Security | checklist run + manual review of virtiofs share scoping and console sanitization |

## 9. Risks & Open Questions

| # | Risk | Mitigation / Owner |
|---|---|---|
| R1 | libkrun v2 upgrade regression or effort | Phase 0 spike + fallback backport (D11) |
| R2 | Console TTY/resize behavior on HVF differs from Linux | Phase 0 spike is the gate; fallback = fixed-size console |
| R3 | virtiofs host exposure on macOS (no namespaces) | Dedicated volume + unprivileged UID; residual risk accepted and documented |
| R4 | Console = one session per VM (no multi-exec) | Product decision; multi-agent = multiple VMs |
| R5 | OAuth loopback needs workload to bind 0.0.0.0 | Document; per-agent env/config; else degraded |
| R6 | `run_as_root` / image USER semantics: libkrun init may not switch users | Verify in P1; if unsupported, images define USER and init runs as root-of-VM (single-tenant) |
| R7 | Console flooding/backpressure | Bounded ring for live clients; file always appended; never block guest |
| R8 | NDJSON headless parsing over TTY artifacts | Reuse the existing tolerant parser; test per agent |
| R9 | Users on old images after upgrade | Legacy flag + pinned digests; deprecation window |
| R10 | `sync` on suspend no longer possible via exec | Virtiofs writes flushed by host on stop; document |

**Open questions to resolve in P0/P1:**
- PTY-based tty port vs default console for raw-mode TUIs (which resizes reliably).
- Whether rootfs can be mounted read-only without breaking common images; if not, define the accepted ephemeral-write model.
- Static IP vs DHCP in init (v2 DHCP feature vs custom netlink).
- Exact set of standard mount targets per agent (state/config paths).

## 10. Deferred / Future

- Linux/KVM enablement of the same design.
- Podman integration via **crun + libkrun** handler.
- Containerd shim v2 adapter (seams: OCI bundle generation, shim-shaped supervisor verbs, stream-shaped stdio) only if a k8s/nerdctl/CRI need appears.
- Graceful shutdown via minimal vsock control message.
- Optional microVM-layer agent (kata-style, in init-blob, never in images) only if host-initiated exec becomes a hard requirement — explicitly out of scope now.

---

## 11. Phase 0.4 Input — v1.19.5 Patch-Series Sustainability vs libkrun v2 Upgrade

*Appended 2026-10-05 after inspecting the pinned v1.19.5 checkout and creating the init patch series.*

### Summary

The v1.19.5 init-blob (`src/init_blob/init/init.c`, 1637 lines) is a standalone C program compiled by `build.rs` via `CC_LINUX` (cross-compiler for the Linux guest). It already has:
- `jsmn` JSON parser embedded
- `mount()` syscall access for standard filesystems (devtmpfs, proc, sysfs, devpts, tmpfs)
- `ioctl`-based network configuration (SIOCSIFADDR, SIOCSIFFLAGS, SIOCADDRT)
- DHCP client (`do_dhcp()` in `dhcp.c`, 626 lines)
- virtio-ports console redirect (`setup_redirects()`)
- Config file parsing (`/.krun_config.json` for OCI Entrypoint/Cmd/Env)
- Exit code propagation via virtiofs ioctl

### Patch feasibility

**Extra virtiofs mounts**: Straightforward. The init already has `mount()` and `jsmn`. Adding a `mount_extra_virtiofs()` function that parses `KRUN_EXTRA_MOUNTS` JSON and calls `mount("virtiofs", target, "virtiofs", flags, "tag=<tag>")` is ~120 lines of C. Gated behind `KRUN_NEXT_MODE=1`.

**Static network bring-up**: Straightforward. The init already has `ioctl`-based network config (see `enable_dummy_interface()`). Adding `configure_static_network()` that parses `KRUN_NET_CONFIG` JSON and configures eth0 with IP/netmask/gateway + writes `/etc/resolv.conf` is ~180 lines of C. Gated behind `KRUN_NEXT_MODE=1`.

**Both patches apply cleanly** to the pinned v1.19.5 checkout (SHA `fb98887`). Verified with `git apply`.

### What cannot be done via patch

1. **Console TTY resize propagation**: Already handled by `krun_add_console_port_tty` on the host side. The init's `setup_redirects()` handles virtio-ports for krun-stdin/stdout/stderr. No init changes needed.
2. **Entrypoint resolution from OCI config**: Already handled by `config_parse_file()` reading `/.krun_config.json`. No patch needed.
3. **Exit code propagation**: Already handled by `set_exit_code()` via virtiofs ioctl. No patch needed.
4. **DHCP**: Already implemented via `KRUN_DHCP=1` + `do_dhcp()`. No patch needed.

### v2 upgrade assessment

**`containers/libkrun` v2** (the `init-blob` branch / future main) is the preferred path per D11. The v2 init-blob is a Rust rewrite with:
- Structured config (not env-var-driven)
- Proper DHCP client
- Console TTY ports
- Cleaner mount management

**Advantages of v2:**
- No patch series to maintain — v2 has init-blob as a first-class feature
- Rust init is safer (no manual memory management in PID1)
- Better console support (TTY ports are native)
- DHCP is built-in (no static IP hack needed)

**Disadvantages of v2:**
- Not yet released (v1.19.5 is the latest tag as of Oct 2026)
- Requires a full upgrade of the libkrun C API surface (may break `libkrun-sys`)
- The Rust init may have different env-var conventions
- macOS HVF support in v2 is unverified

**Recommendation:** Proceed with the v1.19.5 patch series for Phase 1 (it's working today). The patches are small (~300 lines total) and well-isolated behind `KRUN_NEXT_MODE=1`. When v2 ships, the patches can be discarded in favor of native v2 init-blob features. The Rust-side config (`ConsoleSpec`, `ExtraMount`, `RuntimeMode`) is designed to be v2-compatible — the env-var serialization is in the boot subprocess, not in the config types.

### Patch maintenance burden

- **Low**: Two patches, ~300 lines total, touching only one file (`init.c`)
- **No merge conflicts expected**: The patches add new functions and call sites; they don't modify existing code paths
- **Easy to drop**: When v2 ships, delete `runtime/scripts/patches/` and update `build-libkrun.sh` to use v2
- **CI verification**: The `git apply --check` in the build script will catch drift immediately
