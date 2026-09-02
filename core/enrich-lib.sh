#!/bin/bash
# Small lookups the table renderers need per slot, kept as plain
# SLOT_ID-keyed config files rather than anything that needs a backend
# dispatch or content-mapping resolved yet -- decouples "how did this
# title get extracted" (an upstream build step, eventually
# backend_extract_title -- see backend-lib.sh) from "what do we show in
# the table" (these renderers' only concern).

# _capitalize WORD -> WORD with its first character upper-cased (e.g.
# "lecture" -> "Lecture", "view" -> "View"), for column headers/variant
# labels. Portable `tr`/`cut`, not bash 4+'s ${var^} -- macOS ships bash
# 3.2 as /bin/bash, which doesn't support it (see schedule-lib.sh's
# weekday_offset for the same fix, confirmed for real).
_capitalize() {
    local w="$1"
    printf '%s%s' "$(printf '%s' "${w:0:1}" | tr '[:lower:]' '[:upper:]')" "${w:1}"
}

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
    # || true: a scheduled occurrence with nothing in TITLES_FILE yet
    # (e.g. no content-map entry at all) is a normal "nothing to show",
    # not something that should abort a caller running under set -e via
    # grep's "no match" exit status propagating out of a plain command
    # substitution.
    grep -vE '^\s*#|^\s*$' "$titles_file" | grep "^${slot_id}|" | head -1 | cut -d'|' -f2- || true
}

# compose_slot_title SLOT_ID TITLE -> "SLOT_ID: TITLE", or just SLOT_ID
# if TITLE is empty. Won't double-prepend if TITLE already starts with
# "SLOT_ID: " -- a backend's extract-title (e.g. backends/latex-beamer's)
# can't safely strip a slot-ID prefix itself (it has no way to know what
# a course's slot IDs look like), so a raw \title{L1A: Topic} comes back
# with the prefix still on it; this is the one place that knows both
# values and can dedupe correctly rather than guessing a strip pattern.
compose_slot_title() {
    local slot_id="$1" title="$2"
    if [ -z "$title" ]; then
        echo "$slot_id"
    elif [ "$title" = "${title#${slot_id}: }" ]; then
        echo "${slot_id}: ${title}"
    else
        echo "$title"
    fi
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
    # $IFS-based joining (${lines[*]} with IFS='; ') only uses IFS's
    # first character, not the whole separator string -- confirmed for
    # real (silently drops the space, joining "a;b" not "a; b"). Same
    # trap already hit and fixed in render-markdown.sh; an explicit loop
    # avoids it here too.
    local out="${lines[0]}" i
    for ((i = 1; i < ${#lines[@]}; i++)); do
        out="${out}; ${lines[$i]}"
    done
    echo "$out"
}

# is_holiday DATE HOLIDAYS_FILE -> the holiday's name (success/0) if
# DATE is listed, empty + failure (1) otherwise. Format: DATE|NAME
# (YYYY-MM-DD), one per line -- a course supplies this itself (fetching
# a real institution's public-holiday calendar is out of scope for a
# generic toolkit; it's just data here).
is_holiday() {
    local date="$1" holidays_file="$2" name
    [ -f "$holidays_file" ] || return 1
    name=$(grep -vE '^\s*#|^\s*$' "$holidays_file" | grep "^${date}|" | head -1 | cut -d'|' -f2- || true)
    [ -z "$name" ] && return 1
    echo "$name"
}

# holiday_emoji NAME EMOJI_FILE -> one emoji for this holiday, empty if
# none mapped. Format: HOLIDAY_NAME|EMOJI. Strips a trailing
# "(Observed)"/"(observed)" and normalizes a curly apostrophe to
# straight before matching, since a real public-holiday feed can be
# inconsistent about both across years (confirmed for real against
# data.gov.sg's -- both "New Year's Day" and "New Year’s Day" appear) --
# the observed version of a holiday shares its base holiday's emoji.
holiday_emoji() {
    local name="$1" emoji_file="$2"
    [ -f "$emoji_file" ] || return 0
    local base
    base=$(printf '%s' "$name" | sed -E 's/ \([Oo]bserved\)$//' | sed "s/’/'/g")
    awk -F'|' -v n="$base" '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        $1==n { print $2; exit }
    ' "$emoji_file"
}
