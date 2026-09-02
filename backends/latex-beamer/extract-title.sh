#!/bin/bash
# Usage: extract-title.sh SOURCE_PATH
# Pulls the \title{...} argument out of a Beamer-body source file, same
# regex approach as cs1101s/course-materials' date-utils.sh
# extract_latex_title. Returned as-is, including any leading slot-ID
# prefix the source's \title{} happens to embed (e.g. "L1A: Topic") --
# this script has no way to know what a course's slot IDs look like
# (that's session-kinds.conf's slot_pattern, not visible here), so it
# can't safely guess which prefixes to strip. core/render-*.sh's
# render_kind_cell is the one place that already knows both the slot ID
# and the title, so it's responsible for not double-prepending one.
set -euo pipefail
source_path="$1"
[ -f "$source_path" ] || { echo ""; exit 0; }
grep '\\title{' "$source_path" | head -1 | sed -n 's/.*\\title{\([^}]*\)}.*/\1/p'
