test_cli() {
    local scratch
    scratch="$(mktemp -d)"
    mkdir -p "$scratch/config"
    cp "$TOOLKIT_DIR/tests/fixtures/demo101/config/course.mk" "$scratch/config/course.mk"
    printf 'lecture|Lecture|wed|A|L{n}{suffix}|view,print|1|13|-\n' > "$scratch/config/session-kinds.conf"
    # Absolute path -- content-map paths resolve relative to CWD at
    # runtime, not COURSE_ROOT, so this must work regardless of where
    # the test happens to run from.
    printf 'L1A|%s\n' "$TOOLKIT_DIR/tests/fixtures/demo101/L1A-body.tex" > "$scratch/config/content-map.conf"

    local cli="$TOOLKIT_DIR/core/cli.sh"

    assert_success "cli build walks the semester without error" \
        env COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" \
            SESSION_KINDS_FILE="$scratch/config/session-kinds.conf" \
            CONTENT_MAP_FILE="$scratch/config/content-map.conf" \
            "$cli" build

    assert_success "version ledger was actually written" \
        test -f "$scratch/config/versions.conf"
    assert_contains "L1A.view got tracked at 1.0" \
        "$(cat "$scratch/config/versions.conf")" "L1A.view|1.0"

    local readme_out
    readme_out="$(COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" \
        SESSION_KINDS_FILE="$scratch/config/session-kinds.conf" \
        CONTENT_MAP_FILE="$scratch/config/content-map.conf" \
        "$cli" readme)"
    assert_contains "cli readme includes the real, substituted title" \
        "$readme_out" "L1A: Sample Topic"
    assert_not_contains "cli readme has no raw PLACEHOLDER_SLOT text" \
        "$readme_out" "PLACEHOLDER_SLOT"

    local canvas_out
    canvas_out="$(COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" \
        SESSION_KINDS_FILE="$scratch/config/session-kinds.conf" \
        CONTENT_MAP_FILE="$scratch/config/content-map.conf" \
        "$cli" canvas)"
    assert_contains "cli canvas produces an HTML table" "$canvas_out" "<table"

    assert_contains "cli bump moves the version forward" \
        "$(COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" \
            CONTENT_MAP_FILE="$scratch/config/content-map.conf" \
            "$cli" bump L1A view)" \
        "1.0 -> 1.1"

    assert_failure "cli with no command prints usage and fails" "$cli"

    rm -rf "$scratch"
}
