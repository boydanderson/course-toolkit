#!/bin/bash
# Generic "Key Events" table -- one-off dated events with a specific
# time (a competition, an exam, a guest lecture, ...) that don't fall
# into the regular weekly session-kind grid render-markdown.sh/
# render-html.sh already handle. A course that doesn't need this simply
# never creates a KEY_EVENTS_FILE -- both render functions return empty
# output for a missing/empty file, which callers (e.g. cli.sh) treat as
# "nothing to append," same convention as every other optional file in
# this toolkit.

RENDER_EVENTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RENDER_EVENTS_DIR/date-lib.sh"

_html_escape_events() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# _sorted_events EVENTS_FILE -> comment/blank-stripped lines, sorted by
# DATE (field 1 -- ISO dates sort lexicographically = chronologically).
# Empty (not an error) if the file is missing or has no real rows.
_sorted_events() {
    local events_file="$1"
    [ -f "$events_file" ] || return 0
    grep -vE '^\s*#|^\s*$' "$events_file" 2>/dev/null | sort -t'|' -k1,1 || true
}

# render_key_events_html EVENTS_FILE [PALETTE] -> an HTML <table>, or
# empty output if the file's missing/empty. Format:
# DATE|START_TIME|END_TIME|NAME, one per line.
#
# PALETTE (optional): BORDER|HEADER_BG|ROW_ODD_BG|ROW_EVEN_BG -- border/
# header default to a plain #dddddd/#eeeeee if omitted; ROW_ODD_BG/
# ROW_EVEN_BG (also optional, independently) add alternating row
# striping when set, matching cs1101s/course-materials' own real Key
# Events table styling (its ke_parity alternation) -- both empty (the
# default, and every call before this session) reproduces exactly the
# original flat, unstriped table.
render_key_events_html() {
    local events_file="$1" palette="${2:-}"
    local rows
    rows="$(_sorted_events "$events_file")"
    [ -z "$rows" ] && return 0

    local -a p
    IFS='|' read -ra p <<< "$palette"
    local border="${p[0]:-#dddddd}" header_bg="${p[1]:-#eeeeee}"
    local row_odd="${p[2]:-}" row_even="${p[3]:-}"

    local cell_base="border:1px solid ${border};padding:6px 8px;text-align:left;vertical-align:top;"
    local th_style="${cell_base}background:${header_bg};"

    echo '<table style="border-collapse:collapse;width:100%;font-size:0.9rem;margin-top:1rem;">'
    printf '<thead><tr><th style="%s">Date</th><th style="%s">Time</th><th style="%s">Event</th></tr></thead><tbody>\n' \
        "$th_style" "$th_style" "$th_style"
    local date start end name i=0
    while IFS='|' read -r date start end name; do
        [ -z "$date" ] && continue
        local row_bg=""
        if [ $((i % 2)) -eq 1 ]; then row_bg="$row_even"; else row_bg="$row_odd"; fi
        local td_style="$cell_base"
        [ -n "$row_bg" ] && td_style="${cell_base}background:${row_bg};"
        printf '<tr><td style="%s">%s</td><td style="%s">%s&ndash;%s</td><td style="%s">%s</td></tr>\n' \
            "$td_style" "$date" "$td_style" "$start" "$end" \
            "$td_style" "$(echo "$name" | _html_escape_events)"
        i=$((i + 1))
    done <<< "$rows"
    echo '</tbody></table>'
}

# render_key_events_markdown EVENTS_FILE -> a markdown table, or empty
# output if the file's missing/empty. Includes a Day column (derived
# from DATE, not stored) -- matches cs1101s/course-materials' own real
# Key Events table, unlike the HTML version above which never had one.
render_key_events_markdown() {
    local events_file="$1"
    local rows
    rows="$(_sorted_events "$events_file")"
    [ -z "$rows" ] && return 0

    echo "| Date | Day | Time | Event |"
    echo "|------|-----|------|-------|"
    local date start end name
    while IFS='|' read -r date start end name; do
        [ -z "$date" ] && continue
        echo "| $date | $(day_of_week_name "$date") | $start-$end | $name |"
    done <<< "$rows"
}
