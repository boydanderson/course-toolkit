#!/bin/bash
# Reference/test backend -- see build-slot.sh's header comment.
# Usage: content-hash.sh SOURCE_PATH VARIANT [SLOT_ID]
set -euo pipefail
BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_path="$1" variant="$2" slot_id="${3:-}"
source "$BACKEND_DIR/../lib/md5.sh"
{ cat "$source_path"; echo "variant=$variant"; echo "slot_id=$slot_id"; } | _md5
