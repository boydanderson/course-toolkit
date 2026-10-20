source "$TOOLKIT_DIR/core/placement-lib.sh"

test_placement_lib() {
    local scratch out
    scratch="$(mktemp -d)"
    # Two sessions a week sharing one kind (epp2's shape): S1 Mon-Tue,
    # S2 Wed-Fri, weeks 1-3 of a semester starting Mon 2026-08-10.
    printf 'session|Session|mon|S1|W{n}S1|student|1|3|-|-|tue\n' > "$scratch/kinds.conf"
    printf 'session|Session|wed|S2|W{n}S2|student|1|3|-|-|thu,fri\n' >> "$scratch/kinds.conf"
    # Tuesday of week 1: only an extra day of W1S1, but it still cancels it.
    printf '2026-08-11|Some Holiday\n' > "$scratch/holidays.conf"
    {
        printf '# comment\n'
        printf 'session|a.typ\n'
        printf 'session|b.typ|graded\n'
        printf '+Spec|b-spec.typ\n'
        printf 'session|c.typ\n'
        printf 'session|d.typ\n'
        printf 'session|e.typ|graded\n'
    } > "$scratch/order.conf"

    out="$(place_content "$scratch/kinds.conf" "$scratch/order.conf" "$scratch/holidays.conf" 2026-08-10 3 0)"
    assert_eq "a cancelled session pushes every later item forward one session, across S1/S2" \
        "W1S2|a.typ||1|session|S2|
W2S1|b.typ|graded|2|session|S1|
W2S1-Spec|b-spec.typ||2|session|S1|W2S1
W2S2|c.typ||2|session|S2|
W3S1|d.typ||3|session|S1|
W3S2|e.typ|graded|3|session|S2|" "$out"

    # One item more than the 5 eligible sessions: fail, naming it.
    printf 'session|f.typ\n' >> "$scratch/order.conf"
    assert_failure "more content than sessions fails" \
        place_content "$scratch/kinds.conf" "$scratch/order.conf" "$scratch/holidays.conf" 2026-08-10 3 0
    out="$(place_content "$scratch/kinds.conf" "$scratch/order.conf" "$scratch/holidays.conf" 2026-08-10 3 0 2>&1 >/dev/null || true)"
    assert_contains "overflow names the unplaced item" "$out" "no session left for f.typ"

    # HOLIDAY_CONFLICT_WEEKS holds week 1's S1 in place, so it keeps its
    # content and nothing shifts -- now all 6 items fit.
    printf 'session|Session|mon|S1|W{n}S1|student|1|3|-|-|tue|-|1\n' > "$scratch/kinds-hcw.conf"
    printf 'session|Session|wed|S2|W{n}S2|student|1|3|-|-|thu,fri\n' >> "$scratch/kinds-hcw.conf"
    out="$(place_content "$scratch/kinds-hcw.conf" "$scratch/order.conf" "$scratch/holidays.conf" 2026-08-10 3 0)"
    assert_contains "a conflict week keeps its content" "$out" "W1S1|a.typ|"
    assert_contains "...and the last item still fits" "$out" "W3S2|f.typ|"

    # A "+" line before any item fails.
    printf '+Spec|x.typ\n' > "$scratch/bad-order.conf"
    assert_failure "a '+' line with no item above it fails" \
        place_content "$scratch/kinds.conf" "$scratch/bad-order.conf" "$scratch/holidays.conf" 2026-08-10 3 0

    rm -rf "$scratch"
}
