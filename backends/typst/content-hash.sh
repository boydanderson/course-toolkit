#!/bin/bash
# Usage: content-hash.sh SOURCE_PATH VARIANT [SLOT_ID]
# Hashes SOURCE_PATH + every file it `#import`s (resolved relative to
# SOURCE_PATH's own directory, same resolution Typst itself uses for a
# relative import) + VARIANT -- so a shared template/config change
# (e.g. studio_template.typ, studio_numbers.typ) invalidates every
# slot's cached version-tracking hash that imports it, not just ones
# whose own body changed. Only follows one level of #import (not a full
# recursive dependency graph) -- correct for this course's actual import
# depth (a handout imports its kind's template + numbers config, neither
# of which themselves import anything further); a course with deeper
# import chains would need this extended.
#
# SLOT_ID is accepted for contract-compatibility but unused -- this
# backend has no PLACEHOLDER_SLOT-style substitution, see build-slot.sh.
set -uo pipefail
source_path="$1" variant="$2"
# slot_id="${3:-}"  # accepted, unused -- see header comment.

_md5() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum | cut -d' ' -f1
    else
        md5 -q
    fi
}

if [ ! -f "$source_path" ]; then
    echo "content-hash.sh: source file not found: $source_path" >&2
    exit 1
fi

source_dir="$(dirname "$source_path")"

{
    cat "$source_path"
    echo "variant=$variant"

    # Relative #import "PATH" targets only (package imports like
    # "@preview/circuiteria:0.2.0" have no local file to hash and are
    # version-pinned in the source text itself, already covered by the
    # `cat "$source_path"` above).
    grep -oE '#import "[^"]+"' "$source_path" 2>/dev/null | sed -E 's/^#import "([^"]+)"$/\1/' \
        | while IFS= read -r import_path; do
            case "$import_path" in
                @*) continue ;;  # package import, not a local file
            esac
            resolved="$source_dir/$import_path"
            [ -f "$resolved" ] && cat "$resolved"
        done
} | _md5
