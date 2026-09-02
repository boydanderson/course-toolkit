source "$TOOLKIT_DIR/core/enrich-lib.sh"

test_enrich_lib() {
    local scratch
    scratch="$(mktemp -d)"

    # _capitalize
    assert_eq "_capitalize lowercases-then-caps first letter only" "Lecture" "$(_capitalize lecture)"

    # is_slot_released
    printf 'L1A\nL1B\n' > "$scratch/allowlist.conf"
    assert_success "is_slot_released: listed ID" is_slot_released L1A "$scratch/allowlist.conf"
    assert_failure "is_slot_released: unlisted ID" is_slot_released L2A "$scratch/allowlist.conf"
    assert_failure "is_slot_released: missing file doesn't crash" is_slot_released L1A "$scratch/nope.conf"

    # slot_title -- regression: must not abort under set -e when nothing matches
    printf 'L1A|Introduction\n' > "$scratch/titles.conf"
    assert_eq "slot_title: found" "Introduction" "$(slot_title L1A "$scratch/titles.conf")"
    ( set -e; slot_title L9Z "$scratch/titles.conf" > /dev/null )
    assert_eq "slot_title: not found doesn't abort under set -e" "0" "$?"

    # compose_slot_title -- regression: the double-prefix bug
    assert_eq "compose_slot_title: prepends when missing" \
        "L1A: Topic" "$(compose_slot_title L1A Topic)"
    assert_eq "compose_slot_title: does NOT double-prepend" \
        "L1A: Topic" "$(compose_slot_title L1A "L1A: Topic")"
    assert_eq "compose_slot_title: empty title falls back to slot ID" \
        "L1A" "$(compose_slot_title L1A "")"

    # slot_kind_label
    printf '7|reflection|R7: Special\n' > "$scratch/labels.conf"
    assert_eq "slot_kind_label: match" "R7: Special" "$(slot_kind_label 7 reflection "$scratch/labels.conf")"
    assert_eq "slot_kind_label: no match is empty" "" "$(slot_kind_label 7 lecture "$scratch/labels.conf")"

    # week_note -- regression: the IFS='; ' multi-char join bug (was
    # silently dropping the space and producing "a;b" instead of "a; b")
    printf '3|first note\n3|second note\n' > "$scratch/notes.conf"
    assert_eq "week_note joins multiple lines with '; ' (not just ';')" \
        "first note; second note" "$(week_note 3 "$scratch/notes.conf")"
    printf '4|only note\n' > "$scratch/single-note.conf"
    assert_eq "week_note: single line, no join needed" \
        "only note" "$(week_note 4 "$scratch/single-note.conf")"

    # is_holiday / holiday_emoji
    printf '2026-10-09|NUS Well-Being Day\n' > "$scratch/holidays.conf"
    printf "NUS Well-Being Day|🧘\nDeepavali|🪔\nNew Year's Day|🎉\n" > "$scratch/emoji.conf"
    assert_eq "is_holiday: match returns the name" \
        "NUS Well-Being Day" "$(is_holiday 2026-10-09 "$scratch/holidays.conf")"
    assert_failure "is_holiday: no match" is_holiday 2026-10-10 "$scratch/holidays.conf"
    assert_eq "holiday_emoji: exact match" "🧘" "$(holiday_emoji "NUS Well-Being Day" "$scratch/emoji.conf")"
    assert_eq "holiday_emoji: '(Observed)' suffix normalizes to the base holiday" \
        "🪔" "$(holiday_emoji "Deepavali (Observed)" "$scratch/emoji.conf")"
    assert_eq "holiday_emoji: no mapping is empty, not an error" \
        "" "$(holiday_emoji "Not A Real Holiday" "$scratch/emoji.conf")"
    assert_eq "holiday_emoji: a curly apostrophe normalizes to match a straight-apostrophe key" \
        "🎉" "$(holiday_emoji "New Year’s Day" "$scratch/emoji.conf")"

    rm -rf "$scratch"
}
