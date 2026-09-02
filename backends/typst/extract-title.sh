#!/bin/bash
# Usage: extract-title.sh SOURCE_PATH [SLOT_ID]
# Prints SOURCE_PATH's document title, empty if none.
#
# Unlike backends/latex-beamer's extract-title.sh (a plain grep for
# \title{...}), this actually compiles the file: a Typst source's title
# is frequently computed indirectly (e.g. this backend was built against
# CG2111A/EPP2's real content, whose templates look up a title string
# from a separate studio_numbers.typ/tutorial_numbers.typ config file,
# keyed by folder name -- there's no static text in the source itself to
# grep for). Reading the compiled PDF's own /Title metadata (set via
# Typst's `set document(title: ...)`) is the only generically-correct
# way to get the real title regardless of how a course's own template
# computes it. A course whose template never calls `set document(title:
# ...)` at all just gets an empty title here -- the same "nothing found,
# not an error" degradation every other extract-title.sh in this toolkit
# already has (compose_slot_title in enrich-lib.sh falls back to the
# slot ID itself).
#
# SLOT_ID is accepted for contract-compatibility but unused -- this
# backend has no PLACEHOLDER_SLOT-style substitution, see build-slot.sh.
#
# Requires `pdfinfo` (poppler-utils) on PATH -- already a common
# LaTeX-toolchain dependency, so likely already present wherever this
# toolkit's other backend runs; empty output (not a hard error) if it
# isn't, same as a missing source file.
set -uo pipefail
source_path="$1"
# slot_id="${2:-}"  # accepted, unused -- see header comment.

[ -f "$source_path" ] || { echo ""; exit 0; }
command -v pdfinfo >/dev/null 2>&1 || { echo ""; exit 0; }

job_dir="$(mktemp -d)"
job_pdf="$job_dir/title-check.pdf"
trap 'rm -rf "$job_dir"' EXIT

# instructor-mode is irrelevant to the title in every template this
# backend has seen (the title is built from studio-num/studio-title
# alone) -- compiling as "student" is an arbitrary, consistent choice,
# not a claim that a title could never differ by variant.
if ! typst compile --root . --input instructor-mode=false "$source_path" "$job_pdf" > /dev/null 2>&1; then
    echo ""
    exit 0
fi

pdfinfo "$job_pdf" 2>/dev/null | sed -n 's/^Title:[[:space:]]*//p'
