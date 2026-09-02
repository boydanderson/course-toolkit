#!/bin/bash
# Small lookups the table renderers need per slot, kept as plain
# SLOT_ID-keyed config files rather than anything that needs a backend
# dispatch or content-mapping resolved yet -- decouples "how did this
# title get extracted" (an upstream build step, eventually
# backend_extract_title -- see backend-lib.sh) from "what do we show in
# the table" (these renderers' only concern).

# is_slot_released SLOT_ID ALLOWLIST_FILE -> success (0) if SLOT_ID is
# listed, failure (1) otherwise. One ID per line, comments/blanks
# ignored -- the same allow-list shape used throughout this ecosystem
# for "no date/timing logic, just list it when it's ready."
is_slot_released() {
    local slot_id="$1" allowlist_file="$2"
    [ -f "$allowlist_file" ] || return 1
    grep -vE '^\s*#|^\s*$' "$allowlist_file" | grep -Fxq "$slot_id"
}

# slot_title SLOT_ID TITLES_FILE -> the slot's display title, empty if
# none recorded. Format: SLOT_ID|TITLE.
slot_title() {
    local slot_id="$1" titles_file="$2"
    [ -f "$titles_file" ] || return 0
    grep -vE '^\s*#|^\s*$' "$titles_file" | grep "^${slot_id}|" | head -1 | cut -d'|' -f2-
}

# slot_kind_label WEEK KIND_ID LABELS_FILE -> a maintainer-written label
# override for a week+kind that otherwise has no occurrence (e.g. a
# one-off in-class-only session, never a real slot) -- generalizes
# cs1101s/course-materials' config/slot-label-overrides.conf (WEEK|
# COLUMN|LABEL) to use a session kind's own id instead of a fixed
# studio/wed/thu/fri column vocabulary.
slot_kind_label() {
    local week="$1" kind_id="$2" labels_file="$3"
    [ -f "$labels_file" ] || return 0
    awk -F'|' -v w="$week" -v k="$kind_id" '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        $1==w && $2==k { sub(/^[^|]*\|[^|]*\|/, ""); print; exit }
    ' "$labels_file"
}

# week_note WEEK NOTES_FILE -> a maintainer-written note for a whole
# week, joined with "; " if there's more than one line for that week.
# Unchanged in spirit from cs1101s/course-materials' config/canvas-week-
# notes.conf -- this was already week-keyed, not column-keyed, so it
# needed no generalization.
week_note() {
    local week="$1" notes_file="$2"
    [ -f "$notes_file" ] || return 0
    local lines=() line
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        lines+=("$line")
    done < <(grep -vE '^\s*#|^\s*$' "$notes_file" | grep "^${week}|" | cut -d'|' -f2-)
    [ ${#lines[@]} -eq 0 ] && return 0
    local IFS='; '
    echo "${lines[*]}"
}
