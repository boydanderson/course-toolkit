#!/bin/bash
# The toolkit's command-line entry point -- the generic, reusable driver
# every consuming course repo can call directly (via a thin Makefile
# wrapper, see examples/Makefile) instead of writing its own copy of this
# walk-the-semester-and-do-something logic. Promoted out of
# cs1101s/course-materials' scripts/toolkit-build.sh once that proved the
# approach against real data -- see that repo's git history for the
# original, course-specific version this generalizes.
#
# Usage: cli.sh COMMAND [ARGS...]
#   build [--pdfs]   Walk the whole semester; for every scheduled slot
#                     with a content-map entry, extract its title,
#                     compute its hash, and track its version. --pdfs
#                     also actually compiles every variant (slow).
#   readme            Print a markdown calendar table to stdout.
#   canvas             Print an HTML calendar table to stdout.
#   bump SLOT_ID VARIANT
#                     Explicitly bump one slot/variant's version.
#
# Requires COURSE_ROOT (the consuming repo's root; defaults to the
# working directory) and TOOLKIT_DIR (this submodule's path -- defaults
# to the directory this script lives in, so it works when invoked
# directly via its full path too) set as environment variables, or picks
# sane defaults. See README's "Using it" / "What a consuming course repo
# provides" for the full config-file contract this reads.
#
# Config file paths are all overridable via environment variables (same
# convention used throughout this ecosystem for optional overrides) --
# defaults assume generic names; a course with existing, differently-
# named files (e.g. cs1101s/course-materials' config/canvas-release.conf)
# just sets the env var instead of renaming anything:
#   SESSION_KINDS_FILE   default: config/session-kinds.conf
#   CONTENT_MAP_FILE     default: config/content-map.conf
#   ALLOWLIST_FILE        default: config/release-allowlist.conf
#   LABELS_FILE           default: config/session-kind-labels.conf
#   NOTES_FILE            default: config/week-notes.conf
#   HOLIDAYS_FILE         default: config/holidays.conf. `readme`
#                          (markdown only, no Canvas equivalent) also
#                          appends a "Public Holidays Reference" table
#                          of every holiday in this file falling inside
#                          the semester's own span ±7 days -- automatic
#                          whenever HOLIDAYS_FILE has real rows in that
#                          window, no separate opt-in; see
#                          render-holidays-reference.sh.
#   EMOJI_FILE            default: config/holiday-emoji.conf
#   KEY_EVENTS_FILE       default: config/key-events.conf (optional -- a
#                          table of one-off dated events appended after
#                          the main calendar; see render-events.sh)
#   RESOURCES_HTML_FILE   default: config/canvas-resources.html (optional
#                          -- appended verbatim under a "Resources"
#                          heading in `canvas`'s output)
#   RESOURCES_MD_FILE     default: config/readme-resources.md (optional
#                          -- same, for `readme`'s output)
#   KIND_EXTRA_LINKS_FILE  default: config/kind-extra-links.conf
#                          (optional, KIND_ID|LABEL -- e.g. "lecture|
#                          Recording" -- declares which session kinds
#                          get a second, independently-gated link per
#                          occurrence)
#   EXTRA_LINKS_FILE       default: config/extra-links.conf (optional,
#                          SLOT_ID|URL -- the actual links for whichever
#                          kinds KIND_EXTRA_LINKS_FILE declares)
#   OCCASION_LINKS_FILE    default: config/occasion-links.conf (optional,
#                          WEEK|KIND_ID|LINK1_LABEL|LINK1_URL|LINK2_LABEL|
#                          LINK2_URL -- up to 2 links for an occasion
#                          label from LABELS_FILE, e.g. an assessment's
#                          "Details"/"Papers")
#   GRADED_SLOTS_FILE      default: config/graded-slots.conf (optional,
#                          one SLOT_ID per line -- marks a real
#                          occurrence as graded/important with a "🔴 "
#                          title prefix in both readme/canvas; see
#                          enrich-lib.sh's is_graded_slot)
#   EXTRA_SLOTS_FILE       default: config/kind-extra-slots.conf
#                          (optional, WEEK|KIND_ID|SLOT_ID -- extra slots
#                          sharing a week+kind's already-scheduled
#                          occurrence(s) without being a distinct weekly
#                          occurrence of their own, e.g. a studio's
#                          "-in-class" supplement; grouped by matching
#                          title in readme, shown as independent stacked
#                          blocks in canvas; see enrich-lib.sh's
#                          kind_extra_slots)
#
# config/course.mk additionally supplies (beyond COURSE_CODE/COURSE_NAME/
# HOSTING_ORG/CANVAS_HOST/RENDERER, see README):
#   SEMESTER_START_MONDAY  YYYY-MM-DD, the Monday of teaching week 1
#   NUM_WEEKS              total teaching weeks, e.g. 13
#   RECESS_AFTER_WEEK      0 for none, else the teaching week number a
#                          one-calendar-week recess follows
#   PDF_BASE_URL            base URL the calendar's PDF links point at
#   CALENDAR_BORDER_COLOR, CALENDAR_HEADER_BG, CALENDAR_LINK_COLOR,
#   CALENDAR_PENDING_COLOR, CALENDAR_CANCELLED_COLOR, CALENDAR_NOTES_COLOR,
#   CALENDAR_CURRENT_BG, CALENDAR_CURRENT_BORDER_COLOR,
#   CALENDAR_ROW_ODD_BG, CALENDAR_ROW_EVEN_BG
#                          `canvas`'s colors -- all optional, each falls
#                          back to render-html.sh's own default if unset
#                          (CALENDAR_LINK_COLOR and the four current-week/
#                          row-banding keys all default to "", meaning
#                          "no override" -- a course gets no current-week
#                          highlight or row banding unless it sets at
#                          least one of those keys). See README's
#                          "Customizing the calendar's colors".
set -euo pipefail

CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_DIR="${TOOLKIT_DIR:-$(cd "$CLI_DIR/.." && pwd)}"
COURSE_ROOT="${COURSE_ROOT:-.}"
export TOOLKIT_DIR COURSE_ROOT

source "$TOOLKIT_DIR/core/course-lib.sh"
source "$TOOLKIT_DIR/core/schedule-lib.sh"
source "$TOOLKIT_DIR/core/semester-lib.sh"
source "$TOOLKIT_DIR/core/version-lib.sh"
source "$TOOLKIT_DIR/core/backend-lib.sh"
source "$TOOLKIT_DIR/core/enrich-lib.sh"
source "$TOOLKIT_DIR/core/render-markdown.sh"
source "$TOOLKIT_DIR/core/render-html.sh"
source "$TOOLKIT_DIR/core/render-events.sh"
source "$TOOLKIT_DIR/core/render-holidays-reference.sh"

RENDERER="$(get_course_var RENDERER)"
export RENDERER

SESSION_KINDS="${SESSION_KINDS_FILE:-$COURSE_ROOT/config/session-kinds.conf}"
CONTENT_MAP="${CONTENT_MAP_FILE:-$COURSE_ROOT/config/content-map.conf}"
ALLOWLIST="${ALLOWLIST_FILE:-$COURSE_ROOT/config/release-allowlist.conf}"
LABELS="${LABELS_FILE:-$COURSE_ROOT/config/session-kind-labels.conf}"
NOTES="${NOTES_FILE:-$COURSE_ROOT/config/week-notes.conf}"
HOLIDAYS="${HOLIDAYS_FILE:-$COURSE_ROOT/config/holidays.conf}"
EMOJI="${EMOJI_FILE:-$COURSE_ROOT/config/holiday-emoji.conf}"
KEY_EVENTS="${KEY_EVENTS_FILE:-$COURSE_ROOT/config/key-events.conf}"
RESOURCES_HTML="${RESOURCES_HTML_FILE:-$COURSE_ROOT/config/canvas-resources.html}"
RESOURCES_MD="${RESOURCES_MD_FILE:-$COURSE_ROOT/config/readme-resources.md}"
KIND_EXTRA_LINKS="${KIND_EXTRA_LINKS_FILE:-$COURSE_ROOT/config/kind-extra-links.conf}"
EXTRA_LINKS="${EXTRA_LINKS_FILE:-$COURSE_ROOT/config/extra-links.conf}"
OCCASION_LINKS="${OCCASION_LINKS_FILE:-$COURSE_ROOT/config/occasion-links.conf}"
GRADED_SLOTS="${GRADED_SLOTS_FILE:-$COURSE_ROOT/config/graded-slots.conf}"
EXTRA_SLOTS="${EXTRA_SLOTS_FILE:-$COURSE_ROOT/config/kind-extra-slots.conf}"

SEMESTER_START_MONDAY="$(get_course_var SEMESTER_START_MONDAY)"
NUM_WEEKS="$(get_course_var NUM_WEEKS)"
RECESS_AFTER_WEEK="$(get_course_var RECESS_AFTER_WEEK)"
[ -z "$RECESS_AFTER_WEEK" ] && RECESS_AFTER_WEEK=0
PDF_BASE_URL="$(get_course_var PDF_BASE_URL)"

# Each field left blank here falls back to render-html.sh's own default
# (_calendar_palette) -- a course only overriding one color doesn't need
# to respecify the rest. The last four (current-week highlight, row
# banding) default to "" either way -- a course gets neither unless it
# sets at least one of these keys.
CALENDAR_PALETTE="$(get_course_var CALENDAR_BORDER_COLOR)|$(get_course_var CALENDAR_HEADER_BG)|$(get_course_var CALENDAR_LINK_COLOR)|$(get_course_var CALENDAR_PENDING_COLOR)|$(get_course_var CALENDAR_CANCELLED_COLOR)|$(get_course_var CALENDAR_NOTES_COLOR)|$(get_course_var CALENDAR_CURRENT_BG)|$(get_course_var CALENDAR_CURRENT_BORDER_COLOR)|$(get_course_var CALENDAR_ROW_ODD_BG)|$(get_course_var CALENDAR_ROW_EVEN_BG)"

_content_map_path() {
    # || true: a scheduled slot with no content-map entry (unauthored,
    # or displaced by something the schedule doesn't structurally
    # exclude) is a normal state, not an error -- see enrich-lib.sh's
    # slot_title for the identical rationale.
    grep -vE '^\s*#|^\s*$' "$CONTENT_MAP" 2>/dev/null | grep "^${1}|" | head -1 | cut -d'|' -f2- || true
}

# _walk_semester [TITLES_OUT] -> for every scheduled+content-mapped
# slot/variant this semester, track its version (always) and, if
# TITLES_OUT is given, append "SLOT_ID|TITLE" lines to it (truncated
# first). Shared by `build`, `readme`, and `canvas` so the latter two
# never depend on `build` having run first.
_walk_semester() {
    local titles_out="${1:-}"
    [ -n "$titles_out" ] && : > "$titles_out"
    while IFS='|' read -r teaching_week monday; do
        while IFS='|' read -r kind label slot_id date weekday suffix variants cancel_extra; do
            [ -z "$kind" ] && continue
            local source_path
            source_path="$(_content_map_path "$slot_id")"
            [ -z "$source_path" ] || [ ! -f "$source_path" ] && continue
            local title
            title="$(backend_extract_title "$source_path" "$slot_id")"
            [ -n "$titles_out" ] && echo "${slot_id}|${title}" >> "$titles_out"
            local -a vlist
            IFS=',' read -ra vlist <<< "$variants"
            [ "$variants" = "none" ] && vlist=("")
            local v variant_key content_hash
            for v in "${vlist[@]}"; do
                [ -z "$v" ] && variant_key="none" || variant_key="$v"
                content_hash="$(backend_content_hash "$source_path" "$variant_key" "$slot_id")"
                get_slot_version "$slot_id" "$variant_key" "$content_hash" > /dev/null
                if [ "${CLI_BUILD_PDFS:-0}" = 1 ]; then
                    local out_pdf="$COURSE_ROOT/build/toolkit-pdfs/${kind}-${slot_id}$([ -n "$v" ] && echo ".$v").pdf"
                    backend_build_slot "$source_path" "$variant_key" "$out_pdf" "$slot_id"
                    echo "built ${slot_id} (${variant_key}) -> ${out_pdf}" >&2
                fi
            done
        done < <(week_occurrences "$SESSION_KINDS" "$monday" "$teaching_week")
    done < <(semester_weeks "$SEMESTER_START_MONDAY" "$NUM_WEEKS" "$RECESS_AFTER_WEEK")
}

cmd_build() {
    [ "${1:-}" = "--pdfs" ] && CLI_BUILD_PDFS=1
    _walk_semester
}

cmd_readme() {
    local titles
    titles="$(mktemp)"
    _walk_semester "$titles"
    render_markdown_calendar "$SESSION_KINDS" "$SEMESTER_START_MONDAY" \
        "$NUM_WEEKS" "$RECESS_AFTER_WEEK" "$titles" "$ALLOWLIST" "$LABELS" "$NOTES" \
        "$PDF_BASE_URL" "$HOLIDAYS" "$EMOJI" "$KIND_EXTRA_LINKS" "$EXTRA_LINKS" "$OCCASION_LINKS" "$GRADED_SLOTS" "$EXTRA_SLOTS"
    rm -f "$titles"

    local key_events
    key_events="$(render_key_events_markdown "$KEY_EVENTS")"
    if [ -n "$key_events" ]; then
        printf '\n## Key Events\n\n%s\n' "$key_events"
    fi

    local term_window holidays_ref
    term_window="$(semester_term_window "$SEMESTER_START_MONDAY" "$NUM_WEEKS" "$RECESS_AFTER_WEEK")"
    holidays_ref="$(render_holidays_reference_markdown "$HOLIDAYS" "$EMOJI" "${term_window%%|*}" "${term_window##*|}")"
    if [ -n "$holidays_ref" ]; then
        printf '\n## Public Holidays Reference (Term Window)\n\n%s\n' "$holidays_ref"
    fi

    if [ -f "$RESOURCES_MD" ]; then
        printf '\n## Resources\n\n'
        cat "$RESOURCES_MD"
    fi
}

cmd_canvas() {
    local titles
    titles="$(mktemp)"
    _walk_semester "$titles"
    render_html_calendar "$SESSION_KINDS" "$SEMESTER_START_MONDAY" \
        "$NUM_WEEKS" "$RECESS_AFTER_WEEK" "$titles" "$ALLOWLIST" "$LABELS" "$NOTES" \
        "$PDF_BASE_URL" "$HOLIDAYS" "$EMOJI" "$CALENDAR_PALETTE" "" \
        "$KIND_EXTRA_LINKS" "$EXTRA_LINKS" "$OCCASION_LINKS" "$GRADED_SLOTS" "$EXTRA_SLOTS"
    rm -f "$titles"

    local key_events
    key_events="$(render_key_events_html "$KEY_EVENTS")"
    if [ -n "$key_events" ]; then
        printf '\n<h2>Key Events</h2>\n%s\n' "$key_events"
    fi

    if [ -f "$RESOURCES_HTML" ]; then
        printf '\n<h2>Resources</h2>\n'
        cat "$RESOURCES_HTML"
    fi
}

cmd_bump() {
    local slot_id="$1" variant="$2"
    local source_path
    source_path="$(_content_map_path "$slot_id")"
    if [ -z "$source_path" ] || [ ! -f "$source_path" ]; then
        echo "cli.sh bump: no content-map entry for $slot_id" >&2
        exit 1
    fi
    local content_hash
    content_hash="$(backend_content_hash "$source_path" "$variant" "$slot_id")"
    bump_slot_version "$slot_id" "$variant" "$content_hash"
}

case "${1:-}" in
    build) shift; cmd_build "$@" ;;
    readme) cmd_readme ;;
    canvas) cmd_canvas ;;
    bump) shift; cmd_bump "$@" ;;
    *)
        echo "Usage: $0 {build [--pdfs]|readme|canvas|bump SLOT_ID VARIANT}" >&2
        exit 1
        ;;
esac
