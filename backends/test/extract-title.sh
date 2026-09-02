#!/bin/bash
# Reference/test backend -- see build-slot.sh's header comment.
# Usage: extract-title.sh SOURCE_PATH
set -euo pipefail
source_path="$1"
[ -f "$source_path" ] || { echo ""; exit 0; }
sed -n 's/^TITLE: //p' "$source_path" | head -1
