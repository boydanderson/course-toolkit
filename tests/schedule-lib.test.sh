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
}
