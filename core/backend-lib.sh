#!/bin/bash
# Dispatches into a course's chosen renderer backend
# (backends/$RENDERER/*.sh). core/ never contains renderer-specific
# logic itself -- everything that needs to know about the actual slide
# source format goes through these three calls.
#
# Simplified from the plan's original 4-function sketch: "extract_date"
# was dropped. The schedule engine (schedule-lib.sh) already computes
# every occurrence's calendar date authoritatively from
# config/session-kinds.conf -- re-extracting a date from a slot's own
# source content would just be a second, potentially-drifting source of
# truth for the same fact. Only "extract_title" is genuinely
# content-derived (a human-authored string the schedule can't know).
#
# A backend at backends/<name>/ implements exactly three scripts:
#   build-slot.sh SOURCE_PATH VARIANT OUTPUT_PATH [SLOT_ID]
#       Produce VARIANT's artifact for one slot at OUTPUT_PATH. SLOT_ID
#       (this slot's computed public ID, e.g. "L4A" -- optional, empty if
#       the caller doesn't have/want one) is for a backend that supports
#       injecting it into the source at build time (e.g. latex-beamer's
#       "PLACEHOLDER_SLOT" template substitution) -- a backend that
#       doesn't need this just ignores the argument.
#   content-hash.sh SOURCE_PATH VARIANT [SLOT_ID]
#       Print a hash of every input that affects this slot/variant's
#       output (the backend decides what counts -- e.g. shared preamble
#       files, not just SOURCE_PATH itself; SLOT_ID matters too for a
#       backend that substitutes it into the source, like latex-beamer's
#       PLACEHOLDER_SLOT).
#   extract-title.sh SOURCE_PATH
#       Print the slot's display title (empty if none), for calendar/
#       Canvas-page text.
#
# See backends/test/ for a minimal reference implementation (no real
# rendering -- useful as a template and for exercising this dispatcher
# without a real toolchain) and backends/latex-beamer/ for the real one.
#
# Requires TOOLKIT_DIR (where backends/ lives) and RENDERER (which
# backend to use, normally from a course's config/course.mk via
# course-lib.sh's get_course_var) to already be set by the caller.

_backend_script() {
    local script="$1"
    : "${TOOLKIT_DIR:?TOOLKIT_DIR must be set}"
    : "${RENDERER:?RENDERER must be set (see config/course.mk)}"
    local path="$TOOLKIT_DIR/backends/$RENDERER/$script"
    if [ ! -x "$path" ]; then
        echo "backend-lib: $path not found or not executable (RENDERER=$RENDERER)" >&2
        return 1
    fi
    echo "$path"
}

backend_build_slot() {
    local source_path="$1" variant="$2" output_path="$3" slot_id="${4:-}" script
    script="$(_backend_script build-slot.sh)" || return 1
    "$script" "$source_path" "$variant" "$output_path" "$slot_id"
}

backend_content_hash() {
    local source_path="$1" variant="$2" slot_id="${3:-}" script
    script="$(_backend_script content-hash.sh)" || return 1
    "$script" "$source_path" "$variant" "$slot_id"
}

backend_extract_title() {
    local source_path="$1" script
    script="$(_backend_script extract-title.sh)" || return 1
    "$script" "$source_path"
}
