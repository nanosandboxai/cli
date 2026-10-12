#!/usr/bin/env bash
#
# test-packaged-boot.sh — AC9 end-to-end: install the packaged runtime bundle
# into a FRESH NANOSB_HOME and boot a real microVM through the installed helper,
# with zero extra setup.
#
# Exercises the WS9/AC9 path: scripts/package-sdk.sh → bundle install.sh →
# $NANOSB_HOME/{bin,libs} → ManagedRuntime resolves the installed helper →
# supervisor resolves libkrunfw/gvproxy from the installed NANOSB_HOME.
#
# Requires: macOS arm64, libkrun/gvproxy in the source home, a cached image.
#
#   scripts/test-packaged-boot.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Keep the NANOSB_HOME path short: the helper derives the per-sandbox console
# socket from it, and Unix socket paths are capped near 104 bytes (SUN_LEN).
TMP="$(mktemp -d /tmp/nsb9.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

DIST="$TMP/dist"
HOME_NEW="$TMP/nanosandbox-home"
SRC_HOME="${NANOSB_SRC_HOME:-$HOME/.nanosandbox}"

echo "==> 1/5 package the bundle (debug helper)"
DIST="$DIST" PROFILE=debug "$REPO_ROOT/scripts/package-sdk.sh" rust
BUNDLE="$DIST/nanosandbox-sdk-rust"
[ -x "$BUNDLE/bin/nanosb-runtime" ] || { echo "FAIL: bundled helper missing"; exit 1; }

echo "==> 2/5 install into a fresh NANOSB_HOME ($HOME_NEW)"
NANOSB_HOME="$HOME_NEW" "$BUNDLE/install.sh"
for f in bin/nanosb-runtime bin/gvproxy libs/libkrunfw.5.dylib guest-bin/exec-agent; do
  [ -e "$HOME_NEW/$f" ] || { echo "FAIL: not installed: $f"; exit 1; }
  echo "    installed: $f"
done

echo "==> 3/5 verify the installed helper is code-signed"
codesign --verify --verbose=1 "$HOME_NEW/bin/nanosb-runtime" 2>&1 | tail -1

echo "==> 4/5 reuse the existing image cache (images are pulled separately)"
for d in blobs extracted manifests bundles; do
  [ -d "$SRC_HOME/$d" ] && ln -s "$SRC_HOME/$d" "$HOME_NEW/$d" || true
done

echo "==> 5/5 boot a real microVM through the INSTALLED helper"
echo "    NANOSB_RUNTIME_BIN unset; NANOSB_HOME=$HOME_NEW -> resolves \$NANOSB_HOME/bin/nanosb-runtime"
env -u NANOSB_RUNTIME_BIN NANOSB_HOME="$HOME_NEW" NANOSB_E2E=1 \
  python3 "$REPO_ROOT/sdk/python/tests/test_e2e.py"

echo ""
echo "PASS: packaged install boots a microVM with zero extra setup (AC9)"
