#!/bin/bash
# Generic HTML calendar table generator -- the Canvas-release-page
# equivalent of render-markdown.sh, same session-kind-column
# generalization, replacing cs1101s/course-materials' generate-canvas-
# html.sh (which hardcoded exactly Week/Studio/Wed/Thu/Fri/Notes and a
# few hundred lines of matching inline CSS).
#
# Deliberately NOT attempting full visual parity with that original --
# styling is a course-specific polish question (brand colors, current-
# week highlighting, etc.) revisited when cs1101s/course-materials
# actually migrates onto this toolkit (Stage 4-5's baseline-diff is
# where such details get reconciled), not something the generic core
# needs to bake in now. This produces a plain, correctly-structured
# table: a real starting point, not a finished visual design.
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

# _html_variant_links KIND_ID SLOT_ID VARIANTS BASE_URL RELEASED -> HTML
# <a>/<span> links, "&middot;"-joined. Mirrors render-markdown.sh's
# _md_variant_links exactly, just HTML output instead of markdown.
_html_variant_links() {
    local kind_id="$1" slot_id="$2" variants="$3" base_url="$4" released="$5"
    local -a vlist
    IFS=',' read -ra vlist <<< "$variants"
    [ "$variants" = "none" ] && vlist=("")
    local parts=() v label fname
    for v in "${vlist[@]}"; do
        if [ -z "$v" ]; then
            label="Sheet"; fname="${kind_id}-${slot_id}.pdf"
        else
            label="$(_capitalize "$v")"; fname="${kind_id}-${slot_id}.${v}.pdf"
        fi
        if [ "$released" = "1" ]; then
            parts+=("<a href=\"${base_url}/${fname}\">${label}</a>")
        else
            parts+=("<span style=\"color:#888888;\">${label}</span>")
        fi
    done
    local out="${parts[0]}" i
    for ((i = 1; i < ${#parts[@]}; i++)); do
        out="${out} &middot; ${parts[$i]}"
    done
    echo "$out"
}

# S_CANCELLED: a holiday-cancelled occurrence's style -- bold warning red,
# distinct from S_PENDING-style grey (an unreleased-but-coming item) and
# any assessment-callout color a course's own styling might add on top.
_S_CANCELLED='font-weight:600;color:#c0392b;'

# render_kind_cell_html -- same signature/semantics as render-markdown.sh's
# render_kind_cell (see that function's header comment for the
# holiday-cancellation behavior), HTML output.
render_kind_cell_html() {
    local week="$1" kind_id="$2" occurrences_file="$3" titles_file="$4"
    local allowlist_file="$5" labels_file="$6" base_url="$7"
    local holidays_file="$8" emoji_file="$9"
    local rows
    rows=$(awk -F'|' -v k="$kind_id" '$1==k' "$occurrences_file")
    if [ -z "$rows" ]; then
        local label
        label="$(slot_kind_label "$week" "$kind_id" "$labels_file")"
        if [ -n "$label" ]; then
            printf '<div style="font-weight:600;">%s</div>' "$(echo "$label" | _html_escape)"
        else
            echo ""
        fi
        return 0
    fi
    local cell_html="" line
    while IFS='|' read -r rkind rlabel rslot rdate rweekday rsuffix rvariants; do
        [ -z "$rkind" ] && continue
        local holiday_name
        holiday_name="$(is_holiday "$rdate" "$holidays_file")" && {
            local emoji prefix=""
            emoji="$(holiday_emoji "$holiday_name" "$emoji_file")"
            [ -n "$emoji" ] && prefix="${emoji} "
            cell_html="${cell_html}<div style=\"${_S_CANCELLED}\">No $(echo "$rlabel" | _html_escape) (${prefix}$(echo "$holiday_name" | _html_escape))</div>"
            continue
        }
        local title released links
        title="$(slot_title "$rslot" "$titles_file")"
        title="$(compose_slot_title "$rslot" "$title")"
        if is_slot_released "$rslot" "$allowlist_file"; then released=1; else released=0; fi
        links="$(_html_variant_links "$rkind" "$rslot" "$rvariants" "$base_url" "$released")"
        cell_html="${cell_html}<div style=\"font-weight:600;\">$(echo "$title" | _html_escape)</div><div style=\"margin-top:2px;font-size:0.85rem;\">${links}</div>"
    done <<< "$rows"
    echo "$cell_html"
}

# render_html_calendar -- same signature as render-markdown.sh's
# render_markdown_calendar, HTML `<table>` output.
render_html_calendar() {
    local kinds_conf="$1" start_monday="$2" num_weeks="$3" recess_after="$4"
    local titles_file="$5" allowlist_file="$6" labels_file="$7" notes_file="$8"
    local base_url="$9" holidays_file="${10}" emoji_file="${11}"

    local -a kind_ids
    while IFS= read -r k; do kind_ids+=("$k"); done < <(session_kind_ids "$kinds_conf")

    local th_style='border:1px solid #dddddd;padding:6px 8px;background:#eeeeee;text-align:left;'
    local td_style='border:1px solid #dddddd;padding:6px 8px;vertical-align:top;'

    echo '<table style="border-collapse:collapse;width:100%;font-size:0.9rem;">'
    echo '<thead><tr>'
    printf '<th style="%s">Week</th>' "$th_style"
    local k
    for k in "${kind_ids[@]}"; do
        printf "<th style=\"%s\">%s</th>" "$th_style" "$(_capitalize "$k")"
    done
    printf '<th style="%s">Notes</th>' "$th_style"
    echo '</tr></thead><tbody>'

    local occ_file
    occ_file="$(mktemp)"
    while IFS='|' read -r teaching_week monday; do
        echo '<tr>'
        printf '<td style="%sfont-weight:bold;">%s</td>' "$td_style" "$teaching_week"
        week_occurrences "$kinds_conf" "$monday" "$teaching_week" > "$occ_file"
        for k in "${kind_ids[@]}"; do
            local cell
            cell="$(render_kind_cell_html "$teaching_week" "$k" "$occ_file" "$titles_file" "$allowlist_file" "$labels_file" "$base_url" "$holidays_file" "$emoji_file")"
            printf '<td style="%s">%s</td>' "$td_style" "$cell"
        done
        local note
        note="$(week_note "$teaching_week" "$notes_file")"
        [ -z "$note" ] && note="-"
        printf '<td style="%sfont-size:0.85rem;color:#555555;">%s</td>' "$td_style" "$(echo "$note" | _html_escape)"
        echo '</tr>'
    done < <(semester_weeks "$start_monday" "$num_weeks" "$recess_after")
    rm -f "$occ_file"

    echo '</tbody></table>'
}
