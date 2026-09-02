source "$TOOLKIT_DIR/core/render-markdown.sh"

test_render_markdown() {
    local scratch
    scratch="$(mktemp -d)"
    local kinds="$scratch/session-kinds.conf"
    printf 'lecture|Lecture|wed|A|L{n}{suffix}|view,print|1|13|-\n' > "$kinds"
    printf 'lecture|Lecture|fri|B|L{n}{suffix}|view,print|1|13|-\n' >> "$kinds"

    local titles="$scratch/titles.conf" allowlist="$scratch/allowlist.conf"
    printf 'L4A|A Real Title\n' > "$titles"
    printf 'L4A\n' > "$allowlist"

    local out
    out="$(render_markdown_calendar "$kinds" 2026-08-10 4 0 "$titles" "$allowlist" \
        /dev/null /dev/null https://example.org/pdfs /dev/null /dev/null)"

    assert_contains "header row lists both kinds once" "$out" "| Week | Lecture |"
    assert_contains "released slot with a title gets a real markdown link" \
        "$out" "[View](https://example.org/pdfs/lecture-L4A.view.pdf)"
    assert_contains "unreleased slot shows plain text, not a link" "$out" "L4B (View"
    assert_not_contains "unreleased slot has no markdown link syntax for itself" \
        "$(echo "$out" | grep '| 4 |')" "[View](https://example.org/pdfs/lecture-L4B"
    assert_contains "two occurrences in one week join with <br>" "$out" "<br>"

    # release-gate + label-override + holiday-cancellation, together
    local holidays="$scratch/holidays.conf" emoji="$scratch/emoji.conf" labels="$scratch/labels.conf"
    printf '2026-08-14|Test Holiday\n' > "$holidays"
    printf 'Test Holiday|🎉\n' > "$emoji"
    printf '2|lecture|Custom Label\n' > "$labels"

    local kinds2="$scratch/session-kinds2.conf"
    printf 'lecture|Lecture|fri|-|L{n}|view,print|3|13|-\n' > "$kinds2"
    out="$(render_markdown_calendar "$kinds2" 2026-08-10 4 0 /dev/null /dev/null \
        "$labels" /dev/null https://x /dev/null /dev/null)"
    assert_contains "week 2 (before WEEK_START=3) shows the label override" "$out" "Custom Label"

    out="$(render_markdown_calendar "$kinds" 2026-08-10 1 0 /dev/null /dev/null \
        /dev/null /dev/null https://x "$holidays" "$emoji")"
    assert_contains "a holiday date cancels that occurrence" "$out" "No Lecture (🎉 Test Holiday)"

    # render_kind_cell's awk filter against a MIXED occurrences file (all
    # three kinds present at once, as a real week_occurrences() call
    # would produce) -- every render-markdown test above only ever used
    # single-kind fixtures, so this filter was never actually exercised
    # against more than one kind's rows in the same file.
    local mixed_occ="$scratch/mixed-occurrences.tsv"
    cat > "$mixed_occ" <<'EOF'
studio|Studio|S4|2026-08-31|mon|-|problem,solution
lecture|Lecture|L4A|2026-09-02|wed|A|view,print
reflection|Reflection|R4|2026-09-03|thu|-|problem,solution
EOF
    local cell
    cell="$(render_kind_cell 4 lecture "$mixed_occ" /dev/null /dev/null /dev/null https://x /dev/null /dev/null)"
    assert_contains "render_kind_cell picks only the requested kind's row" "$cell" "L4A"
    assert_not_contains "render_kind_cell excludes other kinds' rows" "$cell" "S4"
    assert_not_contains "render_kind_cell excludes other kinds' rows (2)" "$cell" "R4"

    # variant "none" ("Sheet") and "problem,solution" -- every test above
    # only ever used "view,print".
    cell="$(render_kind_cell 4 studio "$mixed_occ" /dev/null /dev/null /dev/null https://x /dev/null /dev/null)"
    assert_contains "problem,solution variant shows Problem" "$cell" "Problem"
    assert_contains "problem,solution variant shows Solution" "$cell" "Solution"

    local none_occ="$scratch/none-occurrences.tsv"
    printf 'lab|Lab|LAB4|2026-09-02|wed|-|none\n' > "$none_occ"
    cell="$(render_kind_cell 4 lab "$none_occ" /dev/null /dev/null /dev/null https://x /dev/null /dev/null)"
    assert_contains "variants=none renders a single 'Sheet' label" "$cell" "Sheet"

    # A title containing markdown-significant characters is passed
    # through as-is (markdown output isn't HTML-escaped the way
    # render-html.sh's output is -- this just confirms it doesn't
    # silently mangle or drop the text).
    printf 'L4A|A & B < C\n' > "$titles"
    out="$(render_markdown_calendar "$kinds" 2026-08-10 4 0 "$titles" "$allowlist" \
        /dev/null /dev/null https://x /dev/null /dev/null)"
    assert_contains "special characters in a title pass through" "$out" "A & B < C"

    rm -rf "$scratch"
}
