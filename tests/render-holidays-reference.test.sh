source "$TOOLKIT_DIR/core/render-holidays-reference.sh"

test_render_holidays_reference() {
    local scratch
    scratch="$(mktemp -d)"

    # Missing/empty file -- not an error, empty output.
    assert_eq "missing file is empty, not an error" \
        "" "$(render_holidays_reference_markdown "$scratch/nope.conf" "$scratch/nope-emoji.conf" 2026-01-01 2026-12-31)"
    local empty_holidays="$scratch/empty-holidays.conf"
    printf '# nothing yet\n\n' > "$empty_holidays"
    assert_eq "comment-only file is empty" \
        "" "$(render_holidays_reference_markdown "$empty_holidays" "$scratch/nope-emoji.conf" 2026-01-01 2026-12-31)"

    local holidays="$scratch/holidays.conf" emoji="$scratch/emoji.conf"
    cat > "$holidays" <<'EOF'
2026-08-09|National Day
2026-12-25|Christmas Day
2026-01-01|New Year's Day
EOF
    printf 'National Day|🇸🇬\n' > "$emoji"

    # Window covering only National Day (Aug) -- the other two (Jan,
    # Dec) fall outside it.
    local out
    out="$(render_holidays_reference_markdown "$holidays" "$emoji" 2026-08-01 2026-08-31)"
    assert_contains "header row" "$out" "| Date | Holiday |"
    assert_contains "in-window holiday with a mapped emoji" "$out" "| 2026-08-09 | 🇸🇬 National Day |"
    assert_not_contains "out-of-window holiday (Dec) excluded" "$out" "Christmas"
    assert_not_contains "out-of-window holiday (Jan) excluded" "$out" "New Year"

    # A holiday with no emoji mapping shows plain (no prefix).
    out="$(render_holidays_reference_markdown "$holidays" "$emoji" 2026-12-01 2026-12-31)"
    assert_contains "unmapped holiday has no emoji prefix" "$out" "| 2026-12-25 | Christmas Day |"

    # Sorted chronologically even though the source file wasn't.
    out="$(render_holidays_reference_markdown "$holidays" "$emoji" 2026-01-01 2026-12-31)"
    local jan_pos aug_pos dec_pos
    jan_pos=$(echo "$out" | grep -bo "New Year" | head -1 | cut -d: -f1)
    aug_pos=$(echo "$out" | grep -bo "National Day" | head -1 | cut -d: -f1)
    dec_pos=$(echo "$out" | grep -bo "Christmas" | head -1 | cut -d: -f1)
    assert_success "rows sorted chronologically, Jan before Aug" [ "$jan_pos" -lt "$aug_pos" ]
    assert_success "rows sorted chronologically, Aug before Dec" [ "$aug_pos" -lt "$dec_pos" ]

    # Window boundaries are inclusive.
    out="$(render_holidays_reference_markdown "$holidays" "$emoji" 2026-08-09 2026-08-09)"
    assert_contains "window start/end date itself is included (inclusive bounds)" \
        "$out" "National Day"

    # No holidays at all fall in the window -- empty output, not a
    # header-only table or a "nothing here" placeholder row (unlike
    # cs1101s/course-materials' own table, which prints a placeholder --
    # deliberately simpler here: cli.sh's caller just doesn't append a
    # heading at all when this returns empty).
    out="$(render_holidays_reference_markdown "$holidays" "$emoji" 2026-02-01 2026-02-28)"
    assert_eq "no holidays in window -> empty output" "" "$out"

    rm -rf "$scratch"
}
