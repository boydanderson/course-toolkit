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
#   DAY_LABEL     optional 10th field (omit entirely, or "-"): overrides
#                 the weekday name a split-column header shows (see
#                 kind_columns) for this one occurrence -- WEEKDAY still
#                 has to name one concrete day for the schedule engine's
#                 own date math (occurrence_date, week_occurrences), but
#                 a course whose real session isn't pinned to that exact
#                 day (e.g. "Session 1, some day Mon-Wed") can set
#                 DAY_LABEL to "Mon-Wed" so the header doesn't assert a
#                 precision that isn't real. No effect on a kind with
#                 only one weekly occurrence (that gets one merged
#                 column, no weekday in its header at all).
#   CANCEL_EXTRA_WEEKDAYS optional 11th field (omit entirely, or "-"):
#                 comma-separated weekday names (e.g. "tue") this same
#                 occurrence ALSO spans, for a session that meets across
#                 more than one calendar day with the same material (e.g.
#                 a studio held Monday AND Tuesday) -- a holiday landing
#                 on ANY of these days, not just WEEKDAY's own, still
#                 cancels the occurrence (see enrich-lib.sh's
#                 occurrence_holiday). Purely a cancellation check: these
#                 extra days don't get their own slot ID, column, or
#                 count -- the occurrence is still exactly one row, one
#                 SLOT_ID, same as a course that never sets this field.
#   AUTO_SHIFT_ON_HOLIDAY optional 12th field (omit entirely, or "-"):
#                 when set, a week whose occurrence collides with a real
#                 holiday (same multi-day check CANCEL_EXTRA_WEEKDAYS
#                 uses) isn't just cancelled for display -- it's skipped
#                 entirely at placement time, so the content that would
#                 have landed there shifts to the next eligible week
#                 instead (see week_occurrences' own comment for the
#                 full mechanism). Requires {count} in SLOT_PATTERN
#                 (rejected with a clear error otherwise) -- shifting
#                 only makes sense for a kind whose slot ID is a flat
#                 running sequence, not tied to a specific calendar
#                 week (e.g. epp2-toolkit-poc's Studio{count}); a
#                 week-derived slot ID like L4A names the week it's
#                 shown in by construction, so it isn't a candidate.
#
# Comment lines (leading #) and blank lines are ignored, same convention
# as every other .conf file in this ecosystem.

SCHEDULE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCHEDULE_LIB_DIR/date-lib.sh"
# semester_weeks -- occurrence_count's AUTO_SHIFT_ON_HOLIDAY re-scan needs
# to know each intermediate teaching week's real calendar Monday
# (recess-gap aware), not just the target week's -- semester-lib.sh owns
# that mapping and doesn't depend on this file, so no cycle.
source "$SCHEDULE_LIB_DIR/semester-lib.sh"

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

# _row_holiday_shift_skip WEEK_MONDAY WEEKDAY CANCEL_EXTRA_WEEKDAYS
# HOLIDAYS_FILE -> success (0) if this occurrence's primary date OR any
# CANCEL_EXTRA_WEEKDAYS date hits a HOLIDAYS_FILE entry, failure (1)
# otherwise. Shared by occurrence_count/week_occurrences for
# AUTO_SHIFT_ON_HOLIDAY -- deliberately separate from enrich-lib.sh's
# occurrence_holiday (same underlying check, different shape: that one
# returns the holiday's NAME for display, this one only needs a
# boolean for scheduling/placement -- and schedule-lib.sh can't depend
# on enrich-lib.sh without a cycle, enrich-lib.sh depends on this file).
_row_holiday_shift_skip() {
    local week_monday="$1" weekday="$2" cancel_extra_weekdays="$3" holidays_file="$4"
    local date
    date="$(occurrence_date "$week_monday" "$weekday")" || return 1
    is_holiday "$date" "$holidays_file" > /dev/null 2>&1 && return 0
    if [ -z "$cancel_extra_weekdays" ] || [ "$cancel_extra_weekdays" = "-" ]; then
        return 1
    fi
    local extra_wd extra_date found=1
    local IFS_SAVE="$IFS"
    IFS=','
    for extra_wd in $cancel_extra_weekdays; do
        IFS="$IFS_SAVE"
        extra_date="$(occurrence_date "$week_monday" "$extra_wd")" || continue
        if is_holiday "$extra_date" "$holidays_file" > /dev/null 2>&1; then
            found=0
            break
        fi
    done
    IFS="$IFS_SAVE"
    return "$found"
}

# occurrence_count CONF_FILE KIND_ID TARGET_WEEK TARGET_WEEKDAY
# TARGET_SUFFIX [HOLIDAYS_FILE] [START_MONDAY] [RECESS_AFTER_WEEK] -> the
# 1-based flat count of the (TARGET_WEEK, TARGET_WEEKDAY, TARGET_SUFFIX)
# occurrence of KIND_ID among all of that kind's active occurrences from
# week 1 through TARGET_WEEK, counted in (week, file-row-order) sequence
# merged across every row sharing KIND_ID. Re-scans from week 1 on every
# call rather than keeping running state across calls -- deliberately,
# since bash 3.2 (macOS's shipped /bin/bash) has no associative arrays to
# hold per-kind counters, and a semester has few enough weeks/rows that
# re-scanning is negligible.
#
# HOLIDAYS_FILE/START_MONDAY/RECESS_AFTER_WEEK (all optional, needed
# together) make a row with AUTO_SHIFT_ON_HOLIDAY (12th field) set skip a
# holiday-colliding week the exact same way an EXCLUDE_WEEKS week already
# skips -- no count consumed, so the next eligible week absorbs that
# occurrence instead. Needs START_MONDAY/RECESS_AFTER_WEEK (not just
# TARGET_WEEK's own Monday, which this function is never given anyway)
# because it has to independently derive *every* intermediate week's real
# calendar Monday to check -- semester_weeks (semester-lib.sh) is the
# single source of truth for that, recess-gap included. A row without
# AUTO_SHIFT_ON_HOLIDAY set, or a caller that omits these three params
# entirely, behaves exactly as before this existed.
occurrence_count() {
    local conf_file="$1" kind_id="$2" target_week="$3" target_weekday="$4" target_suffix="$5"
    local holidays_file="${6:-}" start_monday="${7:-}" recess_after_week="${8:-}"
    local k l w s sp v ws we ew dl cew ashw week count=0
    for ((week = 1; week <= target_week; week++)); do
        while IFS='|' read -r k l w s sp v ws we ew dl cew ashw; do
            [ -z "$k" ] && continue
            case "$k" in \#*) continue ;; esac
            [ "$k" = "$kind_id" ] || continue
            if [ "$week" -lt "$ws" ] || [ "$week" -gt "$we" ]; then continue; fi
            if [ -n "$ew" ] && [ "$ew" != "-" ]; then
                case ",${ew}," in *",${week},"*) continue ;; esac
            fi
            if [ -n "$ashw" ] && [ "$ashw" != "-" ] && [ -n "$holidays_file" ] && [ -n "$start_monday" ]; then
                local this_week_monday
                this_week_monday="$(semester_weeks "$start_monday" "$week" "$recess_after_week" | tail -1 | cut -d'|' -f2)"
                if _row_holiday_shift_skip "$this_week_monday" "$w" "$cew" "$holidays_file"; then
                    continue
                fi
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

# week_occurrences CONF_FILE WEEK_MONDAY TEACHING_WEEK [HOLIDAYS_FILE]
# [START_MONDAY] [RECESS_AFTER_WEEK] -> one line per active occurrence
# for that teaching week, in CONF_FILE's own row order:
#
#   KIND_ID|LABEL|SLOT_ID|DATE|WEEKDAY|SUFFIX|VARIANTS|CANCEL_EXTRA_DATES
#
# HOLIDAYS_FILE/START_MONDAY/RECESS_AFTER_WEEK (all optional, needed
# together) enable a row's optional 12th field, AUTO_SHIFT_ON_HOLIDAY
# (omit, or "-", for no effect): when set, a week whose occurrence would
# land on a HOLIDAYS_FILE date (checking WEEKDAY's own date and any
# CANCEL_EXTRA_WEEKDAYS dates, same multi-day check as cancellation
# display) produces NO occurrence at all this week -- not "cancelled",
# genuinely not placed here -- and (since AUTO_SHIFT_ON_HOLIDAY requires
# {count} in SLOT_PATTERN, enforced with a clear error otherwise) doesn't
# consume a count either, so the content that would have landed here
# shifts to the next eligible week instead, cascading exactly like an
# EXCLUDE_WEEKS week already does. START_MONDAY/RECESS_AFTER_WEEK are
# needed (not just this call's own WEEK_MONDAY) because occurrence_count's
# own re-scan has to independently derive every intermediate week's real
# calendar Monday to check, via semester_weeks. A row without
# AUTO_SHIFT_ON_HOLIDAY set, or a caller that omits these three params,
# behaves exactly as before this existed.
#
# CANCEL_EXTRA_DATES (comma-separated YYYY-MM-DD, empty if the row's
# optional 11th field CANCEL_EXTRA_WEEKDAYS was omitted/"-") is the real
# calendar date of each extra weekday this one occurrence also spans --
# e.g. a studio that meets Monday AND Tuesday with the same material
# declares WEEKDAY=mon, CANCEL_EXTRA_WEEKDAYS=tue, and this field then
# carries Tuesday's actual date so a caller (enrich-lib.sh's
# occurrence_holiday) can check both days for a holiday without knowing
# any weekday names itself -- DATE alone still names the day WEEKDAY
# resolves to, unchanged from before this field existed.
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
    local holidays_file="${4:-}" start_monday="${5:-}" recess_after_week="${6:-}"
    local line kind_id label weekday suffix slot_pattern variants week_start week_end exclude_weeks day_label cancel_extra_weekdays auto_shift_on_holiday
    local date slot_id count cancel_extra_dates
    while IFS='|' read -r kind_id label weekday suffix slot_pattern variants week_start week_end exclude_weeks day_label cancel_extra_weekdays auto_shift_on_holiday; do
        [ -z "$kind_id" ] && continue
        case "$kind_id" in \#*) continue ;; esac
        if [ -n "$auto_shift_on_holiday" ] && [ "$auto_shift_on_holiday" != "-" ]; then
            case "$slot_pattern" in
                *'{count}'*) : ;;
                *)
                    echo "week_occurrences: AUTO_SHIFT_ON_HOLIDAY requires {count} in SLOT_PATTERN for kind '$kind_id'" >&2
                    return 1
                    ;;
            esac
        fi
        if [ "$teaching_week" -lt "$week_start" ] || [ "$teaching_week" -gt "$week_end" ]; then
            continue
        fi
        if [ -n "$exclude_weeks" ] && [ "$exclude_weeks" != "-" ]; then
            case ",${exclude_weeks}," in
                *",${teaching_week},"*) continue ;;
            esac
        fi
        if [ -n "$auto_shift_on_holiday" ] && [ "$auto_shift_on_holiday" != "-" ] && [ -n "$holidays_file" ]; then
            _row_holiday_shift_skip "$week_monday" "$weekday" "$cancel_extra_weekdays" "$holidays_file" && continue
        fi
        date="$(occurrence_date "$week_monday" "$weekday")" || {
            echo "week_occurrences: bad weekday '$weekday' for kind '$kind_id'" >&2
            return 1
        }
        count=""
        case "$slot_pattern" in
            *'{count}'*) count="$(occurrence_count "$conf_file" "$kind_id" "$teaching_week" "$weekday" "$suffix" "$holidays_file" "$start_monday" "$recess_after_week")" ;;
        esac
        slot_id="$(format_slot_id "$slot_pattern" "$teaching_week" "$suffix" "$count")"
        cancel_extra_dates=""
        if [ -n "$cancel_extra_weekdays" ] && [ "$cancel_extra_weekdays" != "-" ]; then
            local extra_wd extra_date
            local IFS_SAVE="$IFS"
            IFS=','
            for extra_wd in $cancel_extra_weekdays; do
                IFS="$IFS_SAVE"
                extra_date="$(occurrence_date "$week_monday" "$extra_wd")" || {
                    echo "week_occurrences: bad weekday '$extra_wd' in CANCEL_EXTRA_WEEKDAYS for kind '$kind_id'" >&2
                    return 1
                }
                cancel_extra_dates="${cancel_extra_dates:+$cancel_extra_dates,}$extra_date"
            done
            IFS="$IFS_SAVE"
        fi
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "$kind_id" "$label" "$slot_id" "$date" "$weekday" "$suffix" "$variants" "$cancel_extra_dates"
    done < <(grep -vE '^\s*#|^\s*$' "$conf_file")
}

# available_slot_count CONF_FILE KIND_ID THROUGH_WEEK [HOLIDAYS_FILE]
# [START_MONDAY] [RECESS_AFTER_WEEK] -> how many eligible occurrences
# exist for KIND_ID from week 1 through THROUGH_WEEK, merged across
# EVERY row sharing that KIND_ID (the same merge {count}/occurrence_count
# already do -- a kind with two weekly rows, e.g. epp2's Session1/
# Session2, shares one running sequence, so "how many slots does this
# kind have" is inherently a whole-kind question, not a per-row one).
# "Eligible" means the same rule occurrence_count/week_occurrences
# already use: not in EXCLUDE_WEEKS, and (only for a row with
# AUTO_SHIFT_ON_HOLIDAY set, and HOLIDAYS_FILE/START_MONDAY given) not
# holiday-colliding either.
#
# Schedule-lib.sh only knows how many *weeks* are available -- it has no
# idea how much real content a course has authored for a kind (that
# lives in course-specific places: a directory of source files, a
# content-map, whatever). This function exists so a course's own build
# step can compare its own real content count against the number this
# returns and hard-fail with a clear message if content doesn't fit --
# this function only ever reports the slot count, never does that
# comparison or raises that error itself.
#
# Implemented as occurrence_count with a (weekday, suffix) target that
# can never match any real row -- guaranteeing its early-return branch
# never fires, so it always falls through to the accumulated total
# count of every eligible occurrence (merged across every row sharing
# KIND_ID) from week 1 through THROUGH_WEEK. Earlier versions of this
# function took a (WEEKDAY, SUFFIX) pair and asked for one row's own
# count, which was wrong for a multi-row kind: occurrence_count's count
# is already merged across every row sharing KIND_ID by design, so a
# per-row query returned that same merged total (right answer, by
# accident) only when the queried row happened to be inactive/excluded
# exactly at its own WEEK_END -- silently wrong otherwise. Found for
# real against epp2-toolkit-poc's own two-row studio kind.
available_slot_count() {
    local conf_file="$1" kind_id="$2" through_week="$3"
    local holidays_file="${4:-}" start_monday="${5:-}" recess_after_week="${6:-}"
    occurrence_count "$conf_file" "$kind_id" "$through_week" "__available_slot_count_no_match__" "__no_match__" \
        "$holidays_file" "$start_monday" "$recess_after_week"
}

# weekday_full_name NAME -> "Monday".."Sunday", or empty + nonzero exit
# if NAME isn't recognized. Companion to weekday_offset, for a column
# header that names the actual day (e.g. "Wednesday (Lecture A)").
weekday_full_name() {
    local lower
    lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
        mon) echo "Monday" ;;
        tue) echo "Tuesday" ;;
        wed) echo "Wednesday" ;;
        thu) echo "Thursday" ;;
        fri) echo "Friday" ;;
        sat) echo "Saturday" ;;
        sun) echo "Sunday" ;;
        *) return 1 ;;
    esac
}

# kind_suffixes CONF_FILE KIND_ID -> one line per distinct SUFFIX
# declared for KIND_ID, in file order: "SUFFIX|WEEKDAY|LABEL|DAY_LABEL".
# A kind with a single weekly occurrence has exactly one row (SUFFIX
# "-"); a kind with several (e.g. two lectures/week) has one row per
# occurrence -- for a renderer deciding whether a kind needs one merged
# column or one column per occurrence (see render-markdown.sh/
# render-html.sh). DAY_LABEL is session-kinds.conf's own optional 10th
# field, empty if that row didn't set one.
kind_suffixes() {
    local conf_file="$1" kind_id="$2"
    local k l w s sp v ws we ew dl cew ashw
    local seen=""
    while IFS='|' read -r k l w s sp v ws we ew dl cew ashw; do
        [ -z "$k" ] && continue
        case "$k" in \#*) continue ;; esac
        [ "$k" = "$kind_id" ] || continue
        case ",${seen}," in *",${s},"*) continue ;; esac
        seen="${seen:+$seen,}$s"
        printf '%s|%s|%s|%s\n' "$s" "$w" "$l" "$dl"
    done < <(grep -vE '^\s*#|^\s*$' "$conf_file")
}

# _capitalize WORD -> WORD with its first character upper-cased (e.g.
# "lecture" -> "Lecture", "view" -> "View"), for column headers/variant
# labels. Portable `tr`/`cut`, not bash 4+'s ${var^} -- macOS ships bash
# 3.2 as /bin/bash, which doesn't support it (see weekday_offset above
# for the same fix, confirmed for real). Lives here (not enrich-lib.sh,
# where it used to live) since kind_columns below needs it and
# schedule-lib.sh shouldn't depend on enrich-lib.sh to get it --
# enrich-lib.sh now sources this file instead, so its own callers still
# get _capitalize from there unchanged.
_capitalize() {
    local w="$1"
    printf '%s%s' "$(printf '%s' "${w:0:1}" | tr '[:lower:]' '[:upper:]')" "${w:1}"
}

# kind_columns CONF_FILE -> one line per output column, shared by both
# render-markdown.sh and render-html.sh: "KIND_ID|SUFFIX_FILTER|HEADER".
# A kind with a single weekly occurrence (kind_suffixes returns exactly
# one row) gets one merged column (SUFFIX_FILTER empty, HEADER the
# capitalized kind id -- exactly the pre-split-column behavior); a kind
# with several (e.g. two lectures/week) gets one column per occurrence
# instead, since cramming e.g. two weekly sessions into one cell loses
# which weekday each one is on -- HEADER then follows cs1101s/course-
# materials' own real convention, "Wednesday (Lecture A)"
# (WeekdayFullName (Label Suffix)), unless that row's own DAY_LABEL
# (session-kinds.conf's optional 10th field) overrides the weekday
# portion -- for a course whose real session isn't pinned to one fixed
# weekday (e.g. "Session 1, some day Mon-Wed" -- WEEKDAY still has to
# name one concrete day for the schedule engine's own date math, but the
# column header can say "Mon-Wed" instead of asserting a specific day
# that isn't actually fixed).
kind_columns() {
    local conf_file="$1"
    local -a kind_ids
    while IFS= read -r k; do kind_ids+=("$k"); done < <(session_kind_ids "$conf_file")
    local k
    for k in "${kind_ids[@]}"; do
        local -a suf_lines=()
        while IFS= read -r line; do [ -n "$line" ] && suf_lines+=("$line"); done < <(kind_suffixes "$conf_file" "$k")
        if [ "${#suf_lines[@]}" -le 1 ]; then
            printf '%s||%s\n' "$k" "$(_capitalize "$k")"
        else
            local sl suf wd lbl dl wd_full
            for sl in "${suf_lines[@]}"; do
                IFS='|' read -r suf wd lbl dl <<< "$sl"
                if [ -n "$dl" ]; then
                    wd_full="$dl"
                else
                    wd_full="$(weekday_full_name "$wd")"
                fi
                printf '%s|%s|%s (%s %s)\n' "$k" "$suf" "$wd_full" "$lbl" "$suf"
            done
        fi
    done
}

# session_kind_ids CONF_FILE -> the distinct KIND_IDs declared, in
# first-appearance order (e.g. for generating one table column per kind
# in Stage 2's calendar/Canvas generators).
session_kind_ids() {
    local conf_file="$1"
    grep -vE '^\s*#|^\s*$' "$conf_file" | cut -d'|' -f1 | awk '!seen[$0]++'
}
