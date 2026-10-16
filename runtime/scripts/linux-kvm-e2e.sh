#!/usr/bin/env bash
# Linux/KVM live E2E harness for nanosandbox (Epic 9 · C1 gate / C9b live matrix).
#
# Boots a real microVM on a Linux+KVM host and asserts end-to-end command
# execution: the VM boots, runs a workload, and its stdout + exit code
# propagate. Self-skips cleanly (exit 0) on non-Linux hosts or when /dev/kvm is
# unavailable, so it is safe to wire into CI as a gate.
#
# Usage:
#   runtime/scripts/linux-kvm-e2e.sh [--image IMAGE] [--binary PATH] [--name NAME]
#
# Environment:
#   NANOSB_BINARY   override the nanosb binary path
#   NANOSB_HOME     state root (default: ~/.nanosandbox)
#
# Exit codes:
#   0  PASS, or SKIP (host is not a Linux/KVM host)
#   1  FAIL
set -uo pipefail

IMAGE="docker.io/library/alpine:latest"
BINARY="${NANOSB_BINARY:-}"
NAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --image)  IMAGE="$2";  shift 2 ;;
    --binary) BINARY="$2"; shift 2 ;;
    --name)   NAME="$2";   shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

skip() { echo "SKIP: $1"; exit 0; }

# ── platform gate ───────────────────────────────────────────────────────────
[ "$(uname -s)" = "Linux" ] || skip "not a Linux host ($(uname -s))"
[ -e /dev/kvm ] || skip "/dev/kvm not present (no KVM)"
if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
  skip "/dev/kvm not accessible — add the user to the 'kvm' group"
fi

NANOSB_HOME="${NANOSB_HOME:-$HOME/.nanosandbox}"
have_gvproxy=false
if command -v gvproxy >/dev/null 2>&1 || [ -x "$NANOSB_HOME/bin/gvproxy" ]; then
  have_gvproxy=true
fi

# ── locate the binary ───────────────────────────────────────────────────────
if [ -z "$BINARY" ]; then
  for c in "$PWD/target/release/nanosb" "$PWD/target/debug/nanosb"; do
    if [ -x "$c" ]; then BINARY="$c"; break; fi
  done
fi
if [ -z "$BINARY" ] || [ ! -x "$BINARY" ]; then
  echo "FAIL: nanosb binary not found (set NANOSB_BINARY or build it)" >&2
  exit 1
fi

[ -n "$NAME" ] || NAME="linux-kvm-e2e-$$"
MARKER="linux-kvm-e2e-ok-$$"

echo "== nanosandbox Linux/KVM live E2E =="
echo "binary:     $BINARY"
echo "image:      $IMAGE"
echo "gvproxy:    $have_gvproxy"
echo "NANOSB_HOME:$NANOSB_HOME"

# ── prerequisites ───────────────────────────────────────────────────────────
echo "-- doctor --"
if ! "$BINARY" doctor; then
  echo "FAIL: 'nanosb doctor' reported missing prerequisites" >&2
  exit 1
fi

"$BINARY" rm -f "$NAME" >/dev/null 2>&1 || true

# ── boot + run a workload (synchronous) ─────────────────────────────────────
echo "-- boot + exec --"
START_MS=$(date +%s%3N)
if ! "$BINARY" run --name "$NAME" "$IMAGE" /bin/echo "$MARKER"; then
  echo "FAIL: 'nanosb run' exited non-zero" >&2
  "$BINARY" rm -f "$NAME" >/dev/null 2>&1 || true
  exit 1
fi
END_MS=$(date +%s%3N)

SANDBOX_DIR="$NANOSB_HOME/sandboxes/$NAME"
CONSOLE_LOG="$SANDBOX_DIR/logs/console.log"
STATE_JSON="$SANDBOX_DIR/state.json"

ok=true
if ! grep -q "$MARKER" "$CONSOLE_LOG" 2>/dev/null; then
  echo "FAIL: expected stdout '$MARKER' not found in $CONSOLE_LOG" >&2
  ok=false
fi

EXIT_CODE=$(sed -n 's/.*"exit_code"[[:space:]]*:[[:space:]]*\(-\?[0-9]\+\).*/\1/p' "$STATE_JSON" 2>/dev/null | head -1)
if [ "$EXIT_CODE" != "0" ]; then
  echo "FAIL: expected exit_code 0 in state.json, got '${EXIT_CODE:-<none>}'" >&2
  ok=false
fi

"$BINARY" rm -f "$NAME" >/dev/null 2>&1 || true

# ── Epic 11 · M4: non-OCI (local_dir) rootfs + ownable entrypoint ───────────
echo "-- non-OCI (local_dir) rootfs via 'nanosb supervise --foreground' --"
EPIC11_TMP="$(mktemp -d)"
EPIC11_OK=true

cat > "$EPIC11_TMP/init.c" <<'C'
int main(void) { return 42; }
C
ROOTFS="$EPIC11_TMP/rootfs"
mkdir -p "$ROOTFS" "$EPIC11_TMP/guest-bin"
printf '#!/bin/sh\n' > "$EPIC11_TMP/guest-bin/exec-agent"

if gcc -static -o "$ROOTFS/init" "$EPIC11_TMP/init.c" 2>/dev/null; then
  cat > "$EPIC11_TMP/spec.json" <<JSON
{"image":"alpine","name":"$NAME-localdir","rootfs":{"kind":"local_dir","path":"$ROOTFS"},"command":"/init"}
JSON
  "$BINARY" rm -f "$NAME-localdir" >/dev/null 2>&1 || true
  NANOSB_GUEST_BIN_DIR="$EPIC11_TMP/guest-bin" "$BINARY" supervise --foreground \
    --name "$NAME-localdir" --spec "$EPIC11_TMP/spec.json"
  LOCALDIR_CODE=$?
  if [ "$LOCALDIR_CODE" != "42" ]; then
    echo "FAIL: local_dir rootfs exit code $LOCALDIR_CODE != 42" >&2
    cat "$NANOSB_HOME/sandboxes/$NAME-localdir/state.json" 2>/dev/null || true
    EPIC11_OK=false
  else
    echo "PASS: local_dir rootfs booted (no OCI bundle) and propagated exit 42"
  fi
  PIDFILE="$NANOSB_HOME/sandboxes/$NAME-localdir/supervisor.pid"
  if [ -s "$PIDFILE" ]; then
    echo "PASS: supervisor.pid written ($(cat "$PIDFILE"))"
  else
    echo "FAIL: supervisor.pid not written at $PIDFILE" >&2
    EPIC11_OK=false
  fi
  "$BINARY" rm -f "$NAME-localdir" >/dev/null 2>&1 || true
else
  echo "SKIP: gcc -static unavailable; cannot build a local_dir rootfs fixture"
fi

# Exec-channel wiring through the supported entrypoint (needs a real host-arch
# guest exec-agent; otherwise covered by unit tests + the verbs E2E).
if [ -x "$NANOSB_HOME/guest-bin/exec-agent" ]; then
  cat > "$EPIC11_TMP/spec2.json" <<JSON
{"image":"alpine","name":"$NAME-exec","rootfs":{"kind":"local_dir","path":"$ROOTFS"}}
JSON
  "$BINARY" rm -f "$NAME-exec" >/dev/null 2>&1 || true
  "$BINARY" supervise --name "$NAME-exec" --spec "$EPIC11_TMP/spec2.json" >/dev/null 2>&1
  EXEC_SOCK="$NANOSB_HOME/sandboxes/$NAME-exec/exec.sock"
  for _ in $(seq 1 60); do [ -S "$EXEC_SOCK" ] && break; sleep 0.5; done
  if [ -S "$EXEC_SOCK" ]; then
    echo "PASS: exec channel (exec.sock) wired through 'nanosb supervise'"
  else
    echo "FAIL: exec.sock not present at $EXEC_SOCK" >&2
    EPIC11_OK=false
  fi
  "$BINARY" rm -f "$NAME-exec" >/dev/null 2>&1 || true
else
  echo "SKIP: no real guest exec-agent staged; exec wiring covered by unit tests"
fi

rm -rf "$EPIC11_TMP"
$EPIC11_OK || ok=false

if ! $ok; then
  echo "state.json:"; cat "$STATE_JSON" 2>/dev/null
  echo "console.log:"; cat "$CONSOLE_LOG" 2>/dev/null
  exit 1
fi

echo "boot+exec wall time: $(( END_MS - START_MS )) ms"
echo "PASS: live Linux/KVM VM booted, ran the workload, stdout + exit code propagated"
exit 0
