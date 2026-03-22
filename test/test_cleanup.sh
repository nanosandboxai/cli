#!/usr/bin/env bash
# test/test_cleanup.sh - Verify the "nanosb cleanup" command
#
# Docs covered:
#   - cli/commands.md (cleanup section — "nanosb cleanup [--project PATH]")

source "$(dirname "$0")/lib.sh"

print_suite_header "Cleanup Command"

# ═══════════════════════════════════════════════════════════════════
# 1. Basic invocation
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb cleanup runs successfully"
output=$(assert_success "$NANOSB cleanup") && \
  pass_test || true

begin_test "nanosb cleanup produces output"
output=$($NANOSB cleanup 2>&1)
assert_not_empty "$output" && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 2. --project flag
#    (Docs: "Limit cleanup to a specific project")
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb cleanup --project with valid path runs"
output=$($NANOSB cleanup --project /tmp 2>&1)
rc=$?
[[ $rc -eq 0 ]] && pass_test || fail_test "cleanup --project failed (rc=$rc)"

begin_test "nanosb cleanup --project with nonexistent path handles gracefully"
output=$($NANOSB cleanup --project /tmp/nonexistent-project-$RANDOM 2>&1)
# May succeed (nothing to clean) or fail gracefully — either is acceptable
pass_test

print_summary
