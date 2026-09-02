#!/bin/bash
# Usage: content-hash.sh SOURCE_PATH VARIANT
# Hashes SOURCE_PATH + the shared preamble + this variant's header (if
# any) -- so a preamble/theme change invalidates every cached slot's
# version-tracking hash (see core/version-lib.sh), not just ones whose
# own body changed.
set -euo pipefail
BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_path="$1" variant="$2"

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
} | _md5
