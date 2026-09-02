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
