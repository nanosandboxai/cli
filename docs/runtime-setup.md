# Runtime setup (macOS arm64)

Nanosandbox runs each agent in a microVM (libkrun). The CLI/TUI and the
protocol helper (`nanosb-runtime`) need three runtime artifacts:

| Artifact | Role | Default location |
|---|---|---|
| `nanosb-runtime` | the slim helper daemon (boots/controls VMs, serves the protocol) | on `PATH`, or `$NANOSB_HOME/bin/` |
| `gvproxy` | user-mode networking sidecar | `$NANOSB_HOME/bin/gvproxy`, `PATH`, or `/usr/local/bin` |
| `libkrunfw.5.dylib` | kernel firmware `dlopen`ed at boot | `$NANOSB_HOME/libs/` or system lib dirs |

`$NANOSB_HOME` defaults to `~/.nanosandbox` and overrides every lookup above.

## Install from source

```bash
# 1. Runtime deps (libkrunfw + gvproxy) into ~/.nanosandbox
./install-deps/install.sh

# 2. Build the binary / helper
cargo build --release -p nanosb-cli
cargo build --release -p nanosb-cli --bin nanosb-runtime \
    --no-default-features --features runtime-host

# 3. Verify
./target/release/nanosb doctor     # 4/4 checks
```

## Bundled packages (WS9)

`scripts/package-sdk.sh` produces a self-contained package per SDK under
`dist/nanosandbox-sdk-<lang>/`:

```
dist/nanosandbox-sdk-<lang>/
├── bin/nanosb-runtime          # pre-signed helper
├── bin/gvproxy                 # networking sidecar
├── libs/libkrunfw.5.dylib      # kernel firmware
├── sdk/<lang>/                 # the SDK sources
├── install.sh                  # lays the runtime into $NANOSB_HOME
└── README.md
```

```bash
scripts/package-sdk.sh               # all SDKs
scripts/package-sdk.sh rust python   # a subset
DIST=/tmp/out scripts/package-sdk.sh # custom output dir
```

### Signing

The helper is code-signed **at package build time** (`codesign`, ad-hoc by
default; use a Developer ID identity for distribution). `install.sh` performs a
**lazy re-sign**: if the copied helper's signature is invalid (for example after
a quarantine xattr is attached during download), it strips the quarantine flag
and re-signs so the `com.apple.security.hypervisor` entitlement is present.

### `NANOSB_HOME`

Every path resolves relative to `$NANOSB_HOME` (default `~/.nanosandbox`):

```bash
NANOSB_HOME=/opt/nanosb ./dist/nanosandbox-sdk-rust/install.sh
NANOSB_HOME=/opt/nanosb nanosb doctor
```

This is also how CI/Linux runs use a prebuilt runtime instead of the bundled one.