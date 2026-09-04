#!/bin/bash
# Generic HTML calendar table generator -- the Canvas-release-page
# equivalent of render-markdown.sh, same session-kind-column
# generalization, replacing cs1101s/course-materials' generate-canvas-
# html.sh (which hardcoded exactly Week/Studio/Wed/Thu/Fri/Notes and a
# few hundred lines of matching inline CSS).
#
# Full visual parity with that original was reconciled once
# cs1101s/course-materials actually migrated onto this toolkit for
# real: every remaining styling gap (occasion-label color, a distinct
# current-week week-cell shade + "This week" marker, a week-date
# sub-line, table/th/week-cell CSS details) became either a new
# _calendar_palette field (still empty-by-default, so a course that
# never sets it is completely unaffected) or a small baked-in default
# fix. Brand colors/current-week highlighting/row banding stay entirely
# opt-in per course via config/course.mk's CALENDAR_* overrides.
#
# NOTE: this whole "gated PDF release table" model is itself only proven
# to fit courses that actually distribute versioned, allow-listed PDF
# artifacts (confirmed for CS1101S; looks plausible for CG2111A's
# Typst-built student/instructor PDF pairs). It does NOT fit every
# course's real distribution strategy -- e.g. nus-cs2030s's actual
# public site is a continuously-published mkdocs/reveal.js site with no
# per-item release gate and no week-numbered artifacts at all. Whether
# this renderer is the right tool for a course like that is an open
# question, not something this file resolves.

RENDER_HTML_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RENDER_HTML_DIR/schedule-lib.sh"
source "$RENDER_HTML_DIR/semester-lib.sh"
source "$RENDER_HTML_DIR/enrich-lib.sh"

_html_escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# _format_date_short YYYY-MM-DD -> "10 Aug" -- same GNU/BSD `date`
# branching used throughout this toolkit (e.g. semester-lib.sh), ported
# verbatim from cs1101s/course-materials' own generate-canvas-html.sh
# (its local `format_date_short`) for `render_html_calendar`'s
# SHOW_WEEK_DATES week-date sub-line.
_format_date_short() {
    local d="$1"
    if date -d "$d" '+%d %b' >/dev/null 2>&1; then
        date -d "$d" '+%d %b'
    else
        date -j -f '%Y-%m-%d' "$d" '+%d %b'
    fi
}

# _calendar_palette -- the calendar's colors, generic defaults out of
# the box, overridable per-course via config/course.mk (see cli.sh's
# CALENDAR_* lookups, and README's "Customizing the calendar's colors").
# PALETTE field order: border|header_bg|link|pending|cancelled|notes|
# current_bg|current_border|row_odd_bg|row_even_bg|occasion_color|
# current_week_bg|week_bg. `link` and fields 7-13 (current-week
# highlight, row banding, occasion color, week-cell backgrounds) default
# to "" (no override -- a course gets no current-week highlight/banding/
# occasion color and no distinct week-cell background unless it opts in,
# so omitting the whole palette still reproduces exactly today's output);
# every other field has a real color default so a course overriding just
# one doesn't need to respecify the rest. `current_week_bg` (12th) falls
# back to `current_bg` (7th) when unset, not to empty -- a course that
# only ever set `current_bg` (every consumer before this field existed)
# keeps applying that one shade uniformly to the week cell too, exactly
# as before; a course that wants the week cell visually distinct from
# the data cells (e.g. a darker accent) sets `current_week_bg` as well.
#
# Every renderer function below takes PALETTE as one opaque trailing
# string (not thirteen separate parameters) precisely so a direct
# unit-test call site (see render-html.test.sh) or an old caller can
# omit it entirely and get the defaults, and so a new color doesn't mean
# touching every function's signature again.
#
# Literal defaults, not a second "defaults" array indexed alongside
# PALETTE's own: `read -ra` silently drops trailing empty fields (a
# palette ending in several `||`s parses shorter than field-count would
# suggest), and `${p[9]:-${d[9]}}` blows up under `set -u` (cli.sh runs
# this under `set -euo pipefail`) whenever `d` itself doesn't have that
# many elements -- confirmed for real. `${p[N]:-LITERAL}` has no such
# problem: `:-` only needs to guard the variable being tested, not a
# second variable reference used as the fallback.
_calendar_palette() {
    local palette="${1:-}"
    local -a p
    IFS='|' read -ra p <<< "$palette"
    CAL_BORDER="${p[0]:-#dddddd}"
    CAL_HEADER_BG="${p[1]:-#eeeeee}"
    CAL_LINK="${p[2]:-}"
    CAL_PENDING="${p[3]:-#888888}"
    CAL_CANCELLED="${p[4]:-#c0392b}"
    CAL_NOTES="${p[5]:-#555555}"
    CAL_CURRENT_BG="${p[6]:-}"
    CAL_CURRENT_BORDER="${p[7]:-}"
    CAL_ROW_ODD_BG="${p[8]:-}"
    CAL_ROW_EVEN_BG="${p[9]:-}"
    CAL_OCCASION_COLOR="${p[10]:-}"
    CAL_CURRENT_WEEK_BG="${p[11]:-$CAL_CURRENT_BG}"
    CAL_WEEK_BG="${p[12]:-}"
}

# _html_variant_links KIND_ID SLOT_ID VARIANTS BASE_URL RELEASED [PALETTE]
# [EXTRA_LINK_LABEL] [EXTRA_LINK_URL] -> HTML <a>/<span> links,
# "&middot;"-joined. Mirrors render-markdown.sh's _md_variant_links
# exactly, just HTML output instead of markdown. EXTRA_LINK_LABEL/_URL
# (both optional -- e.g. "Recording"/a Panopto URL) append one more link
# after the normal variant links, live if EXTRA_LINK_URL is non-empty,
# pending/greyed otherwise -- same always-shown convention as every
# other link here, so a course that wants a second, independently-gated
# link per occurrence (a recording goes up on its own schedule, separate
# from the PDF release) doesn't need its own cell-rendering logic.
_html_variant_links() {
    local kind_id="$1" slot_id="$2" variants="$3" base_url="$4" released="$5"
    _calendar_palette "${6:-}"
    local extra_link_label="${7:-}" extra_link_url="${8:-}"
    local -a vlist
    IFS=',' read -ra vlist <<< "$variants"
    [ "$variants" = "none" ] && vlist=("")
    local parts=() v label fname link_style=""
    [ -n "$CAL_LINK" ] && link_style=" style=\"color:${CAL_LINK};\""
    for v in "${vlist[@]}"; do
        if [ -z "$v" ]; then
            label="Sheet"; fname="${kind_id}-${slot_id}.pdf"
        else
            label="$(_capitalize "$v")"; fname="${kind_id}-${slot_id}.${v}.pdf"
        fi
        if [ "$released" = "1" ]; then
            parts+=("<a href=\"${base_url}/${fname}\"${link_style}>${label}</a>")
        else
            parts+=("<span style=\"color:${CAL_PENDING};\">${label}</span>")
        fi
    done
    if [ -n "$extra_link_label" ]; then
        if [ -n "$extra_link_url" ]; then
            parts+=("<a href=\"${extra_link_url}\"${link_style}>${extra_link_label}</a>")
        else
            parts+=("<span style=\"color:${CAL_PENDING};\">${extra_link_label}</span>")
        fi
    fi
    local out="${parts[0]}" i
    for ((i = 1; i < ${#parts[@]}; i++)); do
        out="${out} &middot; ${parts[$i]}"
    done
    echo "$out"
}

# _occasion_links_html RAW -> HTML <a>/<span> links for occasion_links'
# raw "LABEL1|URL1|LABEL2|URL2" return value, "&middot;"-joined, empty
# if RAW has no non-empty label at all. Same live-vs-pending convention
# as _html_variant_links.
_occasion_links_html() {
    local raw="$1"
    local -a f
    IFS='|' read -ra f <<< "$raw"
    local l1_label="${f[0]:-}" l1_url="${f[1]:-}" l2_label="${f[2]:-}" l2_url="${f[3]:-}"
    local link_style=""
    [ -n "$CAL_LINK" ] && link_style=" style=\"color:${CAL_LINK};\""
    local parts=()
    if [ -n "$l1_label" ]; then
        if [ -n "$l1_url" ]; then
            parts+=("<a href=\"${l1_url}\"${link_style}>${l1_label}</a>")
        else
            parts+=("<span style=\"color:${CAL_PENDING};\">${l1_label}</span>")
        fi
    fi
    if [ -n "$l2_label" ]; then
        if [ -n "$l2_url" ]; then
            parts+=("<a href=\"${l2_url}\"${link_style}>${l2_label}</a>")
        else
            parts+=("<span style=\"color:${CAL_PENDING};\">${l2_label}</span>")
        fi
    fi
    [ "${#parts[@]}" -eq 0 ] && return 0
    local out="${parts[0]}" i
    for ((i = 1; i < ${#parts[@]}; i++)); do
        out="${out} &middot; ${parts[$i]}"
    done
    echo "$out"
}

# render_kind_cell_html -- same signature/semantics as render-markdown.sh's
# render_kind_cell (see that function's header comment for the
# holiday-cancellation and SUFFIX_FILTER behavior), HTML output. PALETTE
# (10th, optional) is _calendar_palette's opaque string; see that
# function's comment. EXTRA_LINK_LABEL (11th, optional -- e.g.
# "Recording") and EXTRA_LINK_FILE (12th, a SLOT_ID|URL file) add a
# second, independently gated link to every occurrence in this kind's
# cell -- see _html_variant_links' own comment. Leave EXTRA_LINK_LABEL
# empty (the default) for a kind that doesn't have one.
# OCCASION_LINKS_FILE (13th, optional) is occasion_links' own
# WEEK|KIND_ID|... file. SUFFIX_FILTER (14th, optional) restricts rows
# to just that one weekly occurrence, for a kind split into one column
# per suffix (see render_html_calendar) -- with no filter (the merged-
# column case), an occasion label (slot_kind_label) is checked
# UNCONDITIONALLY, not just when this kind has zero occurrences this
# week (a real gap: a kind with several occurrences, like two lectures/
# week, couldn't previously flag that just ONE of them was replaced by
# e.g. an assessment -- the excluded occurrence simply vanished with no
# explanation), and the label is prepended to whatever real occurrences
# also rendered. With a filter (the split-column case), each column
# represents exactly one occurrence, so "only when nothing scheduled at
# this specific slot" is both sufficient and correct. The label lookup
# also tries a suffix-qualified key first ("${KIND_ID}-${SUFFIX}", e.g.
# "studio-A" -- not a real session-kind id, just this lookup's own
# convention) with a filter, falling back to the plain KIND_ID if no
# suffix-specific row exists -- see render-markdown.sh's render_kind_cell
# for the full rationale (the same fix, mirrored here). GRADED_FILE
# (15th, optional, one SLOT_ID per line) marks a real occurrence as
# graded/important with a "🔴 " title prefix -- see enrich-lib.sh's
# is_graded_slot. EXTRA_SLOTS_FILE (16th, optional, WEEK|KIND_ID|SLOT_ID
# -- see enrich-lib.sh's kind_extra_slots) lists extra slot IDs sharing
# this week+kind without being a distinct weekly occurrence of their own
# (e.g. a studio's "-in-class" supplement) -- each gets its own stacked
# title+links block appended after the regular occurrence(s), inheriting
# the LAST processed row's VARIANTS since it declares none of its own.
# Unlike the markdown renderer's render_kind_cell, extra slots here are
# NOT grouped/deduped by matching title -- real course-materials Canvas
# rendering (render_studio_cell) already shows each studio number as its
# own independent block, no merging, so this mirrors that directly
# rather than inventing new HTML-side grouping. If any regular occurrence
# this week+kind was holiday-cancelled, extra slots are skipped entirely
# (they ride along with the session that didn't happen). A course that
# never creates EXTRA_SLOTS_FILE (or has none for this week+kind) gets
# today's exact behavior, unchanged. EXTRA_NOTE_FILE (17th, optional,
# SLOT_ID|HTML -- see enrich-lib.sh's extra_note_for_slot) renders one
# more line of arbitrary pre-rendered HTML under a regular occurrence's
# title+links, e.g. cs1101s/course-materials' own SICPy §-section reading
# list (the extraction stays entirely course-owned; this just generalizes
# the RENDERING SLOT it occupies) -- not applied to extra slots (see
# EXTRA_SLOTS_FILE above), since a supplementary linked file doesn't
# generally carry its own separate reading list.
#
# OCCURRENCES_FILE's own 9th column, CONFLICT_HOLIDAY (schedule-lib.sh's
# week_occurrences), overrides the holiday-cancellation rendering above
# when non-empty for a row -- a collision the maintainer has already
# reviewed and deliberately decided to hold anyway (session-kinds.conf's
# HOLIDAY_CONFLICT_WEEKS field) renders normally (title + links, exactly
# as an uncancelled occurrence) with a "⚠️ " title prefix instead of
# "No <label> (...)", and does NOT set any_cancelled -- so, unlike a real
# cancellation, an extra slot sharing this week+kind still renders too.
render_kind_cell_html() {
    local week="$1" kind_id="$2" occurrences_file="$3" titles_file="$4"
    local allowlist_file="$5" labels_file="$6" base_url="$7"
    local holidays_file="$8" emoji_file="$9"
    local palette="${10:-}"
    local extra_link_label="${11:-}" extra_link_file="${12:-}"
    local occasion_links_file="${13:-}" suffix_filter="${14:-}"
    local graded_file="${15:-}" extra_slots_file="${16:-}" extra_note_file="${17:-}"
    _calendar_palette "$palette"
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

    local cell_html=""
    # label_key: see render-markdown.sh's render_kind_cell for the full
    # rationale -- a suffix-qualified key first, falling back to the
    # plain kind_id, so two suffixes excluded the same week can carry
    # two different labels.
    local label_key="$kind_id" occ_label
    [ -n "$suffix_filter" ] && label_key="${kind_id}-${suffix_filter}"
    occ_label="$(slot_kind_label "$week" "$label_key" "$labels_file")"
    if [ -z "$occ_label" ] && [ -n "$suffix_filter" ]; then
        label_key="$kind_id"
        occ_label="$(slot_kind_label "$week" "$label_key" "$labels_file")"
    fi
    if [ -n "$occ_label" ] && { [ -z "$suffix_filter" ] || [ -z "$rows" ]; }; then
        local occ_style="font-weight:600;"
        [ -n "$CAL_OCCASION_COLOR" ] && occ_style="${occ_style}color:${CAL_OCCASION_COLOR};"
        cell_html="<div style=\"${occ_style}\">$(echo "$occ_label" | _html_escape)</div>"
        local occ_raw occ_links_html
        occ_raw="$(occasion_links "$week" "$label_key" "$occasion_links_file")"
        if [ -n "$occ_raw" ]; then
            occ_links_html="$(_occasion_links_html "$occ_raw")"
            [ -n "$occ_links_html" ] && cell_html="${cell_html}<div style=\"margin-top:2px;font-size:0.85rem;\">${occ_links_html}</div>"
        fi
    fi

    if [ -z "$rows" ]; then
        echo "$cell_html"
        return 0
    fi

    local cancelled_style="font-weight:600;color:${CAL_CANCELLED};"
    local primary_variants="" any_cancelled=0
    while IFS='|' read -r rkind rlabel rslot rdate rweekday rsuffix rvariants rcancel_extra rconflict; do
        [ -z "$rkind" ] && continue
        primary_variants="$rvariants"
        if [ -n "$rconflict" ]; then
            local title released links extra_url=""
            title="$(slot_title "$rslot" "$titles_file")"
            title="$(compose_slot_title "$rslot" "$title")"
            if [ -n "$graded_file" ] && is_graded_slot "$rslot" "$graded_file"; then
                title="🔴 ${title}"
            fi
            if is_slot_released "$rslot" "$allowlist_file"; then released=1; else released=0; fi
            [ -n "$extra_link_label" ] && extra_url="$(extra_link_for_slot "$rslot" "$extra_link_file")"
            links="$(_html_variant_links "$rkind" "$rslot" "$rvariants" "$base_url" "$released" "$palette" "$extra_link_label" "$extra_url")"
            cell_html="${cell_html}<div style=\"font-weight:600;\">⚠️ $(echo "$title" | _html_escape)</div><div style=\"margin-top:2px;font-size:0.85rem;\">${links}</div>"
            if [ -n "$extra_note_file" ]; then
                local extra_note
                extra_note="$(extra_note_for_slot "$rslot" "$extra_note_file")"
                [ -n "$extra_note" ] && cell_html="${cell_html}<div style=\"margin-top:2px;font-size:0.85rem;\">${extra_note}</div>"
            fi
            continue
        fi
        local holiday_name
        holiday_name="$(occurrence_holiday "$rdate" "$rcancel_extra" "$holidays_file")" && {
            local emoji prefix=""
            emoji="$(holiday_emoji "$holiday_name" "$emoji_file")"
            [ -n "$emoji" ] && prefix="${emoji} "
            cell_html="${cell_html}<div style=\"${cancelled_style}\">No $(echo "$rlabel" | _html_escape) (${prefix}$(echo "$holiday_name" | _html_escape))</div>"
            any_cancelled=1
            continue
        }
        local title released links extra_url=""
        title="$(slot_title "$rslot" "$titles_file")"
        title="$(compose_slot_title "$rslot" "$title")"
        if [ -n "$graded_file" ] && is_graded_slot "$rslot" "$graded_file"; then
            title="🔴 ${title}"
        fi
        if is_slot_released "$rslot" "$allowlist_file"; then released=1; else released=0; fi
        [ -n "$extra_link_label" ] && extra_url="$(extra_link_for_slot "$rslot" "$extra_link_file")"
        links="$(_html_variant_links "$rkind" "$rslot" "$rvariants" "$base_url" "$released" "$palette" "$extra_link_label" "$extra_url")"
        cell_html="${cell_html}<div style=\"font-weight:600;\">$(echo "$title" | _html_escape)</div><div style=\"margin-top:2px;font-size:0.85rem;\">${links}</div>"
        if [ -n "$extra_note_file" ]; then
            local extra_note
            extra_note="$(extra_note_for_slot "$rslot" "$extra_note_file")"
            [ -n "$extra_note" ] && cell_html="${cell_html}<div style=\"margin-top:2px;font-size:0.85rem;\">${extra_note}</div>"
        fi
    done <<< "$rows"

    if [ "$any_cancelled" -eq 0 ]; then
        local es_i
        for ((es_i = 0; es_i < ${#extra_slot_ids[@]}; es_i++)); do
            local es="${extra_slot_ids[$es_i]}"
            local title released links extra_url=""
            title="$(slot_title "$es" "$titles_file")"
            title="$(compose_slot_title "$es" "$title")"
            if [ -n "$graded_file" ] && is_graded_slot "$es" "$graded_file"; then
                title="🔴 ${title}"
            fi
            if is_slot_released "$es" "$allowlist_file"; then released=1; else released=0; fi
            [ -n "$extra_link_label" ] && extra_url="$(extra_link_for_slot "$es" "$extra_link_file")"
            links="$(_html_variant_links "$kind_id" "$es" "$primary_variants" "$base_url" "$released" "$palette" "$extra_link_label" "$extra_url")"
            cell_html="${cell_html}<div style=\"font-weight:600;\">$(echo "$title" | _html_escape)</div><div style=\"margin-top:2px;font-size:0.85rem;\">${links}</div>"
        done
    fi
    echo "$cell_html"
}

# render_html_calendar -- same signature as render-markdown.sh's
# render_markdown_calendar, HTML `<table>` output, including the same
# "Recess" row (all dashes, cancelled-styled note) inserted when
# RECESS_AFTER_WEEK > 0 -- see that function's own comment and
# semester-lib.sh's semester_recess_week. Not counted toward row_index
# (so real teaching weeks' odd/even banding stays undisturbed by
# whether a recess row was inserted) and not current-week-highlighted
# (it's never "this week" in the teaching-week sense). PALETTE (12th,
# optional) is _calendar_palette's opaque string; see that function's
# comment. TODAY (13th, optional, YYYY-MM-DD) drives current-week
# highlighting -- defaults to the live date (SGT) if omitted, or pass a
# fixed date for deterministic tests. Current-week highlighting and row
# banding are both no-ops unless CAL_CURRENT_BG/CAL_ROW_ODD_BG/etc. are
# actually set in PALETTE (see _DEFAULT_PALETTE's comment).
# KIND_EXTRA_LINKS_FILE (14th, optional, a KIND_ID|LABEL file) and
# EXTRA_LINKS_FILE (15th, optional, a SLOT_ID|URL file) add a second,
# independently-gated link to every occurrence of whichever kinds are
# listed -- see render_kind_cell_html's own comment. A course that
# doesn't want this for any kind just never creates
# KIND_EXTRA_LINKS_FILE. OCCASION_LINKS_FILE (16th, optional) is
# occasion_links' own WEEK|KIND_ID|... file -- see render_kind_cell_html's
# comment for how an occasion label (e.g. an assessment replacing one of
# several occurrences) now always shows, with or without occurrences,
# and this file gives it up to 2 optional links. GRADED_FILE (17th,
# optional, one SLOT_ID per line) marks real occurrences as graded/
# important with a "🔴 " title prefix -- see render_kind_cell_html's
# comment and enrich-lib.sh's is_graded_slot. EXTRA_SLOTS_FILE (18th,
# optional, WEEK|KIND_ID|SLOT_ID) lists extra per-week slots for a kind,
# each its own stacked title+links block (no grouping, unlike the
# markdown renderer -- see render_kind_cell_html's own comment) --
# enrich-lib.sh's kind_extra_slots. EXTRA_NOTE_FILE (19th, optional,
# SLOT_ID|HTML) renders one more line under a regular occurrence's
# title+links -- see render_kind_cell_html's own comment and
# enrich-lib.sh's extra_note_for_slot. SPECIAL_DATES_FILE (20th,
# optional, DATE|NAME -- same shape as HOLIDAYS_FILE) and
# KEY_EVENTS_FILE (21st, optional, DATE|START_TIME|END_TIME|NAME) each
# add their own category to the Notes column, alongside the maintainer
# note and holiday notes -- mirrors render_markdown_calendar's own
# equivalent params; see enrich-lib.sh's week_special_date_notes/
# week_key_event_notes. SHOW_WEEK_DATES (22nd, optional, any non-empty
# value) appends a "10 Aug – 14 Aug" sub-line under every week's number
# (every week, not just the current one) -- off by default, so a course
# that doesn't set it sees no change.
render_html_calendar() {
    local kinds_conf="$1" start_monday="$2" num_weeks="$3" recess_after="$4"
    local titles_file="$5" allowlist_file="$6" labels_file="$7" notes_file="$8"
    local base_url="$9" holidays_file="${10}" emoji_file="${11}" palette="${12:-}"
    local today="${13:-}"
    local kind_extra_links_file="${14:-}" extra_links_file="${15:-}"
    local occasion_links_file="${16:-}" graded_file="${17:-}"
    local extra_slots_file="${18:-}" extra_note_file="${19:-}"
    local special_dates_file="${20:-}" key_events_file="${21:-}" show_week_dates="${22:-}"
    [ -z "$today" ] && today="$(sgt_date '+%Y-%m-%d')"
    _calendar_palette "$palette"

    local -a col_kind col_suffix col_header
    local ck cs ch
    while IFS='|' read -r ck cs ch; do
        col_kind+=("$ck")
        col_suffix+=("$cs")
        col_header+=("$ch")
    done < <(kind_columns "$kinds_conf")

    local th_style="border:1px solid ${CAL_BORDER};padding:6px 8px;background:${CAL_HEADER_BG};text-align:left;vertical-align:top;"
    local td_style="border:1px solid ${CAL_BORDER};padding:6px 8px;vertical-align:top;"

    echo '<table style="border-collapse:collapse;width:100%;font-size:0.9rem;margin-top:1rem;">'
    echo '<thead><tr>'
    printf '<th style="%s">Week</th>' "$th_style"
    local i
    for ((i = 0; i < ${#col_kind[@]}; i++)); do
        printf "<th style=\"%s\">%s</th>" "$th_style" "$(echo "${col_header[$i]}" | _html_escape)"
    done
    printf '<th style="%s">Notes</th>' "$th_style"
    echo '</tr></thead><tbody>'

    local recess_dates recess_monday="" recess_friday=""
    recess_dates="$(semester_recess_week "$start_monday" "$recess_after")"
    if [ -n "$recess_dates" ]; then
        recess_monday="${recess_dates%%|*}"
        recess_friday="${recess_dates##*|}"
    fi

    local occ_file row_index=0
    occ_file="$(mktemp)"
    while IFS='|' read -r teaching_week monday; do
        if [ -n "$recess_monday" ] && [ "$teaching_week" -eq "$((recess_after + 1))" ]; then
            local recess_td="${td_style}color:${CAL_CANCELLED};"
            echo '<tr>'
            printf '<td style="%sfont-weight:bold;">Recess</td>' "$td_style"
            for ((i = 0; i < ${#col_kind[@]}; i++)); do
                printf '<td style="%s">-</td>' "$td_style"
            done
            printf '<td style="%s">🏖️ Recess Week - No classes (%s - %s)</td>' \
                "$recess_td" "$recess_monday" "$recess_friday"
            echo '</tr>'
        fi

        row_index=$((row_index + 1))

        # "Today falls inside this teaching week's Monday..Sunday span"
        # -- same comparison CS1101S's own legacy current_week() used.
        local is_current=0
        if [[ ! "$today" < "$monday" ]] && [[ "$today" < "$(add_days "$monday" 7)" ]]; then
            is_current=1
        fi

        local row_bg=""
        if [ "$is_current" = 1 ] && [ -n "$CAL_CURRENT_BG" ]; then
            row_bg="$CAL_CURRENT_BG"
        elif [ $((row_index % 2)) -eq 1 ] && [ -n "$CAL_ROW_ODD_BG" ]; then
            row_bg="$CAL_ROW_ODD_BG"
        elif [ $((row_index % 2)) -eq 0 ] && [ -n "$CAL_ROW_EVEN_BG" ]; then
            row_bg="$CAL_ROW_EVEN_BG"
        fi
        local row_style="$td_style"
        [ -n "$row_bg" ] && row_style="${td_style}background:${row_bg};"

        # week_bg: the WEEK-NUMBER cell's own background, independent of
        # row_bg above (the data cells') -- CAL_CURRENT_WEEK_BG already
        # falls back to CAL_CURRENT_BG in _calendar_palette when unset,
        # so a course that only ever set CAL_CURRENT_BG keeps applying
        # that one shade uniformly, unchanged from before this field
        # existed; CAL_WEEK_BG (non-current weeks) is independent of row
        # banding, since a banded week-number column reads oddly next to
        # its own always-distinct week-cell background.
        local week_bg=""
        if [ "$is_current" = 1 ] && [ -n "$CAL_CURRENT_WEEK_BG" ]; then
            week_bg="$CAL_CURRENT_WEEK_BG"
        elif [ "$is_current" != 1 ] && [ -n "$CAL_WEEK_BG" ]; then
            week_bg="$CAL_WEEK_BG"
        fi

        local week_style="${td_style}text-align:right;font-weight:bold;"
        if [ "$is_current" = 1 ] && [ -n "$CAL_CURRENT_BORDER" ]; then
            week_style="border:1px solid ${CAL_BORDER};border-left:4px solid ${CAL_CURRENT_BORDER};padding:6px 8px;text-align:right;vertical-align:top;font-weight:bold;"
        fi
        [ -n "$week_bg" ] && week_style="${week_style}background:${week_bg};"

        # "This week" marker: gated on the course having opted into
        # current-week highlighting at all (CAL_CURRENT_BG or
        # CAL_CURRENT_BORDER set) -- a course that never sets either
        # keeps getting the plain week number, unchanged.
        local week_label="$teaching_week"
        if [ "$is_current" = 1 ] && { [ -n "$CAL_CURRENT_BG" ] || [ -n "$CAL_CURRENT_BORDER" ]; }; then
            week_label="${teaching_week} &#128205;<div style=\"font-weight:normal;font-size:0.7rem;color:#99106b;\">This week</div>"
        fi
        local week_dates_html=""
        if [ -n "$show_week_dates" ]; then
            local week_friday
            week_friday="$(add_days "$monday" 4)"
            week_dates_html="<div style=\"font-weight:normal;font-size:0.75rem;color:#666666;\">$(_format_date_short "$monday") &ndash; $(_format_date_short "$week_friday")</div>"
        fi

        echo '<tr>'
        printf '<td style="%s">%s%s</td>' "$week_style" "$week_label" "$week_dates_html"
        week_occurrences "$kinds_conf" "$monday" "$teaching_week" "$holidays_file" "$start_monday" "$recess_after" > "$occ_file"
        for ((i = 0; i < ${#col_kind[@]}; i++)); do
            local k="${col_kind[$i]}" s="${col_suffix[$i]}"
            local cell extra_label=""
            [ -n "$kind_extra_links_file" ] && extra_label="$(kind_extra_link_label "$k" "$kind_extra_links_file")"
            cell="$(render_kind_cell_html "$teaching_week" "$k" "$occ_file" "$titles_file" "$allowlist_file" "$labels_file" "$base_url" "$holidays_file" "$emoji_file" "$palette" "$extra_label" "$extra_links_file" "$occasion_links_file" "$s" "$graded_file" "$extra_slots_file" "$extra_note_file")"
            printf '<td style="%s">%s</td>' "$row_style" "$cell"
        done
        local -a note_parts=()
        local maintainer_note holiday_note special_note key_event_note
        maintainer_note="$(week_note "$teaching_week" "$notes_file")"
        [ -n "$maintainer_note" ] && note_parts+=("$maintainer_note")
        holiday_note="$(week_holiday_notes "$monday" "$holidays_file" "$emoji_file")"
        [ -n "$holiday_note" ] && note_parts+=("$holiday_note")
        if [ -n "$special_dates_file" ]; then
            special_note="$(week_special_date_notes "$monday" "$special_dates_file")"
            [ -n "$special_note" ] && note_parts+=("$special_note")
        fi
        if [ -n "$key_events_file" ]; then
            key_event_note="$(week_key_event_notes "$monday" "$key_events_file")"
            [ -n "$key_event_note" ] && note_parts+=("$key_event_note")
        fi
        local note=""
        if [ ${#note_parts[@]} -gt 0 ]; then
            note="${note_parts[0]}"
            local ni
            for ((ni = 1; ni < ${#note_parts[@]}; ni++)); do
                note="${note}; ${note_parts[$ni]}"
            done
        fi
        [ -z "$note" ] && note="-"
        printf '<td style="%sfont-size:0.85rem;color:%s;">%s</td>' "$row_style" "$CAL_NOTES" "$(echo "$note" | _html_escape)"
        echo '</tr>'
    done < <(semester_weeks "$start_monday" "$num_weeks" "$recess_after")
    rm -f "$occ_file"

    echo '</tbody></table>'
}
