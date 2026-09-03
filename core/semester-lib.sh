#!/bin/bash
# Teaching-week -> calendar-week bookkeeping. Deliberately separate from
# schedule-lib.sh's week_occurrences: that function only needs "this
# week's Monday" and doesn't care how teaching week numbers map onto
# real calendar weeks. This is the (institution-specific, but simple)
# piece that owns that mapping -- e.g. a mid-semester recess week that
# isn't itself a teaching week.

SEMESTER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SEMESTER_LIB_DIR/date-lib.sh"

# semester_weeks START_MONDAY NUM_WEEKS [RECESS_AFTER_WEEK] -> one line
# per teaching week, "TEACHING_WEEK|CALENDAR_MONDAY":
#   semester_weeks 2026-08-10 13 6
# = weeks 1-6 on consecutive Mondays from START_MONDAY, then ONE calendar
# week skipped (recess, not itself numbered), then weeks 7-13 resuming on
# the following Mondays. RECESS_AFTER_WEEK=0 (default) means no recess
# week is inserted.
semester_weeks() {
    local start_monday="$1" num_weeks="$2" recess_after_week="${3:-0}"
    local i calendar_offset monday
    for ((i = 1; i <= num_weeks; i++)); do
        calendar_offset=$((i - 1))
        if [ "$recess_after_week" -gt 0 ] && [ "$i" -gt "$recess_after_week" ]; then
            calendar_offset=$((calendar_offset + 1))
        fi
        monday="$(add_days "$start_monday" "$((calendar_offset * 7))")"
        printf '%s|%s\n' "$i" "$monday"
    done
}

# semester_term_window START_MONDAY NUM_WEEKS [RECESS_AFTER_WEEK]
# [BUFFER_DAYS] -> "WINDOW_START|WINDOW_END", the semester's real
# first-to-last teaching day (START_MONDAY through the last teaching
# week's Friday) padded by BUFFER_DAYS on each side (default 7). For a
# "holidays around the term" reference window, not itself part of the
# weekly schedule -- see render-holidays-reference.sh.
semester_term_window() {
    local start_monday="$1" num_weeks="$2" recess_after_week="${3:-0}" buffer="${4:-7}"
    local last_monday
    last_monday="$(semester_weeks "$start_monday" "$num_weeks" "$recess_after_week" | tail -1 | cut -d'|' -f2)"
    local last_friday
    last_friday="$(add_days "$last_monday" 4)"
    local window_start window_end
    window_start="$(add_days "$start_monday" "-${buffer}")"
    window_end="$(add_days "$last_friday" "$buffer")"
    printf '%s|%s\n' "$window_start" "$window_end"
}
