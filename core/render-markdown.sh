#!/bin/bash
# Generic markdown calendar table generator -- one column per session
# kind (however many a course declares), replacing cs1101s/course-
# materials' generate-dynamic-calendar.sh, which hardcoded exactly
# Week/Studio/Wed/Thu/Fri/Notes.
#
# Depends on: schedule-lib.sh (week_occurrences, session_kind_ids),
# semester-lib.sh (semester_weeks), enrich-lib.sh (is_slot_released,
# slot_title, slot_kind_label, week_note). Caller sources all of these
# (or this file, which sources its own deps) before calling
# render_markdown_calendar.

RENDER_MD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RENDER_MD_DIR/schedule-lib.sh"
source "$RENDER_MD_DIR/semester-lib.sh"
source "$RENDER_MD_DIR/enrich-lib.sh"

# _md_variant_links KIND_ID SLOT_ID VARIANTS PDF_BASE_URL RELEASED ->
# "[View](url) &middot; [Print](url)"-style markdown, or the same labels
# as plain (unlinked) text if RELEASED is false. VARIANTS "none" ->
# single "Sheet" link/label.
_md_variant_links() {
    local kind_id="$1" slot_id="$2" variants="$3" base_url="$4" released="$5"
    local IFS=','
    local -a vlist
    read -ra vlist <<< "$variants"
    local parts=() v label fname
    if [ "$variants" = "none" ]; then
        vlist=("")
    fi
    for v in "${vlist[@]}"; do
        if [ -z "$v" ]; then
            label="Sheet"
            fname="${kind_id}-${slot_id}.pdf"
        else
            label="$(_capitalize "$v")"
            fname="${kind_id}-${slot_id}.${v}.pdf"
        fi
        if [ "$released" = "1" ]; then
            parts+=("[${label}](${base_url}/${fname})")
        else
            parts+=("$label")
        fi
    done
    local out="${parts[0]}"
    local i
    for ((i = 1; i < ${#parts[@]}; i++)); do
        out="$out &middot; ${parts[$i]}"
    done
    echo "$out"
}

# render_kind_cell WEEK KIND_ID OCCURRENCES_FILE TITLES_FILE ALLOWLIST_FILE
# LABELS_FILE PDF_BASE_URL -> this week's cell text for one kind column,
# "-" if nothing scheduled and no override label. OCCURRENCES_FILE holds
# this week's full week_occurrences() output (computed once per week by
# the caller, filtered here by KIND_ID) -- multiple occurrences of the
# same kind (e.g. two lectures/week) are joined with "<br>".
render_kind_cell() {
    local week="$1" kind_id="$2" occurrences_file="$3" titles_file="$4"
    local allowlist_file="$5" labels_file="$6" base_url="$7"
    local rows
    rows=$(awk -F'|' -v k="$kind_id" '$1==k' "$occurrences_file")
    if [ -z "$rows" ]; then
        local label
        label="$(slot_kind_label "$week" "$kind_id" "$labels_file")"
        [ -n "$label" ] && echo "$label" || echo "-"
        return 0
    fi
    local cell_parts=() line
    while IFS='|' read -r rkind rlabel rslot rdate rweekday rsuffix rvariants; do
        [ -z "$rkind" ] && continue
        local title released links
        title="$(slot_title "$rslot" "$titles_file")"
        title="$(compose_slot_title "$rslot" "$title")"
        if is_slot_released "$rslot" "$allowlist_file"; then
            released=1
        else
            released=0
        fi
        links="$(_md_variant_links "$rkind" "$rslot" "$rvariants" "$base_url" "$released")"
        cell_parts+=("${title} (${links})")
    done <<< "$rows"
    # $IFS-based joining only uses IFS's first character, not the whole
    # separator string -- an explicit loop avoids that trap for a
    # multi-character separator like "<br>".
    local out="${cell_parts[0]}"
    local i
    for ((i = 1; i < ${#cell_parts[@]}; i++)); do
        out="${out}<br>${cell_parts[$i]}"
    done
    echo "$out"
}

# render_markdown_calendar SESSION_KINDS_CONF START_MONDAY NUM_WEEKS
# RECESS_AFTER_WEEK TITLES_FILE ALLOWLIST_FILE LABELS_FILE NOTES_FILE
# PDF_BASE_URL -> a full markdown table, one row per teaching week, one
# column per distinct kind (in session-kinds.conf's first-appearance
# order) plus a trailing Notes column.
render_markdown_calendar() {
    local kinds_conf="$1" start_monday="$2" num_weeks="$3" recess_after="$4"
    local titles_file="$5" allowlist_file="$6" labels_file="$7" notes_file="$8"
    local base_url="$9"

    local -a kind_ids
    while IFS= read -r k; do kind_ids+=("$k"); done < <(session_kind_ids "$kinds_conf")

    local header="| Week |"
    local sep="|------|"
    local k
    for k in "${kind_ids[@]}"; do
        header="${header} $(_capitalize "$k") |"
        sep="${sep}------|"
    done
    header="${header} Notes |"
    sep="${sep}-------|"
    echo "$header"
    echo "$sep"

    local occ_file
    occ_file="$(mktemp)"
    while IFS='|' read -r teaching_week monday; do
        week_occurrences "$kinds_conf" "$monday" "$teaching_week" > "$occ_file"
        local row="| $teaching_week |"
        for k in "${kind_ids[@]}"; do
            local cell
            cell="$(render_kind_cell "$teaching_week" "$k" "$occ_file" "$titles_file" "$allowlist_file" "$labels_file" "$base_url")"
            row="${row} ${cell} |"
        done
        local note
        note="$(week_note "$teaching_week" "$notes_file")"
        [ -z "$note" ] && note="-"
        row="${row} ${note} |"
        echo "$row"
    done < <(semester_weeks "$start_monday" "$num_weeks" "$recess_after")
    rm -f "$occ_file"
}
