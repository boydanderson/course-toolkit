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
    printf 'L1A\n' > "$scratch/config/release-allowlist.conf"

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
    assert_contains "cli canvas includes the real, substituted title" \
        "$canvas_out" "L1A: Sample Topic"
    assert_not_contains "cli canvas has no raw PLACEHOLDER_SLOT text" \
        "$canvas_out" "PLACEHOLDER_SLOT"
    assert_contains "cli canvas links an allow-listed slot's real PDF URL" \
        "$canvas_out" '<a href="https://demo-org.example.edu/pdfs/lecture-L1A.view.pdf">View</a>'

    # CALENDAR_* course.mk keys reach cli canvas's actual output --
    # proves the get_course_var -> CALENDAR_PALETTE -> render_html_calendar
    # wiring end to end, not just render-html.sh's own unit tests.
    printf '\nCALENDAR_BORDER_COLOR = #123456\nCALENDAR_LINK_COLOR = #0000ee\n' \
        >> "$scratch/config/course.mk"
    local colored_canvas_out
    colored_canvas_out="$(COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" \
        SESSION_KINDS_FILE="$scratch/config/session-kinds.conf" \
        CONTENT_MAP_FILE="$scratch/config/content-map.conf" \
        "$cli" canvas)"
    assert_contains "course.mk's CALENDAR_BORDER_COLOR reaches cli canvas" \
        "$colored_canvas_out" "border:1px solid #123456;"
    assert_contains "course.mk's CALENDAR_LINK_COLOR reaches cli canvas" \
        "$colored_canvas_out" '<a href="https://demo-org.example.edu/pdfs/lecture-L1A.view.pdf" style="color:#0000ee;">View</a>'

    assert_contains "cli bump moves the version forward" \
        "$(COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" \
            CONTENT_MAP_FILE="$scratch/config/content-map.conf" \
            "$cli" bump L1A view)" \
        "1.0 -> 1.1"

    assert_failure "cli with no command prints usage and fails" "$cli"
    assert_failure "cli with an unknown subcommand fails" \
        env COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" "$cli" not-a-real-command
    local usage_out
    usage_out="$(env COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" "$cli" not-a-real-command 2>&1 >/dev/null)"
    assert_contains "an unknown subcommand prints the usage line" "$usage_out" "Usage:"

    # bump requires both SLOT_ID and VARIANT -- under `set -u`, calling it
    # with too few args hits an unbound-variable error rather than
    # silently bumping the wrong thing.
    assert_failure "cli bump with no args fails, doesn't crash uncontrolled" \
        env COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" \
            CONTENT_MAP_FILE="$scratch/config/content-map.conf" "$cli" bump
    assert_failure "cli bump with only SLOT_ID (missing VARIANT) fails" \
        env COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" \
            CONTENT_MAP_FILE="$scratch/config/content-map.conf" "$cli" bump L1A

    rm -rf "$scratch"
}
