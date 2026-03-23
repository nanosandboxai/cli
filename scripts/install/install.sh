#!/bin/bash
#
# Nanosandbox Installer
#
# A single script that sets up everything needed to run nanosandbox:
#   1. Downloads the nanosb binary (macOS arm64)
#   2. Installs runtime dependencies (libkrun, gvproxy)
#   3. Codesigns the binary on macOS
#
# Usage:
#   curl -fsSL https://github.com/nanosandboxai/cli/releases/latest/download/install.sh | bash
#
# Environment variables:
#   NANOSB_VERSION   - Version to install (default: "latest")
#   INSTALL_DIR      - Binary install directory (default: ~/.local/bin)
#   NANOSB_BINARY    - Path to a local binary to install (skips download)
#
# Supported platforms:
#   - macOS Apple Silicon (arm64) — full support (binary + deps)
#   - Linux x86_64 / aarch64     — deps only (binary must be built from source)
#

set -e

# =============================================================================
# Configuration
# =============================================================================

NANOSB_VERSION="${NANOSB_VERSION:-latest}"
RELEASE_REPO="nanosandboxai/cli"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
GVPROXY_VERSION="v0.8.7"
GVPROXY_REPO="https://github.com/containers/gvisor-tap-vsock/releases/download"

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
# Step 1: Download nanosb binary
# =============================================================================

download_binary() {
    header "Installing nanosb binary"

    mkdir -p "$INSTALL_DIR"

    # If a local binary is provided, use it directly (for testing)
    if [[ -n "$NANOSB_BINARY" ]]; then
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
# Step 2a: macOS dependencies
# =============================================================================

install_macos_deps() {
    # --- Pre-flight checks ---
    if [[ "$ARCH" != "arm64" ]]; then
        error "Nanosandbox requires Apple Silicon (M1/M2/M3/M4). Detected: $ARCH"
    fi
    success "Running on macOS Apple Silicon ($ARCH)"

    if sysctl -n kern.hv_support 2>/dev/null | grep -q "1"; then
        success "Hypervisor.framework is available"
    else
        warn "Hypervisor.framework may not be available"
        warn "VM creation will likely fail without it"
    fi

    # --- Homebrew ---
    header "Checking Homebrew"

    if command -v brew &>/dev/null; then
        success "Homebrew is already installed: $(brew --version | head -1)"
    else
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        if [[ -f "/opt/homebrew/bin/brew" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi

        if command -v brew &>/dev/null; then
            success "Homebrew installed successfully"
        else
            error "Homebrew installation failed"
        fi
    fi

    # --- libkrun ---
    header "Installing libkrun"

    if [[ -f "/opt/homebrew/lib/libkrun.dylib" ]]; then
        success "libkrun is already installed at /opt/homebrew/lib/libkrun.dylib"
    else
        info "Adding slp/krun tap..."
        brew tap slp/krun || warn "Tap may already exist"

        info "Installing libkrun (this may take a few minutes)..."
        brew install slp/krun/libkrun

        if [[ -f "/opt/homebrew/lib/libkrun.dylib" ]]; then
            success "libkrun installed successfully"
        else
            error "libkrun.dylib not found after install"
        fi
    fi

    # --- Codesign nanosb binary ---
    header "Codesigning nanosb"
    codesign_binary
}

# =============================================================================
# Step 2b: Linux dependencies
# =============================================================================

install_linux_deps() {
    # --- KVM check ---
    if [[ -e /dev/kvm ]]; then
        if [[ -r /dev/kvm && -w /dev/kvm ]]; then
            success "KVM is available and accessible"
        else
            warn "KVM exists but may not be accessible"
            warn "Add your user to the kvm group: sudo usermod -aG kvm \$USER"
            warn "Then log out and log back in"
        fi
    else
        warn "/dev/kvm not found — KVM may not be enabled"
        warn "Enable in BIOS/UEFI and load module: sudo modprobe kvm_intel (or kvm_amd)"
    fi

    # --- libkrun ---
    header "Installing libkrun"

    # Check if already installed
    local libkrun_found=false
    for path in /usr/lib/libkrun.so /usr/lib64/libkrun.so /usr/local/lib/libkrun.so \
                /usr/lib/x86_64-linux-gnu/libkrun.so /usr/lib/aarch64-linux-gnu/libkrun.so; do
        if [[ -f "$path" ]]; then
            success "libkrun already installed at: $path"
            libkrun_found=true
            break
        fi
    done

    if [[ "$libkrun_found" != "true" ]]; then
        if command -v apt-get &>/dev/null; then
            install_debian_libkrun
        elif command -v dnf &>/dev/null; then
            install_fedora_libkrun
        else
            error "Unsupported Linux distribution. Install libkrun manually: https://github.com/containers/libkrun"
        fi
    fi
}

install_debian_libkrun() {
    info "Detected Debian/Ubuntu — building libkrun from source..."

    info "Installing build dependencies..."
    sudo apt-get update
    sudo apt-get install -y \
        build-essential \
        git \
        python3 \
        python3-pip \
        ninja-build \
        pkg-config \
        curl

    local build_dir
    build_dir="$(mktemp -d)"
    cd "$build_dir"

    if ldconfig -p | grep -q libkrun; then
        success "libkrun already in library cache"
    else
        info "Cloning and building libkrun..."
        git clone https://github.com/containers/libkrun.git
        cd libkrun

        if ! command -v cargo &>/dev/null; then
            info "Installing Rust..."
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source "$HOME/.cargo/env"
        fi

        make
        sudo make install
    fi

    sudo ldconfig

    cd /
    rm -rf "$build_dir"

    if ldconfig -p | grep -q libkrun; then
        success "libkrun installed successfully"
    else
        warn "libkrun not found in library cache after build"
    fi
}

install_fedora_libkrun() {
    info "Detected Fedora/RHEL — installing libkrun via dnf..."

    sudo dnf install -y libkrun

    if ldconfig -p 2>/dev/null | grep -q libkrun; then
        success "libkrun installed successfully"
    else
        warn "libkrun not found in library cache after install"
    fi
}

# =============================================================================
# Step 3: gvproxy (cross-platform)
# =============================================================================

install_gvproxy() {
    header "Installing gvproxy"

    # Check if already installed
    if command -v gvproxy &>/dev/null; then
        success "gvproxy is already installed: $(which gvproxy)"
        return 0
    fi

    if [[ -x "$HOME/.local/bin/gvproxy" ]]; then
        success "gvproxy is already installed: $HOME/.local/bin/gvproxy"
        return 0
    fi

    # Determine binary name
    local binary_name
    case "$OS" in
        Darwin)
            binary_name="gvproxy-darwin"
            ;;
        Linux)
            case "$ARCH" in
                x86_64|amd64)  binary_name="gvproxy-linux-amd64" ;;
                aarch64|arm64) binary_name="gvproxy-linux-arm64" ;;
                *) error "No gvproxy binary available for architecture: $ARCH" ;;
            esac
            ;;
        *)
            error "No gvproxy binary available for OS: $OS"
            ;;
    esac

    local download_url="${GVPROXY_REPO}/${GVPROXY_VERSION}/${binary_name}"

    info "Downloading gvproxy ${GVPROXY_VERSION} for ${OS} ${ARCH}..."

    local tmp_dir
    tmp_dir="$(mktemp -d)"

    if ! curl -fsSL "$download_url" -o "${tmp_dir}/gvproxy"; then
        rm -rf "$tmp_dir"
        error "Failed to download gvproxy from ${download_url}"
    fi

    chmod +x "${tmp_dir}/gvproxy"

    mkdir -p "$INSTALL_DIR"
    install -m 0755 "${tmp_dir}/gvproxy" "${INSTALL_DIR}/gvproxy"

    rm -rf "$tmp_dir"

    success "gvproxy installed at ${INSTALL_DIR}/gvproxy"
}

# =============================================================================
# Codesign helper (macOS only)
# =============================================================================

codesign_binary() {
    local binary_path="${INSTALL_DIR}/nanosb"

    if [[ ! -f "$binary_path" ]]; then
        # Try common locations
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
        info "After installing, codesign with:"
        info "  codesign --entitlements entitlements.plist --force -s - \$(which nanosb)"
        return 0
    fi

    # Always re-codesign locally.  Ad-hoc signatures applied in CI are
    # invalidated after download, so we must re-sign on this machine.
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

download_binary

case "$OS" in
    Darwin)
        install_macos_deps
        ;;
    Linux)
        install_linux_deps
        ;;
    *)
        error "Unsupported operating system: $OS"
        ;;
esac

install_gvproxy

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
echo "  gvproxy:    ${INSTALL_DIR}/gvproxy"
case "$OS" in
    Darwin)
        echo "  libkrun:    /opt/homebrew/lib/libkrun.dylib"
        echo "  Backend:    Hypervisor.framework (Apple Silicon)"
        ;;
    Linux)
        echo "  libkrun:    $(ldconfig -p 2>/dev/null | grep libkrun | head -1 | awk '{print $NF}' || echo 'installed')"
        echo "  Backend:    KVM"
        ;;
esac
echo ""
echo "Run 'nanosb doctor' to verify the installation."
echo ""
