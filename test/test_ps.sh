#!/usr/bin/env bash
# test/test_ps.sh - Verify the "nanosb ps" command
#
# Docs covered:
#   - cli/commands.md (ps section — ps, ps -a)
#   - cli/global-flags.md (--format json)

source "$(dirname "$0")/lib.sh"

print_suite_header "Ps Command"

# ═══════════════════════════════════════════════════════════════════
# 1. Basic invocation (text)
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb ps runs successfully"
output=$(assert_success "$NANOSB ps") && \
  pass_test || true

begin_test "nanosb ps -a runs successfully"
output=$(assert_success "$NANOSB ps -a") && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 2. JSON output
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb ps --format json produces valid JSON array"
output=$(assert_success "$NANOSB ps --format json") && \
  assert_json "$output" && \
  assert_json_array "$output" && \
  pass_test || true

begin_test "nanosb ps -a --format json produces valid JSON array"
output=$(assert_success "$NANOSB ps -a --format json") && \
  assert_json "$output" && \
  assert_json_array "$output" && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 3. Invariant: ps -a >= ps
#    (Docs: -a shows stopped/exited sandboxes too)
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb ps -a shows >= entries compared to ps"
count_running=$($NANOSB ps --format json 2>&1 | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
count_all=$($NANOSB ps -a --format json 2>&1 | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
if [[ "$count_all" -ge "$count_running" ]]; then
  pass_test
else
  fail_test "ps -a ($count_all) < ps ($count_running)"
fi

# ═══════════════════════════════════════════════════════════════════
# 4. --format text (explicit default)
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb ps --format text runs successfully"
output=$(assert_success "$NANOSB ps --format text") && \
  pass_test || true

print_summary
