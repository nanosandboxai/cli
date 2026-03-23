# Nanosandbox CLI

Command-line interface and TUI for Nanosandbox — run AI coding agents in VM-based sandboxes.

## Install

```bash
curl -fsSL https://github.com/nanosandboxai/cli/releases/latest/download/install.sh | bash
```

This installs the `nanosb` binary along with runtime dependencies (libkrun, gvproxy) and codesigns the binary on macOS.

### Requirements

- macOS Apple Silicon (arm64)
- Linux and Windows are not yet supported

### Build from Source

```bash
git clone https://github.com/nanosandboxai/cli.git
cd cli
cargo build --release
```

The binary will be at `target/release/nanosb`.

## Quick Start

```bash
# Check runtime prerequisites
nanosb doctor

# Pull an agent image
nanosb pull ghcr.io/nanosandboxai/agents-registry/claude:latest

# Run a sandbox from sandbox.yml in the current directory
nanosb
```

## Usage

### TUI Mode

Running `nanosb` with no subcommand launches the interactive TUI. It auto-detects `sandbox.yml` in the current directory and starts sandboxes with a terminal multiplexer interface.

```bash
# Launch TUI with auto-detected config
nanosb

# Launch with explicit config file
nanosb --config path/to/sandbox.yml

# Launch a specific sandbox from config
nanosb --sandbox claude

# Mount a project directory into sandboxes
nanosb --project /path/to/project

# Override resources
nanosb --cpus 4 --memory 8192 --timeout 1200
```

### CLI Commands

```bash
nanosb pull <image>          # Pull an image (full registry path required)
nanosb images                # List cached images
nanosb run <image> [cmd]     # Run a command in a new sandbox
nanosb exec <sandbox> <cmd>  # Execute a command in a running sandbox
nanosb ps [-a]               # List sandboxes (running, or all with -a)
nanosb stop <sandbox>        # Stop a running sandbox
nanosb rm [-f] <sandbox>     # Remove a sandbox
nanosb doctor                # Check runtime prerequisites
nanosb cleanup               # Clean up stale project clones
nanosb cache prune [--all]   # Reclaim disk space from image cache
```

### Global Flags

| Flag | Description |
|---|---|
| `--format text\|json` | Output format (default: text) |
| `--verbose` | Enable debug logging |
| `--config <path>` | Path to sandbox.yml (repeatable) |
| `--sandbox <name>` | Start only the named sandbox |
| `--project <path>` | Project directory to mount |
| `--cpus <n>` | Override CPU cores |
| `--memory <mb>` | Override memory (MB) |
| `--timeout <secs>` | Override timeout (seconds) |
| `--permissions <level>` | Agent permissions: default, accept-edits, allow-all |
| `-e KEY=VALUE` | Inject environment variable |
| `--env-file <path>` | Load env vars from file |

### Environment Variables

| Variable | Description |
|---|---|
| `NANOSB_VERSION` | Version to install (default: latest) |
| `INSTALL_DIR` | Binary install directory (default: `~/.local/bin`) |

## sandbox.yml

Sandboxes are configured via `sandbox.yml`:

```yaml
defaults:
  cpus: 2
  memory: 4096
  timeout: 600

sandboxes:
  claude:
    image: claude
    env:
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
    mcp:
      github:
        command: npx
        args: ["-y", "@modelcontextprotocol/server-github"]

  codex:
    image: codex
    cpus: 4
    env:
      OPENAI_API_KEY: ${OPENAI_API_KEY}
```

Bare image names (e.g., `claude`, `codex`) are automatically resolved to `ghcr.io/nanosandboxai/agents-registry/<name>:latest`.

## License

Apache-2.0
