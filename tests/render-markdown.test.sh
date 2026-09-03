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

    assert_contains "a kind with 2 weekly occurrences splits into 2 real-weekday columns" \
        "$out" "| Week | Wednesday (Lecture A) | Friday (Lecture B) | Notes |"
    assert_contains "released slot with a title gets a real markdown link" \
        "$out" "[View](https://example.org/pdfs/lecture-L4A.view.pdf)"
    assert_contains "unreleased slot shows plain text, not a link" "$out" "L4B (View"
    assert_not_contains "unreleased slot has no markdown link syntax for itself" \
        "$(echo "$out" | grep '| 4 |')" "[View](https://example.org/pdfs/lecture-L4B"

    # GRADED_FILE (15th positional arg): marks a real occurrence's title
    # with a "🔴 " prefix.
    local graded="$scratch/graded.conf"
    printf 'L4A\n' > "$graded"
    out="$(render_markdown_calendar "$kinds" 2026-08-10 4 0 "$titles" "$allowlist" \
        /dev/null /dev/null https://example.org/pdfs /dev/null /dev/null \
        "" "" "" "$graded")"
    assert_contains "graded slot's title gets a 🔴 prefix" "$out" "🔴 L4A: A Real Title"
    assert_not_contains "non-graded slot (L4B) gets no prefix" \
        "$(echo "$out" | grep '| 4 |')" "🔴 L4B"

    # <br>-joining inside one cell is still real, tested code: it fires
    # whenever render_kind_cell's own occurrences_file has >1 row for the
    # given kind_id -- always true for a merged (no SUFFIX_FILTER) call,
    # which is what a single-occurrence-per-week kind (or a direct
    # render_kind_cell caller) still gets. render_markdown_calendar
    # itself no longer reaches this for a *declared* multi-occurrence
    # kind (those now split into columns above), so exercise it directly.
    local br_occ="$scratch/br-occurrences.tsv"
    cat > "$br_occ" <<'EOF'
lecture|Lecture|L4A|2026-09-02|wed|A|view,print
lecture|Lecture|L4B|2026-09-04|fri|B|view,print
EOF
    local br_cell
    br_cell="$(render_kind_cell 4 lecture "$br_occ" "$titles" "$allowlist" /dev/null https://example.org/pdfs /dev/null /dev/null)"
    assert_contains "render_kind_cell (no suffix filter) still joins multiple rows with <br>" \
        "$br_cell" "<br>"

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

    # CONFLICT_HOLIDAY (9th column in week_occurrences' own output, see
    # schedule-lib.sh's HOLIDAY_CONFLICT_WEEKS): overrides the
    # cancellation branch above entirely -- the occurrence renders
    # normally (title + links) with a "⚠️ " prefix instead, for a
    # collision the maintainer has already reviewed and decided to hold
    # anyway.
    local conflict_occ="$scratch/conflict-occurrences.tsv"
    printf 'lecture|Lecture|L4A|2026-08-14|wed|A|view,print||Test Holiday\n' > "$conflict_occ"
    local conflict_cell
    conflict_cell="$(render_kind_cell 4 lecture "$conflict_occ" "$titles" "$allowlist" /dev/null https://example.org/pdfs "$holidays" "$emoji")"
    assert_contains "CONFLICT_HOLIDAY: occurrence renders normally with the warning prefix" \
        "$conflict_cell" "⚠️ L4A: A Real Title"
    assert_not_contains "CONFLICT_HOLIDAY: does not show the usual cancellation text" \
        "$conflict_cell" "No Lecture"
    assert_contains "CONFLICT_HOLIDAY: still gets its real released links" \
        "$conflict_cell" "[View](https://example.org/pdfs/lecture-L4A.view.pdf)"

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

    # Extra link (Recording-style): _md_variant_links directly.
    local links
    links="$(_md_variant_links lecture L4A view https://x 1)"
    assert_not_contains "_md_variant_links: no extra_link_label means no extra link" \
        "$links" "Recording"

    links="$(_md_variant_links lecture L4A view https://x 1 Recording "")"
    assert_contains "_md_variant_links: label set, no URL yet -> plain unlinked text" \
        "$links" "[View](https://x/lecture-L4A.view.pdf) &middot; Recording"
    assert_not_contains "_md_variant_links: the extra link itself has no markdown link syntax" \
        "$links" "(Recording)"

    links="$(_md_variant_links lecture L4A view https://x 1 Recording https://panopto.example/L4A)"
    assert_contains "_md_variant_links: label + URL -> a real markdown link" \
        "$links" "[Recording](https://panopto.example/L4A)"

    # render_markdown_calendar end to end: kind_extra_links.conf declares
    # "lecture" gets a Recording link; extra-links.conf has a URL for
    # L4A (released, week 4) but not L4B (also week 4, unreleased) --
    # proves live-vs-pending through the whole call chain, and that an
    # unreleased slot's extra link still shows (unlinked), same as its
    # normal variant links do.
    local kind_extra_links="$scratch/kind-extra-links.conf"
    printf 'lecture|Recording\n' > "$kind_extra_links"
    local extra_links="$scratch/extra-links.conf"
    printf 'L4A|https://panopto.example/L4A\n' > "$extra_links"

    out="$(render_markdown_calendar "$kinds" 2026-08-10 4 0 "$titles" "$allowlist" \
        /dev/null /dev/null https://example.org/pdfs /dev/null /dev/null \
        "$kind_extra_links" "$extra_links")"
    assert_contains "render_markdown_calendar: L4A's recording is a real link" \
        "$out" "[Recording](https://panopto.example/L4A)"
    assert_contains "render_markdown_calendar: L4B's recording is plain text (not yet listed)" \
        "$out" "Print &middot; Recording"

    # Backward compat: omitting kind_extra_links_file entirely means no
    # kind gets an extra link at all, even ones with real occurrences.
    out="$(render_markdown_calendar "$kinds" 2026-08-10 4 0 "$titles" "$allowlist" \
        /dev/null /dev/null https://example.org/pdfs /dev/null /dev/null)"
    assert_not_contains "no kind_extra_links_file: no Recording links anywhere" \
        "$out" "Recording"

    # The actual Stage-5-discovered gap, markdown side: a kind with
    # several weekly occurrences (lecture A + B) where only ONE is
    # excluded a given week must show the occasion label ALONGSIDE the
    # occurrence that's still active, not lose it entirely -- see
    # render-html.test.sh's identical HTML-side test for the full
    # rationale.
    local kinds3="$scratch/session-kinds3.conf"
    printf 'lecture|Lecture|wed|A|L{n}{suffix}|view,print|1|13|-\n' > "$kinds3"
    printf 'lecture|Lecture|fri|B|L{n}{suffix}|view,print|1|13|4\n' >> "$kinds3"
    local occasion_labels="$scratch/occasion-labels.conf"
    printf '4|lecture|Reading Assessment 1\n' > "$occasion_labels"
    local occasion_links_conf="$scratch/occasion-links.conf"
    printf '4|lecture|Details|https://example.edu/ra1-details|Papers|https://example.edu/ra1-papers\n' \
        > "$occasion_links_conf"

    out="$(render_markdown_calendar "$kinds3" 2026-08-10 4 0 /dev/null /dev/null \
        "$occasion_labels" /dev/null https://example.org/pdfs /dev/null /dev/null \
        "" "" "$occasion_links_conf")"

    local week4_row
    week4_row="$(echo "$out" | grep '^| 4 |')"
    assert_contains "occasion: week 4's row still shows L4A (the non-excluded occurrence)" \
        "$week4_row" "L4A"
    assert_contains "occasion: week 4's row ALSO shows the occasion label" \
        "$week4_row" "Reading Assessment 1"
    assert_contains "occasion: the occasion's Details link is a real markdown link" \
        "$week4_row" "[Details](https://example.edu/ra1-details)"
    assert_contains "occasion: the occasion's Papers link is a real markdown link" \
        "$week4_row" "[Papers](https://example.edu/ra1-papers)"

    local week1_row
    week1_row="$(echo "$out" | grep '^| 1 |')"
    assert_not_contains "occasion: week 1 (no occasion configured) shows no occasion text" \
        "$week1_row" "Reading Assessment"
    assert_contains "occasion: week 1 still shows both L1A and L1B normally" "$week1_row" "L1A"
    assert_contains "occasion: week 1 still shows both L1A and L1B normally (2)" "$week1_row" "L1B"

    # No OCCASION_LINKS_FILE at all -- the plain label still shows (the
    # pre-existing slot_kind_label behavior), just no longer conditional
    # on the kind having zero occurrences.
    out="$(render_markdown_calendar "$kinds3" 2026-08-10 4 0 /dev/null /dev/null \
        "$occasion_labels" /dev/null https://example.org/pdfs /dev/null /dev/null)"
    week4_row="$(echo "$out" | grep '^| 4 |')"
    assert_contains "occasion: label still shows with no OCCASION_LINKS_FILE at all" \
        "$week4_row" "Reading Assessment 1"
    assert_not_contains "occasion: no Details/Papers text without the file" \
        "$week4_row" "Details"

    # Per-suffix labels: real gap found via epp2-toolkit-poc -- when
    # BOTH suffixes of a split kind are excluded the same week (e.g. a
    # "OT OT" Session 1 and a "Trial" Session 2), the plain WEEK|KIND_ID
    # key can't tell them apart; a suffix-qualified key
    # ("${KIND_ID}-${SUFFIX}") lets each column get its own label.
    local kinds4="$scratch/session-kinds4.conf"
    printf 'lecture|Lecture|wed|A|L{n}{suffix}|view,print|1|13|4\n' > "$kinds4"
    printf 'lecture|Lecture|fri|B|L{n}{suffix}|view,print|1|13|4\n' >> "$kinds4"
    local per_suffix_labels="$scratch/per-suffix-labels.conf"
    printf '4|lecture-A|OT OT\n4|lecture-B|Trial\n' > "$per_suffix_labels"
    out="$(render_markdown_calendar "$kinds4" 2026-08-10 4 0 /dev/null /dev/null \
        "$per_suffix_labels" /dev/null https://x /dev/null /dev/null)"
    local week4_row2
    week4_row2="$(echo "$out" | grep '^| 4 |')"
    assert_contains "per-suffix: Session 1 column shows its own label" "$week4_row2" "OT OT"
    assert_contains "per-suffix: Session 2 column shows its own (different) label" "$week4_row2" "Trial"

    # Backward compat: a plain (non-suffix-qualified) key still works
    # unchanged when only one suffix is excluded -- exactly the existing
    # "Reading Assessment 1" fixture above already covers this, but
    # confirm the fallback explicitly with a kind_id-only labels file
    # against the same per-suffix-capable fixture.
    local shared_label="$scratch/shared-label.conf"
    printf '4|lecture|Shared Label\n' > "$shared_label"
    out="$(render_markdown_calendar "$kinds4" 2026-08-10 4 0 /dev/null /dev/null \
        "$shared_label" /dev/null https://x /dev/null /dev/null)"
    week4_row2="$(echo "$out" | grep '^| 4 |')"
    local shared_label_count
    shared_label_count="$(echo "$week4_row2" | grep -o "Shared Label" | wc -l | tr -d ' ')"
    assert_eq "fallback: plain kind_id key shows in BOTH excluded suffixes' columns (unchanged pre-per-suffix behavior)" \
        "2" "$shared_label_count"

    # Recess row: inserted between teaching weeks RECESS_AFTER_WEEK and
    # RECESS_AFTER_WEEK+1 when RECESS_AFTER_WEEK > 0 -- matches
    # cs1101s/course-materials' own real row-insertion computation
    # (semester_recess_week, tested directly in semester-lib.test.sh).
    out="$(render_markdown_calendar "$kinds" 2026-08-10 4 2 "$titles" "$allowlist" \
        /dev/null /dev/null https://x /dev/null /dev/null)"
    assert_contains "recess row appears" "$out" \
        "| Recess | - | - | 🏖️ Recess Week - No classes (2026-08-24 - 2026-08-28) |"
    local recess_pos week2_pos week3_pos
    recess_pos=$(echo "$out" | grep -bo "^| Recess |" | head -1 | cut -d: -f1)
    week2_pos=$(echo "$out" | grep -bo "^| 2 |" | head -1 | cut -d: -f1)
    week3_pos=$(echo "$out" | grep -bo "^| 3 |" | head -1 | cut -d: -f1)
    assert_success "recess row sits after week 2" [ "$week2_pos" -lt "$recess_pos" ]
    assert_success "recess row sits before week 3" [ "$recess_pos" -lt "$week3_pos" ]

    # RECESS_AFTER_WEEK=0 (every test above) -- no recess row at all.
    assert_not_contains "no recess: no Recess row" \
        "$(render_markdown_calendar "$kinds" 2026-08-10 4 0 "$titles" "$allowlist" \
            /dev/null /dev/null https://x /dev/null /dev/null)" \
        "Recess"

    # CANCEL_EXTRA_WEEKDAYS: an occurrence declared mon + "tue" extra
    # must be cancelled by a holiday landing on EITHER day, not just its
    # own primary WEEKDAY -- the real studio Mon+Tue combined-cell need.
    local cew_kinds="$scratch/cew-kinds.conf"
    printf 'studio|Studio|mon|-|S{n}|view,print|1|13|-|-|tue\n' > "$cew_kinds"
    local cew_holidays="$scratch/cew-holidays.conf"
    printf '2026-08-11|Test Holiday\n' > "$cew_holidays"
    out="$(render_markdown_calendar "$cew_kinds" 2026-08-10 1 0 /dev/null /dev/null \
        /dev/null /dev/null https://x "$cew_holidays" /dev/null)"
    assert_contains "a holiday on the EXTRA weekday still cancels the occurrence" \
        "$out" "No Studio (Test Holiday)"

    printf '2026-08-10|Test Holiday\n' > "$cew_holidays"
    out="$(render_markdown_calendar "$cew_kinds" 2026-08-10 1 0 /dev/null /dev/null \
        /dev/null /dev/null https://x "$cew_holidays" /dev/null)"
    assert_contains "a holiday on the PRIMARY weekday still cancels the occurrence (unchanged)" \
        "$out" "No Studio (Test Holiday)"

    printf '2026-08-12|Test Holiday\n' > "$cew_holidays"
    out="$(render_markdown_calendar "$cew_kinds" 2026-08-10 1 0 /dev/null /dev/null \
        /dev/null /dev/null https://x "$cew_holidays" /dev/null)"
    assert_not_contains "a holiday on neither weekday doesn't cancel anything" \
        "$out" "No Studio"
    assert_contains "the occurrence still renders normally" "$out" "S1"

    # EXTRA_SLOTS_FILE: a studio's "-in-class" supplement shares the
    # week's regular occurrence -- grouped by matching title, kept
    # separate when titles genuinely differ (course-materials' own real
    # S3/S3-in-class vs S4/S4-in-class cases).
    local es_occ="$scratch/es-occurrences.tsv"
    printf 'studio|Studio|S3|2026-08-24|mon|-|view,print\n' > "$es_occ"
    local es_titles="$scratch/es-titles.conf"
    printf 'S3|A Title\nS3-in-class|A Title\n' > "$es_titles"
    local es_extra="$scratch/es-extra.conf"
    printf '3|studio|S3-in-class\n' > "$es_extra"
    out="$(render_kind_cell 3 studio "$es_occ" "$es_titles" /dev/null /dev/null https://x /dev/null /dev/null \
        "" "" "" "" "" "$es_extra")"
    assert_contains "matching-title extra slot merges into one title entry" "$out" "A Title ("
    assert_contains "merged entry labels each contributing slot" "$out" "S3: "
    assert_contains "merged entry labels the extra slot too" "$out" "S3-in-class: "

    local es_titles2="$scratch/es-titles2.conf"
    printf 'S3|Title A\nS3-in-class|Title B\n' > "$es_titles2"
    out="$(render_kind_cell 3 studio "$es_occ" "$es_titles2" /dev/null /dev/null https://x /dev/null /dev/null \
        "" "" "" "" "" "$es_extra")"
    assert_contains "different-title extra slot stays a separate entry (1)" "$out" "Title A ("
    assert_contains "different-title extra slot stays a separate entry (2)" "$out" "Title B ("
    assert_contains "different-title entries are NOT merged: separate blocks joined by <br>" \
        "$out" "<br>"
    assert_not_contains "different-title entries are NOT merged: no semicolon-joined sub-entries" \
        "$out" "; S3-in-class: "

    # No EXTRA_SLOTS_FILE, or none for this week+kind: identical to
    # today's plain single-entry output -- one cell_parts entry, no
    # semicolon-joined multi-slot form.
    out="$(render_kind_cell 3 studio "$es_occ" "$es_titles" /dev/null /dev/null https://x /dev/null /dev/null)"
    assert_contains "no extra_slots_file: plain single entry" "$out" "A Title ("
    assert_not_contains "no extra_slots_file: extra slot never looked up" "$out" "S3-in-class"

    out="$(render_kind_cell 4 studio "$es_occ" "$es_titles" /dev/null /dev/null https://x /dev/null /dev/null \
        "" "" "" "" "" "$es_extra")"
    assert_not_contains "extra_slots_file present but no entry for THIS week: unchanged" "$out" "S3-in-class"

    # render_markdown_calendar end to end: the 16th positional param
    # threads through to render_kind_cell. es_kinds2's slot_pattern
    # "S{n}" produces "S3" at teaching week 3 -- matches es_titles'/
    # es_extra's own "S3"/"S3-in-class"/week-3 fixtures above.
    local es_kinds2="$scratch/es-kinds2.conf"
    printf 'studio|Studio|mon|-|S{n}|view,print|1|13|-\n' > "$es_kinds2"
    out="$(render_markdown_calendar "$es_kinds2" 2026-08-10 3 0 "$es_titles" /dev/null \
        /dev/null /dev/null https://x /dev/null /dev/null "" "" "" "" "$es_extra")"
    local week3_row_es
    week3_row_es="$(echo "$out" | grep '^| 3 |')"
    assert_contains "render_markdown_calendar: EXTRA_SLOTS_FILE threads through end to end" \
        "$week3_row_es" "A Title ("

    # CONFLICT_HOLIDAY in the extra-slots-grouped code path too: bypasses
    # grouping entirely, same as a real cancellation already does in
    # this same loop (an extra slot sharing the cancelled primary's
    # title already rendered as its own separate, un-merged entry before
    # this change -- this is that exact existing behavior, extended to
    # the new conflict case, not a new inconsistency).
    local es_conflict_occ="$scratch/es-conflict-occurrences.tsv"
    printf 'studio|Studio|S3|2026-08-24|mon|-|view,print||CNY\n' > "$es_conflict_occ"
    out="$(render_kind_cell 3 studio "$es_conflict_occ" "$es_titles" /dev/null /dev/null https://x /dev/null /dev/null \
        "" "" "" "" "" "$es_extra")"
    assert_contains "CONFLICT_HOLIDAY in the extra-slots-grouped path renders with the warning prefix" \
        "$out" "⚠️ S3: A Title ("
    assert_contains "CONFLICT_HOLIDAY in the extra-slots-grouped path: extra slot still its own entry" \
        "$out" "S3-in-class: A Title ("
    assert_contains "render_markdown_calendar: the merged entry shows both slots" \
        "$week3_row_es" "S3-in-class: "

    # week_holiday_notes wired into the Notes column: a holiday that
    # lands on a day this kind doesn't meet (kinds is wed/fri; Thursday
    # is neither) must still surface in Notes, not silently disappear
    # the way is_holiday's per-occurrence cancellation alone would leave
    # it -- the real gap this was built to close.
    local nonclass_holidays="$scratch/nonclass-holidays.conf"
    printf '2026-08-13|Non-Class Holiday\n' > "$nonclass_holidays"
    out="$(render_markdown_calendar "$kinds" 2026-08-10 1 0 "$titles" "$allowlist" \
        /dev/null /dev/null https://example.org/pdfs "$nonclass_holidays" "$emoji")"
    assert_contains "a holiday on a non-class day still shows in Notes" \
        "$out" "⚠️ Thursday: Non-Class Holiday"
    assert_contains "a holiday on a non-class day doesn't cancel any occurrence" \
        "$out" "L1A"

    # Joins with an existing maintainer week_note via "; ", same
    # separator week_note itself already uses for multiple lines.
    local week_notes_file="$scratch/week-notes.conf"
    printf '1|Maintainer note\n' > "$week_notes_file"
    out="$(render_markdown_calendar "$kinds" 2026-08-10 1 0 "$titles" "$allowlist" \
        /dev/null "$week_notes_file" https://example.org/pdfs "$nonclass_holidays" "$emoji")"
    assert_contains "maintainer note and holiday note join with '; '" \
        "$out" "Maintainer note; ⚠️ Thursday: Non-Class Holiday"

    # All four Notes categories together, in fixed order (maintainer,
    # holiday, special date, key event) -- SPECIAL_DATES_FILE (17th) and
    # KEY_EVENTS_FILE (18th) are new optional trailing params.
    local special_dates_file="$scratch/special-dates.conf"
    printf '2026-08-11|Special Day\n' > "$special_dates_file"
    local key_events_file="$scratch/key-events.conf"
    printf '2026-08-12|10:00|12:00|Info Session\n' > "$key_events_file"
    out="$(render_markdown_calendar "$kinds" 2026-08-10 1 0 "$titles" "$allowlist" \
        /dev/null "$week_notes_file" https://example.org/pdfs "$nonclass_holidays" "$emoji" \
        "" "" "" "" "" "$special_dates_file" "$key_events_file")"
    assert_contains "all four Notes categories combine in the fixed order" \
        "$out" "Maintainer note; ⚠️ Thursday: Non-Class Holiday; 📅 Tuesday: Special Day; 📌 Wednesday: Info Session (10:00-12:00)"

    # Backward compat: omitting SPECIAL_DATES_FILE/KEY_EVENTS_FILE
    # entirely still behaves exactly as before Part A.
    out="$(render_markdown_calendar "$kinds" 2026-08-10 1 0 "$titles" "$allowlist" \
        /dev/null "$week_notes_file" https://example.org/pdfs "$nonclass_holidays" "$emoji")"
    assert_not_contains "no special_dates_file/key_events_file: no stray categories appear" \
        "$out" "📅"

    # SOURCE_LINKS_FILE: a course whose calendar links straight at its
    # own source repo (a .tex file on GitHub) rather than a built PDF
    # variant -- render_kind_cell's 16th positional param.
    local sl_occ="$scratch/sl-occurrences.tsv"
    printf 'lecture|Lecture|L1A|2026-08-12|wed|A|view,print\n' > "$sl_occ"
    local sl_titles="$scratch/sl-titles.conf"
    printf 'L1A|A Real Title\n' > "$sl_titles"
    local sl_sources="$scratch/sl-sources.conf"
    printf 'L1A|src/lectures/lecture-1.tex\n' > "$sl_sources"
    out="$(render_kind_cell 1 lecture "$sl_occ" "$sl_titles" /dev/null /dev/null https://x /dev/null /dev/null \
        "" "" "" "" "" "" "$sl_sources")"
    assert_contains "SOURCE_LINKS_FILE: a listed slot gets a single [source](path) link" \
        "$out" "[source](src/lectures/lecture-1.tex)"
    assert_not_contains "SOURCE_LINKS_FILE: no View/Print variant links when a source link is used" \
        "$out" "View"

    local sl_titles2="$scratch/sl-titles2.conf"
    printf 'L2A|Another Title\n' > "$sl_titles2"
    local sl_occ2="$scratch/sl-occurrences2.tsv"
    printf 'lecture|Lecture|L2A|2026-08-19|wed|A|view,print\n' > "$sl_occ2"
    out="$(render_kind_cell 2 lecture "$sl_occ2" "$sl_titles2" /dev/null /dev/null https://x /dev/null /dev/null \
        "" "" "" "" "" "" "$sl_sources")"
    assert_contains "SOURCE_LINKS_FILE: a slot with no entry falls through to normal variant links" \
        "$out" "View"
    assert_not_contains "SOURCE_LINKS_FILE: falls through cleanly, no stray [source] text" \
        "$out" "[source]"

    # SOURCE_LINKS_FILE combined with Stage 8's extra-slot grouping: each
    # contributing slot in a merged group gets its own source link.
    local sl_extra="$scratch/sl-extra.conf"
    printf '3|studio|S3-in-class\n' > "$sl_extra"
    local sl_studio_occ="$scratch/sl-studio-occurrences.tsv"
    printf 'studio|Studio|S3|2026-08-24|mon|-|view,print\n' > "$sl_studio_occ"
    local sl_studio_titles="$scratch/sl-studio-titles.conf"
    printf 'S3|A Title\nS3-in-class|A Title\n' > "$sl_studio_titles"
    local sl_studio_sources="$scratch/sl-studio-sources.conf"
    printf 'S3|src/studios/studio-S3.tex\nS3-in-class|src/studios/studio-S3-in-class.tex\n' > "$sl_studio_sources"
    out="$(render_kind_cell 3 studio "$sl_studio_occ" "$sl_studio_titles" /dev/null /dev/null https://x /dev/null /dev/null \
        "" "" "" "" "" "$sl_extra" "$sl_studio_sources")"
    assert_contains "SOURCE_LINKS_FILE + grouping: primary slot's source link" \
        "$out" "[source](src/studios/studio-S3.tex)"
    assert_contains "SOURCE_LINKS_FILE + grouping: extra slot's source link" \
        "$out" "[source](src/studios/studio-S3-in-class.tex)"

    # HOLIDAY_FIRST: swaps the cancellation phrase order -- 17th param.
    local hf_holidays="$scratch/hf-holidays.conf"
    printf '2026-08-12|Test Holiday\n' > "$hf_holidays"
    out="$(render_kind_cell 1 lecture "$sl_occ" "$sl_titles" /dev/null /dev/null https://x "$hf_holidays" /dev/null)"
    assert_contains "HOLIDAY_FIRST unset: today's default phrase order" \
        "$out" "No Lecture (Test Holiday)"
    out="$(render_kind_cell 1 lecture "$sl_occ" "$sl_titles" /dev/null /dev/null https://x "$hf_holidays" /dev/null \
        "" "" "" "" "" "" "" "1")"
    assert_contains "HOLIDAY_FIRST set: holiday-name-first phrase order" \
        "$out" "Test Holiday (No Lecture)"

    # render_markdown_calendar end to end: SOURCE_LINKS_FILE (19th) and
    # HOLIDAY_FIRST (20th) thread through to render_kind_cell.
    local sl_kinds="$scratch/sl-kinds.conf"
    printf 'lecture|Lecture|wed|A|L{n}{suffix}|view,print|1|13|-\n' > "$sl_kinds"
    out="$(render_markdown_calendar "$sl_kinds" 2026-08-10 1 0 "$sl_titles" /dev/null \
        /dev/null /dev/null https://x "$hf_holidays" /dev/null "" "" "" "" "" "" "" \
        "$sl_sources" "1")"
    assert_contains "render_markdown_calendar: HOLIDAY_FIRST threads through end to end" \
        "$out" "Test Holiday (No Lecture)"

    rm -rf "$scratch"
}
