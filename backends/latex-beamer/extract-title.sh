#!/bin/bash
# Usage: extract-title.sh SOURCE_PATH
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
# Returned as-is, including any leading slot-ID prefix the source
# happens to embed (e.g. "L1A: Topic") -- this script has no way to know
# what a course's slot IDs look like (that's session-kinds.conf's
# slot_pattern, not visible here), so it can't safely guess which
# prefixes to strip. core/render-*.sh's render_kind_cell (via
# compose_slot_title) is the one place that already knows both the slot
# ID and the title, so it's responsible for not double-prepending one.
set -uo pipefail
source_path="$1"
[ -f "$source_path" ] || { echo ""; exit 0; }

title=$(grep '\\title{' "$source_path" 2>/dev/null | head -1 | sed -n 's/.*\\title{\([^}]*\)}.*/\1/p')
if [ -z "$title" ]; then
    title=$(grep '\\psetheader{' "$source_path" 2>/dev/null | head -1 \
        | sed -n 's/^\\psetheader{[^}]*}{[^}]*}{\(.*\)}$/\1/p')
fi
echo "$title"
