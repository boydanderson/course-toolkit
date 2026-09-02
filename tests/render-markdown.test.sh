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

    rm -rf "$scratch"
}
