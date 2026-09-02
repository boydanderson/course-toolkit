#!/bin/bash
# Usage: extract-title.sh SOURCE_PATH [SLOT_ID]
# Pulls a display title out of a Beamer-body source file: \title{...} if
# present (same regex approach as cs1101s/course-materials' date-utils.sh
# extract_latex_title), else \psetheader{semester}{number}{title}'s third
# brace group (cs1101s/course-materials' studio/reflection convention,
# see that repo's date-utils.sh get_studio_reflection_title). Empty, not
# an error, if neither is present -- confirmed for real: a reflection/
# studio file has no \title{} at all, only \psetheader{}, so treating a
# failed \title{} grep as fatal (this script used to, under set -e)
# would abort on every single one of them.
#
# If SLOT_ID is given and the extracted title starts with the literal
# placeholder "PLACEHOLDER_SLOT: ", it's replaced with "SLOT_ID: " --
# the same substitution build-slot.sh applies to the compiled PDF, so
# the calendar/Canvas table's displayed title actually matches it,
# instead of showing the raw, unsubstituted placeholder text.
#
# Otherwise returned as-is, including any leading slot-ID prefix the
# source happens to already embed (e.g. "L1A: Topic") -- this script has
# no way to know what a course's slot IDs look like in general (that's
# session-kinds.conf's slot_pattern, not visible here), so beyond the
# one literal placeholder it can't safely guess which prefixes to strip.
# core/render-*.sh's render_kind_cell (via compose_slot_title) is the
# one place that already knows both the slot ID and the title, so it's
# responsible for not double-prepending one.
set -uo pipefail
source_path="$1"
slot_id="${2:-}"
[ -f "$source_path" ] || { echo ""; exit 0; }

# Strip the backslash off common LaTeX-escaped punctuation (e.g.
# "Recursion \& Iteration" -> "Recursion & Iteration") so a title reads
# correctly once it lands in Markdown/HTML -- neither destination wants
# the LaTeX escape itself, and HTML-escaping the result is the caller's
# job, not this script's.
_unescape_latex_title() {
    sed -E 's/\\([&%$#_{}])/\1/g'
}

title=$(grep '\\title{' "$source_path" 2>/dev/null | head -1 | sed -n 's/.*\\title{\([^}]*\)}.*/\1/p' | _unescape_latex_title)
if [ -z "$title" ]; then
    title=$(grep '\\psetheader{' "$source_path" 2>/dev/null | head -1 \
        | sed -n 's/^\\psetheader{[^}]*}{[^}]*}{\(.*\)}$/\1/p' | _unescape_latex_title)
fi
if [ -n "$slot_id" ] && [ "${title#PLACEHOLDER_SLOT: }" != "$title" ]; then
    title="${slot_id}: ${title#PLACEHOLDER_SLOT: }"
fi
echo "$title"
