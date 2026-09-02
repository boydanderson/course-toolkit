#!/bin/bash
# The session-kind schedule engine -- the generic replacement for what
# used to be three independently-duplicated (and subtly inconsistent) day-
# offset implementations in cs1101s/course-materials:
# generate-dynamic-calendar.sh's mon/tue/wed/thu/fri arithmetic,
# get-slot-date.sh, and get-week-weekday-date.sh (the latter two shared a
# hardcoded "recess always falls after week 6" rule the first one didn't).
#
# A course declares its weekly shape as a flat list of (kind, occurrence)
# rows in config/session-kinds.conf -- see core/testdata/*.conf for two
# worked examples (CS1101S's real shape: studio + two lectures + a
# reflection; CS2030S's target shape: one lecture + one recitation + one
# lab). This engine turns that declaration + a calendar Monday date into
# the concrete slot IDs/dates/variants for one teaching week.
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
#   KIND_ID|LABEL|WEEKDAY|SUFFIX|SLOT_PATTERN|VARIANTS|WEEK_START|WEEK_END
#
#   KIND_ID       short id, e.g. "lecture", "studio", "recitation"
#   LABEL         display name, e.g. "Lecture"
#   WEEKDAY       mon|tue|wed|thu|fri|sat|sun -- this occurrence's day
#   SUFFIX        distinguishes multiple weekly occurrences of the same
#                 kind (e.g. "A"/"B" for two lectures/week); "-" if the
#                 kind only occurs once a week
#   SLOT_PATTERN  templated public slot ID: {n} -> teaching week number,
#                 {suffix} -> SUFFIX (empty string if SUFFIX is "-"), e.g.
#                 "L{n}{suffix}" -> "L4A", "R{n}" -> "R7"
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
#
# Comment lines (leading #) and blank lines are ignored, same convention
# as every other .conf file in this ecosystem.

# add_days D N -> D + N calendar days (N may be negative), YYYY-MM-DD in,
# YYYY-MM-DD out. Same GNU/BSD date branching as course-materials'
# date-utils.sh (that script's own copy moves into core/ wholesale at
# Stage 2 -- duplicated here for now so this engine has no Stage-2
# dependency yet).
add_days() {
    local d="$1" n="$2"
    if date -d "$d" '+%Y-%m-%d' >/dev/null 2>&1; then
        date -d "$d $n days" '+%Y-%m-%d'
    else
        if [[ "$n" =~ ^- ]]; then
            date -j -v"${n}d" -f "%Y-%m-%d" "$d" '+%Y-%m-%d'
        else
            date -j -v+"${n}d" -f "%Y-%m-%d" "$d" '+%Y-%m-%d'
        fi
    fi
}

# weekday_offset NAME -> 0-6 (Monday=0 .. Sunday=6), or empty + nonzero
# exit if NAME isn't recognized. NAME is case-insensitive.
weekday_offset() {
    case "${1,,}" in
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

# format_slot_id SLOT_PATTERN N SUFFIX -> SLOT_PATTERN with "{n}"
# replaced by N and "{suffix}" replaced by SUFFIX (or "" if SUFFIX is
# the literal "-", the "no suffix" marker).
format_slot_id() {
    local pattern="$1" n="$2" suffix="$3"
    [ "$suffix" = "-" ] && suffix=""
    pattern="${pattern//\{n\}/$n}"
    pattern="${pattern//\{suffix\}/$suffix}"
    echo "$pattern"
}

# week_occurrences CONF_FILE WEEK_MONDAY TEACHING_WEEK -> one line per
# active occurrence for that teaching week, in CONF_FILE's own row order:
#
#   KIND_ID|LABEL|SLOT_ID|DATE|WEEKDAY|SUFFIX|VARIANTS
#
# A row is "active" for TEACHING_WEEK when WEEK_START <= TEACHING_WEEK <=
# WEEK_END. Multiple occurrences of the same KIND_ID (e.g. two lectures/
# week) each produce their own line, distinguished by SUFFIX/SLOT_ID.
week_occurrences() {
    local conf_file="$1" week_monday="$2" teaching_week="$3"
    local line kind_id label weekday suffix slot_pattern variants week_start week_end
    local date slot_id
    while IFS='|' read -r kind_id label weekday suffix slot_pattern variants week_start week_end; do
        [ -z "$kind_id" ] && continue
        case "$kind_id" in \#*) continue ;; esac
        if [ "$teaching_week" -lt "$week_start" ] || [ "$teaching_week" -gt "$week_end" ]; then
            continue
        fi
        date="$(occurrence_date "$week_monday" "$weekday")" || {
            echo "week_occurrences: bad weekday '$weekday' for kind '$kind_id'" >&2
            return 1
        }
        slot_id="$(format_slot_id "$slot_pattern" "$teaching_week" "$suffix")"
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
