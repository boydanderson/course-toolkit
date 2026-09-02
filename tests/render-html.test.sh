source "$TOOLKIT_DIR/core/render-html.sh"

test_render_html() {
    local scratch
    scratch="$(mktemp -d)"
    local kinds="$scratch/session-kinds.conf"
    printf 'lecture|Lecture|wed|A|L{n}{suffix}|view,print|1|13|-\n' > "$kinds"

    local titles="$scratch/titles.conf" allowlist="$scratch/allowlist.conf"
    printf 'L4A|A Real Title\n' > "$titles"
    printf 'L4A\n' > "$allowlist"

    local out
    out="$(render_html_calendar "$kinds" 2026-08-10 4 0 "$titles" "$allowlist" \
        /dev/null /dev/null https://example.org/pdfs /dev/null /dev/null)"

    assert_contains "well-formed table opens" "$out" "<table"
    assert_contains "well-formed table closes" "$out" "</table>"
    assert_contains "released slot gets a real <a> link" \
        "$out" '<a href="https://example.org/pdfs/lecture-L4A.view.pdf">View</a>'

    local open_tr close_tr
    open_tr="$(echo "$out" | grep -o '<tr>' | wc -l | tr -d ' ')"
    close_tr="$(echo "$out" | grep -o '</tr>' | wc -l | tr -d ' ')"
    assert_eq "balanced <tr>/</tr> tags" "$open_tr" "$close_tr"

    local holidays="$scratch/holidays.conf" emoji="$scratch/emoji.conf"
    printf '2026-08-12|Test Holiday\n' > "$holidays"
    printf 'Test Holiday|🎉\n' > "$emoji"
    out="$(render_html_calendar "$kinds" 2026-08-10 1 0 /dev/null /dev/null \
        /dev/null /dev/null https://x "$holidays" "$emoji")"
    assert_contains "holiday cancellation renders in the cancelled style" "$out" "No Lecture (🎉 Test Holiday)"
    assert_contains "cancellation is styled distinctly (bold red)" "$out" "$_S_CANCELLED"

    rm -rf "$scratch"
}
