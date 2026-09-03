#!/bin/bash
# Generic date/timezone utilities -- no schedule-kind or renderer
# concepts, just date arithmetic. Ported from cs1101s/course-materials'
# scripts/date-utils.sh (its add_days and sgt_date only -- that script's
# extract_latex_date/extract_latex_title are LaTeX-specific and belong in
# backends/latex-beamer/ instead, see Stage 3).

# add_days D N -> D + N calendar days (N may be negative), YYYY-MM-DD in,
# YYYY-MM-DD out. GNU and BSD/macOS `date` take incompatible flags, hence
# the branch.
add_days() {
    local d="$1" n="$2"
    if date -d "$d" '+%Y-%m-%d' >/dev/null 2>&1; then
        date -d "$d $n days" '+%Y-%m-%d'
    else
        if [[ "$n" =~ ^- ]]; then
            date -j -v"${n}d" -f "%Y-%m-%d" "$d" '+%Y-%m-%d'
        else
            date -j -v+"${n}d" -f "%Y-%m-%d" "$d" '+%Y-%m-%d'
        fi
    fi
}

# sgt_date FMT [BASE_EPOCH] -> Singapore time (UTC+8) for FMT (a `date`
# format string incl. leading "+"), as of BASE_EPOCH (Unix seconds;
# defaults to now -- pass a fixed epoch for deterministic builds).
# Computed by adding a fixed 8-hour offset to epoch seconds, never by
# asking `date`/TZ to look up "Asia/Singapore" in the system zoneinfo
# database -- that silently falls back to UTC inside minimal CI
# containers with no Singapore zoneinfo installed, while the output still
# claims "SGT" (confirmed for real in cs1101s/course-materials' CI).
# Singapore has used a fixed UTC+8 offset with no DST since 1982, so this
# manual arithmetic is always exactly correct and needs no zoneinfo file.
sgt_date() {
    local fmt="$1"
    local base_epoch="${2:-$(date -u +%s)}"
    local epoch=$(( base_epoch + 8 * 3600 ))
    if date -u -d "@$epoch" "$fmt" >/dev/null 2>&1; then
        date -u -d "@$epoch" "$fmt"
    else
        date -u -r "$epoch" "$fmt"
    fi
}

# day_of_week_name DATE -> full weekday name (e.g. "Wednesday"), same
# GNU/BSD `date` fallback as add_days above.
day_of_week_name() {
    date -d "$1" '+%A' 2>/dev/null || date -j -f "%Y-%m-%d" "$1" '+%A' 2>/dev/null
}
