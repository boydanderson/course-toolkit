#!/bin/bash
# Small lookups the table renderers need per slot, kept as plain
# SLOT_ID-keyed config files rather than anything that needs a backend
# dispatch or content-mapping resolved yet -- decouples "how did this
# title get extracted" (an upstream build step, eventually
# backend_extract_title -- see backend-lib.sh) from "what do we show in
# the table" (these renderers' only concern).

ENRICH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# _capitalize now lives in schedule-lib.sh (schedule-lib.sh's own
# kind_columns needs it too, and shouldn't depend on this file to get
# it) -- sourced here so every existing caller of enrich-lib.sh keeps
# getting it from here as well, unchanged.
source "$ENRICH_LIB_DIR/schedule-lib.sh"

# is_slot_released SLOT_ID ALLOWLIST_FILE -> success (0) if SLOT_ID is
# listed, failure (1) otherwise. One ID per line, comments/blanks
# ignored -- the same allow-list shape used throughout this ecosystem
# for "no date/timing logic, just list it when it's ready."
is_slot_released() {
    local slot_id="$1" allowlist_file="$2"
    [ -f "$allowlist_file" ] || return 1
    grep -vE '^\s*#|^\s*$' "$allowlist_file" | grep -Fxq "$slot_id"
}

# is_graded_slot SLOT_ID GRADED_FILE -> success (0) if SLOT_ID is
# listed, failure (1) otherwise. One ID per line, comments/blanks
# ignored -- same allow-list shape as is_slot_released, but for marking
# a slot as graded/important in the calendar table (e.g. a checkpoint
# or a trial run) rather than gating a PDF release. Optional: a course
# that doesn't create GRADED_FILE just gets no slot marked.
is_graded_slot() {
    local slot_id="$1" graded_file="$2"
    [ -f "$graded_file" ] || return 1
    grep -vE '^\s*#|^\s*$' "$graded_file" | grep -Fxq "$slot_id"
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

# occurrence_holiday DATE EXTRA_DATES HOLIDAYS_FILE -> the first holiday
# name found (success/0), checking DATE first, then each comma-separated
# EXTRA_DATES entry in order (schedule-lib.sh's week_occurrences already
# computes these from a row's optional CANCEL_EXTRA_WEEKDAYS field);
# empty + failure (1) if none of them land on a holiday. Thin wrapper
# around is_holiday, looped -- lets an occurrence spanning more than one
# real calendar day (e.g. a studio meeting Monday AND Tuesday with the
# same material) be cancelled by a holiday on ANY of those days, not just
# its own primary DATE. With EXTRA_DATES empty (the default -- a course
# that never sets CANCEL_EXTRA_WEEKDAYS), behaves exactly like a plain
# is_holiday call.
occurrence_holiday() {
    local date="$1" extra_dates="$2" holidays_file="$3" name
    name="$(is_holiday "$date" "$holidays_file")" && { echo "$name"; return 0; }
    [ -z "$extra_dates" ] && return 1
    local d
    local IFS_SAVE="$IFS"
    IFS=','
    for d in $extra_dates; do
        IFS="$IFS_SAVE"
        name="$(is_holiday "$d" "$holidays_file")" && { echo "$name"; return 0; }
    done
    IFS="$IFS_SAVE"
    return 1
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

# week_holiday_notes MONDAY HOLIDAYS_FILE EMOJI_FILE -> "⚠️ <Weekday>:
# <emoji> <Holiday>" for every day Monday..Sunday of the calendar week
# starting MONDAY that has a HOLIDAYS_FILE entry, semicolon-joined --
# empty if none. is_holiday's per-occurrence cancellation (above) only
# surfaces a holiday when it lands exactly on a day this course actually
# has a scheduled occurrence; this instead scans the whole week so a
# holiday landing on a day the course never meets (e.g. a Tuesday) still
# shows up somewhere. Scans all 7 days, not just Mon-Fri, since a course
# may schedule a real occurrence on a weekend (e.g. a Saturday quiz).
week_holiday_notes() {
    local monday="$1" holidays_file="$2" emoji_file="$3"
    [ -f "$holidays_file" ] || return 0
    local lines=() i date dow holiday emoji prefix
    for ((i = 0; i < 7; i++)); do
        date="$(add_days "$monday" "$i")"
        holiday="$(is_holiday "$date" "$holidays_file")" || continue
        dow="$(day_of_week_name "$date")"
        emoji="$(holiday_emoji "$holiday" "$emoji_file")"
        prefix=""
        [ -n "$emoji" ] && prefix="${emoji} "
        lines+=("⚠️ ${dow}: ${prefix}${holiday}")
    done
    [ ${#lines[@]} -eq 0 ] && return 0
    local out="${lines[0]}" j
    for ((j = 1; j < ${#lines[@]}; j++)); do
        out="${out}; ${lines[$j]}"
    done
    echo "$out"
}

# kind_extra_slots WEEK KIND_ID EXTRA_SLOTS_FILE -> one SLOT_ID per line
# (file order), for slots that share WEEK+KIND_ID with whatever
# week_occurrences() already produced but aren't a distinct weekly
# occurrence of their own -- e.g. a studio's "-in-class" supplement, the
# same session as the week's regular studio occurrence, no separate
# weekday/date/holiday-cancellation check, just a second linked file.
# Format: WEEK|KIND_ID|SLOT_ID. Empty if none/no file -- a course that
# never creates EXTRA_SLOTS_FILE just never gets this behavior (see
# render-markdown.sh's render_kind_cell / render-html.sh's
# render_kind_cell_html, both take it as an optional trailing param).
kind_extra_slots() {
    local week="$1" kind_id="$2" extra_slots_file="$3"
    [ -f "$extra_slots_file" ] || return 0
    awk -F'|' -v w="$week" -v k="$kind_id" '$1==w && $2==k {print $3}' "$extra_slots_file"
}

# extra_note_for_slot SLOT_ID NOTES_FILE -> arbitrary already-rendered
# HTML/text for this slot, empty if none listed. Format: SLOT_ID|HTML.
# Generalizes the RENDERING SLOT a course-specific extraction step (e.g.
# cs1101s/course-materials' scripts/sicpy-sections.py, which parses
# LaTeX for SICPy `§`-section references) can occupy under a lecture's
# title+links -- not the extraction itself, which stays entirely course-
# owned; this function doesn't know or care how the text was produced,
# same as extra_link_for_slot doesn't know how a Recording URL was
# obtained. render_kind_cell_html (HTML only -- no markdown equivalent
# exists to preserve) renders a non-empty result as one more line under
# the title+links, same shape render_item's own optional third line
# already used in the original bespoke code this generalizes.
extra_note_for_slot() {
    local slot_id="$1" notes_file="$2"
    [ -f "$notes_file" ] || return 0
    grep -vE '^\s*#|^\s*$' "$notes_file" | grep "^${slot_id}|" | head -1 | cut -d'|' -f2- || true
}

# kind_extra_link_label KIND_ID LABELS_FILE -> the label for this kind's
# optional second link (e.g. "lecture" -> "Recording"), empty if this
# kind doesn't have one. Format: KIND_ID|LABEL. A course that doesn't
# want a second link per occurrence (Panopto recordings, a livestream,
# whatever) just never creates this file -- every kind's cell renders
# exactly as before.
kind_extra_link_label() {
    local kind_id="$1" labels_file="$2"
    [ -f "$labels_file" ] || return 0
    grep -vE '^\s*#|^\s*$' "$labels_file" | grep "^${kind_id}|" | head -1 | cut -d'|' -f2- || true
}

# extra_link_for_slot SLOT_ID LINKS_FILE -> the URL for this slot's
# extra link, empty if none listed yet (renders as a pending/greyed
# label rather than a live link -- same "no date/timing logic, just
# list it when it's ready" convention as is_slot_released). Format:
# SLOT_ID|URL, one per line.
extra_link_for_slot() {
    local slot_id="$1" links_file="$2"
    [ -f "$links_file" ] || return 0
    grep -vE '^\s*#|^\s*$' "$links_file" | grep "^${slot_id}|" | head -1 | cut -d'|' -f2- || true
}

# occasion_links WEEK KIND_ID LINKS_FILE -> "LABEL1|URL1|LABEL2|URL2"
# (URLs may be empty -- pending, same convention as extra_link_for_slot;
# LABEL2/URL2 may be entirely absent for a single-link occasion), empty
# if this week+kind has no occasion at all. Format: WEEK|KIND_ID|
# LABEL1|URL1|LABEL2|URL2, capped at exactly 2 links (matches every real
# observed need -- e.g. an assessment's "Details"/"Papers") rather than
# an arbitrary N, so this stays parseable with a fixed-arity `read`
# rather than a variable-arity parser. A course only needing the plain
# label (no links) just gives LINK1_LABEL/LINK1_URL empty too -- see
# slot_kind_label for that simpler, links-free case, which this is
# meant to be layered on top of, not a replacement for.
occasion_links() {
    local week="$1" kind_id="$2" links_file="$3"
    [ -f "$links_file" ] || return 0
    awk -F'|' -v w="$week" -v k="$kind_id" '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        $1==w && $2==k { sub(/^[^|]*\|[^|]*\|/, ""); print; exit }
    ' "$links_file"
}
