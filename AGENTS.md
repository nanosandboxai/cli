# AGENTS.md

Guidance for AI coding agents (and humans) working in the **Nanosandbox** monorepo.

Nanosandbox runs AI coding agents inside hardware-isolated microVM sandboxes
(via [libkrun](https://github.com/containers/libkrun)). This monorepo contains
the `nanosb` CLI + TUI, the microVM runtime, the agent-aware sandbox SDK, the
protocol-first language SDKs, the agents registry, and the release/dependency
tooling.

## Repository layout

| Path | Contents |
|------|----------|
| `src/` | `nanosb` CLI + TUI (clap surface in `src/main.rs`, TUI in `src/tui/`) |
| `crates/protocol` | Versioned NDJSON protocol types (source of truth for the wire) |
| `crates/client` | `SandboxClient` + live conformance tests |
| `crates/conformance` | CI-safe protocol conformance harness |
| `runtime/` | MicroVM engine (libkrun FFI), OCI images, config defaults |
| `sandbox/` | Agent-aware sandbox SDK + `deploy` module + `sandbox.yml` parsing |
| `sdk/` | 8 language SDKs (Rust, Python, TypeScript/Node, Go, Ruby, Java, C#/.NET, Kotlin) + `conformance/` |
| `agents-registry/` | Agent definitions, skills, MCP sources, model catalog, Docker images |
| `install-deps/` | Runtime dependency (libkrunfw + gvproxy) installer |
| `guest/crates/exec-agent` | In-guest exec agent (linux/aarch64, cross-compiled) |
| `docs/` | Protocol spec, ADRs, epics/plans, live-verification reports |
| `scripts/` | Install, packaging, and smoke-test scripts |
| `test/` | Shell-based CLI/config integration tests |

> Content under `runtime/deps/**` is **vendored/submodule** (libkrunfw, gvproxy).
> Do not edit or document files there.

## Build, test, and lint

```bash
# Build the CLI (debug): binary at target/debug/nanosb
cargo build -p nanosb-cli

# Build the CLI (release)
cargo build --release -p nanosb-cli

# TUI/CLI unit tests (no TTY, no VM) — runs in CI
cargo test -p nanosb-cli
cargo test -p sandbox -p gateway
cargo test -p runtime --lib

# Workspace checks (what CI runs)
cargo check -p nanosb-cli -p sandbox -p gateway -p runtime

# Format and lint
cargo fmt --all
cargo clippy --workspace -- -D warnings
```

Opt-in / environment-dependent checks:

```bash
# Build the libkrun static library (first time, requires submodules)
runtime/scripts/build-libkrun.sh

# Scripted VM end-to-end test (requires libkrun/gvproxy + a codesigned binary)
NANOSB_BINARY_PATH="$PWD/target/debug/nanosb" \
  cargo test -p nanosb-cli tui::vm_test -- --ignored --nocapture

# Protocol conformance harness
cargo build -p nanosb-conformance

# Local PTY smoke harness
scripts/tui-smoke.sh
```

## Conventions

- **Rust edition 2021.** Match the existing style in the file you are editing.
- **Single version source of truth.** The workspace version lives in the root
  `Cargo.toml` `[workspace.package] version`; member crates use
  `version.workspace = true`. Exception: `guest/crates/exec-agent` is excluded
  from the workspace (linux-only, cross-compiled) and carries its own version.
- **Never suppress type errors** (`as any`, `@ts-ignore`, `unwrap_or_default`
  used to hide a real error, etc.). Fix the cause.
- **Keep changes minimal and focused.** Do not refactor unrelated code in the
  same change. Fix bugs minimally; never refactor while fixing.
- **Atomic commits.** One logical change per commit, with a conventional-commit
  subject (`feat:`, `fix:`, `chore:`, `docs:`, `ci:`) matching existing history.
- Never commit unless the user asked for it.

## Documentation is part of the change (MANDATORY)

**Any change or refactor MUST update the documentation it affects, in the same
change.** Documentation is not a follow-up task.

Before you consider a change complete, search for and update every affected
first-party document:

1. **Root** [`README.md`](README.md) — repository layout, install, CLI surface,
   `sandbox.yml`, platform support.
2. **Component READMEs** — [`runtime/README.md`](runtime/README.md),
   [`sandbox/README.md`](sandbox/README.md),
   [`agents-registry/README.md`](agents-registry/README.md),
   [`install-deps/README.md`](install-deps/README.md).
3. **SDK docs** — [`sdk/README.md`](sdk/README.md) and `sdk/<lang>/README.md`.
4. **Docs** — everything under `docs/**/*.md` (protocol spec, ADRs,
   live-verification reports).
5. **This file** — `AGENTS.md`, if conventions, layout, or commands change.

The rule, concretely:

- If you add/remove/rename a **CLI command or flag**, update the README CLI/flag
  lists — the surface is defined in `src/main.rs`.
- If you add/remove a **`sandbox.yml` field**, update the README config example —
  the schema is defined in `sandbox/crates/sandbox/src/config/file.rs`.
- If you change a **config field, env var, file path, default, or platform
  support statement**, update every doc that mentions it.
- Remove or correct any doc that describes behavior the code no longer has
  (stale docs are treated as bugs).
- Mark superseded design/plan docs with a clear **superseded** note rather than
  leaving them misleading.

A quick self-audit before finishing:

```bash
git diff --name-only            # what changed
grep -rn "<the symbol/command/field you changed>" --include='*.md' . \
  | grep -v runtime/deps
```

Vendored content under `runtime/deps/**` is out of scope.

## Sources of truth (for keeping docs accurate)

| Concern | Source of truth |
|---------|-----------------|
| CLI commands, flags, subcommands | `src/main.rs` (clap definitions) |
| TUI slash-commands | `src/tui/commands.rs` (`HELP_ENTRIES`) |
| `sandbox.yml` schema / defaults | `sandbox/crates/sandbox/src/config/file.rs` + `config/mod.rs` |
| Runtime `SandboxConfig` defaults | `runtime/crates/runtime/src/config/mod.rs` |
| Wire protocol | `docs/protocol/protocol.md` + `crates/protocol` |
| Environment variables | `src/deploy.rs`, `src/supervisor/mod.rs`, `src/tui/run.rs`, `sandbox/crates/sandbox/src/agents_registry.rs`, `scripts/install.sh` |
| Install paths / bundles | `scripts/install.sh`, `install-deps/install.sh`, `scripts/package-sdk.sh` |

## License

Apache-2.0 (see [`LICENSE`](LICENSE)).
