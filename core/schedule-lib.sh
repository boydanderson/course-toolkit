#!/bin/bash
# The session-kind schedule engine -- the generic replacement for what
# used to be three independently-duplicated (and subtly inconsistent) day-
# offset implementations in cs1101s/course-materials:
# generate-dynamic-calendar.sh's mon/tue/wed/thu/fri arithmetic,
# get-slot-date.sh, and get-week-weekday-date.sh (the latter two shared a
# hardcoded "recess always falls after week 6" rule the first one didn't).
#
# A course declares its weekly shape as a flat list of (kind, occurrence)
# rows in config/session-kinds.conf -- see tests/fixtures/*/config/ for
# two worked examples (demo101: studio + two lectures + a reflection;
# demo201: one lecture + one recitation + one lab -- a genuinely
# different session-kind vocabulary, proving the engine doesn't assume a
# fixed kind set). This engine turns that declaration + a calendar
# Monday date into the concrete slot IDs/dates/variants for one teaching
# week.
#
# Deliberately renderer- and institution-agnostic:
#   - Doesn't know or care what format a slot's source file is (that's a
#     backend's job, see backends/*/).
#   - Doesn't compute which calendar week a "teaching week number" falls
#     on -- recess/reading-week insertion is institution-specific
#     bookkeeping a course repo supplies (e.g. a list of skipped calendar
#     weeks), not something this engine fetches or assumes. Callers pass
#     in the actual calendar Monday for the teaching week they're asking
#     about.
#
# config/session-kinds.conf format (pipe-delimited, one row per weekly
# occurrence -- a kind with N occurrences/week, e.g. two lectures, gets N
# rows sharing the same KIND_ID):
#
#   KIND_ID|LABEL|WEEKDAY|SUFFIX|SLOT_PATTERN|VARIANTS|WEEK_START|WEEK_END|EXCLUDE_WEEKS
#
#   KIND_ID       short id, e.g. "lecture", "studio", "recitation"
#   LABEL         display name, e.g. "Lecture"
#   WEEKDAY       mon|tue|wed|thu|fri|sat|sun -- this occurrence's day
#   SUFFIX        distinguishes multiple weekly occurrences of the same
#                 kind (e.g. "A"/"B" for two lectures/week); "-" if the
#                 kind only occurs once a week
#   SLOT_PATTERN  templated public slot ID: {n} -> teaching week number,
#                 {suffix} -> SUFFIX (empty string if SUFFIX is "-"), e.g.
#                 "L{n}{suffix}" -> "L4A", "R{n}" -> "R7". A third
#                 placeholder, {count}, is a flat 1-based counter across
#                 every active occurrence of this KIND_ID so far (in
#                 (week, file-row-order) sequence, merged across all rows
#                 sharing the KIND_ID) rather than a week-derived number
#                 -- for a kind whose real-world numbering doesn't reset
#                 or split per week (e.g. 17 labs run 2/week on different
#                 weekdays, numbered Lab1..Lab17 straight through, not
#                 Lab1A/Lab1B/Lab2A...). A week where this row is skipped
#                 (via EXCLUDE_WEEKS -- e.g. a tutorial taking over that
#                 week's slot) simply doesn't consume a count, so the
#                 remaining occurrences stay a dense, gap-free sequence.
#   VARIANTS      comma-separated build-artifact variants this kind
#                 produces, e.g. "view,print", "problem,solution", or
#                 "none" for a single undifferentiated PDF. This is the
#                 FULL build-artifact set -- public-visibility policy
#                 (e.g. "solutions are never distributed") is a separate,
#                 later concern, not encoded here.
#   WEEK_START,
#   WEEK_END      teaching-week bounds this occurrence is active for
#                 (inclusive); a kind that runs the whole semester repeats
#                 the same bounds on every one of its occurrence rows.
#   EXCLUDE_WEEKS optional (omit the field, or use "-"): comma-separated
#                 teaching week numbers this occurrence is skipped even
#                 though it's within WEEK_START..WEEK_END, e.g. "4,6,8"
#                 for weeks displaced by assessments/holidays.
#
# Comment lines (leading #) and blank lines are ignored, same convention
# as every other .conf file in this ecosystem.

SCHEDULE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCHEDULE_LIB_DIR/date-lib.sh"

# weekday_offset NAME -> 0-6 (Monday=0 .. Sunday=6), or empty + nonzero
# exit if NAME isn't recognized. NAME is case-insensitive.
#
# Lowercasing via `tr`, not bash 4+'s ${var,,} -- macOS ships bash 3.2 as
# /bin/bash (confirmed for real: a plain #!/bin/bash script hits "bad
# substitution" there), and this toolkit shouldn't assume every consumer
# has a newer bash ahead of it on PATH.
weekday_offset() {
    local lower
    lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
        mon) echo 0 ;;
        tue) echo 1 ;;
        wed) echo 2 ;;
        thu) echo 3 ;;
        fri) echo 4 ;;
        sat) echo 5 ;;
        sun) echo 6 ;;
        *) return 1 ;;
    esac
}

# occurrence_date WEEK_MONDAY WEEKDAY -> the calendar date of WEEKDAY
# within the week starting WEEK_MONDAY.
occurrence_date() {
    local week_monday="$1" weekday="$2" offset
    offset="$(weekday_offset "$weekday")" || return 1
    add_days "$week_monday" "$offset"
}

# format_slot_id SLOT_PATTERN N SUFFIX [COUNT] -> SLOT_PATTERN with "{n}"
# replaced by N, "{suffix}" replaced by SUFFIX (or "" if SUFFIX is the
# literal "-", the "no suffix" marker), and "{count}" replaced by COUNT
# (if given -- see occurrence_count for what it means).
format_slot_id() {
    local pattern="$1" n="$2" suffix="$3" count="${4:-}"
    [ "$suffix" = "-" ] && suffix=""
    pattern="${pattern//\{n\}/$n}"
    pattern="${pattern//\{suffix\}/$suffix}"
    pattern="${pattern//\{count\}/$count}"
    echo "$pattern"
}

# occurrence_count CONF_FILE KIND_ID TARGET_WEEK TARGET_WEEKDAY
# TARGET_SUFFIX -> the 1-based flat count of the (TARGET_WEEK,
# TARGET_WEEKDAY, TARGET_SUFFIX) occurrence of KIND_ID among all of that
# kind's active occurrences from week 1 through TARGET_WEEK, counted in
# (week, file-row-order) sequence merged across every row sharing
# KIND_ID. Re-scans from week 1 on every call rather than keeping running
# state across calls -- deliberately, since bash 3.2 (macOS's shipped
# /bin/bash) has no associative arrays to hold per-kind counters, and a
# semester has few enough weeks/rows that re-scanning is negligible.
occurrence_count() {
    local conf_file="$1" kind_id="$2" target_week="$3" target_weekday="$4" target_suffix="$5"
    local k l w s sp v ws we ew week count=0
    for ((week = 1; week <= target_week; week++)); do
        while IFS='|' read -r k l w s sp v ws we ew; do
            [ -z "$k" ] && continue
            case "$k" in \#*) continue ;; esac
            [ "$k" = "$kind_id" ] || continue
            if [ "$week" -lt "$ws" ] || [ "$week" -gt "$we" ]; then continue; fi
            if [ -n "$ew" ] && [ "$ew" != "-" ]; then
                case ",${ew}," in *",${week},"*) continue ;; esac
            fi
            count=$((count + 1))
            if [ "$week" -eq "$target_week" ] && [ "$w" = "$target_weekday" ] && [ "$s" = "$target_suffix" ]; then
                echo "$count"
                return 0
            fi
        done < <(grep -vE '^\s*#|^\s*$' "$conf_file")
    done
    echo "$count"
}

# week_occurrences CONF_FILE WEEK_MONDAY TEACHING_WEEK -> one line per
# active occurrence for that teaching week, in CONF_FILE's own row order:
#
#   KIND_ID|LABEL|SLOT_ID|DATE|WEEKDAY|SUFFIX|VARIANTS
#
# A row is "active" for TEACHING_WEEK when WEEK_START <= TEACHING_WEEK <=
# WEEK_END AND TEACHING_WEEK isn't listed in the row's optional 9th field,
# EXCLUDE_WEEKS (comma-separated teaching week numbers, e.g. "4,6,8" --
# omit the field entirely, or leave it "-", for "no exceptions"). This is
# for the common real-world case a plain range can't express: a lecture
# kind that meets almost every week except a handful displaced by
# assessments/holidays on specific weeks -- rather than forcing that
# irregularity into several adjacent WEEK_START/WEEK_END row-splits.
# What shows in an excluded week's now-empty cell (e.g. an assessment
# callout) is a maintainer-supplied label override
# (enrich-lib.sh's slot_kind_label), same mechanism as any other week
# with no occurrence -- this list only says "skip the regular occurrence
# here," it doesn't itself know or care why.
#
# Multiple occurrences of the same KIND_ID (e.g. two lectures/week) each
# produce their own line, distinguished by SUFFIX/SLOT_ID.
week_occurrences() {
    local conf_file="$1" week_monday="$2" teaching_week="$3"
    local line kind_id label weekday suffix slot_pattern variants week_start week_end exclude_weeks
    local date slot_id count
    while IFS='|' read -r kind_id label weekday suffix slot_pattern variants week_start week_end exclude_weeks; do
        [ -z "$kind_id" ] && continue
        case "$kind_id" in \#*) continue ;; esac
        if [ "$teaching_week" -lt "$week_start" ] || [ "$teaching_week" -gt "$week_end" ]; then
            continue
        fi
        if [ -n "$exclude_weeks" ] && [ "$exclude_weeks" != "-" ]; then
            case ",${exclude_weeks}," in
                *",${teaching_week},"*) continue ;;
            esac
        fi
        date="$(occurrence_date "$week_monday" "$weekday")" || {
            echo "week_occurrences: bad weekday '$weekday' for kind '$kind_id'" >&2
            return 1
        }
        count=""
        case "$slot_pattern" in
            *'{count}'*) count="$(occurrence_count "$conf_file" "$kind_id" "$teaching_week" "$weekday" "$suffix")" ;;
        esac
        slot_id="$(format_slot_id "$slot_pattern" "$teaching_week" "$suffix" "$count")"
        printf '%s|%s|%s|%s|%s|%s|%s\n' \
            "$kind_id" "$label" "$slot_id" "$date" "$weekday" "$suffix" "$variants"
    done < <(grep -vE '^\s*#|^\s*$' "$conf_file")
}

# session_kind_ids CONF_FILE -> the distinct KIND_IDs declared, in
# first-appearance order (e.g. for generating one table column per kind
# in Stage 2's calendar/Canvas generators).
session_kind_ids() {
    local conf_file="$1"
    grep -vE '^\s*#|^\s*$' "$conf_file" | cut -d'|' -f1 | awk '!seen[$0]++'
}
