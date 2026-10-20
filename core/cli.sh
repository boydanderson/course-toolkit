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
#   place             Regenerate CONTENT_MAP_FILE, GRADED_SLOTS_FILE and
#                     EXTRA_SLOTS_FILE from CONTENT_ORDER_FILE, holiday-
#                     aware: a cancelled session pushes every later item
#                     forward one session (see placement-lib.sh). Those
#                     three files are then generated -- edit the order
#                     file and re-run instead of editing them.
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
#   CONTENT_ORDER_FILE   default: config/content-order.conf (`place`
#                          only -- KIND_ID|SOURCE_PATH[|FLAGS] in
#                          curriculum order, see placement-lib.sh)
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
#                          the main calendar; see render-events.sh. Also
#                          fed into `readme`'s own Notes column -- see
#                          SPECIAL_DATES_FILE below)
#   SPECIAL_DATES_FILE    default: config/special-dates.conf (optional,
#                          DATE|NAME -- `readme` only. Surfaces a non-
#                          holiday calendar marker in the weekly Notes
#                          column, e.g. an institution's own academic-
#                          calendar entries; see enrich-lib.sh's
#                          week_special_date_notes/week_key_event_notes)
#   SOURCE_LINKS_FILE     default: config/source-links.conf (optional,
#                          SLOT_ID|PATH -- `readme` only. A slot with an
#                          entry renders a single "[source](PATH)" link
#                          instead of the usual View/Print/Sheet variant
#                          links, for a course whose calendar links
#                          straight at its own source repo rather than a
#                          built PDF; see enrich-lib.sh's
#                          source_link_for_slot)
#   HOLIDAY_FIRST         default: unset (optional, any non-empty value
#                          -- `readme` only). Swaps the holiday-
#                          cancellation phrase order from "No <Kind>
#                          (<holiday>)" to "<holiday> (No <Kind>)".
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
#   EXTRA_NOTE_FILE        default: config/extra-notes.conf (optional,
#                          SLOT_ID|HTML -- canvas only, one more line
#                          under a regular occurrence's title+links, e.g.
#                          a course-specific reading-list extraction step
#                          feeding this file; see enrich-lib.sh's
#                          extra_note_for_slot)
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
#   CALENDAR_ROW_ODD_BG, CALENDAR_ROW_EVEN_BG, CALENDAR_OCCASION_COLOR,
#   CALENDAR_CURRENT_WEEK_BG, CALENDAR_WEEK_BG
#                          `canvas`'s colors -- all optional, each falls
#                          back to render-html.sh's own default if unset
#                          (CALENDAR_LINK_COLOR and every key past
#                          CALENDAR_NOTES_COLOR all default to "", meaning
#                          "no override" -- a course gets no current-week
#                          highlight, row banding, occasion color, or
#                          distinct week-cell background unless it sets
#                          at least one of those keys;
#                          CALENDAR_CURRENT_WEEK_BG itself further falls
#                          back to CALENDAR_CURRENT_BG when unset). See
#                          README's "Customizing the calendar's colors".
#   CALENDAR_SHOW_WEEK_DATES  any non-empty value -> `canvas` shows a
#                          date-range sub-line under every week's number
#                          (e.g. "10 Aug – 14 Aug"). Unset/empty = off.
#   HOLIDAY_FIRST          any non-empty value -> both `readme` and
#                          `canvas` swap a cancelled occurrence's phrase
#                          order to "<holiday> (No <label>)" instead of
#                          "No <label> (<holiday>)". Unset/empty keeps
#                          the default order.
#   CALENDAR_COLUMN_WIDTHS comma-separated CSS width values (one per
#                          column: Week, then each kind column, then
#                          Notes) -> `canvas` emits a `<colgroup>` with
#                          those widths right after `<table>`. Unset =
#                          no `<colgroup>`, leaving widths to the
#                          browser.
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
source "$TOOLKIT_DIR/core/placement-lib.sh"

RENDERER="$(get_course_var RENDERER)"
export RENDERER

SESSION_KINDS="${SESSION_KINDS_FILE:-$COURSE_ROOT/config/session-kinds.conf}"
CONTENT_MAP="${CONTENT_MAP_FILE:-$COURSE_ROOT/config/content-map.conf}"
CONTENT_ORDER="${CONTENT_ORDER_FILE:-$COURSE_ROOT/config/content-order.conf}"
ALLOWLIST="${ALLOWLIST_FILE:-$COURSE_ROOT/config/release-allowlist.conf}"
LABELS="${LABELS_FILE:-$COURSE_ROOT/config/session-kind-labels.conf}"
NOTES="${NOTES_FILE:-$COURSE_ROOT/config/week-notes.conf}"
HOLIDAYS="${HOLIDAYS_FILE:-$COURSE_ROOT/config/holidays.conf}"
EMOJI="${EMOJI_FILE:-$COURSE_ROOT/config/holiday-emoji.conf}"
KEY_EVENTS="${KEY_EVENTS_FILE:-$COURSE_ROOT/config/key-events.conf}"
SPECIAL_DATES="${SPECIAL_DATES_FILE:-$COURSE_ROOT/config/special-dates.conf}"
SOURCE_LINKS="${SOURCE_LINKS_FILE:-$COURSE_ROOT/config/source-links.conf}"
HOLIDAY_FIRST="${HOLIDAY_FIRST:-}"
RESOURCES_HTML="${RESOURCES_HTML_FILE:-$COURSE_ROOT/config/canvas-resources.html}"
RESOURCES_MD="${RESOURCES_MD_FILE:-$COURSE_ROOT/config/readme-resources.md}"
KIND_EXTRA_LINKS="${KIND_EXTRA_LINKS_FILE:-$COURSE_ROOT/config/kind-extra-links.conf}"
EXTRA_LINKS="${EXTRA_LINKS_FILE:-$COURSE_ROOT/config/extra-links.conf}"
OCCASION_LINKS="${OCCASION_LINKS_FILE:-$COURSE_ROOT/config/occasion-links.conf}"
GRADED_SLOTS="${GRADED_SLOTS_FILE:-$COURSE_ROOT/config/graded-slots.conf}"
EXTRA_SLOTS="${EXTRA_SLOTS_FILE:-$COURSE_ROOT/config/kind-extra-slots.conf}"
EXTRA_NOTE="${EXTRA_NOTE_FILE:-$COURSE_ROOT/config/extra-notes.conf}"

SEMESTER_START_MONDAY="$(get_course_var SEMESTER_START_MONDAY)"
NUM_WEEKS="$(get_course_var NUM_WEEKS)"
RECESS_AFTER_WEEK="$(get_course_var RECESS_AFTER_WEEK)"
[ -z "$RECESS_AFTER_WEEK" ] && RECESS_AFTER_WEEK=0
PDF_BASE_URL="$(get_course_var PDF_BASE_URL)"

# Each field left blank here falls back to render-html.sh's own default
# (_calendar_palette) -- a course only overriding one color doesn't need
# to respecify the rest. Every field past CALENDAR_NOTES_COLOR defaults
# to "" either way -- a course gets no current-week highlight, row
# banding, occasion color, or distinct week-cell background unless it
# sets at least one of those keys.
CALENDAR_PALETTE="$(get_course_var CALENDAR_BORDER_COLOR)|$(get_course_var CALENDAR_HEADER_BG)|$(get_course_var CALENDAR_LINK_COLOR)|$(get_course_var CALENDAR_PENDING_COLOR)|$(get_course_var CALENDAR_CANCELLED_COLOR)|$(get_course_var CALENDAR_NOTES_COLOR)|$(get_course_var CALENDAR_CURRENT_BG)|$(get_course_var CALENDAR_CURRENT_BORDER_COLOR)|$(get_course_var CALENDAR_ROW_ODD_BG)|$(get_course_var CALENDAR_ROW_EVEN_BG)|$(get_course_var CALENDAR_OCCASION_COLOR)|$(get_course_var CALENDAR_CURRENT_WEEK_BG)|$(get_course_var CALENDAR_WEEK_BG)|$(get_course_var CALENDAR_RECESS_BG)"
CALENDAR_SHOW_WEEK_DATES="$(get_course_var CALENDAR_SHOW_WEEK_DATES)"
CALENDAR_COLUMN_WIDTHS="$(get_course_var CALENDAR_COLUMN_WIDTHS)"
CALENDAR_CANCELLED_NEWLINE="$(get_course_var CALENDAR_CANCELLED_NEWLINE)"

_content_map_path() {
    # || true: a scheduled slot with no content-map entry (unauthored,
    # or displaced by something the schedule doesn't structurally
    # exclude) is a normal state, not an error -- see enrich-lib.sh's
    # slot_title for the identical rationale.
    grep -vE '^\s*#|^\s*$' "$CONTENT_MAP" 2>/dev/null | grep "^${1}|" | head -1 | cut -d'|' -f2- || true
}

# _walk_slot KIND SLOT_ID VARIANTS [TITLES_OUT] -> one content-mapped
# slot's share of _walk_semester: extract its title (appended to
# TITLES_OUT as "SLOT_ID|TITLE" if given), track every variant's version,
# and compile each variant when CLI_BUILD_PDFS=1. A slot with no
# content-map entry (or a missing source file) is silently skipped.
_walk_slot() {
    local kind="$1" slot_id="$2" variants="$3" titles_out="${4:-}"
    local source_path
    source_path="$(_content_map_path "$slot_id")"
    [ -z "$source_path" ] || [ ! -f "$source_path" ] && return 0
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
}

# _walk_semester [TITLES_OUT] -> for every scheduled+content-mapped
# slot/variant this semester, track its version (always) and, if
# TITLES_OUT is given, append "SLOT_ID|TITLE" lines to it (truncated
# first). Shared by `build`, `readme`, and `canvas` so the latter two
# never depend on `build` having run first. A week's EXTRA_SLOTS_FILE
# slots are walked too, with the variants of the occurrence whose
# KIND_ID (or KIND_ID-SUFFIX) they're keyed by.
_walk_semester() {
    local titles_out="${1:-}"
    [ -n "$titles_out" ] && : > "$titles_out"
    local occ
    occ="$(mktemp)"
    while IFS='|' read -r teaching_week monday; do
        week_occurrences "$SESSION_KINDS" "$monday" "$teaching_week" "$HOLIDAYS" "$SEMESTER_START_MONDAY" "$RECESS_AFTER_WEEK" > "$occ"
        while IFS='|' read -r kind label slot_id date weekday suffix variants cancel_extra; do
            [ -z "$kind" ] && continue
            _walk_slot "$kind" "$slot_id" "$variants" "$titles_out"
        done < "$occ"
        [ -f "$EXTRA_SLOTS" ] || continue
        local es_key es_slot es_kind es_variants
        while IFS='|' read -r es_key es_slot; do
            es_kind="" es_variants=""
            IFS='|' read -r es_kind es_variants < <(awk -F'|' -v OFS='|' -v key="$es_key" \
                '$1 == key || $1 "-" $6 == key { print $1, $7; exit }' "$occ") || true
            [ -n "$es_kind" ] && _walk_slot "$es_kind" "$es_slot" "$es_variants" "$titles_out"
        done < <(grep -vE '^\s*#|^\s*$' "$EXTRA_SLOTS" | awk -F'|' -v OFS='|' -v w="$teaching_week" '$1 == w { print $2, $3 }')
    done < <(semester_weeks "$SEMESTER_START_MONDAY" "$NUM_WEEKS" "$RECESS_AFTER_WEEK")
    rm -f "$occ"
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
        "$PDF_BASE_URL" "$HOLIDAYS" "$EMOJI" "$KIND_EXTRA_LINKS" "$EXTRA_LINKS" "$OCCASION_LINKS" "$GRADED_SLOTS" "$EXTRA_SLOTS" \
        "$SPECIAL_DATES" "$KEY_EVENTS" "$SOURCE_LINKS" "$HOLIDAY_FIRST"
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
        "$KIND_EXTRA_LINKS" "$EXTRA_LINKS" "$OCCASION_LINKS" "$GRADED_SLOTS" "$EXTRA_SLOTS" "$EXTRA_NOTE" \
        "$SPECIAL_DATES" "$KEY_EVENTS" "$CALENDAR_SHOW_WEEK_DATES" "$HOLIDAY_FIRST" "$CALENDAR_COLUMN_WIDTHS" \
        "$CALENDAR_CANCELLED_NEWLINE"
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

# _write_if_changed TARGET NEW_FILE -> replaces TARGET with NEW_FILE only
# if their contents differ, so a no-op `place` never touches mtimes.
_write_if_changed() {
    local target="$1" new_file="$2"
    if [ -f "$target" ] && cmp -s "$target" "$new_file"; then
        echo "$(basename "$target") unchanged" >&2
    else
        cp "$new_file" "$target"
        echo "Updated $target" >&2
    fi
    rm -f "$new_file"
}

cmd_place() {
    if [ ! -f "$CONTENT_ORDER" ]; then
        echo "cli.sh place: no content order file at $CONTENT_ORDER" >&2
        exit 1
    fi
    local placed
    placed="$(mktemp)"
    if ! place_content "$SESSION_KINDS" "$CONTENT_ORDER" "$HOLIDAYS" \
        "$SEMESTER_START_MONDAY" "$NUM_WEEKS" "$RECESS_AFTER_WEEK" > "$placed"; then
        rm -f "$placed"
        echo "cli.sh place: more content than sessions -- nothing written" >&2
        exit 1
    fi
    local header="# GENERATED by \`cli.sh place\` from $(basename "$CONTENT_ORDER") -- do not hand-edit."
    local map graded extras
    map="$(mktemp)"; graded="$(mktemp)"; extras="$(mktemp)"
    { echo "$header"; echo "# SLOT_ID|SOURCE_PATH"; cut -d'|' -f1,2 "$placed"; } > "$map"
    { echo "$header"; echo "# SLOT_ID -- graded/assessed sessions";
      awk -F'|' '(","$3",") ~ /,graded,/ { print $1 }' "$placed"; } > "$graded"
    # An extra's key is suffix-qualified (e.g. session-S2) so it shows only
    # in its own session's column -- see enrich-lib.sh's kind_extra_slots.
    { echo "$header"; echo "# WEEK|KIND_ID|SLOT_ID -- extra handouts sharing a session";
      awk -F'|' -v OFS='|' '$7 != "" { print $4, ($6 == "-" ? $5 : $5 "-" $6), $1 }' "$placed"; } > "$extras"
    rm -f "$placed"
    _write_if_changed "$CONTENT_MAP" "$map"
    _write_if_changed "$GRADED_SLOTS" "$graded"
    _write_if_changed "$EXTRA_SLOTS" "$extras"
}

case "${1:-}" in
    build) shift; cmd_build "$@" ;;
    readme) cmd_readme ;;
    canvas) cmd_canvas ;;
    bump) shift; cmd_bump "$@" ;;
    place) cmd_place ;;
    *)
        echo "Usage: $0 {build [--pdfs]|readme|canvas|bump SLOT_ID VARIANT|place}" >&2
        exit 1
        ;;
esac
