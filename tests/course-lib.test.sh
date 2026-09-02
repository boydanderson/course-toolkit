source "$TOOLKIT_DIR/core/course-lib.sh"

test_course_lib() {
    local old_course_root="${COURSE_ROOT:-}"
    COURSE_ROOT="$TOOLKIT_DIR/tests/fixtures/demo101"

    assert_eq "get_course_var COURSE_CODE" "DEMO101" "$(get_course_var COURSE_CODE)"
    assert_eq "get_course_var RENDERER" "latex-beamer" "$(get_course_var RENDERER)"
    assert_eq "get_course_var of an unset key is empty, not an error" "" "$(get_course_var NOT_A_REAL_KEY)"

    COURSE_ROOT="$TOOLKIT_DIR/tests/fixtures/demo201"
    assert_eq "a different COURSE_ROOT reads its own course.mk" "DEMO201" "$(get_course_var COURSE_CODE)"

    COURSE_ROOT="$old_course_root"
}
