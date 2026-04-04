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
#   DEPS_VERSION     - Dependencies version (default: same as NANOSB_VERSION)
#   INSTALL_DIR      - Binary install directory (default: ~/.local/bin)
#   NANOSB_BINARY    - Path to a local binary to install (skips download)
#

set -e

# =============================================================================
# Configuration
# =============================================================================

NANOSB_VERSION="${NANOSB_VERSION:-latest}"
DEPS_VERSION="${DEPS_VERSION:-$NANOSB_VERSION}"
RELEASE_REPO="nanosandboxai/cli"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# =============================================================================
# Helpers
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

header() {
    echo ""
    echo "========================================"
    echo "  $1"
    echo "========================================"
    echo ""
}

# =============================================================================
# Platform detection
# =============================================================================

OS="$(uname -s)"
ARCH="$(uname -m)"

header "Nanosandbox Installer"

info "Detected platform: ${OS} ${ARCH}"

# =============================================================================
# Step 1: Install runtime dependencies (libkrunfw + gvproxy)
# =============================================================================

install_deps() {
    header "Installing runtime dependencies"

    local deps_install_url
    if [[ "$DEPS_VERSION" == "latest" ]]; then
        deps_install_url="https://github.com/nanosandboxai/install-deps/releases/latest/download/install.sh"
    else
        deps_install_url="https://github.com/nanosandboxai/install-deps/releases/download/${DEPS_VERSION}/install.sh"
    fi

    info "Downloading dependency installer..."
    if curl -fsSL "$deps_install_url" | DEPS_VERSION="$DEPS_VERSION" bash; then
        success "Runtime dependencies installed"
    else
        warn "Failed to install runtime dependencies via install-deps"
        warn "You may need to install libkrunfw and gvproxy manually"
        warn "See: https://github.com/nanosandboxai/install-deps"
    fi
}

# =============================================================================
# Step 2: Download nanosb binary
# =============================================================================

download_binary() {
    header "Installing nanosb binary"

    mkdir -p "$INSTALL_DIR"

    # If a local binary is provided, use it directly (for testing)
    if [[ -n "${NANOSB_BINARY:-}" ]]; then
        if [[ ! -f "$NANOSB_BINARY" ]]; then
            error "NANOSB_BINARY set but file not found: $NANOSB_BINARY"
        fi
        info "Installing nanosb from local path: $NANOSB_BINARY"
        cp "$NANOSB_BINARY" "${INSTALL_DIR}/nanosb"
        chmod +x "${INSTALL_DIR}/nanosb"
        success "nanosb installed at ${INSTALL_DIR}/nanosb"
        return 0
    fi

    if [[ "$OS" != "Darwin" || "$ARCH" != "arm64" ]]; then
        warn "Pre-built binaries are currently available for macOS arm64 only."
        warn "For other platforms, build from source:"
        warn "  git clone https://github.com/nanosandboxai/runtime.git"
        warn "  cd runtime && cargo build --release --features cli"
        return 0
    fi

    local asset_name="nanosb"
    local url

    if [[ "$NANOSB_VERSION" == "latest" ]]; then
        url="https://github.com/${RELEASE_REPO}/releases/latest/download/${asset_name}"
    else
        url="https://github.com/${RELEASE_REPO}/releases/download/v${NANOSB_VERSION}/${asset_name}"
    fi

    # Check if already installed
    if command -v nanosb &>/dev/null; then
        local current_version
        current_version="$(nanosb --version 2>/dev/null || true)"
        success "nanosb is already installed: ${current_version}"
        if [[ "$NANOSB_VERSION" == "latest" ]]; then
            info "Reinstalling latest version..."
        fi
    fi

    info "Downloading nanosb from ${url}..."
    if curl -fsSL "$url" -o "${INSTALL_DIR}/nanosb"; then
        chmod +x "${INSTALL_DIR}/nanosb"
        success "nanosb installed at ${INSTALL_DIR}/nanosb"
    else
        warn "Failed to download nanosb binary."
        warn "The release may not exist yet. You can build from source instead."
        return 0
    fi
}

# =============================================================================
# Step 3: Codesign (macOS only)
# =============================================================================

codesign_binary() {
    local binary_path="${INSTALL_DIR}/nanosb"

    if [[ ! -f "$binary_path" ]]; then
        for candidate in \
            "$(which nanosb 2>/dev/null || true)" \
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

    local entitlements_plist
    entitlements_plist="$(mktemp /tmp/nanosb-entitlements.XXXXXX.plist)"
    cat > "$entitlements_plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.hypervisor</key>
    <true/>
</dict>
</plist>
PLIST

    if codesign --entitlements "$entitlements_plist" --force -s - "$binary_path" 2>/dev/null; then
        success "Signed nanosb with com.apple.security.hypervisor: $binary_path"
    else
        warn "Failed to sign $binary_path"
        warn "Sign manually: codesign --entitlements entitlements.plist --force -s - $binary_path"
    fi

    rm -f "$entitlements_plist"
}

# =============================================================================
# Main
# =============================================================================

# 1. Install runtime dependencies first
install_deps

# 2. Download CLI binary
download_binary

# 3. Codesign on macOS
if [[ "$OS" == "Darwin" ]]; then
    header "Codesigning nanosb"
    codesign_binary
fi

# =============================================================================
# PATH check
# =============================================================================

if ! echo "$PATH" | tr ':' '\n' | grep -q "$INSTALL_DIR"; then
    echo ""
    warn "${INSTALL_DIR} is not in your PATH."
    warn "Add it to your shell profile:"
    warn "  echo 'export PATH=\"${INSTALL_DIR}:\$PATH\"' >> ~/.zshrc"
    warn "Then reload: source ~/.zshrc"
fi

# =============================================================================
# Summary
# =============================================================================

header "Installation Complete"

echo "Installed components:"
echo "  nanosb:     ${INSTALL_DIR}/nanosb"
echo "  libkrunfw:  /usr/local/lib/"
echo "  gvproxy:    ~/.local/bin/gvproxy"
case "$OS" in
    Darwin) echo "  Backend:    Hypervisor.framework (Apple Silicon)" ;;
    Linux)  echo "  Backend:    KVM" ;;
esac
echo ""
echo "Run 'nanosb doctor' to verify the installation."
echo ""
