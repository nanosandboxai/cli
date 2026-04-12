#!/bin/bash
#
# Nanosandbox CLI Installer
#
# Installs the nanosb CLI binary and its runtime dependencies.
#
#   1. Installs runtime dependencies via install-deps (libkrunfw + gvproxy)
#   2. Downloads the nanosb binary
#   3. Codesigns on macOS (Hypervisor.framework entitlement)
#
# Usage:
#   curl -fsSL https://github.com/nanosandboxai/cli/releases/latest/download/install.sh | bash
#
# Environment variables:
#   NANOSB_VERSION   - CLI version to install (default: "latest")
#   DEPS_VERSION     - Dependencies version (default: "latest")
#   INSTALL_DIR      - Binary install directory (default: ~/.local/bin)
#   NANOSB_BINARY    - Path to a local binary to install (skips download)
#

set -eo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

NANOSB_VERSION="${NANOSB_VERSION:-latest}"
NANOSB_VERSION="${NANOSB_VERSION#v}"   # strip leading "v" — tags use v-prefix internally
DEPS_VERSION="${DEPS_VERSION:-latest}"
RELEASE_REPO="nanosandboxai/cli"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# ─── Helpers ─────────────────────────────────────────────────────────────────

if [ -t 1 ]; then
    BLUE=$'\033[0;34m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
    RED=$'\033[0;31m'; NC=$'\033[0m'
else
    BLUE=""; GREEN=""; YELLOW=""; RED=""; NC=""
fi

info()    { printf '  %s\n' "$1"; }
success() { printf '  %s[OK]%s %s\n' "$GREEN" "$NC" "$1"; }
warn()    { printf '  %s[WARN]%s %s\n' "$YELLOW" "$NC" "$1"; }
error()   { printf '  %s[ERROR]%s %s\n' "$RED" "$NC" "$1" >&2; exit 1; }
header()  { printf '\n%s==>%s %s\n' "$BLUE" "$NC" "$1"; }

# ─── Platform detection ──────────────────────────────────────────────────────

OS="$(uname -s)"
ARCH="$(uname -m)"

echo "Nanosandbox CLI Installer"
echo "========================="
info "Platform: ${OS} ${ARCH}"

# ─── Step 1: Runtime dependencies (libkrunfw + gvproxy) ──────────────────────

# Resolve "latest" to the most recent install-deps release tag, including
# prereleases. Required because GitHub's /releases/latest/ redirect only matches
# stable (non-prerelease) releases — if install-deps has only prereleases, the
# /latest/ URL returns 404.
resolve_deps_version() {
    curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/nanosandboxai/install-deps/releases" \
        2>/dev/null \
        | grep -m1 '"tag_name":' \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

install_deps() {
    header "Installing runtime dependencies"

    local resolved_version="$DEPS_VERSION"
    if [[ "$DEPS_VERSION" == "latest" ]]; then
        resolved_version="$(resolve_deps_version || true)"
        if [[ -z "$resolved_version" ]]; then
            warn "Could not resolve install-deps release tag"
            info "Install libkrunfw + gvproxy manually from:"
            info "  https://github.com/nanosandboxai/install-deps"
            return 0
        fi
        info "Resolved install-deps latest → ${resolved_version}"
    fi

    local deps_install_url="https://github.com/nanosandboxai/install-deps/releases/download/${resolved_version}/install.sh"
    local tmpfile
    tmpfile="$(mktemp -t nanosb-install-deps.XXXXXX)"

    info "Downloading install-deps installer..."
    if ! curl -fsSL "$deps_install_url" -o "$tmpfile"; then
        warn "Could not download install-deps installer (release ${resolved_version})"
        info "Install libkrunfw + gvproxy manually from:"
        info "  https://github.com/nanosandboxai/install-deps"
        rm -f "$tmpfile"
        return 0
    fi

    info "Running install-deps installer..."
    if DEPS_VERSION="$resolved_version" bash "$tmpfile"; then
        success "Runtime dependencies installed"
    else
        warn "install-deps installer exited with an error"
        warn "Install libkrunfw + gvproxy manually if needed"
        warn "See: https://github.com/nanosandboxai/install-deps"
    fi
    rm -f "$tmpfile"
}

# ─── Step 2: Download nanosb binary ──────────────────────────────────────────

download_binary() {
    header "Installing nanosb binary"

    mkdir -p "$INSTALL_DIR"

    # Local-binary override (used by tests / dev installs)
    if [[ -n "${NANOSB_BINARY:-}" ]]; then
        [[ -f "$NANOSB_BINARY" ]] || error "NANOSB_BINARY not found: $NANOSB_BINARY"
        info "Using local binary: $NANOSB_BINARY"
        cp "$NANOSB_BINARY" "${INSTALL_DIR}/nanosb"
        chmod +x "${INSTALL_DIR}/nanosb"
        success "Installed at ${INSTALL_DIR}/nanosb"
        return 0
    fi

    if [[ "$OS" != "Darwin" || "$ARCH" != "arm64" ]]; then
        warn "Pre-built binaries are available for macOS arm64 only."
        info "For other platforms, build from source:"
        info "  git clone https://github.com/nanosandboxai/runtime.git"
        info "  cd runtime && cargo build --release --features cli"
        return 0
    fi

    local url
    if [[ "$NANOSB_VERSION" == "latest" ]]; then
        url="https://github.com/${RELEASE_REPO}/releases/latest/download/nanosb"
    else
        url="https://github.com/${RELEASE_REPO}/releases/download/v${NANOSB_VERSION}/nanosb"
    fi

    if command -v nanosb &>/dev/null; then
        success "nanosb already installed: $(nanosb --version 2>/dev/null || echo 'unknown')"
        [[ "$NANOSB_VERSION" == "latest" ]] && info "Reinstalling latest..."
    fi

    info "Downloading from ${url}"
    if curl -fsSL "$url" -o "${INSTALL_DIR}/nanosb"; then
        chmod +x "${INSTALL_DIR}/nanosb"
        success "Installed at ${INSTALL_DIR}/nanosb"
    else
        warn "Failed to download nanosb (release may not exist yet)"
        info "Build from source instead — see project README"
        return 0
    fi
}

# ─── Step 3: Codesign (macOS only) ───────────────────────────────────────────

codesign_binary() {
    local binary_path="${INSTALL_DIR}/nanosb"

    if [[ ! -f "$binary_path" ]]; then
        for candidate in \
            "$(command -v nanosb 2>/dev/null || true)" \
            "./target/debug/nanosb" \
            "./target/release/nanosb" \
            "/usr/local/bin/nanosb"; do
            if [[ -n "$candidate" && -f "$candidate" ]]; then
                binary_path="$candidate"
                break
            fi
        done
    fi

    if [[ ! -f "$binary_path" ]]; then
        info "nanosb binary not found — skipping codesign"
        return 0
    fi

    local entitlements
    entitlements="$(mktemp /tmp/nanosb-entitlements.XXXXXX.plist)"
    cat > "$entitlements" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.hypervisor</key>
    <true/>
</dict>
</plist>
PLIST

    if codesign --entitlements "$entitlements" --force -s - "$binary_path" 2>/dev/null; then
        success "Signed with com.apple.security.hypervisor"
    else
        warn "codesign failed for $binary_path"
        info "Sign manually: codesign --entitlements <plist> --force -s - $binary_path"
    fi

    rm -f "$entitlements"
}

# ─── Main ────────────────────────────────────────────────────────────────────

install_deps
download_binary
[[ "$OS" == "Darwin" ]] && { header "Codesigning nanosb"; codesign_binary; }

# PATH check
if ! printf '%s' ":$PATH:" | grep -q ":${INSTALL_DIR}:"; then
    header "PATH not configured"
    warn "${INSTALL_DIR} is not in your PATH"
    info "Add to your shell profile:"
    info "  echo 'export PATH=\"${INSTALL_DIR}:\$PATH\"' >> ~/.zshrc"
    info "Then: source ~/.zshrc"
fi

# Summary
header "Installation complete"
case "$OS" in
    Darwin) backend="Hypervisor.framework (Apple Silicon)" ;;
    Linux)  backend="KVM" ;;
    *)      backend="$OS" ;;
esac
cat <<EOF
  nanosb     → ${INSTALL_DIR}/nanosb
  libkrunfw  → /usr/local/lib/
  gvproxy    → ${HOME}/.local/bin/gvproxy
  backend    → ${backend}

  Run 'nanosb doctor' to verify the installation.
EOF
