#!/bin/bash
# Compiles a Beamer-body source file into a PDF via pdflatex.
# Usage: build-slot.sh SOURCE_PATH VARIANT OUTPUT_PATH
#
# SOURCE_PATH is expected to contain \title{...}/\author{...}/etc.
# through \begin{document}...\end{document} (everything except the
# preamble), same convention as cs1101s/course-materials'
# src/lectures/lecture-N.tex files -- this script supplies only
# \documentclass and the shared preamble ahead of it.
#
# VARIANT selects an additional per-variant header, if one exists at
# backends/latex-beamer/headers/<variant>.tex (e.g. a "print" variant
# might force grayscale) -- silently skipped if there's no such file for
# this variant, so a kind that doesn't need per-variant styling
# (studios' "problem"/"solution", or a "none" variant) just gets the
# shared preamble.
set -euo pipefail
BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source_path="$1" variant="$2" output_path="$3"

if [ ! -f "$source_path" ]; then
    echo "build-slot.sh: source file not found: $source_path" >&2
    exit 1
fi

job_dir="$(mktemp -d)"
trap 'rm -rf "$job_dir"' EXIT

combined="$job_dir/slot.tex"
{
    echo '\documentclass{beamer}'
    cat "$BACKEND_DIR/preamble.tex"
    variant_header="$BACKEND_DIR/headers/${variant}.tex"
    [ -f "$variant_header" ] && cat "$variant_header"
    # SOURCE_PATH already contains \begin{document}...\end{document}
    # (the "body", per the header comment above) -- not added here.
    cat "$source_path"
} > "$combined"

if ! pdflatex -interaction=nonstopmode -halt-on-error -output-directory "$job_dir" "$combined" > "$job_dir/pdflatex.log" 2>&1; then
    echo "build-slot.sh: pdflatex failed -- see log below" >&2
    cat "$job_dir/pdflatex.log" >&2
    exit 1
fi

mkdir -p "$(dirname "$output_path")"
cp "$job_dir/slot.pdf" "$output_path"
