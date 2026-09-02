#!/bin/bash
# Reference/test backend -- see build-slot.sh's header comment.
# Usage: content-hash.sh SOURCE_PATH VARIANT
set -euo pipefail
source_path="$1" variant="$2"
_md5() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum | cut -d' ' -f1
    else
        md5 -q
    fi
}
{ cat "$source_path"; echo "variant=$variant"; } | _md5
