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
    assert_contains "cancellation is styled distinctly (bold red)" "$out" "font-weight:600;color:#c0392b;"

    # _html_escape -- a title containing HTML-significant characters must
    # come out escaped, not passed through raw (which would either break
    # the table's markup or silently swallow the text depending on the
    # browser). No test above ever used a title with any of these.
    assert_eq "_html_escape: ampersand" "A &amp; B" "$(_html_escape <<< 'A & B')"
    assert_eq "_html_escape: angle brackets" "&lt;script&gt;" "$(_html_escape <<< '<script>')"
    printf 'L4A|Fish & Chips\n' > "$titles"
    out="$(render_html_calendar "$kinds" 2026-08-10 4 0 "$titles" "$allowlist" \
        /dev/null /dev/null https://x /dev/null /dev/null)"
    assert_contains "a title's ampersand is escaped in the real rendered table" "$out" "Fish &amp; Chips"
    assert_not_contains "the raw unescaped ampersand doesn't leak through" \
        "$(echo "$out" | grep 'Fish')" "Fish & Chips"

    # render_kind_cell_html's awk filter against a mixed occurrences
    # file, and the variants=none / problem,solution paths -- same gaps
    # as render-markdown.test.sh, HTML side.
    local mixed_occ="$scratch/mixed-occurrences.tsv"
    cat > "$mixed_occ" <<'EOF'
studio|Studio|S4|2026-08-31|mon|-|problem,solution
lecture|Lecture|L4A|2026-09-02|wed|A|view,print
reflection|Reflection|R4|2026-09-03|thu|-|problem,solution
EOF
    local cell
    cell="$(render_kind_cell_html 4 lecture "$mixed_occ" /dev/null /dev/null /dev/null https://x /dev/null /dev/null)"
    assert_contains "render_kind_cell_html picks only the requested kind's row" "$cell" "L4A"
    assert_not_contains "render_kind_cell_html excludes other kinds' rows" "$cell" "S4"

    local none_occ="$scratch/none-occurrences.tsv"
    printf 'lab|Lab|LAB4|2026-09-02|wed|-|none\n' > "$none_occ"
    cell="$(render_kind_cell_html 4 lab "$none_occ" /dev/null /dev/null /dev/null https://x /dev/null /dev/null)"
    assert_contains "variants=none renders a single 'Sheet' label" "$cell" "Sheet"

    # The rest of render-markdown.test.sh's coverage, re-exercised on the
    # HTML side -- these behavioral paths (multi-kind header columns, the
    # unreleased-slot span vs. released-slot link distinction, the
    # label-override cell, two occurrences in one week, and the Notes
    # column) were never actually driven through render_html_calendar
    # before, only through render_markdown_calendar.
    local kinds2="$scratch/session-kinds2.conf"
    printf 'lecture|Lecture|wed|A|L{n}{suffix}|view,print|1|13|-\n' > "$kinds2"
    printf 'lecture|Lecture|fri|B|L{n}{suffix}|view,print|1|13|-\n' >> "$kinds2"
    local allowlist2="$scratch/allowlist2.conf"
    printf 'L1A\n' > "$allowlist2"

    # num_weeks=1: exactly one row, so there's no ambiguity about which
    # week's cell a plain substring/div count is looking at.
    out="$(render_html_calendar "$kinds2" 2026-08-10 1 0 "$titles" "$allowlist2" \
        /dev/null /dev/null https://example.org/pdfs /dev/null /dev/null)"
    local th_count
    th_count="$(echo "$out" | grep -o '<th style=' | wc -l | tr -d ' ')"
    assert_eq "a kind with 2 weekly occurrences splits into 2 columns: Week + 2 x Lecture + Notes = 4 <th>s" "4" "$th_count"
    assert_contains "split columns are headered with the real weekday, like cs1101s' own convention" \
        "$out" "<th style=\"border:1px solid #dddddd;padding:6px 8px;background:#eeeeee;text-align:left;\">Wednesday (Lecture A)</th>"
    assert_contains "unreleased slot renders as a grey <span>, not a link" "$out" "<span style=\"color:#888888;\">View</span>"
    assert_not_contains "unreleased slot has no <a> for itself" \
        "$out" 'href="https://example.org/pdfs/lecture-L1B'
    assert_contains "released slot still gets a real <a> link" \
        "$out" '<a href="https://example.org/pdfs/lecture-L1A.view.pdf">View</a>'

    # GRADED_FILE (17th positional arg): marks a real occurrence's title
    # with a "🔴 " prefix.
    local graded="$scratch/graded.conf"
    printf 'L1A\n' > "$graded"
    local graded_out
    graded_out="$(render_html_calendar "$kinds2" 2026-08-10 1 0 "$titles" "$allowlist2" \
        /dev/null /dev/null https://example.org/pdfs /dev/null /dev/null \
        "" "" "" "" "" "$graded")"
    assert_contains "graded slot's title gets a 🔴 prefix" "$graded_out" "🔴 L1A"
    assert_not_contains "non-graded slot (L1B) gets no prefix" "$graded_out" "🔴 L1B"

    local occ_row_count
    occ_row_count="$(echo "$out" | grep -o '<div style="font-weight:600;">' | wc -l | tr -d ' ')"
    assert_eq "two occurrences in one week each get their own title <div>" "2" "$occ_row_count"

    local labels="$scratch/labels.conf"
    printf '2|lecture|Custom Label\n' > "$labels"
    local kinds3="$scratch/session-kinds3.conf"
    printf 'lecture|Lecture|fri|-|L{n}|view,print|3|13|-\n' > "$kinds3"
    out="$(render_html_calendar "$kinds3" 2026-08-10 4 0 /dev/null /dev/null \
        "$labels" /dev/null https://x /dev/null /dev/null)"
    assert_contains "week 2 (before WEEK_START=3) shows the label override" "$out" "Custom Label"

    local notes="$scratch/notes.conf"
    printf '1|A <special> & noted week\n' > "$notes"
    out="$(render_html_calendar "$kinds" 2026-08-10 1 0 "$titles" "$allowlist" \
        /dev/null "$notes" https://x /dev/null /dev/null)"
    assert_contains "a week note is escaped in the Notes column" "$out" "A &lt;special&gt; &amp; noted week"
    out="$(render_html_calendar "$kinds" 2026-08-10 1 0 /dev/null /dev/null \
        /dev/null /dev/null https://x /dev/null /dev/null)"
    assert_contains "a week with no note falls back to a bare '-' cell" "$out" '>-</td>'

    # Palette: no palette argument at all (omitted, matching every call
    # above) must still produce exactly today's hardcoded colors -- this
    # is the "old caller, unaware colors exist" backward-compat case.
    # kinds2/allowlist2 (from the earlier block above): L1A released,
    # L1B not.
    out="$(render_html_calendar "$kinds2" 2026-08-10 1 0 "$titles" "$allowlist2" \
        /dev/null /dev/null https://example.org/pdfs /dev/null /dev/null)"
    assert_contains "no palette arg: border/header still default" \
        "$out" 'border:1px solid #dddddd;padding:6px 8px;background:#eeeeee;'
    assert_contains "no palette arg: released link has no explicit color (inherits the page's)" \
        "$out" '<a href="https://example.org/pdfs/lecture-L1A.view.pdf">View</a>'

    # A course overriding only SOME fields (border, pending) keeps the
    # rest at their defaults -- proves _calendar_palette's per-field
    # fallback, not just "all six or none." Uses kinds2/allowlist2 (from
    # the earlier block above): L1A released, L1B not -- $kinds/$allowlist
    # only ever has one, always-released occurrence, so it can't exercise
    # the pending-color path at all.
    local partial_palette='#123456|||#abcdef|'
    out="$(render_html_calendar "$kinds2" 2026-08-10 1 0 "$titles" "$allowlist2" \
        /dev/null /dev/null https://example.org/pdfs /dev/null /dev/null "$partial_palette")"
    assert_contains "partial palette: overridden border takes effect" "$out" "border:1px solid #123456;"
    assert_contains "partial palette: un-overridden header_bg keeps its default" "$out" "background:#eeeeee;"
    assert_contains "partial palette: overridden pending color takes effect" \
        "$out" '<span style="color:#abcdef;">View</span>'
    assert_contains "partial palette: un-overridden notes color keeps its default" \
        "$out" 'color:#555555;'

    # A full palette override, including a real link color -- proves the
    # released-link path actually emits a style attribute when
    # CALENDAR_LINK_COLOR is set (the default leaves <a> unstyled).
    local full_palette='#111111|#222222|#0000ee|#999999|#ff0000|#333333'
    out="$(render_html_calendar "$kinds2" 2026-08-10 1 0 "$titles" "$allowlist2" \
        /dev/null /dev/null https://example.org/pdfs /dev/null /dev/null "$full_palette")"
    assert_contains "full palette: released link gets an explicit style" \
        "$out" '<a href="https://example.org/pdfs/lecture-L1A.view.pdf" style="color:#0000ee;">View</a>'
    assert_contains "full palette: cancelled style uses the override, not the default" \
        "$(render_html_calendar "$kinds" 2026-08-10 1 0 /dev/null /dev/null \
            /dev/null /dev/null https://x "$holidays" "$emoji" "$full_palette")" \
        "font-weight:600;color:#ff0000;"

    # Current-week highlighting + row banding: 4 weeks starting Monday
    # 2026-08-10 -- week 2 spans Mon 2026-08-17..Sun 2026-08-23. Palette
    # fields 6-9 (current_bg|current_border|row_odd_bg|row_even_bg),
    # verified by direct field-index inspection before writing this test
    # (bash's `read -ra` field-counting is exactly what broke this
    # feature's own implementation once already).
    local hl_palette='||||||#ffeeee|#ff0000|#f0f0f0|#e0e0e0'

    out="$(render_html_calendar "$kinds" 2026-08-10 4 0 /dev/null /dev/null \
        /dev/null /dev/null https://x /dev/null /dev/null "$hl_palette" 2026-08-20)"
    assert_contains "current-week: the matching week's cell uses current_bg" \
        "$out" "background:#ffeeee;"
    assert_contains "current-week: the matching week's number cell gets the border accent" \
        "$out" "border-left:4px solid #ff0000;"

    # Isolate week 2's own <tr>...</tr> block (each row is one giant
    # line -- see render-html.sh's own printf-without-newlines pattern)
    # to confirm the highlight lands on THAT week specifically, not just
    # somewhere in the table.
    local week2_row
    week2_row="$(echo "$out" | grep '>2</td>')"
    assert_contains "current-week: week 2's own row has the highlight" "$week2_row" "#ffeeee"
    local week1_row
    week1_row="$(echo "$out" | grep '>1</td>')"
    assert_not_contains "current-week: week 1's row does NOT get the highlight" "$week1_row" "#ffeeee"

    # Row banding on the non-current weeks: week 1 (odd) gets row_odd_bg,
    # week 3 (odd, after the current week 2) gets row_odd_bg too --
    # banding is by row_index, not by proximity to the current week.
    assert_contains "row banding: week 1 (odd) gets row_odd_bg" "$week1_row" "background:#f0f0f0;"
    local week4_row
    week4_row="$(echo "$out" | grep '>4</td>')"
    assert_contains "row banding: week 4 (even) gets row_even_bg" "$week4_row" "background:#e0e0e0;"

    # No TODAY arg (omitted) still works and doesn't crash -- exercises
    # the live sgt_date fallback path, even though the actual "is it
    # current" result depends on when the test runs.
    assert_success "render_html_calendar with no TODAY arg doesn't crash" \
        bash -c "source '$TOOLKIT_DIR/core/render-html.sh'; render_html_calendar '$kinds' 2026-08-10 1 0 /dev/null /dev/null /dev/null /dev/null https://x /dev/null /dev/null '$hl_palette' > /dev/null"

    # Backward compat: omitting the palette (or TODAY) entirely must
    # produce zero highlight/banding markup -- these features are opt-in.
    out="$(render_html_calendar "$kinds" 2026-08-10 4 0 /dev/null /dev/null \
        /dev/null /dev/null https://x /dev/null /dev/null)"
    assert_not_contains "no palette: no border-left accent appears anywhere" "$out" "border-left"
    assert_not_contains "no palette: no #ffeeee/current-week color appears" "$out" "#ffeeee"

    # Extra link (Recording-style): _html_variant_links directly.
    local links
    links="$(_html_variant_links lecture L1A view https://x 1 "" "")"
    assert_not_contains "_html_variant_links: no extra_link_label means no extra link" \
        "$links" "Recording"

    links="$(_html_variant_links lecture L1A view https://x 1 "" Recording "")"
    assert_contains "_html_variant_links: label set, no URL yet -> pending span" \
        "$links" '<span style="color:#888888;">Recording</span>'

    links="$(_html_variant_links lecture L1A view https://x 1 "" Recording "https://panopto.example/L1A")"
    assert_contains "_html_variant_links: label + URL -> a live link" \
        "$links" '<a href="https://panopto.example/L1A">Recording</a>'
    assert_contains "_html_variant_links: extra link comes after the normal variant link" \
        "$links" '<a href="https://x/lecture-L1A.view.pdf">View</a> &middot; <a href="https://panopto.example/L1A">Recording</a>'

    # render_html_calendar end to end: kind_extra_links.conf declares
    # "lecture" gets a Recording link; extra-links.conf has a URL for
    # L1A but not L1B -- proves the per-kind opt-in AND the
    # live-vs-pending distinction through the whole call chain.
    local kind_extra_links="$scratch/kind-extra-links.conf"
    printf 'lecture|Recording\n' > "$kind_extra_links"
    local extra_links="$scratch/extra-links.conf"
    printf 'L1A|https://panopto.example/L1A\n' > "$extra_links"

    out="$(render_html_calendar "$kinds2" 2026-08-10 1 0 "$titles" "$allowlist2" \
        /dev/null /dev/null https://example.org/pdfs /dev/null /dev/null \
        "" 2026-08-10 "$kind_extra_links" "$extra_links")"
    assert_contains "render_html_calendar: L1A's recording is a live link" \
        "$out" '<a href="https://panopto.example/L1A">Recording</a>'
    assert_contains "render_html_calendar: L1B's recording is pending (not yet listed)" \
        "$out" '<span style="color:#888888;">Recording</span>'

    # Backward compat: omitting kind_extra_links_file entirely means no
    # kind gets an extra link at all, even ones with real occurrences.
    out="$(render_html_calendar "$kinds2" 2026-08-10 1 0 "$titles" "$allowlist2" \
        /dev/null /dev/null https://example.org/pdfs /dev/null /dev/null)"
    assert_not_contains "no kind_extra_links_file: no Recording links anywhere" \
        "$out" "Recording"

    # The actual Stage-5-discovered gap: a kind with SEVERAL weekly
    # occurrences (lecture A + B) where only ONE is excluded a given
    # week (matching CS1101S's real config: Friday's slot excluded on
    # assessment weeks, Wednesday's still meets) must show the occasion
    # label ALONGSIDE the occurrence that's still active, not lose it
    # entirely (the old behavior: slot_kind_label only fired when the
    # WHOLE kind had zero occurrences that week).
    local kinds3="$scratch/session-kinds3.conf"
    printf 'lecture|Lecture|wed|A|L{n}{suffix}|view,print|1|13|-\n' > "$kinds3"
    printf 'lecture|Lecture|fri|B|L{n}{suffix}|view,print|1|13|4\n' >> "$kinds3"
    local occasion_labels="$scratch/occasion-labels.conf"
    printf '4|lecture|Reading Assessment 1\n' > "$occasion_labels"
    local occasion_links_conf="$scratch/occasion-links.conf"
    printf '4|lecture|Details|https://example.edu/ra1-details|Papers|https://example.edu/ra1-papers\n' \
        > "$occasion_links_conf"

    out="$(render_html_calendar "$kinds3" 2026-08-10 4 0 /dev/null /dev/null \
        "$occasion_labels" /dev/null https://example.org/pdfs /dev/null /dev/null \
        "" 2026-08-10 "" "" "$occasion_links_conf")"

    local week4_row
    week4_row="$(echo "$out" | grep '>4</td>')"
    assert_contains "occasion: week 4's cell still shows L4A (the non-excluded occurrence)" \
        "$week4_row" "L4A"
    assert_contains "occasion: week 4's cell ALSO shows the occasion label" \
        "$week4_row" "Reading Assessment 1"
    assert_contains "occasion: the occasion's Details link is live" \
        "$week4_row" '<a href="https://example.edu/ra1-details">Details</a>'
    assert_contains "occasion: the occasion's Papers link is live" \
        "$week4_row" '<a href="https://example.edu/ra1-papers">Papers</a>'

    local week1_row
    week1_row="$(echo "$out" | grep '>1</td>')"
    assert_not_contains "occasion: week 1 (no occasion configured) shows no occasion text" \
        "$week1_row" "Reading Assessment"
    assert_contains "occasion: week 1 still shows both L1A and L1B normally" \
        "$week1_row" "L1A"
    assert_contains "occasion: week 1 still shows both L1A and L1B normally (2)" \
        "$week1_row" "L1B"

    # A course with no OCCASION_LINKS_FILE still gets the plain label --
    # this is exactly the pre-existing slot_kind_label behavior, just no
    # longer conditional on the kind having zero occurrences.
    out="$(render_html_calendar "$kinds3" 2026-08-10 4 0 /dev/null /dev/null \
        "$occasion_labels" /dev/null https://example.org/pdfs /dev/null /dev/null)"
    week4_row="$(echo "$out" | grep '>4</td>')"
    assert_contains "occasion: label still shows with no OCCASION_LINKS_FILE at all" \
        "$week4_row" "Reading Assessment 1"
    assert_not_contains "occasion: no Details/Papers text without the file" \
        "$week4_row" "Details"

    # Per-suffix labels: real gap found via epp2-toolkit-poc -- when
    # BOTH suffixes of a split kind are excluded the same week, a
    # suffix-qualified key ("${KIND_ID}-${SUFFIX}") lets each column get
    # its own label instead of one shared WEEK|KIND_ID key.
    local kinds4="$scratch/session-kinds4.conf"
    printf 'lecture|Lecture|wed|A|L{n}{suffix}|view,print|1|13|4\n' > "$kinds4"
    printf 'lecture|Lecture|fri|B|L{n}{suffix}|view,print|1|13|4\n' >> "$kinds4"
    local per_suffix_labels="$scratch/per-suffix-labels.conf"
    printf '4|lecture-A|OT OT\n4|lecture-B|Trial\n' > "$per_suffix_labels"
    out="$(render_html_calendar "$kinds4" 2026-08-10 4 0 /dev/null /dev/null \
        "$per_suffix_labels" /dev/null https://x /dev/null /dev/null)"
    local week4_row2
    week4_row2="$(echo "$out" | grep '>4</td>')"
    assert_contains "per-suffix: Session 1 column shows its own label" "$week4_row2" "OT OT"
    assert_contains "per-suffix: Session 2 column shows its own (different) label" "$week4_row2" "Trial"

    # Backward compat: a plain (non-suffix-qualified) key still shows in
    # BOTH excluded suffixes' columns, unchanged from before this feature.
    local shared_label="$scratch/shared-label.conf"
    printf '4|lecture|Shared Label\n' > "$shared_label"
    out="$(render_html_calendar "$kinds4" 2026-08-10 4 0 /dev/null /dev/null \
        "$shared_label" /dev/null https://x /dev/null /dev/null)"
    week4_row2="$(echo "$out" | grep '>4</td>')"
    local shared_label_count
    shared_label_count="$(echo "$week4_row2" | grep -o "Shared Label" | wc -l | tr -d ' ')"
    assert_eq "fallback: plain kind_id key shows in BOTH excluded suffixes' columns" \
        "2" "$shared_label_count"

    # Recess row: inserted between teaching weeks RECESS_AFTER_WEEK and
    # RECESS_AFTER_WEEK+1 when RECESS_AFTER_WEEK > 0 -- same dates as
    # render-markdown.sh's equivalent test (semester_recess_week is
    # shared, tested directly in semester-lib.test.sh).
    out="$(render_html_calendar "$kinds2" 2026-08-10 4 2 "$titles" "$allowlist2" \
        /dev/null /dev/null https://x /dev/null /dev/null)"
    assert_contains "recess row's week cell" "$out" "<td style=\"border:1px solid #dddddd;padding:6px 8px;vertical-align:top;font-weight:bold;\">Recess</td>"
    assert_contains "recess row's note" "$out" "🏖️ Recess Week - No classes (2026-08-24 - 2026-08-28)"
    local recess_pos week2_pos week3_pos
    recess_pos=$(echo "$out" | grep -bo ">Recess<" | head -1 | cut -d: -f1)
    week2_pos=$(echo "$out" | grep -bo ">2</td>" | head -1 | cut -d: -f1)
    week3_pos=$(echo "$out" | grep -bo ">3</td>" | head -1 | cut -d: -f1)
    assert_success "recess row sits after week 2" [ "$week2_pos" -lt "$recess_pos" ]
    assert_success "recess row sits before week 3" [ "$recess_pos" -lt "$week3_pos" ]

    # RECESS_AFTER_WEEK=0 -- no recess row at all.
    assert_not_contains "no recess: no Recess row" \
        "$(render_html_calendar "$kinds2" 2026-08-10 4 0 "$titles" "$allowlist2" \
            /dev/null /dev/null https://x /dev/null /dev/null)" \
        "Recess"

    # week_holiday_notes wired into the Notes column: a holiday landing
    # on a day this kind doesn't meet (kinds is wed-only; Thursday isn't)
    # must still surface in Notes -- same real gap render-markdown.test.sh
    # covers, HTML side.
    local nonclass_holidays="$scratch/nonclass-holidays.conf"
    printf '2026-08-13|Non-Class Holiday\n' > "$nonclass_holidays"
    out="$(render_html_calendar "$kinds" 2026-08-10 1 0 "$titles" "$allowlist" \
        /dev/null /dev/null https://example.org/pdfs "$nonclass_holidays" "$emoji")"
    assert_contains "a holiday on a non-class day still shows in Notes" \
        "$out" "⚠️ Thursday: Non-Class Holiday"
    assert_contains "a holiday on a non-class day doesn't cancel any occurrence" \
        "$out" "L1A"

    local week_notes_file="$scratch/week-notes.conf"
    printf '1|Maintainer note\n' > "$week_notes_file"
    out="$(render_html_calendar "$kinds" 2026-08-10 1 0 "$titles" "$allowlist" \
        /dev/null "$week_notes_file" https://example.org/pdfs "$nonclass_holidays" "$emoji")"
    assert_contains "maintainer note and holiday note join with '; '" \
        "$out" "Maintainer note; ⚠️ Thursday: Non-Class Holiday"

    rm -rf "$scratch"
}
