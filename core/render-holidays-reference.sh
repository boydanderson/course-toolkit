#!/bin/bash
# A "Public Holidays Reference" table -- every holiday from HOLIDAYS_FILE
# that falls inside a given date window (typically the semester's own
# span, padded a week on each side -- see semester-lib.sh's
# semester_term_window), for a course that wants a plain reference legend
# of what's coming up, rather than relying on spotting cancellations in
# the calendar table itself. Ported from cs1101s/course-materials' own
# README-only "Public Holidays Reference (Term Window)" section
# (generate-dynamic-calendar.sh's write_footer) -- that repo has no
# Canvas-HTML equivalent, so neither does this (markdown only).
#
# A course that doesn't want this just never has anything in
# HOLIDAYS_FILE, or its window has nothing in it -- either way, empty
# output, same "nothing to append" convention as render-events.sh.

RENDER_HOLIDAYS_REF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RENDER_HOLIDAYS_REF_DIR/enrich-lib.sh"

# render_holidays_reference_markdown HOLIDAYS_FILE EMOJI_FILE WINDOW_START
# WINDOW_END -> a markdown table, or empty output if HOLIDAYS_FILE is
# missing/empty or nothing in it falls inside the window. WINDOW_START/
# END are inclusive ISO dates (compare lexicographically =
# chronologically) -- see semester-lib.sh's semester_term_window for the
# usual way to get them.
render_holidays_reference_markdown() {
    local holidays_file="$1" emoji_file="$2" window_start="$3" window_end="$4"
    [ -f "$holidays_file" ] || return 0
    local rows
    rows="$(grep -vE '^\s*#|^\s*$' "$holidays_file" 2>/dev/null | sort -t'|' -k1,1)"
    [ -z "$rows" ] && return 0

    local out="" date name printed_any=false
    while IFS='|' read -r date name; do
        [ -z "$date" ] && continue
        if [[ ( "$date" == "$window_start" || "$date" > "$window_start" ) \
           && ( "$date" == "$window_end"   || "$date" < "$window_end" ) ]]; then
            local emoji prefix=""
            emoji="$(holiday_emoji "$name" "$emoji_file")"
            [ -n "$emoji" ] && prefix="${emoji} "
            out="${out}| ${date} | ${prefix}${name} |
"
            printed_any=true
        fi
    done <<< "$rows"
    [ "$printed_any" = false ] && return 0

    printf '| Date | Holiday |\n|------|---------|\n%s' "$out"
}
