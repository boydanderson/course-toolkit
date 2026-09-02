#!/bin/bash
# Reference/test backend -- see build-slot.sh's header comment.
# Usage: content-hash.sh SOURCE_PATH VARIANT [SLOT_ID]
set -euo pipefail
source_path="$1" variant="$2" slot_id="${3:-}"
_md5() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum | cut -d' ' -f1
    else
        md5 -q
    fi
}
{ cat "$source_path"; echo "variant=$variant"; echo "slot_id=$slot_id"; } | _md5
