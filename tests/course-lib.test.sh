source "$TOOLKIT_DIR/core/course-lib.sh"

test_course_lib() {
    local old_course_root="${COURSE_ROOT:-}"
    COURSE_ROOT="$TOOLKIT_DIR/tests/fixtures/demo101"

    assert_eq "get_course_var COURSE_CODE" "DEMO101" "$(get_course_var COURSE_CODE)"
    assert_eq "get_course_var RENDERER" "latex-beamer" "$(get_course_var RENDERER)"
    assert_eq "get_course_var of an unset key is empty, not an error" "" "$(get_course_var NOT_A_REAL_KEY)"

    COURSE_ROOT="$TOOLKIT_DIR/tests/fixtures/demo201"
    assert_eq "a different COURSE_ROOT reads its own course.mk" "DEMO201" "$(get_course_var COURSE_CODE)"

    # A trailing "# comment" on a course.mk line is real, common
    # Makefile-comment style (see cs1101s/course-materials' own
    # config/course.mk header) -- never exercised by the fixture files,
    # which don't have any inline comments.
    local scratch
    scratch="$(mktemp -d)"
    mkdir -p "$scratch/config"
    cat > "$scratch/config/course.mk" <<'EOF'
COURSE_CODE = DEMO999  # this is a comment
RENDERER = latex-beamer# no space before the comment either
NUM_WEEKS = 13
EOF
    COURSE_ROOT="$scratch"
    assert_eq "get_course_var strips a trailing '# comment'" "DEMO999" "$(get_course_var COURSE_CODE)"
    assert_eq "get_course_var strips a comment with no leading space" \
        "latex-beamer" "$(get_course_var RENDERER)"
    assert_eq "get_course_var with no comment at all still works" "13" "$(get_course_var NUM_WEEKS)"

    # A value that itself starts with '#' (a hex color, e.g.
    # CALENDAR_BORDER_COLOR) must not be eaten whole by the trailing-
    # comment rule above -- regression: the comment-stripping regex used
    # to treat the leading '#' as "zero-length value, then a comment",
    # discarding the entire color.
    cat > "$scratch/config/course.mk" <<'EOF'
CALENDAR_BORDER_COLOR = #123456
CALENDAR_LINK_COLOR = #0000ee  # a real trailing comment after a hex value
EOF
    assert_eq "get_course_var: a value starting with '#' is kept, not stripped as a comment" \
        "#123456" "$(get_course_var CALENDAR_BORDER_COLOR)"
    assert_eq "get_course_var: a real trailing comment after a '#'-value is still stripped" \
        "#0000ee" "$(get_course_var CALENDAR_LINK_COLOR)"
    rm -rf "$scratch"

    COURSE_ROOT="$old_course_root"
}
