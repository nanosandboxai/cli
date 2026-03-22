#!/usr/bin/env bash
# test/test_cache.sh - Verify the "nanosb cache" command
#
# Docs covered:
#   - cli/commands.md (cache section — "nanosb cache prune [--all]")

source "$(dirname "$0")/lib.sh"

print_suite_header "Cache Command"

# ═══════════════════════════════════════════════════════════════════
# 1. cache help
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb cache --help lists prune subcommand"
output=$(assert_success "$NANOSB cache --help") && \
  assert_contains "$output" "prune" && \
  pass_test || true

begin_test "nanosb cache prune --help shows --all flag"
output=$(assert_success "$NANOSB cache prune --help") && \
  assert_contains "$output" "--all" && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 2. cache prune (default — prune unused)
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb cache prune runs successfully"
output=$(assert_success "$NANOSB cache prune") && \
  pass_test || true

begin_test "nanosb cache prune produces output"
output=$($NANOSB cache prune 2>&1)
assert_not_empty "$output" && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 3. cache prune --all (removes everything)
#    (Docs: commands.md — "--all removes everything")
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb cache prune --all runs successfully"
output=$(assert_success "$NANOSB cache prune --all") && \
  pass_test || true

print_summary
