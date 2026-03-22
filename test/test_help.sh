#!/usr/bin/env bash
# test/test_help.sh - Verify --help and --version output for all commands
#
# Docs covered:
#   - cli/commands.md        (all command names and their flags)
#   - cli/global-flags.md    (every global flag)
#   - cli/tui-mode.md        (TUI launch without subcommand)

source "$(dirname "$0")/lib.sh"

print_suite_header "Help & Version Output"

# ═══════════════════════════════════════════════════════════════════
# 1. Top-level help
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb --help shows Usage, Commands, and Options sections"
output=$(assert_success "$NANOSB --help") && \
  assert_contains "$output" "Usage:" && \
  assert_contains "$output" "Commands:" && \
  assert_contains "$output" "Options:" && \
  pass_test || true

begin_test "nanosb --version prints a semver-like version"
output=$(assert_success "$NANOSB --version") && \
  assert_matches "$output" "[0-9]+\.[0-9]+" && \
  pass_test || true

begin_test "nanosb -h is equivalent to --help"
output=$(assert_success "$NANOSB -h") && \
  assert_contains "$output" "Usage:" && \
  pass_test || true

begin_test "nanosb -V is equivalent to --version"
output=$(assert_success "$NANOSB -V") && \
  assert_matches "$output" "[0-9]+\.[0-9]+" && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 2. All documented commands appear in top-level help
# ═══════════════════════════════════════════════════════════════════

begin_test "Top-level help lists every documented command"
output=$($NANOSB --help 2>&1)
all_ok=true
for cmd in pull images run exec ps stop rm doctor cleanup cache help; do
  if ! echo "$output" | grep -qw "$cmd"; then
    fail_test "Missing command '$cmd' in --help output"
    all_ok=false
    break
  fi
done
$all_ok && pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 3. All documented global flags appear in top-level help
#    (Docs: cli/global-flags.md)
# ═══════════════════════════════════════════════════════════════════

begin_test "Top-level help lists every documented global flag"
output=$($NANOSB --help 2>&1)
all_ok=true
for flag in "--format" "--verbose" "--project" "--config" "--sandbox" \
            "--cpus" "--memory" "--timeout" "--permissions" \
            "--env" "--env-file"; do
  if ! echo "$output" | grep -qF -- "$flag"; then
    fail_test "Missing global flag '$flag' in --help"
    all_ok=false
    break
  fi
done
$all_ok && pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 4. Subcommand --help for every documented command
#    (Docs: cli/commands.md)
# ═══════════════════════════════════════════════════════════════════

for sub in pull images run exec ps stop rm doctor cleanup "cache prune"; do
  begin_test "nanosb $sub --help shows Usage"
  output=$(assert_success "$NANOSB $sub --help") && \
    assert_contains "$output" "Usage:" && \
    pass_test || true
done

# ═══════════════════════════════════════════════════════════════════
# 5. Command-specific flags documented in commands.md
# ═══════════════════════════════════════════════════════════════════

# -- run flags: --name, --cpus, --memory, --timeout, -e, --env-file, --buffered
begin_test "nanosb run --help lists all documented flags"
output=$($NANOSB run --help 2>&1)
all_ok=true
for flag in "--name" "--cpus" "--memory" "--timeout" "--buffered" "--env" "--env-file"; do
  if ! echo "$output" | grep -qF -- "$flag"; then
    fail_test "Missing flag '$flag' in 'run --help'"
    all_ok=false
    break
  fi
done
$all_ok && pass_test || true

# -- exec flags: --buffered
begin_test "nanosb exec --help lists --buffered flag"
output=$(assert_success "$NANOSB exec --help") && \
  assert_contains "$output" "--buffered" && \
  pass_test || true

# -- ps flags: -a / --all
begin_test "nanosb ps --help shows -a / --all flag"
output=$(assert_success "$NANOSB ps --help") && \
  assert_matches "$output" "-a|--all" && \
  pass_test || true

# -- rm flags: -f / --force
begin_test "nanosb rm --help shows -f / --force flag"
output=$(assert_success "$NANOSB rm --help") && \
  assert_matches "$output" "-f|--force" && \
  pass_test || true

# -- cache prune flags: --all
begin_test "nanosb cache prune --help shows --all flag"
output=$(assert_success "$NANOSB cache prune --help") && \
  assert_contains "$output" "--all" && \
  pass_test || true

# -- cleanup flags: --project
begin_test "nanosb cleanup --help shows --project flag"
output=$(assert_success "$NANOSB cleanup --help") && \
  assert_contains "$output" "--project" && \
  pass_test || true

# -- doctor (no command-specific flags beyond global, but verify --format mentioned)
begin_test "nanosb doctor --help mentions format or json"
output=$(assert_success "$NANOSB doctor --help") && \
  assert_matches "$output" "format|json" && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 6. --format possible values documented (text, json)
# ═══════════════════════════════════════════════════════════════════

begin_test "--format help text lists text and json as possible values"
output=$($NANOSB --help 2>&1)
assert_contains "$output" "text" && \
  assert_contains "$output" "json" && \
  pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 7. --permissions possible values documented
#    (Docs: global-flags.md — default, accept-edits, allow-all)
# ═══════════════════════════════════════════════════════════════════

begin_test "--permissions help text mentions all three levels"
output=$($NANOSB --help 2>&1)
all_ok=true
for level in "default" "accept-edits" "allow-all"; do
  if ! echo "$output" | grep -qF -- "$level"; then
    fail_test "Missing permissions level '$level' in --help"
    all_ok=false
    break
  fi
done
$all_ok && pass_test || true

# ═══════════════════════════════════════════════════════════════════
# 8. cache subcommand structure
# ═══════════════════════════════════════════════════════════════════

begin_test "nanosb cache --help shows prune subcommand"
output=$(assert_success "$NANOSB cache --help") && \
  assert_contains "$output" "prune" && \
  pass_test || true

print_summary
