#!/bin/bash
# splice_markers -- replaces the content between two marker lines in a
# tracked file (e.g. README.md's own `<!-- CALENDAR_START -->` ...
# `<!-- CALENDAR_END -->`) with freshly generated content, in place.
#
# Ported from what was, before this existed, four near-identical
# hand-rolled awk blocks: cs1101s/course-materials'
# update-readme-with-calendar.sh and generate-lecture-list.sh, and
# epp2-toolkit-poc's update-readme.sh and update-file-list.sh -- each
# splicing a different generated section (a calendar table, a lecture/
# studio listing) into the same README.md by the same "find the start
# marker, dump new content, skip through to the end marker" convention,
# each with its own copy of the same guard (fail clearly if the markers
# are missing) and the same "no markers found" error wording.

# splice_markers FILE START_MARKER END_MARKER CONTENT_FILE -> in place,
# replaces everything between the lines containing START_MARKER and
# END_MARKER (both kept as-is) with CONTENT_FILE's own content. Matches
# markers by literal substring (awk's index(), not a regex), so a
# marker string containing regex-special characters still works
# correctly -- every real marker in this ecosystem happens not to
# contain any, but this doesn't rely on that being true. FILE must
# already contain a line with START_MARKER (checked up front, a clear
# error otherwise naming both markers and the file) -- same guard every
# hand-rolled version already had, so a maintainer who forgot to add
# the markers in the first place gets a clear message instead of a
# silently-unchanged file.
splice_markers() {
    local file="$1" start_marker="$2" end_marker="$3" content_file="$4"
    if ! grep -qF "$start_marker" "$file"; then
        echo "splice_markers: $start_marker/$end_marker markers not found in $file" >&2
        return 1
    fi
    local tmp
    tmp="$(mktemp)"
    awk -v start="$start_marker" -v end="$end_marker" -v contentfile="$content_file" '
        index($0, start) {
            print
            while ((getline line < contentfile) > 0) print line
            close(contentfile)
            f = 1
            next
        }
        index($0, end) { f = 0 }
        !f
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}
