#!/bin/bash
# Install build dependencies on openSUSE (zypper)
set -euo pipefail

zypper --non-interactive --gpg-auto-import-keys refresh

# Tumbleweed packages pyelftools under a versioned python3xx name.
PYELFTOOLS="python3-pyelftools"
if ! zypper --non-interactive install --no-recommends "$PYELFTOOLS" 2>/dev/null; then
    PYELFTOOLS="python311-pyelftools"
fi

zypper --non-interactive install --no-recommends \
    gcc \
    make \
    curl \
    ca-certificates \
    git \
    python3 \
    bc \
    flex \
    bison \
    libelf-devel \
    pkg-config \
    libopenssl-devel \
    cpio \
    patch \
    diffutils \
    gawk \
    clang-devel \
    glibc-devel-static \
    rust \
    cargo \
    "$PYELFTOOLS"

# Install Go from upstream (distro Go may be too old for deps)
if ! command -v go >/dev/null 2>&1 || ! go version 2>/dev/null | grep -qE 'go1\.(2[4-9]|[3-9])'; then
    curl -fsSL "https://go.dev/dl/go1.24.0.linux-amd64.tar.gz" | tar -C /usr/local -xzf -
    export PATH="/usr/local/go/bin:$PATH"
    echo 'export PATH="/usr/local/go/bin:$PATH"' >> "$HOME/.bashrc"
fi

echo "Build dependencies installed (zypper)"
