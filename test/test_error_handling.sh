#!/usr/bin/env bash
# test/test_error_handling.sh - Verify graceful error handling
#
# Docs covered:
#   - troubleshooting/common-errors.md (error scenarios)
#   - cli/commands.md (required arguments for each command)
#   - cli/global-flags.md (invalid flag values)

source "$(dirname "$0")/lib.sh"

print_suite_header "Error Handling"

# ═══════════════════════════════════════════════════════════════════
# 1. Unknown command / flag
# ═══════════════════════════════════════════════════════════════════

begin_test "Unknown command produces an error"
output=$(assert_failure "$NANOSB nonexistent-command") && \
  pass_test || true

begin_test "Unknown flag produces an error"
output=$(assert_failure "$NANOSB --unknown-flag ps") && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 2. Missing required arguments per command
#    (Docs: commands.md — each command's required args)
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb pull without image argument fails"
output=$(assert_failure "$NANOSB pull") && \
  pass_test || true

begin_test "nanosb run without image argument fails"
output=$(assert_failure "$NANOSB run") && \
  pass_test || true

begin_test "nanosb exec without sandbox argument fails"
output=$(assert_failure "$NANOSB exec") && \
  pass_test || true

begin_test "nanosb exec with sandbox but no command fails"
output=$(assert_failure "$NANOSB exec some-sandbox") && \
  pass_test || true

begin_test "nanosb stop without sandbox argument fails"
output=$(assert_failure "$NANOSB stop") && \
  pass_test || true

begin_test "nanosb rm without sandbox argument fails"
output=$(assert_failure "$NANOSB rm") && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 3. Operations on non-existent sandboxes
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb stop on non-existent sandbox produces error"
output=$($NANOSB stop "nonexistent-$RANDOM" 2>&1) && rc=0 || rc=$?
[[ $rc -ne 0 ]] && pass_test || fail_test "Expected non-zero exit for stop on missing sandbox"

begin_test "nanosb rm on non-existent sandbox produces error"
output=$($NANOSB rm "nonexistent-$RANDOM" 2>&1) && rc=0 || rc=$?
[[ $rc -ne 0 ]] && pass_test || fail_test "Expected non-zero exit for rm on missing sandbox"

begin_test "nanosb exec on non-existent sandbox produces error"
output=$($NANOSB exec "nonexistent-$RANDOM" echo test 2>&1) && rc=0 || rc=$?
[[ $rc -ne 0 ]] && pass_test || fail_test "Expected non-zero exit for exec on missing sandbox"

# ═══════════════════════════════════════════════════════════════════
# 4. Invalid image names
#    (Docs: common-errors.md — "Image Not Found")
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb pull with invalid image name fails"
output=$(assert_failure "$NANOSB pull not-a-valid-registry/nonexistent:tag") && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 5. Invalid flag values — type mismatches
#    (Docs: global-flags.md — format, cpus, memory, timeout, permissions)
# ═══════════════════════════════════════════════════════════════════

begin_test "--format with invalid value (xml) fails"
output=$(assert_failure "$NANOSB --format xml ps") && \
  pass_test || true

begin_test "--format with invalid value (yaml) fails"
output=$(assert_failure "$NANOSB --format yaml ps") && \
  pass_test || true

begin_test "--cpus with non-numeric value fails"
output=$(assert_failure "$NANOSB --cpus abc ps") && \
  pass_test || true

begin_test "--memory with non-numeric value fails"
output=$(assert_failure "$NANOSB --memory abc ps") && \
  pass_test || true

begin_test "--timeout with non-numeric value fails"
output=$(assert_failure "$NANOSB --timeout abc ps") && \
  pass_test || true

begin_test "--permissions with invalid value fails"
output=$(assert_failure "$NANOSB --permissions bogus ps") && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 6. Invalid -e format
# ═══════════════════════════════════════════════════════════════════

begin_test "-e with malformed value (no =) fails"
output=$(assert_failure "$NANOSB -e 'NOEQUALS' ps") && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 7. Invalid config files
#    (Docs: common-errors.md — configuration issues)
# ═══════════════════════════════════════════════════════════════════

begin_test "--config with nonexistent file fails"
output=$(assert_failure "$NANOSB --config /tmp/does-not-exist-$RANDOM.yml ps") && \
  pass_test || true

begin_test "--env-file with nonexistent file fails"
output=$(assert_failure "$NANOSB --env-file /tmp/does-not-exist-$RANDOM ps") && \
  pass_test || true

begin_test "Invalid YAML in --config fails gracefully"
bad_cfg="$TEST_TMPDIR/bad.yml"
echo "{{{{not yaml" > "$bad_cfg"
output=$(assert_failure "$NANOSB --config $bad_cfg ps") && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 8. Error output is helpful (contains hints)
# ═══════════════════════════════════════════════════════════════════

begin_test "Missing argument error suggests usage"
output=$($NANOSB run 2>&1) || true
# clap typically shows "Usage:" on argument errors
assert_matches "$output" "Usage:|usage:|error|required" && \
  pass_test || true

begin_test "Unknown flag error message is descriptive"
output=$($NANOSB --bogus-flag 2>&1) || true
assert_matches "$output" "error|unexpected|unrecognized|unknown" && \
  pass_test || true

print_summary
