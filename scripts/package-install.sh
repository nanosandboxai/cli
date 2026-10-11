#!/usr/bin/env bash
#
# package-install.sh — install the bundled runtime into $NANOSB_HOME.
#
# Copied into each dist bundle by scripts/package-sdk.sh. Lays out:
#   $NANOSB_HOME/bin/nanosb-runtime
#   $NANOSB_HOME/bin/gvproxy
#   $NANOSB_HOME/libs/libkrunfw.5.dylib
# and re-signs the helper lazily if its signature is missing/invalid.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NANOSB_HOME="${NANOSB_HOME:-$HOME/.nanosandbox}"

mkdir -p "$NANOSB_HOME/bin" "$NANOSB_HOME/libs"

cp "$HERE/bin/nanosb-runtime" "$NANOSB_HOME/bin/nanosb-runtime"; chmod +x "$NANOSB_HOME/bin/nanosb-runtime"
if [ -f "$HERE/bin/gvproxy" ]; then
  cp "$HERE/bin/gvproxy" "$NANOSB_HOME/bin/gvproxy"; chmod +x "$NANOSB_HOME/bin/gvproxy"
fi
if ls "$HERE"/libs/libkrunfw*.dylib >/dev/null 2>&1; then
  cp "$HERE"/libs/libkrunfw*.dylib "$NANOSB_HOME/libs/"
fi

# Lazy re-sign: if the helper's signature is invalid (e.g. after a copy with a
# quarantine xattr), re-sign ad-hoc so the hypervisor entitlement is present.
if command -v codesign >/dev/null 2>&1; then
  if ! codesign --verify --quiet "$NANOSB_HOME/bin/nanosb-runtime" 2>/dev/null; then
    echo "re-signing helper (lazy)"
    xattr -dr com.apple.quarantine "$NANOSB_HOME/bin/nanosb-runtime" 2>/dev/null || true
    codesign --force --sign - "$NANOSB_HOME/bin/nanosb-runtime" \
      || echo "warning: re-sign failed; the helper may need manual signing"
  fi
fi

echo "runtime installed into $NANOSB_HOME"
echo "  bin/nanosb-runtime, bin/gvproxy, libs/libkrunfw.5.dylib"