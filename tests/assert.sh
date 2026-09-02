#!/bin/bash
# Minimal, dependency-free assertion library for tests/run.sh's test
# files -- no external test framework (bats etc.), matching this repo's
# own "target bash 3.2, minimal dependencies" rule (see README's
# "Portability" section). Each assert_* prints a PASS/FAIL line to
# stdout and increments the counters run.sh reads back via
# TESTS_RUN/TESTS_FAILED (exported by the caller).

TESTS_RUN=0
TESTS_FAILED=0

_test_pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "  PASS: $1"
}

_test_fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $1"
}

# assert_eq DESCRIPTION EXPECTED ACTUAL
assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        _test_pass "$desc"
    else
        _test_fail "$desc -- expected [$expected], got [$actual]"
    fi
}

# assert_ne DESCRIPTION NOT_EXPECTED ACTUAL
assert_ne() {
    local desc="$1" not_expected="$2" actual="$3"
    if [ "$not_expected" != "$actual" ]; then
        _test_pass "$desc"
    else
        _test_fail "$desc -- expected something other than [$actual]"
    fi
}

# assert_contains DESCRIPTION HAYSTACK NEEDLE
assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    case "$haystack" in
        *"$needle"*) _test_pass "$desc" ;;
        *) _test_fail "$desc -- [$needle] not found in [$haystack]" ;;
    esac
}

# assert_not_contains DESCRIPTION HAYSTACK NEEDLE
assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    case "$haystack" in
        *"$needle"*) _test_fail "$desc -- [$needle] unexpectedly found in [$haystack]" ;;
        *) _test_pass "$desc" ;;
    esac
}

# assert_success DESCRIPTION -- run the rest of the args as a command,
# pass if it exits 0.
assert_success() {
    local desc="$1"; shift
    if "$@" > /dev/null 2>&1; then
        _test_pass "$desc"
    else
        _test_fail "$desc -- command failed: $*"
    fi
}

# assert_failure DESCRIPTION -- run the rest of the args as a command,
# pass if it exits nonzero.
assert_failure() {
    local desc="$1"; shift
    if "$@" > /dev/null 2>&1; then
        _test_fail "$desc -- command unexpectedly succeeded: $*"
    else
        _test_pass "$desc"
    fi
}
