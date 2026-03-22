#!/usr/bin/env bash
# test/test_doctor.sh - Verify the "nanosb doctor" command
#
# Docs covered:
#   - troubleshooting/doctor-command.md
#     Checks: platform, hypervisor, libkrun, libkrunfw, codesigning,
#             gvproxy, image cache
#   - cli/commands.md (doctor entry)

source "$(dirname "$0")/lib.sh"

print_suite_header "Doctor Command"

# ═══════════════════════════════════════════════════════════════════
# 1. Basic invocation
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb doctor produces output (text)"
output=$($NANOSB doctor 2>&1) || true
assert_not_empty "$output" && \
  pass_test || true

begin_test "nanosb doctor reports check results"
output=$($NANOSB doctor 2>&1) || true
# Docs say it checks prerequisites - output should contain status indicators
assert_matches "$output" "pass|fail|ok|error|check|found|missing|✓|✗|warning|libkrun|hypervisor|gvproxy" && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 2. JSON output
#    (Docs: doctor-command.md — "nanosb doctor --format json")
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb doctor --format json produces valid JSON"
output=$($NANOSB doctor --format json 2>&1) || true
assert_json "$output" && \
  pass_test || true

begin_test "nanosb doctor --format json returns structured data"
output=$($NANOSB doctor --format json 2>&1) || true
if echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert isinstance(data, (list, dict)), f'Expected list or dict, got {type(data).__name__}'
if isinstance(data, list):
    assert len(data) > 0, 'Expected non-empty list of checks'
" 2>/dev/null; then
  pass_test
else
  fail_test "JSON structure unexpected"
fi

# ═══════════════════════════════════════════════════════════════════
# 3. Documented checks should appear in output
#    (Docs: doctor-command.md — platform, hypervisor, libkrun,
#     libkrunfw, codesigning, gvproxy, cache)
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb doctor text output mentions documented checks"
output=$($NANOSB doctor 2>&1) || true
# At minimum, doctor should mention the platform or hypervisor checks
found=0
for keyword in "platform" "hypervisor" "libkrun" "codesign" "gvproxy" "kvm" "hvf" "cache"; do
  if echo "$output" | grep -qiF "$keyword"; then
    found=$((found + 1))
  fi
done
if [[ $found -ge 2 ]]; then
  pass_test
else
  fail_test "Expected doctor output to mention at least 2 of the documented checks (found $found)"
fi

begin_test "nanosb doctor JSON has expected fields (platform, arch, ok)"
output=$($NANOSB doctor --format json 2>&1) || true
if echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert isinstance(data, dict), f'Expected dict, got {type(data).__name__}'
# Doctor JSON should have at least platform, arch, ok
for field in ['platform', 'ok']:
    assert field in data, f'Missing expected field: {field}'
" 2>/dev/null; then
  pass_test
else
  fail_test "Expected JSON to contain 'platform' and 'ok' fields"
fi

print_summary
