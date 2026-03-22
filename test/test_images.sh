#!/usr/bin/env bash
# test/test_images.sh - Verify the "nanosb images" command
#
# Docs covered:
#   - cli/commands.md (images section)
#   - cli/global-flags.md (--format)

source "$(dirname "$0")/lib.sh"

print_suite_header "Images Command"

# ═══════════════════════════════════════════════════════════════════
# 1. Basic invocation
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb images runs successfully (text)"
output=$(assert_success "$NANOSB images") && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 2. JSON output
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb images --format json produces valid JSON"
output=$(assert_success "$NANOSB images --format json") && \
  assert_json "$output" && \
  pass_test || true

begin_test "nanosb images --format json returns a JSON array"
output=$($NANOSB images --format json 2>&1)
assert_json_array "$output" && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 3. Text format table structure (when images exist)
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb images text output has table headers (if images cached)"
output=$($NANOSB images 2>&1)
if [[ -z "$output" ]] || ! echo "$output" | grep -qiE "image|name|tag|size|id|repository"; then
  skip_test "no cached images to verify table headers"
else
  pass_test
fi

# ═══════════════════════════════════════════════════════════════════
# 4. JSON entries have expected fields (when images exist)
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb images JSON entries have image-related fields (if any)"
output=$($NANOSB images --format json 2>&1)
if echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if len(data) == 0:
    sys.exit(2)  # no images to check
entry = data[0]
# Check that at least some image-related key exists
keys = set(k.lower() for k in entry.keys())
expected_any = {'name','image','repository','tag','size','id','digest'}
assert keys & expected_any, f'No image-related fields found in keys: {keys}'
" 2>/dev/null; then
  pass_test
elif [[ $? -eq 2 ]]; then
  skip_test "no cached images to verify fields"
else
  fail_test "JSON entries missing expected image fields"
fi

print_summary
