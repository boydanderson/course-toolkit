#!/bin/bash
# Holiday-aware content placement: turns one curriculum-ordered list of
# content into the SLOT_ID-keyed files the rest of the toolkit reads
# (content map, graded slots, extra slots), so a holiday that cancels a
# session pushes every later item forward one session instead of
# dropping one -- and the graded marks and extra handouts move with the
# content they belong to rather than staying on a fixed slot ID.
#
# Built on schedule-lib.sh's CONTENT_LIST_FILE mechanism
# (content_ref_count): every row of a kind named in the order file is
# given a scratch content list, so a kind with several weekly rows
# (e.g. epp2's Mon-Tue and Wed-Fri sessions) shares one running
# sequence across all of them, in (week, file-row-order) order. Slot IDs
# stay week-derived; only which content lands in them moves.
#
# Order file format (CONTENT_ORDER_FILE, default
# config/content-order.conf), one line per item in curriculum order:
#   KIND_ID|SOURCE_PATH[|FLAGS]
#   +NAME|SOURCE_PATH[|FLAGS]
# A "+" line is an extra handout sharing the session of the nearest
# KIND_ID line above it; its slot ID is "<that slot>-NAME". FLAGS is a
# comma-separated list; "graded" is the only flag read today.

PLACEMENT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PLACEMENT_LIB_DIR/schedule-lib.sh"
source "$PLACEMENT_LIB_DIR/semester-lib.sh"

# place_content CONF_FILE ORDER_FILE HOLIDAYS_FILE START_MONDAY NUM_WEEKS
# RECESS_AFTER_WEEK -> one line per placed item, in calendar order:
#   SLOT_ID|SOURCE_PATH|FLAGS|WEEK|KIND_ID|SUFFIX|PARENT_SLOT_ID
# PARENT_SLOT_ID is empty for a KIND_ID line, and the slot it shares for
# a "+" line. Fails (1) with every unplaced item listed on stderr if the
# order file has more items than the kind has eligible sessions --
# content never silently falls off the end of term.
place_content() {
    local conf_file="$1" order_file="$2" holidays_file="$3"
    local start_monday="$4" num_weeks="$5" recess_after_week="$6"
    local tmp
    tmp="$(mktemp -d)"

    # entries: line i = KIND|PATH|FLAGS for the i-th KIND_ID line.
    # extras: ENTRY_INDEX|NAME|PATH|FLAGS.
    local entries="$tmp/entries" extras="$tmp/extras" kinds="$tmp/kinds"
    : > "$entries"; : > "$extras"; : > "$kinds"
    local a b c n=0
    while IFS='|' read -r a b c; do
        case "$a" in
            +*)
                if [ "$n" -eq 0 ]; then
                    echo "place_content: '+${a#+}' line before any KIND_ID line in $order_file" >&2
                    rm -rf "$tmp"
                    return 1
                fi
                printf '%s|%s|%s|%s\n' "$n" "${a#+}" "$b" "$c" >> "$extras"
                ;;
            *)
                n=$((n + 1))
                printf '%s|%s|%s\n' "$a" "$b" "$c" >> "$entries"
                # Content list per kind: the global entry numbers, so a
                # content_ref is directly a line number in $entries.
                echo "$n" >> "$tmp/list.$a"
                grep -qx "$a" "$kinds" || echo "$a" >> "$kinds"
                ;;
        esac
    done < <(grep -vE '^\s*#|^\s*$' "$order_file")

    # Scratch copy of CONF_FILE with each ordered kind's rows pointed at
    # its content list (field 14), padding short rows first and leaving
    # any later fields untouched.
    local tmp_conf="$tmp/session-kinds.conf"
    awk -F'|' -v OFS='|' -v dir="$tmp" -v kinds_file="$kinds" '
        BEGIN { while ((getline k < kinds_file) > 0) ordered[k] = 1 }
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
        ($1 in ordered) {
            while (NF < 13) { $(NF + 1) = "-" }
            $14 = dir "/list." $1
            print
            next
        }
        { print }
    ' "$conf_file" > "$tmp_conf"

    local week monday kind label slot date weekday suffix variants cancel_extra conflict content_ref rest
    local placed="$tmp/placed"
    : > "$placed"
    while IFS='|' read -r week monday; do
        while IFS='|' read -r kind label slot date weekday suffix variants cancel_extra conflict content_ref rest; do
            [ -n "$content_ref" ] || continue
            grep -qx "$kind" "$kinds" || continue
            local entry
            entry="$(sed -n "${content_ref}p" "$entries")"
            printf '%s|%s|%s|%s|%s|%s|\n' "$slot" "$(echo "$entry" | cut -d'|' -f2)" \
                "$(echo "$entry" | cut -d'|' -f3)" "$week" "$kind" "$suffix"
            echo "$content_ref" >> "$placed"
            awk -F'|' -v OFS='|' -v i="$content_ref" -v s="$slot" -v w="$week" -v k="$kind" -v x="$suffix" \
                '$1 == i { print s "-" $2, $3, $4, w, k, x, s }' "$extras"
        done < <(week_occurrences "$tmp_conf" "$monday" "$week" "$holidays_file" "$start_monday" "$recess_after_week")
    done < <(semester_weeks "$start_monday" "$num_weeks" "$recess_after_week")

    local i status=0
    for ((i = 1; i <= n; i++)); do
        grep -qx "$i" "$placed" && continue
        echo "place_content: no session left for $(sed -n "${i}p" "$entries" | cut -d'|' -f2) (item $i of $n)" >&2
        status=1
    done
    rm -rf "$tmp"
    return "$status"
}
