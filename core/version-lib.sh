#!/bin/bash
# The version/content-hash ledger -- replaces cs1101s/course-materials'
# two hand-coordinated, differently-shaped ID schemes (get-lecture-
# version.sh's "CALENDAR_SLOT.VARIANT", e.g. "L1A.view", vs
# get-studio-version.sh's "KIND-ID.VARIANT", e.g. "studio-S2.problem" --
# sharing one config/versions.conf only by convention, never enforced)
# with one: every tracked artifact's key is simply "SLOT_ID.VARIANT",
# where SLOT_ID already comes out of schedule-lib.sh's format_slot_id and
# is kind-agnostic by construction (L4A, S4, REC3, ... whatever a
# course's session-kinds.conf produces) -- no more per-kind-type special
# casing needed to track versions.
#
# A build never increments a slot's version by itself, even when content
# changed -- get_slot_version only refreshes the stored content hash/date
# so future incremental builds keep detecting "no change" correctly. The
# version number only moves on explicit request via bump_slot_version.
# (Preserves cs1101s/course-materials' own deliberate design: the old
# auto-increment-on-every-change behavior made routine same-day edits
# look like real revision history.)
#
# Version data lives in two files under COURSE_ROOT (env var, default
# "."; see README's "Path resolution"), split so routine builds never
# touch git:
#   config/versions.conf (tracked)   -- SLOT_ID.VARIANT|VERSION, moved
#                                        only by bump_slot_version, or
#                                        once when an ID is first built
#   .versions-cache (gitignored)     -- SLOT_ID.VARIANT|HASH|BUILD_DATE,
#                                        refreshed by every build; a pure
#                                        performance cache, safe to delete
#
# BUILD_DATE is always Singapore time (see date-lib.sh's sgt_date) --
# never the build machine's own local time, which is UTC on most CI
# runners and would otherwise silently mis-date a build made near the
# SGT day boundary.

VERSION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$VERSION_LIB_DIR/date-lib.sh"

_version_file() { echo "${COURSE_ROOT:-.}/config/versions.conf"; }
_cache_file() { echo "${COURSE_ROOT:-.}/.versions-cache"; }

_ensure_version_files() {
    local vf cf
    vf="$(_version_file)"; cf="$(_cache_file)"
    mkdir -p "$(dirname "$vf")" "$(dirname "$cf")"
    [ -f "$vf" ] || echo "# Format: SLOT_ID.VARIANT|VERSION" > "$vf"
    [ -f "$cf" ] || echo "# Format: SLOT_ID.VARIANT|HASH|BUILD_DATE" > "$cf"
}

# Serializes read-modify-write access to both files against concurrent
# builds (`make -j`) touching different slots at once -- a mkdir-based
# lock, not flock, since flock isn't available on macOS by default. Same
# lock name covers both files (always written together by one caller).
_with_version_lock() {
    local cf lock_dir
    cf="$(_cache_file)"
    lock_dir="${cf}.lock"
    trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT
    until mkdir "$lock_dir" 2>/dev/null; do sleep 0.1; done
    "$@"
    rmdir "$lock_dir" 2>/dev/null || true
    trap - EXIT
}

# get_slot_version SLOT_ID VARIANT CONTENT_HASH [SOURCE_DATE_EPOCH] ->
# prints the current version (creating a "1.0" entry the first time this
# ID.VARIANT is seen). Refreshes the cached hash/date if CONTENT_HASH
# changed; leaves the version number untouched either way.
get_slot_version() {
    local slot_id="$1" variant="$2" content_hash="$3" source_date_epoch="${4:-}"
    local id="${slot_id}.${variant}"
    local vf cf
    vf="$(_version_file)"; cf="$(_cache_file)"
    _ensure_version_files

    local current_version_line current_cache_line new_version
    current_version_line=$(grep "^${id}|" "$vf" 2>/dev/null || true)
    current_cache_line=$(grep "^${id}|" "$cf" 2>/dev/null || true)

    if [ -z "$current_version_line" ]; then
        new_version="1.0"
    else
        new_version=$(echo "$current_version_line" | cut -d'|' -f2)
        local current_hash
        current_hash=$(echo "$current_cache_line" | cut -d'|' -f2)
        if [ -n "$current_cache_line" ] && [ "$content_hash" = "$current_hash" ]; then
            echo "$new_version"
            return 0
        fi
    fi

    local build_date
    build_date=$(sgt_date '+%Y-%m-%d' "$source_date_epoch")

    _with_version_lock _get_slot_version_write "$vf" "$cf" "$id" "$new_version" \
        "$content_hash" "$build_date" "$current_version_line" "$current_cache_line"
    echo "$new_version"
}

_get_slot_version_write() {
    local vf="$1" cf="$2" id="$3" version="$4" hash="$5" date="$6"
    local existing_version_line="$7" existing_cache_line="$8"
    if [ -z "$existing_version_line" ]; then
        echo "${id}|${version}" >> "$vf"
    fi
    if [ -z "$existing_cache_line" ]; then
        echo "${id}|${hash}|${date}" >> "$cf"
    else
        local tmp; tmp=$(mktemp "${cf}.XXXXXX")
        awk -v id="$id" -v newline="${id}|${hash}|${date}" \
            'BEGIN { FS="|" } $1==id { print newline; next } { print }' \
            "$cf" > "$tmp"
        mv "$tmp" "$cf"
    fi
}

# bump_slot_version SLOT_ID VARIANT CONTENT_HASH [SOURCE_DATE_EPOCH] ->
# increments the minor version (error if this ID.VARIANT has never been
# built), refreshes the cache to CONTENT_HASH, prints "OLD -> NEW".
bump_slot_version() {
    local slot_id="$1" variant="$2" content_hash="$3" source_date_epoch="${4:-}"
    local id="${slot_id}.${variant}"
    local vf cf
    vf="$(_version_file)"; cf="$(_cache_file)"
    if [ ! -f "$vf" ]; then
        echo "Error: $vf not found -- nothing to bump (build it first)." >&2
        return 1
    fi
    local current_line current_version major minor new_version
    current_line=$(grep "^${id}|" "$vf" 2>/dev/null || true)
    if [ -z "$current_line" ]; then
        echo "Error: no existing entry for ${id} in $vf -- build it first." >&2
        return 1
    fi
    current_version=$(echo "$current_line" | cut -d'|' -f2)
    major=$(echo "$current_version" | cut -d'.' -f1)
    minor=$(echo "$current_version" | cut -d'.' -f2)
    minor=$((minor + 1))
    new_version="${major}.${minor}"

    local build_date
    build_date=$(sgt_date '+%Y-%m-%d' "$source_date_epoch")

    _with_version_lock _bump_slot_version_write "$vf" "$cf" "$id" "$new_version" "$content_hash" "$build_date"
    echo "${id}: ${current_version} -> ${new_version}"
}

_bump_slot_version_write() {
    local vf="$1" cf="$2" id="$3" new_version="$4" hash="$5" date="$6"
    local tmp; tmp=$(mktemp "${vf}.XXXXXX")
    awk -v id="$id" -v newline="${id}|${new_version}" \
        'BEGIN { FS="|" } $1==id { print newline; next } { print }' \
        "$vf" > "$tmp"
    mv "$tmp" "$vf"

    if [ -f "$cf" ] && grep -q "^${id}|" "$cf" 2>/dev/null; then
        tmp=$(mktemp "${cf}.XXXXXX")
        awk -v id="$id" -v newline="${id}|${hash}|${date}" \
            'BEGIN { FS="|" } $1==id { print newline; next } { print }' \
            "$cf" > "$tmp"
        mv "$tmp" "$cf"
    else
        [ -f "$cf" ] || echo "# Format: SLOT_ID.VARIANT|HASH|BUILD_DATE" > "$cf"
        echo "${id}|${hash}|${date}" >> "$cf"
    fi
}
