source "$TOOLKIT_DIR/institutions/nus/calendar-data-lib.sh"

test_institutions_nus() {
    # nus_recess_after_week: verified against real, matching data --
    # cs1101s/course-materials' AY2026/2027 Semester 1 (SEMESTER_START_DATE
    # 2026-08-12, a Wednesday; the Monday of that same week is
    # 2026-08-10) with its real fetched Recess Week dates
    # (2026-09-19..2026-09-27) -- both the old, retired
    # get_recess_week_number(2026-08-12) - 1 and this function give 6.
    NUS_SPECIAL_DATES=(
        "2026-09-19|Recess Week"
        "2026-09-20|Recess Week"
        "2026-09-21|Recess Week"
        "2026-09-22|Recess Week"
        "2026-09-23|Recess Week"
        "2026-09-24|Recess Week"
        "2026-09-25|Recess Week"
        "2026-09-26|Recess Week"
        "2026-09-27|Recess Week"
    )
    assert_eq "nus_recess_after_week: real CS1101S AY2026/2027 Sem 1 data -> 6" \
        "6" "$(nus_recess_after_week 2026-08-10)"

    # A second, later "Recess Week" block (e.g. Semester 2's, also in
    # the same fetched cache -- the parser now captures both semesters)
    # must be ignored in favor of the earliest one when computing a
    # Semester-1-anchored start's own recess.
    NUS_SPECIAL_DATES+=(
        "2027-02-20|Recess Week"
        "2027-02-21|Recess Week"
    )
    assert_eq "nus_recess_after_week: a later, unrelated recess block doesn't change the answer" \
        "6" "$(nus_recess_after_week 2026-08-10)"

    # No Recess Week entry at all -- a normal state (e.g. cache not yet
    # fetched, or a semester genuinely has none), not an error.
    NUS_SPECIAL_DATES=()
    assert_eq "nus_recess_after_week: no Recess Week entry -> 0" \
        "0" "$(nus_recess_after_week 2026-08-10)"

    # Reading Week entries (also stored in NUS_SPECIAL_DATES) must not
    # be mistaken for Recess Week.
    NUS_SPECIAL_DATES=("2026-11-15|Reading Week" "2026-11-16|Reading Week")
    assert_eq "nus_recess_after_week: Reading Week entries alone -> 0" \
        "0" "$(nus_recess_after_week 2026-08-10)"

    # A "recess" that predates the semester start entirely (a stale or
    # mismatched cache) is nonsense, not a real answer -- 0, not a
    # negative or wildly wrong week number.
    NUS_SPECIAL_DATES=("2025-01-01|Recess Week")
    assert_eq "nus_recess_after_week: recess predating semester start -> 0" \
        "0" "$(nus_recess_after_week 2026-08-10)"

    # nus_academic_semester: consolidates what used to be four
    # independently hand-rolled, silently inconsistent implementations
    # in cs1101s/course-materials (three thresholded on month >= 7,
    # contradicting their own "August" comments; one correctly used
    # >= 8) -- real regression coverage for exactly the case that used
    # to make them disagree.
    assert_eq "nus_academic_semester: August start -> Sem 1, AY starts this year" \
        "1|2026|2027" "$(nus_academic_semester 2026-08-12)"
    assert_eq "nus_academic_semester: December start -> still Sem 1" \
        "1|2026|2027" "$(nus_academic_semester 2026-12-01)"
    assert_eq "nus_academic_semester: January start -> Sem 2, AY started previous year" \
        "2|2025|2026" "$(nus_academic_semester 2026-01-15)"
    # The exact boundary case that used to disagree: canvas-hosting-
    # repo.sh (>= 8) called this Sem 2 of the AY that began the previous
    # August; build-studio.sh/generate-canvas-html.sh/new-semester-
    # reset.sh (>= 7) called it Sem 1 of the AY beginning THIS August.
    assert_eq "nus_academic_semester: July start -> Sem 2 (the regression case)" \
        "2|2025|2026" "$(nus_academic_semester 2026-07-15)"
}
