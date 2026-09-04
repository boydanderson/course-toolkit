source "$TOOLKIT_DIR/core/splice-lib.sh"

test_splice_lib() {
    local scratch
    scratch="$(mktemp -d)"

    local file="$scratch/README.md"
    cat > "$file" <<'EOF'
# Title

Some intro text.

<!-- CALENDAR_START -->
old content
still old
<!-- CALENDAR_END -->

Footer text.
EOF

    local content_file="$scratch/content.txt"
    printf 'new line 1\nnew line 2\nnew line 3\n' > "$content_file"

    splice_markers "$file" "<!-- CALENDAR_START -->" "<!-- CALENDAR_END -->" "$content_file"

    assert_contains "splice_markers: new content appears" "$(cat "$file")" "new line 1"
    assert_contains "splice_markers: new content appears (2)" "$(cat "$file")" "new line 3"
    assert_not_contains "splice_markers: old content is gone" "$(cat "$file")" "old content"
    assert_not_contains "splice_markers: old content is gone (2)" "$(cat "$file")" "still old"
    assert_contains "splice_markers: start marker itself is preserved" "$(cat "$file")" "<!-- CALENDAR_START -->"
    assert_contains "splice_markers: end marker itself is preserved" "$(cat "$file")" "<!-- CALENDAR_END -->"
    assert_contains "splice_markers: text before the markers is untouched" "$(cat "$file")" "Some intro text."
    assert_contains "splice_markers: text after the markers is untouched" "$(cat "$file")" "Footer text."

    # Order: start marker, new content, end marker, in that exact
    # sequence -- not just "all three substrings present somewhere".
    local start_pos content_pos end_pos
    start_pos="$(grep -n '<!-- CALENDAR_START -->' "$file" | cut -d: -f1)"
    content_pos="$(grep -n 'new line 1' "$file" | cut -d: -f1)"
    end_pos="$(grep -n '<!-- CALENDAR_END -->' "$file" | cut -d: -f1)"
    assert_success "splice_markers: start marker comes before new content" \
        [ "$start_pos" -lt "$content_pos" ]
    assert_success "splice_markers: new content comes before end marker" \
        [ "$content_pos" -lt "$end_pos" ]

    # Running it a second time (regenerate-and-splice-again, the real
    # convention) replaces the content again rather than accumulating.
    local content_file2="$scratch/content2.txt"
    printf 'second-run content\n' > "$content_file2"
    splice_markers "$file" "<!-- CALENDAR_START -->" "<!-- CALENDAR_END -->" "$content_file2"
    assert_contains "splice_markers: second run's content appears" "$(cat "$file")" "second-run content"
    assert_not_contains "splice_markers: first run's content doesn't linger" "$(cat "$file")" "new line 1"

    # Missing markers: a clear error, not a silently-unchanged file.
    local no_markers_file="$scratch/no-markers.md"
    printf '# No markers here\n' > "$no_markers_file"
    assert_failure "splice_markers: missing markers fails" \
        splice_markers "$no_markers_file" "<!-- CALENDAR_START -->" "<!-- CALENDAR_END -->" "$content_file"
    local err
    err="$(splice_markers "$no_markers_file" "<!-- CALENDAR_START -->" "<!-- CALENDAR_END -->" "$content_file" 2>&1 >/dev/null)"
    assert_contains "splice_markers: error message names the missing markers" "$err" "CALENDAR_START"

    # An empty content file splices in cleanly (no stray blank-line
    # artifacts breaking the marker sequence).
    local empty_content="$scratch/empty.txt"
    : > "$empty_content"
    local file2="$scratch/README2.md"
    cat > "$file2" <<'EOF'
<!-- LIST_START -->
stale
<!-- LIST_END -->
EOF
    splice_markers "$file2" "<!-- LIST_START -->" "<!-- LIST_END -->" "$empty_content"
    assert_contains "splice_markers: empty content -- markers still present" "$(cat "$file2")" "<!-- LIST_START -->"
    assert_not_contains "splice_markers: empty content -- stale content gone" "$(cat "$file2")" "stale"
}
