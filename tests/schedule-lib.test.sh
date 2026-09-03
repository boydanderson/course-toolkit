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

    # Regression: a real bug found via epp2-toolkit-poc -- DAY_LABEL
    # (the 10th field) silently got absorbed into EXCLUDE_WEEKS by
    # occurrence_count's own row parser (only week_occurrences/
    # kind_suffixes were updated to expect a 10th field, not this one),
    # which broke the EXCLUDE_WEEKS match entirely and threw {count}'s
    # numbering off by one from the point of the first exclusion onward.
    # Combines {count} + EXCLUDE_WEEKS + DAY_LABEL on the same rows,
    # which no other test above does.
    local dlx_conf
    dlx_conf="$(mktemp)"
    {
        printf 'studio|Studio|mon|A|Studio{count}|instructor,student|1|4|3|Mon-Wed\n'
        printf 'studio|Studio|thu|B|Studio{count}|instructor,student|1|4|-|Thu-Fri\n'
    } > "$dlx_conf"
    out="$(week_occurrences "$dlx_conf" 2026-08-10 3)"
    assert_eq "DAY_LABEL doesn't break EXCLUDE_WEEKS: week 3's mon row is excluded, only thu's Studio5 remains" \
        "studio|Studio|Studio5|2026-08-13|thu|B|instructor,student|" "$out"
    out="$(week_occurrences "$dlx_conf" 2026-08-10 4 | head -1 | cut -d'|' -f3)"
    assert_eq "DAY_LABEL doesn't break {count}: week 4 mon is Studio6, no gap/shift from the exclusion" \
        "Studio6" "$out"
    rm -f "$dlx_conf"

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

    # CANCEL_EXTRA_WEEKDAYS (11th field): a studio meeting Monday AND
    # Tuesday with the same material declares WEEKDAY=mon,
    # CANCEL_EXTRA_WEEKDAYS=tue -- week_occurrences computes Tuesday's
    # real date too, carried in the new trailing CANCEL_EXTRA_DATES field.
    local cew_conf
    cew_conf="$(mktemp)"
    printf 'studio|Studio|mon|-|S{n}|view,print|1|13|-|-|tue\n' > "$cew_conf"
    out="$(week_occurrences "$cew_conf" 2026-08-10 1 | cut -d'|' -f8)"
    assert_eq "CANCEL_EXTRA_WEEKDAYS: single extra weekday's date is computed" \
        "2026-08-11" "$out"

    printf 'studio|Studio|mon|-|S{n}|view,print|1|13|-|-|tue,wed\n' > "$cew_conf"
    out="$(week_occurrences "$cew_conf" 2026-08-10 1 | cut -d'|' -f8)"
    assert_eq "CANCEL_EXTRA_WEEKDAYS: multiple extra weekdays, comma-joined dates" \
        "2026-08-11,2026-08-12" "$out"

    printf 'studio|Studio|mon|-|S{n}|view,print|1|13|-|-|-\n' > "$cew_conf"
    out="$(week_occurrences "$cew_conf" 2026-08-10 1 | cut -d'|' -f8)"
    assert_eq "CANCEL_EXTRA_WEEKDAYS: '-' means no extra dates, field stays empty" \
        "" "$out"

    printf 'studio|Studio|mon|-|S{n}|view,print|1|13|-\n' > "$cew_conf"
    out="$(week_occurrences "$cew_conf" 2026-08-10 1 | cut -d'|' -f8)"
    assert_eq "CANCEL_EXTRA_WEEKDAYS: field omitted entirely, still empty (backward compat)" \
        "" "$out"
    rm -f "$cew_conf"

    # AUTO_SHIFT_ON_HOLIDAY (12th field): a {count}-numbered kind skips a
    # holiday-colliding week entirely at placement time -- the content
    # that would have landed there shifts to the next eligible week,
    # cascading the same way an EXCLUDE_WEEKS week already does.
    local ash_conf ash_holidays
    ash_conf="$(mktemp)"
    ash_holidays="$(mktemp)"
    printf 'studio|Studio|mon|-|S{count}|view,print|1|3|-|-|-|1\n' > "$ash_conf"
    printf '2026-08-17|Test Holiday\n' > "$ash_holidays"
    out="$(week_occurrences "$ash_conf" 2026-08-10 1 "$ash_holidays" 2026-08-10 0)"
    assert_contains "AUTO_SHIFT_ON_HOLIDAY: week 1 (clean) still produces S1" "$out" "S1|"
    out="$(week_occurrences "$ash_conf" 2026-08-17 2 "$ash_holidays" 2026-08-10 0)"
    assert_eq "AUTO_SHIFT_ON_HOLIDAY: week 2 (holiday on its own Monday) produces nothing" \
        "" "$out"
    out="$(week_occurrences "$ash_conf" 2026-08-24 3 "$ash_holidays" 2026-08-10 0)"
    assert_contains "AUTO_SHIFT_ON_HOLIDAY: week 3 absorbs the shifted content as S2, not S3" \
        "$out" "S2|"

    # Backward compat: a row WITHOUT AUTO_SHIFT_ON_HOLIDAY set is
    # completely unaffected even when HOLIDAYS_FILE/START_MONDAY are
    # passed in -- the field is per-row opt-in.
    local noash_conf
    noash_conf="$(mktemp)"
    printf 'studio|Studio|mon|-|S{count}|view,print|1|3|-\n' > "$noash_conf"
    out="$(week_occurrences "$noash_conf" 2026-08-17 2 "$ash_holidays" 2026-08-10 0)"
    assert_contains "AUTO_SHIFT_ON_HOLIDAY unset: holiday week still produces the normal occurrence" \
        "$out" "S2|"
    rm -f "$noash_conf"

    # The collision may also come from CANCEL_EXTRA_WEEKDAYS (the *extra*
    # day, not the row's own primary WEEKDAY) -- still triggers a shift.
    local ash_extra_conf ash_extra_holidays
    ash_extra_conf="$(mktemp)"
    ash_extra_holidays="$(mktemp)"
    printf 'studio|Studio|mon|-|S{count}|view,print|1|3|-|-|tue|1\n' > "$ash_extra_conf"
    printf '2026-08-18|Test Holiday\n' > "$ash_extra_holidays"
    out="$(week_occurrences "$ash_extra_conf" 2026-08-17 2 "$ash_extra_holidays" 2026-08-10 0)"
    assert_eq "AUTO_SHIFT_ON_HOLIDAY: a collision on the CANCEL_EXTRA_WEEKDAYS day also shifts" \
        "" "$out"
    out="$(week_occurrences "$ash_extra_conf" 2026-08-24 3 "$ash_extra_holidays" 2026-08-10 0)"
    assert_contains "AUTO_SHIFT_ON_HOLIDAY: extra-day collision, week 3 absorbs it as S2" \
        "$out" "S2|"
    rm -f "$ash_extra_conf" "$ash_extra_holidays"

    # Two consecutive holiday weeks: the shift cascades past both, not
    # just the first.
    local ash_double_holidays
    ash_double_holidays="$(mktemp)"
    printf '2026-08-17|Holiday A\n2026-08-24|Holiday B\n' > "$ash_double_holidays"
    out="$(week_occurrences "$ash_conf" 2026-08-17 2 "$ash_double_holidays" 2026-08-10 0)"
    assert_eq "AUTO_SHIFT_ON_HOLIDAY: two consecutive holidays, week 2 produces nothing" "" "$out"
    out="$(week_occurrences "$ash_conf" 2026-08-24 3 "$ash_double_holidays" 2026-08-10 0)"
    assert_eq "AUTO_SHIFT_ON_HOLIDAY: two consecutive holidays, week 3 ALSO produces nothing" "" "$out"
    rm -f "$ash_double_holidays"

    # Hard error: AUTO_SHIFT_ON_HOLIDAY set on a row whose SLOT_PATTERN
    # has no {count} -- shifting only makes sense for a flat, week-
    # independent numbering.
    local ash_bad_conf
    ash_bad_conf="$(mktemp)"
    printf 'lecture|Lecture|wed|A|L{n}{suffix}|view,print|1|13|-|-|-|1\n' > "$ash_bad_conf"
    assert_failure "AUTO_SHIFT_ON_HOLIDAY without {count} in SLOT_PATTERN is a hard error" \
        week_occurrences "$ash_bad_conf" 2026-08-10 1 "$ash_holidays" 2026-08-10 0
    out="$(week_occurrences "$ash_bad_conf" 2026-08-10 1 "$ash_holidays" 2026-08-10 0 2>&1 >/dev/null)"
    assert_contains "AUTO_SHIFT_ON_HOLIDAY error message names the kind" "$out" "lecture"
    rm -f "$ash_bad_conf"

    # Recess interaction: occurrence_count's own multi-week re-scan must
    # derive each intermediate week's real calendar Monday via
    # semester_weeks (recess-gap aware), not naive +7-day arithmetic --
    # a holiday landing in the calendar week right after a recess gap
    # must still be found correctly.
    local ash_recess_conf ash_recess_holidays
    ash_recess_conf="$(mktemp)"
    ash_recess_holidays="$(mktemp)"
    printf 'studio|Studio|mon|-|S{count}|view,print|1|3|-|-|-|1\n' > "$ash_recess_conf"
    # start_monday=2026-08-10 (week1), recess after week 1 -> week 2's
    # real Monday is 2026-08-24 (one calendar week skipped), not
    # 2026-08-17 (naive +7).
    printf '2026-08-24|Recess-Adjacent Holiday\n' > "$ash_recess_holidays"
    out="$(week_occurrences "$ash_recess_conf" 2026-08-24 2 "$ash_recess_holidays" 2026-08-10 1)"
    assert_eq "AUTO_SHIFT_ON_HOLIDAY + recess: week 2's real (post-recess) Monday is checked" \
        "" "$out"
    out="$(week_occurrences "$ash_recess_conf" 2026-08-31 3 "$ash_recess_holidays" 2026-08-10 1)"
    assert_contains "AUTO_SHIFT_ON_HOLIDAY + recess: week 3 absorbs the shifted content as S2" \
        "$out" "S2|"
    rm -f "$ash_recess_conf" "$ash_recess_holidays"

    # available_slot_count: how many eligible occurrences exist for a
    # KIND_ID through a given week, merged across every row sharing that
    # KIND_ID -- a course's own build step compares this against real
    # authored content count and errors out itself if content doesn't
    # fit; this function only reports the number. $ash_conf (a single
    # studio|mon|- row, WEEK_END=3, AUTO_SHIFT_ON_HOLIDAY) + $ash_holidays
    # (holiday on week 2's Monday) are still in scope.
    assert_eq "available_slot_count: 3-week kind with 1 holiday-colliding week = 2 eligible" \
        "2" "$(available_slot_count "$ash_conf" studio 3 "$ash_holidays" 2026-08-10 0)"
    assert_eq "available_slot_count: no HOLIDAYS_FILE given, holiday never checked, all 3 eligible" \
        "3" "$(available_slot_count "$ash_conf" studio 3 "" 2026-08-10 0)"
    assert_eq "available_slot_count: no rows for this KIND_ID is 0" \
        "0" "$(available_slot_count "$ash_conf" reflection 3 "$ash_holidays" 2026-08-10 0)"
    assert_eq "available_slot_count: THROUGH_WEEK before any eligible week is 0" \
        "0" "$(available_slot_count "$ash_conf" studio 0 "$ash_holidays" 2026-08-10 0)"

    # Real regression: a KIND_ID with TWO rows sharing one merged
    # {count} sequence (epp2-toolkit-poc's real studio shape -- Session1/
    # Session2) -- confirmed for real that an earlier, per-ROW version of
    # this function silently returned the right answer only by
    # coincidence (when the queried row happened to be excluded/holiday-
    # colliding exactly at its own WEEK_END) and a wrong one otherwise.
    # mon/A: weeks 1,3 eligible (week 2 holiday-collides) = 2. thu/B: all
    # of weeks 1-3 eligible = 3. Merged in (week, row-order) sequence:
    # w1(mon)=1, w1(thu)=2, w2(mon)=skip, w2(thu)=3, w3(mon)=4, w3(thu)=5.
    local ash_multirow_conf
    ash_multirow_conf="$(mktemp)"
    {
        printf 'studio|Studio|mon|A|Studio{count}|instructor,student|1|3|-|-|-|1\n'
        printf 'studio|Studio|thu|B|Studio{count}|instructor,student|1|3|-\n'
    } > "$ash_multirow_conf"
    assert_eq "available_slot_count: merged total across two rows sharing one KIND_ID" \
        "5" "$(available_slot_count "$ash_multirow_conf" studio 3 "$ash_holidays" 2026-08-10 0)"
    rm -f "$ash_multirow_conf"

    rm -f "$ash_conf" "$ash_holidays"

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
