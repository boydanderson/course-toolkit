source "$TOOLKIT_DIR/core/schedule-lib.sh"

test_schedule_lib() {
    local out

    # weekday_offset
    assert_eq "weekday_offset mon" "0" "$(weekday_offset mon)"
    assert_eq "weekday_offset sun" "6" "$(weekday_offset sun)"
    assert_eq "weekday_offset is case-insensitive" "2" "$(weekday_offset WED)"
    assert_failure "weekday_offset rejects garbage" weekday_offset notaday

    # format_slot_id
    assert_eq "format_slot_id with suffix" "L4A" "$(format_slot_id 'L{n}{suffix}' 4 A)"
    assert_eq "format_slot_id with '-' suffix drops it" "R7" "$(format_slot_id 'R{n}' 7 -)"

    # weekday_full_name
    assert_eq "weekday_full_name mon" "Monday" "$(weekday_full_name mon)"
    assert_eq "weekday_full_name is case-insensitive" "Wednesday" "$(weekday_full_name WED)"
    assert_failure "weekday_full_name rejects garbage" weekday_full_name notaday

    # _capitalize
    assert_eq "_capitalize lowercases-then-caps first letter only" "Lecture" "$(_capitalize lecture)"

    # kind_suffixes / kind_columns
    local ks_conf
    ks_conf="$(mktemp)"
    {
        printf 'lecture|Lecture|wed|A|L{n}{suffix}|view,print|1|13|-\n'
        printf 'lecture|Lecture|fri|B|L{n}{suffix}|view,print|1|13|-\n'
        printf 'quiz|Quiz|sat|-|Quiz{n}|view|5|9|-\n'
    } > "$ks_conf"
    out="$(kind_suffixes "$ks_conf" lecture)"
    assert_eq "kind_suffixes: lecture has 2 rows, in file order" \
        "A|wed|Lecture|
B|fri|Lecture|" "$out"
    out="$(kind_suffixes "$ks_conf" quiz)"
    assert_eq "kind_suffixes: a single-occurrence kind has exactly one row" "-|sat|Quiz|" "$out"

    out="$(kind_columns "$ks_conf")"
    assert_eq "kind_columns: a multi-occurrence kind splits, a single one doesn't" \
        "lecture|A|Wednesday (Lecture A)
lecture|B|Friday (Lecture B)
quiz||Quiz" "$out"
    rm -f "$ks_conf"

    # DAY_LABEL (optional 10th field): overrides a split column's
    # weekday header for a course whose real session isn't pinned to one
    # fixed day (e.g. "Session 1, some day Mon-Wed") -- WEEKDAY still has
    # to name one concrete day for the schedule engine's own date math.
    local dl_conf
    dl_conf="$(mktemp)"
    {
        printf 'studio|Studio|mon|A|Studio{count}|instructor,student|1|9|-|Mon-Wed\n'
        printf 'studio|Studio|thu|B|Studio{count}|instructor,student|1|9|-|Thu-Fri\n'
    } > "$dl_conf"
    out="$(kind_suffixes "$dl_conf" studio)"
    assert_eq "kind_suffixes: DAY_LABEL passes through as the 4th field" \
        "A|mon|Studio|Mon-Wed
B|thu|Studio|Thu-Fri" "$out"
    out="$(kind_columns "$dl_conf")"
    assert_eq "kind_columns: DAY_LABEL overrides the header's weekday portion" \
        "studio|A|Mon-Wed (Studio A)
studio|B|Thu-Fri (Studio B)" "$out"
    # A row's own WEEKDAY still drives real date math even when its
    # header is overridden -- DAY_LABEL is display-only.
    assert_eq "week_occurrences still uses the real WEEKDAY for date math, not DAY_LABEL" \
        "2026-08-10" "$(week_occurrences "$dl_conf" 2026-08-10 1 | head -1 | cut -d'|' -f4)"
    rm -f "$dl_conf"

    # occurrence_date
    assert_eq "occurrence_date mon = week_monday" "2026-08-10" "$(occurrence_date 2026-08-10 mon)"
    assert_eq "occurrence_date fri = +4 days" "2026-08-14" "$(occurrence_date 2026-08-10 fri)"

    # week_occurrences against the demo101 fixture (studio starts week 2)
    out="$(week_occurrences "$TOOLKIT_DIR/tests/fixtures/demo101/config/session-kinds.conf" 2026-08-10 1)"
    assert_not_contains "demo101 week 1 has no studio (starts week 2)" "$out" "studio|"
    assert_contains "demo101 week 1 has lecture L1A" "$out" "L1A"
    assert_contains "demo101 week 1 has lecture L1B" "$out" "L1B"
    assert_contains "demo101 week 1 has reflection R1" "$out" "R1"

    out="$(week_occurrences "$TOOLKIT_DIR/tests/fixtures/demo101/config/session-kinds.conf" 2026-08-17 2)"
    assert_contains "demo101 week 2 has studio S2" "$out" "S2"

    # EXCLUDE_WEEKS
    local excl_conf
    excl_conf="$(mktemp)"
    printf 'lecture|Lecture|wed|A|L{n}{suffix}|view,print|1|13|4,6,7\n' > "$excl_conf"
    out="$(week_occurrences "$excl_conf" 2026-08-10 4)"
    assert_eq "EXCLUDE_WEEKS 4 is skipped" "" "$out"
    out="$(week_occurrences "$excl_conf" 2026-08-10 5)"
    assert_contains "EXCLUDE_WEEKS: week 5 (not excluded) still occurs" "$out" "L5A"
    rm -f "$excl_conf"

    # demo201's different kind vocabulary
    out="$(week_occurrences "$TOOLKIT_DIR/tests/fixtures/demo201/config/session-kinds.conf" 2026-08-10 1)"
    assert_contains "demo201 has recitation (not in demo101's vocabulary)" "$out" "recitation|"
    assert_contains "demo201 has lab (not in demo101's vocabulary)" "$out" "lab|"

    # session_kind_ids dedupes multiple occurrence rows of the same kind
    out="$(session_kind_ids "$TOOLKIT_DIR/tests/fixtures/demo101/config/session-kinds.conf" | tr '\n' ' ')"
    assert_eq "session_kind_ids: 3 distinct kinds, lecture not doubled" "studio lecture reflection " "$out"

    # week_occurrences: a bad weekday must propagate as a real failure
    # (not silently produce a garbage/empty date), since a typo'd
    # session-kinds.conf row should be loud, not swallowed.
    local bad_conf
    bad_conf="$(mktemp)"
    printf 'lecture|Lecture|notaday|A|L{n}{suffix}|view,print|1|13|-\n' > "$bad_conf"
    assert_failure "week_occurrences propagates a bad weekday as a failure" \
        week_occurrences "$bad_conf" 2026-08-10 1
    out="$(week_occurrences "$bad_conf" 2026-08-10 1 2>&1 >/dev/null)"
    assert_contains "week_occurrences: bad-weekday error message names the kind" "$out" "lecture"
    rm -f "$bad_conf"

    # {count}: flat sequential numbering across occurrences, not
    # week-derived -- e.g. 2 labs/week (mon/A, thu/B) numbered Lab1..LabN
    # straight through, not Lab1A/Lab1B/Lab2A...
    local count_conf
    count_conf="$(mktemp)"
    {
        printf 'lab|Lab|mon|A|Lab{count}|instructor,student|1|9|-\n'
        printf 'lab|Lab|thu|B|Lab{count}|instructor,student|1|9|3\n'
    } > "$count_conf"
    out="$(week_occurrences "$count_conf" 2026-08-10 1)"
    assert_contains "week 1 mon lab is Lab1" "$out" "Lab1|"
    out="$(week_occurrences "$count_conf" 2026-08-10 1 | tail -1)"
    assert_contains "week 1 thu lab is Lab2" "$out" "Lab2|"
    out="$(week_occurrences "$count_conf" 2026-08-10 2 | head -1)"
    assert_contains "week 2 mon lab is Lab3" "$out" "Lab3|"
    out="$(week_occurrences "$count_conf" 2026-08-10 2 | tail -1)"
    assert_contains "week 2 thu lab is Lab4" "$out" "Lab4|"
    # week 3's thu occurrence is EXCLUDE_WEEKS'd out (e.g. a tutorial
    # takes that slot) -- the count must not reserve a gap for it.
    out="$(week_occurrences "$count_conf" 2026-08-10 3)"
    assert_contains "week 3 mon lab is Lab5 (only occurrence that week)" "$out" "Lab5|"
    out="$(week_occurrences "$count_conf" 2026-08-10 4 | head -1)"
    assert_contains "week 4 mon lab is Lab6 (no gap left by week 3's exclusion)" "$out" "Lab6|"
    out="$(week_occurrences "$count_conf" 2026-08-10 4 | tail -1)"
    assert_contains "week 4 thu lab is Lab7" "$out" "Lab7|"
    rm -f "$count_conf"

    # empty-or-comment-only conf files are a normal state (e.g. a course
    # with no session kinds declared yet), not an error.
    local empty_conf
    empty_conf="$(mktemp)"
    printf '# nothing here yet\n\n' > "$empty_conf"
    assert_eq "week_occurrences: comment-only conf yields no occurrences, not an error" \
        "" "$(week_occurrences "$empty_conf" 2026-08-10 1)"
    assert_eq "session_kind_ids: comment-only conf yields no kinds, not an error" \
        "" "$(session_kind_ids "$empty_conf")"
    rm -f "$empty_conf"
}
