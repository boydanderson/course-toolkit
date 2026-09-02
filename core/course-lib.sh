#!/bin/bash
# Reads a consuming course repo's config/course.mk -- course identity and
# which renderer backend it uses. Makefile-compatible (KEY = value lines,
# optional trailing "# comment") so the same file can be `include`d
# directly by Make, not just parsed here.
#
# Expected keys (a course repo's course.mk supplies these; nothing here
# enforces the set, matching this ecosystem's convention of config files
# documenting their own expected keys in a header comment rather than a
# schema validator):
#   COURSE_CODE   short code, e.g. CS1101S, CS2030S
#   COURSE_NAME   full name, e.g. "Programming Methodology"
#   HOSTING_ORG   GitHub org the public PDF hosting repo lives under
#   CANVAS_HOST   e.g. canvas.nus.edu.sg
#   RENDERER      which backends/ directory to dispatch into, e.g.
#                 latex-beamer
#
# COURSE_ROOT (env var, default ".") is the consuming repo's root -- see
# README's "Path resolution": this library never derives it from its own
# location, since it runs from inside a submodule.

# get_course_var KEY -> current value in COURSE_ROOT/config/course.mk,
# comment/whitespace stripped. Empty (not an error) if KEY isn't set --
# callers that require a value should check for that themselves.
get_course_var() {
    local key="$1"
    local course_root="${COURSE_ROOT:-.}"
    local course_mk="$course_root/config/course.mk"
    [ -f "$course_mk" ] || return 0
    # || true: a key not present in course.mk is a normal "unset, use my
    # own default" state for the caller, not an error -- without this, a
    # caller running under `set -o pipefail` (e.g. cli.sh) sees grep's
    # no-match exit status propagate through the pipe and abort under
    # `set -e`, even though sed (the pipeline's last command) exits 0.
    local raw
    raw="$(grep -E "^$key[[:space:]]*=" "$course_mk" | head -1 \
        | sed -E 's/^[A-Za-z_][A-Za-z_0-9]*[[:space:]]*=[[:space:]]*//' || true)"
    # A value that itself starts with '#' (e.g. a hex color like
    # "#123456") isn't a comment -- only strip a '#' that comes after at
    # least one character of real value, so CALENDAR_BORDER_COLOR = #fff
    # doesn't get eaten whole by the same rule that strips "KEY = value #
    # trailing note".
    case "$raw" in
        '#'*) raw="#$(printf '%s' "${raw#\#}" | sed -E 's/[[:space:]]*#.*$//')" ;;
        *) raw="$(printf '%s' "$raw" | sed -E 's/[[:space:]]*#.*$//')" ;;
    esac
    printf '%s' "$raw" | sed -E 's/[[:space:]]*$//'
}
