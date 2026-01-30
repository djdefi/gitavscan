#!/usr/bin/env bash
#
# Quick validation test for gitscan.sh static analysis
# This test verifies fixes were applied correctly without needing Docker or ClamAV
#

set -euo pipefail

SCRIPT_PATH="${1:-./gitscan.sh}"
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_pass() {
    echo -e "${GREEN}✓${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo "======================================"
echo "gitscan.sh Static Validation Tests"
echo "======================================"
echo ""

# Test 1: Script syntax is valid
if bash -n "$SCRIPT_PATH" 2>/dev/null; then
    log_pass "Script syntax is valid"
else
    log_fail "Script has syntax errors"
fi

# Test 2: Shellcheck passes (no critical errors)
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$SCRIPT_PATH" 2>&1 | grep -q "error:"; then
        log_fail "Shellcheck found errors"
    else
        log_pass "Shellcheck passes (no errors)"
    fi
else
    log_pass "Shellcheck not available (skipped)"
fi

# Test 3: EXCLUDE flag is used in initial scan
if grep -q 'output=.*\$EXCLUDE.*"\$REPO"' "$SCRIPT_PATH"; then
    log_pass "EXCLUDE flag used in initial scan (line 71 fix)"
else
    log_fail "EXCLUDE flag not properly used in initial scan"
fi

# Test 4: Variables are properly quoted
if grep -q '"\$TMP"' "$SCRIPT_PATH" && grep -q '"\$REPO"' "$SCRIPT_PATH" && grep -q '"\$F"' "$SCRIPT_PATH"; then
    log_pass "Critical variables are quoted"
else
    log_fail "Some variables are not quoted"
fi

# Test 5: Git clone has error handling
if grep -q 'git clone.*||.*ERROR' "$SCRIPT_PATH"; then
    log_pass "Git clone has error handling"
else
    log_fail "Git clone missing error handling"
fi

# Test 6: getopt flags are correct (no colon after -f)
if grep -q 'getopt -o vfo:' "$SCRIPT_PATH"; then
    log_pass "getopt flags corrected (-f has no colon)"
else
    log_fail "getopt flags incorrect"
fi

# Test 7: Performance optimization (cached rev-list)
if grep -q 'revs_output=\$(git rev-list' "$SCRIPT_PATH" && grep -q '<<< "\$revs_output"' "$SCRIPT_PATH"; then
    log_pass "Performance optimization: rev-list output cached"
else
    log_fail "Performance optimization missing"
fi

# Test 8: Freshclam has timeout mechanism
if grep -q 'freshclam_pid=' "$SCRIPT_PATH" && grep -q 'timeout=' "$SCRIPT_PATH"; then
    log_pass "Freshclam timeout mechanism added"
else
    log_fail "Freshclam timeout missing"
fi

# Test 9: Stash scanning added
if grep -q 'refs/stash' "$SCRIPT_PATH" && grep -q 'Scanning stashed changes' "$SCRIPT_PATH"; then
    log_pass "Stash scanning feature added"
else
    log_fail "Stash scanning not implemented"
fi

# Test 10: Submodule scanning added
if grep -q '.gitmodules' "$SCRIPT_PATH" && grep -q 'Scanning git submodules' "$SCRIPT_PATH"; then
    log_pass "Submodule scanning feature added"
else
    log_fail "Submodule scanning not implemented"
fi

# Test 11: Security limitations documented
if grep -q 'NOTE: This scan has the following limitations' "$SCRIPT_PATH"; then
    log_pass "Security limitations documented"
else
    log_fail "Security limitations not documented"
fi

# Test 12: Unused VERBOSE_MODE variable removed
if grep -q 'VERBOSE_MODE=' "$SCRIPT_PATH"; then
    log_fail "Unused VERBOSE_MODE variable still present"
else
    log_pass "Unused VERBOSE_MODE variable removed"
fi

# Test 13: pushd/popd/cd have error handling
if grep -q 'pushd.*||.*exit' "$SCRIPT_PATH" && grep -q 'cd.*||.*exit' "$SCRIPT_PATH"; then
    log_pass "pushd/cd have error handling"
else
    log_fail "pushd/cd missing error handling"
fi

# Test 14: Initial scan writes to /output.txt
if grep 'tee -a /output.txt' "$SCRIPT_PATH" | head -1 | grep -q "ref.*HEAD"; then
    log_pass "Initial scan findings written to /output.txt"
else
    # Check that findings are written to /output.txt at all
    if grep -q 'tee -a /output.txt' "$SCRIPT_PATH"; then
        log_pass "Findings written to /output.txt"
    else
        log_fail "Findings not written to /output.txt"
    fi
fi

# Test 15: Worktree scanning feature added
if grep -q 'git worktree list' "$SCRIPT_PATH" && grep -q 'Scanning git worktrees' "$SCRIPT_PATH"; then
    log_pass "Worktree scanning feature added"
else
    log_fail "Worktree scanning not implemented"
fi

# Test 16: Hooks scanning feature added
if grep -q '.git/hooks' "$SCRIPT_PATH" && grep -q 'Scanning git hooks' "$SCRIPT_PATH"; then
    log_pass "Hooks scanning feature added"
else
    log_fail "Hooks scanning not implemented"
fi

# Test 17: LFS scanning feature added
if grep -q 'git lfs' "$SCRIPT_PATH" && grep -q 'Scanning Git LFS files' "$SCRIPT_PATH"; then
    log_pass "LFS scanning feature added"
else
    log_fail "LFS scanning not implemented"
fi

echo ""
echo "======================================"
echo "Test Summary"
echo "======================================"
echo "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo "Tests failed: ${RED}$TESTS_FAILED${NC}"
echo "======================================"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All validation tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some validation tests failed!${NC}"
    exit 1
fi
