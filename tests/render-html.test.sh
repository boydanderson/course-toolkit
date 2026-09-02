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
    assert_eq "header has exactly Week + Lecture + Notes = 3 <th>s (kind not doubled per occurrence)" "3" "$th_count"
    assert_contains "unreleased slot renders as a grey <span>, not a link" "$out" "<span style=\"color:#888888;\">View</span>"
    assert_not_contains "unreleased slot has no <a> for itself" \
        "$out" 'href="https://example.org/pdfs/lecture-L1B'
    assert_contains "released slot still gets a real <a> link" \
        "$out" '<a href="https://example.org/pdfs/lecture-L1A.view.pdf">View</a>'

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

    rm -rf "$scratch"
}
