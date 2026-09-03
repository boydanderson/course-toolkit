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

    # is_graded_slot -- same allow-list shape, different purpose
    printf 'Studio8\nStudio14\n' > "$scratch/graded.conf"
    assert_success "is_graded_slot: listed ID" is_graded_slot Studio8 "$scratch/graded.conf"
    assert_failure "is_graded_slot: unlisted ID" is_graded_slot Studio1 "$scratch/graded.conf"
    assert_failure "is_graded_slot: missing file doesn't crash" is_graded_slot Studio8 "$scratch/nope.conf"

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

    # occurrence_holiday -- checks a primary date first, then optional
    # comma-separated extra dates (schedule-lib.sh's week_occurrences own
    # CANCEL_EXTRA_DATES output), for an occurrence spanning more than one
    # real calendar day (e.g. a studio meeting Monday AND Tuesday).
    assert_eq "occurrence_holiday: primary date matches, extra_dates never checked" \
        "NUS Well-Being Day" "$(occurrence_holiday 2026-10-09 "" "$scratch/holidays.conf")"
    assert_eq "occurrence_holiday: primary date is clean, extra date matches" \
        "NUS Well-Being Day" "$(occurrence_holiday 2026-10-08 2026-10-09 "$scratch/holidays.conf")"
    assert_eq "occurrence_holiday: primary clean, second of two extra dates matches" \
        "NUS Well-Being Day" "$(occurrence_holiday 2026-10-06 2026-10-07,2026-10-09 "$scratch/holidays.conf")"
    assert_failure "occurrence_holiday: neither primary nor any extra date matches" \
        occurrence_holiday 2026-10-06 2026-10-07,2026-10-08 "$scratch/holidays.conf"
    assert_failure "occurrence_holiday: empty extra_dates behaves exactly like plain is_holiday" \
        occurrence_holiday 2026-10-06 "" "$scratch/holidays.conf"

    # kind_extra_link_label / extra_link_for_slot
    printf 'lecture|Recording\n' > "$scratch/kind-extra-links.conf"
    assert_eq "kind_extra_link_label: match" "Recording" \
        "$(kind_extra_link_label lecture "$scratch/kind-extra-links.conf")"
    assert_eq "kind_extra_link_label: no match is empty, not an error" "" \
        "$(kind_extra_link_label studio "$scratch/kind-extra-links.conf")"
    assert_eq "kind_extra_link_label: missing file is empty, not an error" "" \
        "$(kind_extra_link_label lecture "$scratch/nope.conf")"

    printf 'L1A|https://example.edu/recordings/L1A\n' > "$scratch/extra-links.conf"
    assert_eq "extra_link_for_slot: match" "https://example.edu/recordings/L1A" \
        "$(extra_link_for_slot L1A "$scratch/extra-links.conf")"
    assert_eq "extra_link_for_slot: not-yet-listed slot is empty, not an error" "" \
        "$(extra_link_for_slot L1B "$scratch/extra-links.conf")"
    assert_eq "extra_link_for_slot: missing file is empty, not an error" "" \
        "$(extra_link_for_slot L1A "$scratch/nope.conf")"

    # occasion_links -- note the occasion's own title ("Reading
    # Assessment 1") lives in labels_file/slot_kind_label, a separate
    # lookup; this file's own fields are LINK labels ("Details",
    # "Papers"), not the occasion's title.
    cat > "$scratch/occasion-links.conf" <<'EOF'
4|lecture|Details|https://example.edu/ra1-details|Papers|https://example.edu/ra1-papers
6|lecture|Details||
7|lecture|Details|
EOF
    assert_eq "occasion_links: both links present" \
        "Details|https://example.edu/ra1-details|Papers|https://example.edu/ra1-papers" \
        "$(occasion_links 4 lecture "$scratch/occasion-links.conf")"
    assert_eq "occasion_links: a link label with no URL yet -- still returns the label" \
        "Details||" \
        "$(occasion_links 6 lecture "$scratch/occasion-links.conf")"
    assert_eq "occasion_links: a link label with a bare trailing pipe, no second link at all" \
        "Details|" "$(occasion_links 7 lecture "$scratch/occasion-links.conf")"
    assert_eq "occasion_links: no match is empty, not an error" "" \
        "$(occasion_links 5 lecture "$scratch/occasion-links.conf")"
    assert_eq "occasion_links: missing file is empty, not an error" "" \
        "$(occasion_links 4 lecture "$scratch/nope.conf")"

    # week_holiday_notes -- surfaces a holiday even when it doesn't land
    # on any day this course actually schedules an occurrence (unlike
    # is_holiday's per-occurrence cancellation above, which only fires
    # for a date that IS a scheduled occurrence).
    assert_eq "week_holiday_notes: a holiday on a day mid-week" \
        "⚠️ Friday: 🧘 NUS Well-Being Day" \
        "$(week_holiday_notes 2026-10-05 "$scratch/holidays.conf" "$scratch/emoji.conf")"
    assert_eq "week_holiday_notes: no holiday in this week's span is empty" \
        "" "$(week_holiday_notes 2026-09-28 "$scratch/holidays.conf" "$scratch/emoji.conf")"
    assert_eq "week_holiday_notes: missing holidays file is empty, not an error" \
        "" "$(week_holiday_notes 2026-10-05 "$scratch/nope.conf" "$scratch/emoji.conf")"

    printf '2026-10-06|Deepavali\n2026-10-09|NUS Well-Being Day\n' > "$scratch/multi-holidays.conf"
    assert_eq "week_holiday_notes: two holidays in one week, joined and in Mon..Sun order" \
        "⚠️ Tuesday: 🪔 Deepavali; ⚠️ Friday: 🧘 NUS Well-Being Day" \
        "$(week_holiday_notes 2026-10-05 "$scratch/multi-holidays.conf" "$scratch/emoji.conf")"

    printf '2026-10-06|Not Mapped Holiday\n' > "$scratch/unmapped-holiday.conf"
    assert_eq "week_holiday_notes: holiday with no emoji mapping still shows, no stray space" \
        "⚠️ Tuesday: Not Mapped Holiday" \
        "$(week_holiday_notes 2026-10-05 "$scratch/unmapped-holiday.conf" "$scratch/emoji.conf")"

    rm -rf "$scratch"
}
