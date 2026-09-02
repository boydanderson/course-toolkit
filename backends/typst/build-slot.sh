#!/bin/bash
# Compiles a Typst source file into a PDF via `typst compile`.
# Usage: build-slot.sh SOURCE_PATH VARIANT OUTPUT_PATH [SLOT_ID]
#
# VARIANT is "instructor" or "student" -- passed to Typst as
# `--input instructor-mode=true|false`, matching the real convention
# this backend was built against (CG2111A/EPP2's own build workflow):
# one Typst source, compiled twice with different input values, rather
# than two separate header files the way backends/latex-beamer's
# view/print variants work. A course whose Typst source doesn't
# branch on `instructor-mode` at all just ignores the input, same as
# any unused Typst `--input`.
#
# SLOT_ID is accepted for contract-compatibility but unused -- this
# backend has no PLACEHOLDER_SLOT-style substitution (EPP2's templates
# get their titles from studio_numbers.typ/tutorial_numbers.typ's own
# per-unit config, not a placeholder embedded in the source).
#
# Run with CWD = the course repo root (same convention every other
# script in this ecosystem relies on for path resolution) -- SOURCE_PATH
# and OUTPUT_PATH are resolved relative to that, and `--root .` lets
# Typst resolve this course's own absolute-style imports (`/...`) if it
# has any; relative imports (`../studio_template.typ`) work regardless.
set -uo pipefail

source_path="$1" variant="$2" output_path="$3"
# slot_id="${4:-}"  # accepted, unused -- see header comment.

if [ ! -f "$source_path" ]; then
    echo "build-slot.sh: source file not found: $source_path" >&2
    exit 1
fi

case "$variant" in
    instructor) instructor_mode=true ;;
    student) instructor_mode=false ;;
    *)
        echo "build-slot.sh: unknown variant '$variant' (expected instructor|student)" >&2
        exit 1
        ;;
esac

mkdir -p "$(dirname "$output_path")"

compile_log="$(mktemp)"
trap 'rm -f "$compile_log"' EXIT
if ! typst compile --root . --input "instructor-mode=$instructor_mode" \
        "$source_path" "$output_path" > "$compile_log" 2>&1; then
    echo "build-slot.sh: typst compile failed for $source_path ($variant) -- log below" >&2
    cat "$compile_log" >&2
    exit 1
fi
