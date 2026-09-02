#!/bin/bash
# Usage: content-hash.sh SOURCE_PATH VARIANT [SLOT_ID]
# Hashes SOURCE_PATH + the shared preamble + this variant's header (if
# any) + SLOT_ID -- so a preamble/theme change invalidates every cached
# slot's version-tracking hash (see core/version-lib.sh), not just ones
# whose own body changed, and so does a SLOT_ID change for a source that
# uses PLACEHOLDER_SLOT (see build-slot.sh) -- its actual compiled output
# depends on SLOT_ID too in that case, even though the source bytes
# didn't change.
set -euo pipefail
BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_path="$1" variant="$2" slot_id="${3:-}"

_md5() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum | cut -d' ' -f1
    else
        md5 -q
    fi
}

variant_header="$BACKEND_DIR/headers/${variant}.tex"
{
    cat "$source_path"
    cat "$BACKEND_DIR/preamble.tex"
    [ -f "$variant_header" ] && cat "$variant_header"
    echo "variant=$variant"
    echo "slot_id=$slot_id"
} | _md5
