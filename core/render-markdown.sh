#!/bin/bash
# Generic markdown calendar table generator -- one column per session
# kind (however many a course declares), replacing cs1101s/course-
# materials' generate-dynamic-calendar.sh, which hardcoded exactly
# Week/Studio/Wed/Thu/Fri/Notes.
#
# Depends on: schedule-lib.sh (week_occurrences, session_kind_ids),
# semester-lib.sh (semester_weeks), enrich-lib.sh (is_slot_released,
# slot_title, slot_kind_label, week_note, is_holiday, holiday_emoji).
# Caller sources all of these (or this file, which sources its own
# deps) before calling render_markdown_calendar.

RENDER_MD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RENDER_MD_DIR/schedule-lib.sh"
source "$RENDER_MD_DIR/semester-lib.sh"
source "$RENDER_MD_DIR/enrich-lib.sh"

# _md_variant_links KIND_ID SLOT_ID VARIANTS PDF_BASE_URL RELEASED
# [EXTRA_LINK_LABEL] [EXTRA_LINK_URL] -> "[View](url) &middot;
# [Print](url)"-style markdown, or the same labels as plain (unlinked)
# text if RELEASED is false. VARIANTS "none" -> single "Sheet" link/
# label. EXTRA_LINK_LABEL/_URL (both optional -- e.g. "Recording"/a
# Panopto URL) append one more link after the normal variant links, same
# convention as render-html.sh's _html_variant_links: a live
# [label](url) if EXTRA_LINK_URL is set, plain unlinked text otherwise.
_md_variant_links() {
    local kind_id="$1" slot_id="$2" variants="$3" base_url="$4" released="$5"
    local extra_link_label="${6:-}" extra_link_url="${7:-}"
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
    if [ -n "$extra_link_label" ]; then
        if [ -n "$extra_link_url" ]; then
            parts+=("[${extra_link_label}](${extra_link_url})")
        else
            parts+=("$extra_link_label")
        fi
    fi
    local out="${parts[0]}"
    local i
    for ((i = 1; i < ${#parts[@]}; i++)); do
        out="$out &middot; ${parts[$i]}"
    done
    echo "$out"
}

# _occasion_links_markdown RAW -> markdown-linked text for
# occasion_links' raw "LABEL1|URL1|LABEL2|URL2" return value,
# "&middot;"-joined, empty if RAW has no non-empty label at all. Same
# live-vs-plain-text convention as _md_variant_links.
_occasion_links_markdown() {
    local raw="$1"
    local -a f
    IFS='|' read -ra f <<< "$raw"
    local l1_label="${f[0]:-}" l1_url="${f[1]:-}" l2_label="${f[2]:-}" l2_url="${f[3]:-}"
    local parts=()
    if [ -n "$l1_label" ]; then
        if [ -n "$l1_url" ]; then
            parts+=("[${l1_label}](${l1_url})")
        else
            parts+=("$l1_label")
        fi
    fi
    if [ -n "$l2_label" ]; then
        if [ -n "$l2_url" ]; then
            parts+=("[${l2_label}](${l2_url})")
        else
            parts+=("$l2_label")
        fi
    fi
    [ "${#parts[@]}" -eq 0 ] && return 0
    local out="${parts[0]}" i
    for ((i = 1; i < ${#parts[@]}; i++)); do
        out="${out} &middot; ${parts[$i]}"
    done
    echo "$out"
}

# render_kind_cell WEEK KIND_ID OCCURRENCES_FILE TITLES_FILE ALLOWLIST_FILE
# LABELS_FILE PDF_BASE_URL HOLIDAYS_FILE EMOJI_FILE [EXTRA_LINK_LABEL]
# [EXTRA_LINK_FILE] [OCCASION_LINKS_FILE] -> this week's cell text for
# one kind column, "-" if nothing scheduled and no override label.
# OCCURRENCES_FILE holds this week's full week_occurrences() output
# (computed once per week by the caller, filtered here by KIND_ID) --
# multiple occurrences of the same kind (e.g. two lectures/week) are
# joined with "<br>". An occurrence whose real date (OCCURRENCES_FILE's
# own date column) falls on a HOLIDAYS_FILE entry renders as "No <label>
# (<emoji> <holiday>)" instead of its usual title+links -- this
# overrides even an authored/released slot, since the session didn't
# happen regardless of whether content exists for it. EXTRA_LINK_LABEL/
# _FILE (both optional -- e.g. "Recording"/a SLOT_ID|URL file) add a
# second, independently-gated link to every occurrence -- see
# _md_variant_links' own comment. An occasion label (slot_kind_label) is
# checked UNCONDITIONALLY, not just when this kind has zero occurrences
# this week -- see render-html.sh's render_kind_cell_html for the full
# rationale (the same fix, mirrored here) -- and OCCASION_LINKS_FILE
# (optional) gives it up to 2 links.
render_kind_cell() {
    local week="$1" kind_id="$2" occurrences_file="$3" titles_file="$4"
    local allowlist_file="$5" labels_file="$6" base_url="$7"
    local holidays_file="$8" emoji_file="$9"
    local extra_link_label="${10:-}" extra_link_file="${11:-}"
    local occasion_links_file="${12:-}"
    local rows
    rows=$(awk -F'|' -v k="$kind_id" '$1==k' "$occurrences_file")

    local cell_parts=()
    local occ_label
    occ_label="$(slot_kind_label "$week" "$kind_id" "$labels_file")"
    if [ -n "$occ_label" ]; then
        local occ_raw occ_links_md occ_part="$occ_label"
        occ_raw="$(occasion_links "$week" "$kind_id" "$occasion_links_file")"
        if [ -n "$occ_raw" ]; then
            occ_links_md="$(_occasion_links_markdown "$occ_raw")"
            [ -n "$occ_links_md" ] && occ_part="${occ_label} (${occ_links_md})"
        fi
        cell_parts+=("$occ_part")
    fi

    if [ -z "$rows" ]; then
        if [ ${#cell_parts[@]} -eq 0 ]; then
            echo "-"
        else
            echo "${cell_parts[0]}"
        fi
        return 0
    fi
    while IFS='|' read -r rkind rlabel rslot rdate rweekday rsuffix rvariants; do
        [ -z "$rkind" ] && continue
        local holiday_name
        holiday_name="$(is_holiday "$rdate" "$holidays_file")" && {
            local emoji prefix=""
            emoji="$(holiday_emoji "$holiday_name" "$emoji_file")"
            [ -n "$emoji" ] && prefix="${emoji} "
            cell_parts+=("No ${rlabel} (${prefix}${holiday_name})")
            continue
        }
        local title released links extra_url=""
        title="$(slot_title "$rslot" "$titles_file")"
        title="$(compose_slot_title "$rslot" "$title")"
        if is_slot_released "$rslot" "$allowlist_file"; then
            released=1
        else
            released=0
        fi
        [ -n "$extra_link_label" ] && extra_url="$(extra_link_for_slot "$rslot" "$extra_link_file")"
        links="$(_md_variant_links "$rkind" "$rslot" "$rvariants" "$base_url" "$released" "$extra_link_label" "$extra_url")"
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
# PDF_BASE_URL HOLIDAYS_FILE EMOJI_FILE [KIND_EXTRA_LINKS_FILE]
# [EXTRA_LINKS_FILE] -> a full markdown table, one row per teaching
# week, one column per distinct kind (in session-kinds.conf's
# first-appearance order) plus a trailing Notes column.
# HOLIDAYS_FILE/EMOJI_FILE are optional -- pass "/dev/null" (or any
# nonexistent path) for either to disable holiday-cancellation rendering
# entirely. KIND_EXTRA_LINKS_FILE (a KIND_ID|LABEL file) and
# EXTRA_LINKS_FILE (a SLOT_ID|URL file) are both optional -- see
# render_kind_cell's own comment; a course that doesn't want a second
# link per occurrence for any kind just never creates
# KIND_EXTRA_LINKS_FILE. OCCASION_LINKS_FILE (optional) is
# occasion_links' own WEEK|KIND_ID|... file, giving an occasion label up
# to 2 optional links -- see render_kind_cell's comment.
render_markdown_calendar() {
    local kinds_conf="$1" start_monday="$2" num_weeks="$3" recess_after="$4"
    local titles_file="$5" allowlist_file="$6" labels_file="$7" notes_file="$8"
    local base_url="$9" holidays_file="${10}" emoji_file="${11}"
    local kind_extra_links_file="${12:-}" extra_links_file="${13:-}"
    local occasion_links_file="${14:-}"

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
            local cell extra_label=""
            [ -n "$kind_extra_links_file" ] && extra_label="$(kind_extra_link_label "$k" "$kind_extra_links_file")"
            cell="$(render_kind_cell "$teaching_week" "$k" "$occ_file" "$titles_file" "$allowlist_file" "$labels_file" "$base_url" "$holidays_file" "$emoji_file" "$extra_label" "$extra_links_file" "$occasion_links_file")"
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
