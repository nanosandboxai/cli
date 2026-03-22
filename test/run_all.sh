#!/usr/bin/env bash
# test/run_all.sh - Main test runner for nanosb CLI tests
#
# Usage:
#   ./test/run_all.sh              # Run all tests
#   ./test/run_all.sh help doctor  # Run only specified suites
#   NANOSB=/path/to/nanosb ./test/run_all.sh  # Custom binary
#
# Test suites (in execution order):
#   help           - --help/--version output for all commands
#   doctor         - Runtime prerequisite checks
#   error_handling - Graceful failure on invalid inputs
#   global_flags   - Global flags across commands
#   config         - sandbox.yml configuration parsing
#   images         - Image listing
#   cache          - Cache management
#   cleanup        - Stale clone cleanup
#   pull           - Image pulling (network required)
#   ps             - Sandbox listing
#   lifecycle      - Full sandbox lifecycle (run/exec/stop/rm)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

# ── All available suites in recommended order ───────────────────────
ALL_SUITES=(
  help
  doctor
  error_handling
  global_flags
  config
  images
  cache
  cleanup
  pull
  ps
  lifecycle
)

# ── Parse arguments ─────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
  SUITES=("$@")
else
  SUITES=("${ALL_SUITES[@]}")
fi

# ── Banner ──────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║       nanosb CLI Test Suite                   ║${RESET}"
echo -e "${BOLD}╚═══════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Binary:  ${NANOSB:-nanosb}"
echo -e "  Suites:  ${SUITES[*]}"
echo ""

# ── Run suites ──────────────────────────────────────────────────────
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
FAILED_NAMES=()

for suite in "${SUITES[@]}"; do
  script="$SCRIPT_DIR/test_${suite}.sh"

  if [[ ! -f "$script" ]]; then
    echo -e "${RED}ERROR: Test suite not found: $script${RESET}"
    FAILED_SUITES=$((FAILED_SUITES + 1))
    FAILED_NAMES+=("$suite (not found)")
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    continue
  fi

  TOTAL_SUITES=$((TOTAL_SUITES + 1))

  if bash "$script"; then
    PASSED_SUITES=$((PASSED_SUITES + 1))
  else
    FAILED_SUITES=$((FAILED_SUITES + 1))
    FAILED_NAMES+=("$suite")
  fi
done

# ── Overall summary ─────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║       Overall Results                         ║${RESET}"
echo -e "${BOLD}╚═══════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Total suites:  $TOTAL_SUITES"
echo -e "  ${GREEN}Passed:        $PASSED_SUITES${RESET}"

if [[ $FAILED_SUITES -gt 0 ]]; then
  echo -e "  ${RED}Failed:        $FAILED_SUITES${RESET}"
  echo ""
  echo -e "  ${RED}Failed suites:${RESET}"
  for name in "${FAILED_NAMES[@]}"; do
    echo -e "    ${RED}- $name${RESET}"
  done
  echo ""
  exit 1
else
  echo -e "  Failed:        0"
  echo ""
  echo -e "  ${GREEN}${BOLD}ALL SUITES PASSED${RESET}"
  echo ""
  exit 0
fi
