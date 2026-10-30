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
source "$RENDER_EVENTS_DIR/html-lib.sh"

# _sorted_events EVENTS_FILE -> comment/blank-stripped lines, sorted by
# DATE (field 1 -- ISO dates sort lexicographically = chronologically).
# Empty (not an error) if the file is missing or has no real rows.
_sorted_events() {
    local events_file="$1"
    [ -f "$events_file" ] || return 0
    grep -vE '^\s*#|^\s*$' "$events_file" 2>/dev/null | sort -t'|' -k1,1 || true
}

# key_event_links NAME LINKS_FILE -> "LABEL1|URL1|LABEL2|URL2|..." for
# the event called NAME (the line minus its NAME field), empty if it has
# no line or there's no file. See render_key_events_html for the format.
key_event_links() {
    local name="$1" links_file="$2"
    [ -f "$links_file" ] || return 0
    awk -F'|' -v n="$name" '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        $1==n { sub(/^[^|]*\|/, ""); print; exit }
    ' "$links_file"
}

# _key_event_links_html NAME LINKS_FILE LINK PENDING -> NAME's links as
# "&middot;"-joined <a>s (LINK-coloured if LINK is set; PENDING-coloured
# <span>s for an empty URL), empty if it has none.
_key_event_links_html() {
    local raw
    raw="$(key_event_links "$1" "$2")"
    [ -z "$raw" ] && return 0
    local link_style="" pending="$4" out="" part label url i
    [ -n "$3" ] && link_style=" style=\"color:$3;\""
    local -a f
    IFS='|' read -ra f <<< "$raw"
    for ((i = 0; i < ${#f[@]}; i += 2)); do
        label="$(echo "${f[$i]}" | _html_escape)"
        url="${f[$((i + 1))]:-}"
        [ -z "$label" ] && continue
        if [ -n "$url" ]; then
            part="<a href=\"${url}\"${link_style}>${label}</a>"
        else
            part="<span style=\"color:${pending};\">${label}</span>"
        fi
        out="${out:+${out} &middot; }${part}"
    done
    echo "$out"
}

# render_key_events_html EVENTS_FILE [PALETTE] [LINKS_FILE] -> an HTML <table>, or
# empty output if the file's missing/empty. Format:
# DATE|START_TIME|END_TIME|NAME, one per line. The Date column shows
# date-lib.sh's format_date_long ("10 Aug 2026") rather than the raw
# ISO input -- unlike a teaching week's own date sub-line (which has no
# year, since it's already anchored to a specific week), a Key Events
# table lists dates with no such context, so the year stays in.
#
# PALETTE (optional): BORDER|HEADER_BG|ROW_ODD_BG|ROW_EVEN_BG -- border/
# header default to a plain #dddddd/#eeeeee if omitted; ROW_ODD_BG/
# ROW_EVEN_BG (also optional, independently) add alternating row
# striping when set, matching cs1101s/course-materials' own real Key
# Events table styling (its ke_parity alternation) -- both empty (the
# default, and every call before this session) reproduces exactly the
# original flat, unstriped table. Two more optional fields colour the
# LINKS_FILE links below: LINK (default: the browser's own link colour)
# and PENDING (default #888888, a label whose URL is still empty).
#
# LINKS_FILE (optional): per-event links shown under the event name, e.g.
# an exam's past papers or a competition's results. Format:
# NAME|LABEL1|URL1|LABEL2|URL2|..., any number of LABEL|URL pairs, keyed
# by the event's NAME exactly as EVENTS_FILE spells it -- EVENTS_FILE is
# often generated (dates fetched from elsewhere), so the links live in a
# hand-edited file of their own. An empty URL renders as a greyed-out
# pending label, same convention as occasion_links.
render_key_events_html() {
    local events_file="$1" palette="${2:-}" links_file="${3:-}"
    local rows
    rows="$(_sorted_events "$events_file")"
    [ -z "$rows" ] && return 0

    local -a p
    IFS='|' read -ra p <<< "$palette"
    local border="${p[0]:-#dddddd}" header_bg="${p[1]:-#eeeeee}"
    local row_odd="${p[2]:-}" row_even="${p[3]:-}"
    local link="${p[4]:-}" pending="${p[5]:-#888888}"

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
        local event_html links_html
        event_html="$(echo "$name" | _html_escape)"
        links_html="$(_key_event_links_html "$name" "$links_file" "$link" "$pending")"
        [ -n "$links_html" ] && event_html="${event_html}<div style=\"margin-top:2px;font-size:0.85rem;\">${links_html}</div>"
        printf '<tr><td style="%s">%s</td><td style="%s">%s&ndash;%s</td><td style="%s">%s</td></tr>\n' \
            "$td_style" "$(format_date_long "$date")" "$td_style" "$start" "$end" \
            "$td_style" "$event_html"
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
        echo "| $(format_date_long "$date") | $(day_of_week_name "$date") | $start-$end | $name |"
    done <<< "$rows"
}
