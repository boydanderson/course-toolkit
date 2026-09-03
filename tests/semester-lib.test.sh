source "$TOOLKIT_DIR/core/semester-lib.sh"

test_semester_lib() {
    local out

    out="$(semester_weeks 2026-08-10 13 0)"
    assert_eq "no recess: week 1 monday" "1|2026-08-10" "$(echo "$out" | sed -n '1p')"
    assert_eq "no recess: week 2 monday is exactly +7 days" "2|2026-08-17" "$(echo "$out" | sed -n '2p')"
    assert_eq "no recess: 13 weeks produces 13 lines" "13" "$(echo "$out" | wc -l | tr -d ' ')"

    out="$(semester_weeks 2026-08-10 13 6)"
    assert_eq "recess after week 6: week 6 monday unaffected" "6|2026-09-14" "$(echo "$out" | sed -n '6p')"
    assert_eq "recess after week 6: week 7 monday skips a calendar week" "7|2026-09-28" "$(echo "$out" | sed -n '7p')"

    # semester_term_window: START_MONDAY - buffer through the last
    # teaching week's Friday + buffer (default buffer 7).
    assert_eq "semester_term_window: default 7-day buffer, recess included" \
        "2026-08-03|2026-11-20" "$(semester_term_window 2026-08-10 13 6)"
    assert_eq "semester_term_window: no recess (window shrinks by the 1 skipped calendar week)" \
        "2026-08-03|2026-11-13" "$(semester_term_window 2026-08-10 13 0)"
    assert_eq "semester_term_window: custom buffer=0 gives the exact term span" \
        "2026-08-10|2026-11-13" "$(semester_term_window 2026-08-10 13 6 0)"
}
