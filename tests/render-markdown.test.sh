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

    rm -rf "$scratch"
}
