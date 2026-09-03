source "$TOOLKIT_DIR/core/render-events.sh"

test_render_events() {
    local scratch
    scratch="$(mktemp -d)"

    # Missing file -- not an error, empty output.
    assert_eq "render_key_events_html: missing file is empty, not an error" \
        "" "$(render_key_events_html "$scratch/nope.conf")"
    assert_eq "render_key_events_markdown: missing file is empty, not an error" \
        "" "$(render_key_events_markdown "$scratch/nope.conf")"

    # Empty (comment-only) file -- same as missing.
    local empty_events="$scratch/empty-events.conf"
    printf '# nothing yet\n\n' > "$empty_events"
    assert_eq "render_key_events_html: comment-only file is empty" \
        "" "$(render_key_events_html "$empty_events")"
    assert_eq "render_key_events_markdown: comment-only file is empty" \
        "" "$(render_key_events_markdown "$empty_events")"

    # Real events, out of date order in the file -- must come out sorted.
    local events="$scratch/key-events.conf"
    cat > "$events" <<'EOF'
2026-11-25|09:00|11:00|Final Exam
2026-10-14|18:00|21:00|Sumobot Competition
EOF

    local html
    html="$(render_key_events_html "$events")"
    assert_contains "html: table opens" "$html" "<table"
    assert_contains "html: table closes" "$html" "</table>"
    assert_contains "html: header row" "$html" "<th style=\""
    assert_contains "html: Sumobot row present" "$html" "Sumobot Competition"
    assert_contains "html: Final Exam row present" "$html" "Final Exam"
    assert_contains "html: time range uses an en dash" "$html" "18:00&ndash;21:00"

    # Sort order: Sumobot (Oct) must appear before Final Exam (Nov) in
    # the rendered output, even though the source file listed Final Exam
    # first.
    local sumobot_pos exam_pos
    sumobot_pos=$(echo "$html" | grep -bo "Sumobot Competition" | head -1 | cut -d: -f1)
    exam_pos=$(echo "$html" | grep -bo "Final Exam" | head -1 | cut -d: -f1)
    assert_success "html: rows are sorted chronologically, not file order" \
        [ "$sumobot_pos" -lt "$exam_pos" ]

    local md
    md="$(render_key_events_markdown "$events")"
    assert_contains "markdown: header row (incl. Day)" "$md" "| Date | Day | Time | Event |"
    assert_contains "markdown: Sumobot row present, with its real weekday" \
        "$md" "2026-10-14 | Wednesday | 18:00-21:00 | Sumobot Competition"
    assert_contains "markdown: Final Exam row present, with its real weekday" \
        "$md" "2026-11-25 | Wednesday | 09:00-11:00 | Final Exam"

    # HTML never had a Day column (unlike markdown -- matches
    # cs1101s/course-materials' own real, asymmetric tables).
    assert_not_contains "html: no Day column, no weekday text leaking in" \
        "$html" "Wednesday"

    # Optional PALETTE: BORDER|HEADER_BG|ROW_ODD_BG|ROW_EVEN_BG -- with
    # no palette (every call above), the table is flat/unstriped; with
    # one, alternating rows get real background colors, matching
    # cs1101s/course-materials' own Key Events table styling.
    local striped
    striped="$(render_key_events_html "$events" "#cccccc|#f0f0f0|#ffffff|#fafafa")"
    assert_contains "html palette: header uses the given header_bg" "$striped" "background:#f0f0f0;"
    assert_contains "html palette: first row uses row_odd_bg" "$striped" "background:#ffffff;"
    assert_contains "html palette: second row uses row_even_bg" "$striped" "background:#fafafa;"
    assert_not_contains "html with no palette: no striping background at all" \
        "$html" "background:#fafafa;"

    # A '&'/'<' in an event name must come out escaped in HTML, raw in
    # markdown -- same convention as titles elsewhere in this toolkit.
    local special="$scratch/special-events.conf"
    printf '2026-12-01|10:00|11:00|Q&A <Session>\n' > "$special"
    assert_contains "html: event name is escaped" \
        "$(render_key_events_html "$special")" "Q&amp;A &lt;Session&gt;"
    assert_contains "markdown: event name passes through unescaped" \
        "$(render_key_events_markdown "$special")" "Q&A <Session>"

    rm -rf "$scratch"
}
