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

    # CALENDAR_ROW_ODD_BG (one of the 4 current-week/banding fields
    # appended after the original 6) -- deterministic, unlike
    # CALENDAR_CURRENT_BG, which cli.sh deliberately never lets a test
    # override (TODAY always means the real live date in production), so
    # testing it end-to-end through the CLI would depend on which week
    # the test happened to run in.
    printf '\nCALENDAR_ROW_ODD_BG = #f0f0f0\n' >> "$scratch/config/course.mk"
    local banded_canvas_out
    banded_canvas_out="$(COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" \
        SESSION_KINDS_FILE="$scratch/config/session-kinds.conf" \
        CONTENT_MAP_FILE="$scratch/config/content-map.conf" \
        "$cli" canvas)"
    assert_contains "course.mk's CALENDAR_ROW_ODD_BG reaches cli canvas" \
        "$banded_canvas_out" "background:#f0f0f0;"

    # Key Events / Resources: optional, config-driven, absent from
    # readme_out/canvas_out above since this scratch course has none of
    # the three files -- proves the feature is opt-in, not just that it
    # works when wired up.
    assert_not_contains "no key-events.conf: no Key Events section in readme" \
        "$readme_out" "Key Events"
    assert_not_contains "no key-events.conf: no Key Events section in canvas" \
        "$canvas_out" "Key Events"
    assert_not_contains "no resources file: no Resources section in readme" \
        "$readme_out" "Resources"
    assert_not_contains "no resources file: no Resources section in canvas" \
        "$canvas_out" "Resources"
    assert_not_contains "no holidays.conf: no Public Holidays Reference in readme" \
        "$readme_out" "Public Holidays Reference"

    printf '2026-10-14|18:00|21:00|Sumobot Competition\n' > "$scratch/config/key-events.conf"
    printf '<ul><li><a href="https://example.edu/faq">FAQ</a></li></ul>\n' \
        > "$scratch/config/canvas-resources.html"
    printf -- '- [FAQ](https://example.edu/faq)\n' > "$scratch/config/readme-resources.md"
    # 2026-10-19 falls inside this fixture's real term window (its
    # SEMESTER_START_MONDAY 2026-08-10 + 13 weeks + a week 6 recess ->
    # 2026-08-03..2026-11-20, per semester_term_window); 2026-12-25 is
    # deliberately outside it.
    printf '2026-10-19|Deepavali\n2026-12-25|Christmas Day\n' > "$scratch/config/holidays.conf"

    local readme_with_extras canvas_with_extras
    readme_with_extras="$(COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" \
        SESSION_KINDS_FILE="$scratch/config/session-kinds.conf" \
        CONTENT_MAP_FILE="$scratch/config/content-map.conf" \
        "$cli" readme)"
    canvas_with_extras="$(COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" \
        SESSION_KINDS_FILE="$scratch/config/session-kinds.conf" \
        CONTENT_MAP_FILE="$scratch/config/content-map.conf" \
        "$cli" canvas)"

    assert_contains "readme: Key Events heading appears once configured" \
        "$readme_with_extras" "## Key Events"
    assert_contains "readme: the actual event shows up" \
        "$readme_with_extras" "Sumobot Competition"
    assert_contains "readme: Resources heading appears once configured" \
        "$readme_with_extras" "## Resources"
    assert_contains "readme: the resources file's content is appended verbatim" \
        "$readme_with_extras" "[FAQ](https://example.edu/faq)"
    assert_contains "readme: Public Holidays Reference heading appears once configured" \
        "$readme_with_extras" "## Public Holidays Reference (Term Window)"
    assert_contains "readme: an in-window holiday shows up" \
        "$readme_with_extras" "Deepavali"
    assert_not_contains "readme: an out-of-window holiday is excluded" \
        "$readme_with_extras" "Christmas"
    assert_not_contains "canvas: Public Holidays Reference never appears (readme-only feature)" \
        "$canvas_with_extras" "Public Holidays Reference"

    assert_contains "canvas: Key Events heading appears once configured" \
        "$canvas_with_extras" "<h2>Key Events</h2>"
    assert_contains "canvas: the actual event shows up" \
        "$canvas_with_extras" "Sumobot Competition"
    assert_contains "canvas: Resources heading appears once configured" \
        "$canvas_with_extras" "<h2>Resources</h2>"
    assert_contains "canvas: the resources file's content is appended verbatim" \
        "$canvas_with_extras" '<a href="https://example.edu/faq">FAQ</a>'

    # Recording-style extra link, end to end through the CLI.
    printf 'lecture|Recording\n' > "$scratch/config/kind-extra-links.conf"
    printf 'L1A|https://panopto.example/L1A\n' > "$scratch/config/extra-links.conf"
    local canvas_with_recording readme_with_recording
    canvas_with_recording="$(COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" \
        SESSION_KINDS_FILE="$scratch/config/session-kinds.conf" \
        CONTENT_MAP_FILE="$scratch/config/content-map.conf" \
        "$cli" canvas)"
    readme_with_recording="$(COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" \
        SESSION_KINDS_FILE="$scratch/config/session-kinds.conf" \
        CONTENT_MAP_FILE="$scratch/config/content-map.conf" \
        "$cli" readme)"
    assert_contains "cli canvas: L1A's recording is a live link" \
        "$canvas_with_recording" 'href="https://panopto.example/L1A"'
    assert_contains "cli canvas: L1A's recording label is Recording" \
        "$canvas_with_recording" ">Recording</a>"
    assert_contains "cli readme: L1A's recording is a real markdown link" \
        "$readme_with_recording" "[Recording](https://panopto.example/L1A)"

    # Occasion label + links, end to end through the CLI -- week 1
    # already has a real L1A occurrence (this fixture's session-kinds.conf
    # has no excluded weeks), so this also proves the label shows
    # ALONGSIDE a real occurrence, not just in an otherwise-empty cell.
    printf '1|lecture|Special Session\n' > "$scratch/config/session-kind-labels.conf"
    printf '1|lecture|Details|https://example.edu/special-details|Papers|\n' \
        > "$scratch/config/occasion-links.conf"
    local canvas_with_occasion readme_with_occasion
    canvas_with_occasion="$(COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" \
        SESSION_KINDS_FILE="$scratch/config/session-kinds.conf" \
        CONTENT_MAP_FILE="$scratch/config/content-map.conf" \
        "$cli" canvas)"
    readme_with_occasion="$(COURSE_ROOT="$scratch" TOOLKIT_DIR="$TOOLKIT_DIR" \
        SESSION_KINDS_FILE="$scratch/config/session-kinds.conf" \
        CONTENT_MAP_FILE="$scratch/config/content-map.conf" \
        "$cli" readme)"
    assert_contains "cli canvas: occasion label shows alongside the real L1A occurrence" \
        "$canvas_with_occasion" "Special Session"
    assert_contains "cli canvas: L1A itself still shows too" \
        "$canvas_with_occasion" "L1A: Sample Topic"
    assert_contains "cli canvas: the occasion's live Details link shows" \
        "$canvas_with_occasion" 'href="https://example.edu/special-details"'
    assert_contains "cli canvas: the occasion's Papers link is pending (no URL yet)" \
        "$canvas_with_occasion" '<span style="color:#888888;">Papers</span>'
    assert_contains "cli readme: occasion label shows alongside the real L1A occurrence" \
        "$readme_with_occasion" "Special Session"
    assert_contains "cli readme: the occasion's live Details link shows" \
        "$readme_with_occasion" "[Details](https://example.edu/special-details)"

    # Kitchen sink: every config file set up above (CALENDAR_* colors,
    # row banding, Key Events, Resources, Recording, occasion label +
    # links) is still active in this same scratch course -- confirms all
    # 5 Stage 5.5 features compose correctly in one real render, not
    # just in isolation from each other.
    assert_contains "kitchen sink: CALENDAR_BORDER_COLOR" "$canvas_with_occasion" "border:1px solid #123456;"
    assert_contains "kitchen sink: CALENDAR_ROW_ODD_BG" "$canvas_with_occasion" "background:#f0f0f0;"
    assert_contains "kitchen sink: Key Events section" "$canvas_with_occasion" "<h2>Key Events</h2>"
    assert_contains "kitchen sink: Resources section" "$canvas_with_occasion" "<h2>Resources</h2>"
    assert_contains "kitchen sink: Recording link" "$canvas_with_occasion" 'href="https://panopto.example/L1A"'
    assert_contains "kitchen sink: occasion label" "$canvas_with_occasion" "Special Session"
    assert_contains "kitchen sink: real L1A occurrence still renders too" \
        "$canvas_with_occasion" "L1A: Sample Topic"
    assert_contains "kitchen sink (readme): Key Events section" "$readme_with_occasion" "## Key Events"
    assert_contains "kitchen sink (readme): Resources section" "$readme_with_occasion" "## Resources"
    assert_contains "kitchen sink (readme): Recording link" \
        "$readme_with_occasion" "[Recording](https://panopto.example/L1A)"

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
