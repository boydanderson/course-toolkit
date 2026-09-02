#!/bin/bash
# Test runner -- no external framework, matching this repo's own
# "target bash 3.2, minimal dependencies" rule. Finds every
# tests/*.test.sh file, sources it (so tests/assert.sh's TESTS_RUN/
# TESTS_FAILED counters accumulate across all of them in one process),
# and calls the function it defines (a file named foo.test.sh must
# define test_foo). Exits nonzero if anything failed, so this is
# CI-usable as-is.
#
# Usage: tests/run.sh [--skip-latex]
#   --skip-latex   skip tests/backends-latex-beamer.test.sh (real
#                  pdflatex compiles) -- for an environment without a
#                  LaTeX install. Auto-skipped anyway if `pdflatex`
#                  isn't on PATH; this flag is for explicitly opting out
#                  even when it is.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TOOLKIT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

SKIP_LATEX=0
[ "${1:-}" = "--skip-latex" ] && SKIP_LATEX=1

source "$TESTS_DIR/assert.sh"

for test_file in "$TESTS_DIR"/*.test.sh; do
    [ -f "$test_file" ] || continue
    base="$(basename "$test_file" .test.sh)"
    if [ "$base" = "backends-latex-beamer" ]; then
        if [ "$SKIP_LATEX" = 1 ] || ! command -v pdflatex > /dev/null 2>&1; then
            echo "=== $base (skipped -- no pdflatex, or --skip-latex) ==="
            continue
        fi
    fi
    echo "=== $base ==="
    source "$test_file"
    fn="test_$(echo "$base" | tr '-' '_')"
    if ! command -v "$fn" > /dev/null 2>&1; then
        echo "  FAIL: $test_file doesn't define $fn()"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        continue
    fi
    "$fn"
done

echo
echo "=== $TESTS_RUN run, $TESTS_FAILED failed ==="
[ "$TESTS_FAILED" -eq 0 ]
