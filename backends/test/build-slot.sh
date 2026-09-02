#!/bin/bash
# Reference/test backend -- NOT for real course use. Minimal
# implementation of the renderer backend contract (see
# ../../core/backend-lib.sh), used to verify core/ can dispatch into a
# backend generically, and as a template for a real one.
#
# "Source" format: a plain text file whose first line is "TITLE: ...".
# "Building" just copies it to the output path with a variant marker --
# there's no real rendering toolchain here.
#
# Usage: build-slot.sh SOURCE_PATH VARIANT OUTPUT_PATH [SLOT_ID]
set -euo pipefail
source_path="$1" variant="$2" output_path="$3" slot_id="${4:-}"
mkdir -p "$(dirname "$output_path")"
{
    echo "# built by backends/test, variant=$variant, slot_id=$slot_id"
    cat "$source_path"
} > "$output_path"
