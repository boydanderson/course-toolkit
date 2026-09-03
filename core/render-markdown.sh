#!/bin/bash
# Generic markdown calendar table generator -- one column per session
# kind (however many a course declares), replacing cs1101s/course-
# materials' generate-dynamic-calendar.sh, which hardcoded exactly
# Week/Studio/Wed/Thu/Fri/Notes.
#
# Depends on: schedule-lib.sh (week_occurrences, session_kind_ids),
# semester-lib.sh (semester_weeks), enrich-lib.sh (is_slot_released,
# slot_title, slot_kind_label, week_note, is_holiday, holiday_emoji,
# occurrence_holiday, kind_extra_slots).
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

# _row_title_and_links KIND_ID SLOT_ID VARIANTS TITLES_FILE ALLOWLIST_FILE
# BASE_URL EXTRA_LINK_LABEL EXTRA_LINK_FILE GRADED_FILE -> "TITLE|LINKS"
# (split by the caller on the first "|") -- the title/graded-prefix/
# release-gate/variant-links computation a normal occurrence row and an
# extra slot (see kind_extra_slots, enrich-lib.sh) both need identically;
# an extra slot just has no weekday/date/holiday-cancellation check of
# its own, so it never calls this via the holiday branch.
_row_title_and_links() {
    local kind_id="$1" slot_id="$2" variants="$3" titles_file="$4" allowlist_file="$5"
    local base_url="$6" extra_link_label="$7" extra_link_file="$8" graded_file="$9"
    local title released links extra_url=""
    title="$(slot_title "$slot_id" "$titles_file")"
    title="$(compose_slot_title "$slot_id" "$title")"
    if [ -n "$graded_file" ] && is_graded_slot "$slot_id" "$graded_file"; then
        title="🔴 ${title}"
    fi
    if is_slot_released "$slot_id" "$allowlist_file"; then
        released=1
    else
        released=0
    fi
    [ -n "$extra_link_label" ] && extra_url="$(extra_link_for_slot "$slot_id" "$extra_link_file")"
    links="$(_md_variant_links "$kind_id" "$slot_id" "$variants" "$base_url" "$released" "$extra_link_label" "$extra_url")"
    printf '%s|%s\n' "$title" "$links"
}

# _row_raw_title_and_links -- same args/shape as _row_title_and_links,
# but returns the RAW title (before compose_slot_title's own SLOT_ID
# prefix), for the grouping path only. compose_slot_title always
# prefixes a slot's OWN id onto its title, so two different slots
# sharing the same real title (e.g. a studio "S3" and its "S3-in-class"
# supplement) would never produce matching COMPOSED titles to group
# by -- grouping has to key on the raw title instead, then compose the
# merged group's display title once, using its own representative slot
# (see render_kind_cell's grouping branch).
_row_raw_title_and_links() {
    local kind_id="$1" slot_id="$2" variants="$3" titles_file="$4" allowlist_file="$5"
    local base_url="$6" extra_link_label="$7" extra_link_file="$8" graded_file="$9"
    local title released links extra_url=""
    title="$(slot_title "$slot_id" "$titles_file")"
    if [ -n "$graded_file" ] && is_graded_slot "$slot_id" "$graded_file"; then
        title="🔴 ${title}"
    fi
    if is_slot_released "$slot_id" "$allowlist_file"; then
        released=1
    else
        released=0
    fi
    [ -n "$extra_link_label" ] && extra_url="$(extra_link_for_slot "$slot_id" "$extra_link_file")"
    links="$(_md_variant_links "$kind_id" "$slot_id" "$variants" "$base_url" "$released" "$extra_link_label" "$extra_url")"
    printf '%s|%s\n' "$title" "$links"
}

# _md_group_add TITLE SLOT_ID LINKS -> merges (SLOT_ID, LINKS) into
# module-private globals _MD_GROUP_TITLE/_MD_GROUP_ENTRY/_MD_GROUP_SLOT/
# _MD_GROUP_COUNT (reset by the caller -- see render_kind_cell's grouping
# branch -- before its first call this invocation) under an exact TITLE
# match; a title's first entry renders plain ("TITLE (LINKS)"), a second
# or later entry switches the WHOLE group to a slot-labeled form
# ("TITLE (SLOT1: LINKS1; SLOT2: LINKS2)") so a reader can tell which
# link belongs to which slot once there's more than one under one title.
# Plain top-level function operating on module-private globals, not
# caller-local arrays -- bash 3.2 (macOS's shipped /bin/bash) has no
# nameref support to pass arrays by reference.
_md_group_add() {
    local t="$1" slot="$2" links="$3" j found=0
    for ((j = 0; j < ${#_MD_GROUP_TITLE[@]}; j++)); do
        if [ "${_MD_GROUP_TITLE[$j]}" = "$t" ]; then
            if [ "${_MD_GROUP_COUNT[$j]}" -eq 1 ]; then
                _MD_GROUP_ENTRY[$j]="${_MD_GROUP_SLOT[$j]}: ${_MD_GROUP_ENTRY[$j]}"
            fi
            _MD_GROUP_ENTRY[$j]="${_MD_GROUP_ENTRY[$j]}; ${slot}: ${links}"
            _MD_GROUP_COUNT[$j]=$((_MD_GROUP_COUNT[$j] + 1))
            found=1
            break
        fi
    done
    if [ "$found" -eq 0 ]; then
        _MD_GROUP_TITLE+=("$t")
        _MD_GROUP_ENTRY+=("$links")
        _MD_GROUP_SLOT+=("$slot")
        _MD_GROUP_COUNT+=(1)
    fi
}

# render_kind_cell WEEK KIND_ID OCCURRENCES_FILE TITLES_FILE ALLOWLIST_FILE
# LABELS_FILE PDF_BASE_URL HOLIDAYS_FILE EMOJI_FILE [EXTRA_LINK_LABEL]
# [EXTRA_LINK_FILE] [OCCASION_LINKS_FILE] [SUFFIX_FILTER] [GRADED_FILE]
# [EXTRA_SLOTS_FILE]
# -> this week's cell text for one kind column, "-" if nothing scheduled and no
# override label. OCCURRENCES_FILE holds this week's full
# week_occurrences() output (computed once per week by the caller,
# filtered here by KIND_ID) -- multiple occurrences of the same kind
# (e.g. two lectures/week) are joined with "<br>". An occurrence whose
# real date (OCCURRENCES_FILE's own date column) falls on a
# HOLIDAYS_FILE entry renders as "No <label> (<emoji> <holiday>)"
# instead of its usual title+links -- this overrides even an authored/
# released slot, since the session didn't happen regardless of whether
# content exists for it. EXTRA_LINK_LABEL/_FILE (both optional -- e.g.
# "Recording"/a SLOT_ID|URL file) add a second, independently-gated link
# to every occurrence -- see _md_variant_links' own comment.
#
# SUFFIX_FILTER (optional) restricts rows to just that one weekly
# occurrence -- for a kind split into one column per suffix (see
# render_markdown_calendar) rather than one merged column. It also
# changes the occasion-label behavior: with no filter (the merged-
# column case), an occasion label (slot_kind_label) is checked
# UNCONDITIONALLY, not just when this kind has zero occurrences this
# week -- see render-html.sh's render_kind_cell_html for the full
# rationale (the same fix, mirrored here). With a filter (the
# split-column case), each column represents exactly one occurrence, so
# the simpler "only when nothing scheduled at this specific slot" rule
# is both sufficient and correct -- the unconditional check exists only
# to handle a merged cell where a sibling occurrence's presence would
# otherwise hide the label. With a filter, the label lookup also tries a
# suffix-qualified key first ("${KIND_ID}-${SUFFIX}", e.g. "studio-A" --
# not a real session-kind id, just this lookup's own convention), falling
# back to the plain KIND_ID if no suffix-specific row exists -- lets two
# different suffixes excluded the same week carry two different labels
# (e.g. week 12's Session 1 "OT OT" vs. Session 2 "Trial"), while an
# existing single-label-shared-across-suffixes config (the plain KIND_ID
# key) keeps working unchanged. OCCASION_LINKS_FILE (optional) gives the
# label up to 2 links either way, looked up under whichever key the
# label itself matched. GRADED_FILE (optional, one SLOT_ID per line --
# see enrich-lib.sh's is_graded_slot) marks a real occurrence as
# graded/important by prefixing its title with "🔴 " -- a course that
# doesn't create GRADED_FILE just gets no slot marked. EXTRA_SLOTS_FILE
# (optional, WEEK|KIND_ID|SLOT_ID -- see enrich-lib.sh's
# kind_extra_slots) lists extra slot IDs that share this week+kind
# without being a distinct weekly occurrence of their own (e.g. a
# studio's "-in-class" supplement riding along with the same session, no
# separate weekday/holiday-check) -- each gets the same title+links
# treatment as a normal row (inheriting the LAST processed row's
# VARIANTS, since an extra slot declares none of its own), then merges
# with any row/extra sharing an EXACTLY matching composed title (see
# _md_group_add) rather than always adding a separate entry. A course
# that never creates EXTRA_SLOTS_FILE (or has none for this week+kind)
# gets today's exact behavior, unchanged.
render_kind_cell() {
    local week="$1" kind_id="$2" occurrences_file="$3" titles_file="$4"
    local allowlist_file="$5" labels_file="$6" base_url="$7"
    local holidays_file="$8" emoji_file="$9"
    local extra_link_label="${10:-}" extra_link_file="${11:-}"
    local occasion_links_file="${12:-}" suffix_filter="${13:-}"
    local graded_file="${14:-}" extra_slots_file="${15:-}"
    local rows
    local -a extra_slot_ids=()
    if [ -n "$extra_slots_file" ]; then
        local es
        while IFS= read -r es; do
            [ -n "$es" ] && extra_slot_ids+=("$es")
        done < <(kind_extra_slots "$week" "$kind_id" "$extra_slots_file")
    fi
    if [ -n "$suffix_filter" ]; then
        rows=$(awk -F'|' -v k="$kind_id" -v s="$suffix_filter" '$1==k && $6==s' "$occurrences_file")
    else
        rows=$(awk -F'|' -v k="$kind_id" '$1==k' "$occurrences_file")
    fi

    local cell_parts=()
    # label_key: with a suffix filter, try a suffix-qualified key first
    # ("studio-A", not a real session-kind id, just this lookup's own
    # convention) so two different suffixes excluded the same week can
    # carry two different labels (e.g. week 12's Session 1 "OT OT" vs.
    # Session 2 "Trial") -- falls back to the plain kind_id (today's
    # only behavior) if no suffix-specific row exists, so an existing
    # single-label-shared-across-suffixes config keeps working unchanged.
    local label_key="$kind_id" occ_label
    [ -n "$suffix_filter" ] && label_key="${kind_id}-${suffix_filter}"
    occ_label="$(slot_kind_label "$week" "$label_key" "$labels_file")"
    if [ -z "$occ_label" ] && [ -n "$suffix_filter" ]; then
        label_key="$kind_id"
        occ_label="$(slot_kind_label "$week" "$label_key" "$labels_file")"
    fi
    if [ -n "$occ_label" ] && { [ -z "$suffix_filter" ] || [ -z "$rows" ]; }; then
        local occ_raw occ_links_md occ_part="$occ_label"
        occ_raw="$(occasion_links "$week" "$label_key" "$occasion_links_file")"
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
    if [ ${#extra_slot_ids[@]} -eq 0 ]; then
        # No extra slots for this week+kind -- today's exact behavior,
        # completely unchanged.
        while IFS='|' read -r rkind rlabel rslot rdate rweekday rsuffix rvariants rcancel_extra; do
            [ -z "$rkind" ] && continue
            local holiday_name
            holiday_name="$(occurrence_holiday "$rdate" "$rcancel_extra" "$holidays_file")" && {
                local emoji prefix=""
                emoji="$(holiday_emoji "$holiday_name" "$emoji_file")"
                [ -n "$emoji" ] && prefix="${emoji} "
                cell_parts+=("No ${rlabel} (${prefix}${holiday_name})")
                continue
            }
            local title released links extra_url=""
            title="$(slot_title "$rslot" "$titles_file")"
            title="$(compose_slot_title "$rslot" "$title")"
            if [ -n "$graded_file" ] && is_graded_slot "$rslot" "$graded_file"; then
                title="🔴 ${title}"
            fi
            if is_slot_released "$rslot" "$allowlist_file"; then
                released=1
            else
                released=0
            fi
            [ -n "$extra_link_label" ] && extra_url="$(extra_link_for_slot "$rslot" "$extra_link_file")"
            links="$(_md_variant_links "$rkind" "$rslot" "$rvariants" "$base_url" "$released" "$extra_link_label" "$extra_url")"
            cell_parts+=("${title} (${links})")
        done <<< "$rows"
    else
        # One or more extra slots share this week+kind (e.g. a studio's
        # "-in-class" supplement) -- group by exact composed-title match
        # via _md_group_add instead of always adding a separate entry.
        _MD_GROUP_TITLE=() _MD_GROUP_ENTRY=() _MD_GROUP_SLOT=() _MD_GROUP_COUNT=()
        local primary_variants=""
        while IFS='|' read -r rkind rlabel rslot rdate rweekday rsuffix rvariants rcancel_extra; do
            [ -z "$rkind" ] && continue
            primary_variants="$rvariants"
            local holiday_name
            holiday_name="$(occurrence_holiday "$rdate" "$rcancel_extra" "$holidays_file")" && {
                local emoji prefix=""
                emoji="$(holiday_emoji "$holiday_name" "$emoji_file")"
                [ -n "$emoji" ] && prefix="${emoji} "
                cell_parts+=("No ${rlabel} (${prefix}${holiday_name})")
                continue
            }
            local tl title links
            tl="$(_row_raw_title_and_links "$rkind" "$rslot" "$rvariants" "$titles_file" "$allowlist_file" "$base_url" "$extra_link_label" "$extra_link_file" "$graded_file")"
            title="${tl%%|*}"
            links="${tl#*|}"
            _md_group_add "$title" "$rslot" "$links"
        done <<< "$rows"
        local es_i
        for ((es_i = 0; es_i < ${#extra_slot_ids[@]}; es_i++)); do
            local es="${extra_slot_ids[$es_i]}"
            local tl title links
            tl="$(_row_raw_title_and_links "$kind_id" "$es" "$primary_variants" "$titles_file" "$allowlist_file" "$base_url" "$extra_link_label" "$extra_link_file" "$graded_file")"
            title="${tl%%|*}"
            links="${tl#*|}"
            _md_group_add "$title" "$es" "$links"
        done
        local gi
        for ((gi = 0; gi < ${#_MD_GROUP_TITLE[@]}; gi++)); do
            local composed
            composed="$(compose_slot_title "${_MD_GROUP_SLOT[$gi]}" "${_MD_GROUP_TITLE[$gi]}")"
            cell_parts+=("${composed} (${_MD_GROUP_ENTRY[$gi]})")
        done
    fi
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
# first-appearance order -- split into one column per occurrence for a
# kind with more than one/week, see schedule-lib.sh's kind_columns) plus
# a trailing Notes column. If RECESS_AFTER_WEEK > 0, a "Recess" row (all
# dashes, plus a "🏖️ Recess Week - No classes (dates)" note) is inserted
# between that teaching week and the next -- see semester-lib.sh's
# semester_recess_week, ported from cs1101s/course-materials' own
# equivalent row. HOLIDAYS_FILE/EMOJI_FILE are optional -- pass
# "/dev/null" (or any nonexistent path) for either to disable holiday-
# cancellation rendering entirely. KIND_EXTRA_LINKS_FILE (a
# KIND_ID|LABEL file) and EXTRA_LINKS_FILE (a SLOT_ID|URL file) are both
# optional -- see render_kind_cell's own comment; a course that doesn't
# want a second link per occurrence for any kind just never creates
# KIND_EXTRA_LINKS_FILE. OCCASION_LINKS_FILE (optional) is
# occasion_links' own WEEK|KIND_ID|... file, giving an occasion label up
# to 2 optional links -- see render_kind_cell's comment. GRADED_FILE
# (optional, one SLOT_ID per line) marks real occurrences as graded/
# important with a "🔴 " title prefix -- see render_kind_cell's comment
# and enrich-lib.sh's is_graded_slot. EXTRA_SLOTS_FILE (optional,
# WEEK|KIND_ID|SLOT_ID) lists extra per-week slots for a kind, grouped by
# matching title with whatever occurrence(s) that week+kind already has
# -- see render_kind_cell's comment and enrich-lib.sh's kind_extra_slots.
render_markdown_calendar() {
    local kinds_conf="$1" start_monday="$2" num_weeks="$3" recess_after="$4"
    local titles_file="$5" allowlist_file="$6" labels_file="$7" notes_file="$8"
    local base_url="$9" holidays_file="${10}" emoji_file="${11}"
    local kind_extra_links_file="${12:-}" extra_links_file="${13:-}"
    local occasion_links_file="${14:-}" graded_file="${15:-}"
    local extra_slots_file="${16:-}"

    local -a col_kind col_suffix col_header
    local ck cs ch
    while IFS='|' read -r ck cs ch; do
        col_kind+=("$ck")
        col_suffix+=("$cs")
        col_header+=("$ch")
    done < <(kind_columns "$kinds_conf")

    local header="| Week |"
    local sep="|------|"
    local i
    for ((i = 0; i < ${#col_kind[@]}; i++)); do
        header="${header} ${col_header[$i]} |"
        sep="${sep}------|"
    done
    header="${header} Notes |"
    sep="${sep}-------|"
    echo "$header"
    echo "$sep"

    local recess_dates recess_monday="" recess_friday=""
    recess_dates="$(semester_recess_week "$start_monday" "$recess_after")"
    if [ -n "$recess_dates" ]; then
        recess_monday="${recess_dates%%|*}"
        recess_friday="${recess_dates##*|}"
    fi

    local occ_file
    occ_file="$(mktemp)"
    while IFS='|' read -r teaching_week monday; do
        if [ -n "$recess_monday" ] && [ "$teaching_week" -eq "$((recess_after + 1))" ]; then
            local recess_row="| Recess |"
            for ((i = 0; i < ${#col_kind[@]}; i++)); do
                recess_row="${recess_row} - |"
            done
            recess_row="${recess_row} 🏖️ Recess Week - No classes (${recess_monday} - ${recess_friday}) |"
            echo "$recess_row"
        fi

        week_occurrences "$kinds_conf" "$monday" "$teaching_week" > "$occ_file"
        local row="| $teaching_week |"
        for ((i = 0; i < ${#col_kind[@]}; i++)); do
            local k="${col_kind[$i]}" s="${col_suffix[$i]}"
            local cell extra_label=""
            [ -n "$kind_extra_links_file" ] && extra_label="$(kind_extra_link_label "$k" "$kind_extra_links_file")"
            cell="$(render_kind_cell "$teaching_week" "$k" "$occ_file" "$titles_file" "$allowlist_file" "$labels_file" "$base_url" "$holidays_file" "$emoji_file" "$extra_label" "$extra_links_file" "$occasion_links_file" "$s" "$graded_file" "$extra_slots_file")"
            row="${row} ${cell} |"
        done
        local note maintainer_note holiday_note
        maintainer_note="$(week_note "$teaching_week" "$notes_file")"
        holiday_note="$(week_holiday_notes "$monday" "$holidays_file" "$emoji_file")"
        if [ -n "$maintainer_note" ] && [ -n "$holiday_note" ]; then
            note="${maintainer_note}; ${holiday_note}"
        else
            note="${maintainer_note}${holiday_note}"
        fi
        [ -z "$note" ] && note="-"
        row="${row} ${note} |"
        echo "$row"
    done < <(semester_weeks "$start_monday" "$num_weeks" "$recess_after")
    rm -f "$occ_file"
}
