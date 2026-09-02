#!/bin/bash
# Generic "Key Events" table -- one-off dated events with a specific
# time (a competition, an exam, a guest lecture, ...) that don't fall
# into the regular weekly session-kind grid render-markdown.sh/
# render-html.sh already handle. A course that doesn't need this simply
# never creates a KEY_EVENTS_FILE -- both render functions return empty
# output for a missing/empty file, which callers (e.g. cli.sh) treat as
# "nothing to append," same convention as every other optional file in
# this toolkit.

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

# render_key_events_html EVENTS_FILE -> an HTML <table>, or empty output
# if the file's missing/empty. Format: DATE|START_TIME|END_TIME|NAME,
# one per line.
render_key_events_html() {
    local events_file="$1"
    local rows
    rows="$(_sorted_events "$events_file")"
    [ -z "$rows" ] && return 0

    local th_style='border:1px solid #dddddd;padding:6px 8px;background:#eeeeee;text-align:left;'
    local td_style='border:1px solid #dddddd;padding:6px 8px;vertical-align:top;'

    echo '<table style="border-collapse:collapse;width:100%;font-size:0.9rem;">'
    printf '<thead><tr><th style="%s">Date</th><th style="%s">Time</th><th style="%s">Event</th></tr></thead><tbody>\n' \
        "$th_style" "$th_style" "$th_style"
    local date start end name
    while IFS='|' read -r date start end name; do
        [ -z "$date" ] && continue
        printf '<tr><td style="%s">%s</td><td style="%s">%s&ndash;%s</td><td style="%s">%s</td></tr>\n' \
            "$td_style" "$date" "$td_style" "$start" "$end" \
            "$td_style" "$(echo "$name" | _html_escape_events)"
    done <<< "$rows"
    echo '</tbody></table>'
}

# render_key_events_markdown EVENTS_FILE -> a markdown table, or empty
# output if the file's missing/empty. Same format as the HTML version.
render_key_events_markdown() {
    local events_file="$1"
    local rows
    rows="$(_sorted_events "$events_file")"
    [ -z "$rows" ] && return 0

    echo "| Date | Time | Event |"
    echo "|------|------|-------|"
    local date start end name
    while IFS='|' read -r date start end name; do
        [ -z "$date" ] && continue
        echo "| $date | $start-$end | $name |"
    done <<< "$rows"
}
