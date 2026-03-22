#!/usr/bin/env bash
# test/lib.sh - Shared test utilities for nanosb CLI tests
#
# Source this file in each test script:
#   source "$(dirname "$0")/lib.sh"

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Counters ────────────────────────────────────────────────────────
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
CURRENT_TEST=""

# ── Binary ──────────────────────────────────────────────────────────
NANOSB="${NANOSB:-nanosb}"

# Verify the binary exists
if ! command -v "$NANOSB" &>/dev/null; then
  echo -e "${RED}ERROR: '$NANOSB' not found in PATH.${RESET}"
  echo "Set NANOSB=/path/to/nanosb or ensure it is on your PATH."
  exit 1
fi

# ── Temp directory for test artifacts ───────────────────────────────
TEST_TMPDIR="$(mktemp -d)"
cleanup_tmpdir() { rm -rf "$TEST_TMPDIR"; }
trap cleanup_tmpdir EXIT

# ── Test lifecycle ──────────────────────────────────────────────────

# Begin a named test case
begin_test() {
  CURRENT_TEST="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  echo -e "  ${BLUE}RUN${RESET}  $CURRENT_TEST"
}

# Mark current test as passed
pass_test() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "  ${GREEN}PASS${RESET} $CURRENT_TEST"
}

# Mark current test as failed with a message
fail_test() {
  local msg="${1:-}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "  ${RED}FAIL${RESET} $CURRENT_TEST"
  [[ -n "$msg" ]] && echo -e "       ${RED}$msg${RESET}"
}

# Skip a test with a reason
skip_test() {
  local reason="${1:-}"
  TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
  echo -e "  ${YELLOW}SKIP${RESET} $CURRENT_TEST${reason:+ ($reason)}"
}

# ── Assertions ──────────────────────────────────────────────────────

# Assert exit code is 0
assert_success() {
  local cmd="$1"
  local output
  if output=$(eval "$cmd" 2>&1); then
    echo "$output"
    return 0
  else
    local rc=$?
    echo "$output"
    fail_test "Expected success (exit 0), got exit $rc"
    echo "       Command: $cmd"
    echo "       Output:  $(echo "$output" | head -5)"
    return 1
  fi
}

# Assert exit code is non-zero
assert_failure() {
  local cmd="$1"
  local output
  if output=$(eval "$cmd" 2>&1); then
    echo "$output"
    fail_test "Expected failure (non-zero exit), got exit 0"
    echo "       Command: $cmd"
    return 1
  else
    echo "$output"
    return 0
  fi
}

# Assert output contains a substring
assert_contains() {
  local output="$1"
  local expected="$2"
  if echo "$output" | grep -qF -- "$expected"; then
    return 0
  else
    fail_test "Expected output to contain: '$expected'"
    echo "       Got: $(echo "$output" | head -5)"
    return 1
  fi
}

# Assert output matches a regex
assert_matches() {
  local output="$1"
  local pattern="$2"
  if echo "$output" | grep -qE -- "$pattern"; then
    return 0
  else
    fail_test "Expected output to match pattern: '$pattern'"
    echo "       Got: $(echo "$output" | head -5)"
    return 1
  fi
}

# Assert output does NOT contain a substring
assert_not_contains() {
  local output="$1"
  local unexpected="$2"
  if echo "$output" | grep -qF -- "$unexpected"; then
    fail_test "Expected output NOT to contain: '$unexpected'"
    echo "       Got: $(echo "$output" | head -5)"
    return 1
  else
    return 0
  fi
}

# Assert output is valid JSON
assert_json() {
  local output="$1"
  if echo "$output" | python3 -m json.tool &>/dev/null; then
    return 0
  else
    fail_test "Expected valid JSON output"
    echo "       Got: $(echo "$output" | head -5)"
    return 1
  fi
}

# Assert a JSON field exists (using python3)
assert_json_field() {
  local output="$1"
  local field="$2"
  if echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if isinstance(data, list):
    data = data[0] if data else {}
assert '$field' in data, f'Field $field not found in {list(data.keys())}'
" 2>/dev/null; then
    return 0
  else
    fail_test "Expected JSON to have field: '$field'"
    return 1
  fi
}

# Assert output is non-empty
assert_not_empty() {
  local output="$1"
  if [[ -n "$output" ]]; then
    return 0
  else
    fail_test "Expected non-empty output"
    return 1
  fi
}

# ── Summary ─────────────────────────────────────────────────────────

print_suite_header() {
  local name="$1"
  echo ""
  echo -e "${BOLD}━━━ $name ━━━${RESET}"
}

print_summary() {
  echo ""
  echo -e "${BOLD}──────────────────────────────────${RESET}"
  echo -e "  Total:   $TESTS_RUN"
  echo -e "  ${GREEN}Passed:  $TESTS_PASSED${RESET}"
  if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "  ${RED}Failed:  $TESTS_FAILED${RESET}"
  else
    echo -e "  Failed:  0"
  fi
  if [[ $TESTS_SKIPPED -gt 0 ]]; then
    echo -e "  ${YELLOW}Skipped: $TESTS_SKIPPED${RESET}"
  fi
  echo -e "${BOLD}──────────────────────────────────${RESET}"

  if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "  ${RED}${BOLD}SOME TESTS FAILED${RESET}"
    return 1
  else
    echo -e "  ${GREEN}${BOLD}ALL TESTS PASSED${RESET}"
    return 0
  fi
}

# ── Stderr helpers ──────────────────────────────────────────────────

# Run a command, capture stdout and stderr separately.
# Sets: CMD_STDOUT, CMD_STDERR, CMD_RC
run_split() {
  local cmd="$1"
  CMD_STDERR="$TEST_TMPDIR/.stderr"
  CMD_STDOUT=$(eval "$cmd" 2>"$CMD_STDERR") && CMD_RC=0 || CMD_RC=$?
  CMD_STDERR=$(cat "$CMD_STDERR")
}

# Assert stderr contains a substring
assert_stderr_contains() {
  local stderr="$1"
  local expected="$2"
  if echo "$stderr" | grep -qF -- "$expected"; then
    return 0
  else
    fail_test "Expected stderr to contain: '$expected'"
    echo "       Stderr: $(echo "$stderr" | head -3)"
    return 1
  fi
}

# Assert output is a JSON array
assert_json_array() {
  local output="$1"
  if echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert isinstance(data, list), f'Expected list, got {type(data).__name__}'
" 2>/dev/null; then
    return 0
  else
    fail_test "Expected a JSON array"
    echo "       Got: $(echo "$output" | head -3)"
    return 1
  fi
}

# Assert JSON array has at least N elements
assert_json_min_length() {
  local output="$1"
  local min="$2"
  if echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert isinstance(data, list), 'Not a list'
assert len(data) >= $min, f'Expected >= $min elements, got {len(data)}'
" 2>/dev/null; then
    return 0
  else
    fail_test "Expected JSON array with >= $min elements"
    return 1
  fi
}

# ── Sandbox helpers ─────────────────────────────────────────────────

# Generate a unique sandbox name for tests
test_sandbox_name() {
  echo "test-$(date +%s)-$$-$RANDOM"
}

# Wait for a sandbox to appear in ps output (max ~10s)
wait_for_sandbox() {
  local name="$1"
  local max_attempts="${2:-20}"
  for ((i = 0; i < max_attempts; i++)); do
    if $NANOSB ps 2>/dev/null | grep -qF "$name"; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

# Cleanup: stop and remove a sandbox (best-effort)
cleanup_sandbox() {
  local name="$1"
  $NANOSB stop "$name" &>/dev/null || true
  $NANOSB rm -f "$name" &>/dev/null || true
}
