source "$TOOLKIT_DIR/core/date-lib.sh"

test_date_lib() {
    assert_eq "add_days: simple forward" "2026-08-15" "$(add_days 2026-08-10 5)"
    assert_eq "add_days: zero is a no-op" "2026-08-10" "$(add_days 2026-08-10 0)"
    assert_eq "add_days: negative goes backward" "2026-08-05" "$(add_days 2026-08-10 -5)"
    assert_eq "add_days: crosses a month boundary" "2026-09-02" "$(add_days 2026-08-28 5)"
    assert_eq "add_days: crosses a year boundary" "2027-01-03" "$(add_days 2026-12-29 5)"
    assert_eq "add_days: backward across a month boundary" "2026-07-30" "$(add_days 2026-08-02 -3)"

    # sgt_date: fixed epoch so this is deterministic, not "now"-dependent.
    # 1609459200 = 2021-01-01 00:00:00 UTC -> +8h = 2021-01-01 08:00:00 SGT
    assert_eq "sgt_date: UTC+8 offset against a fixed epoch" \
        "2021-01-01 08:00:00" "$(sgt_date '+%Y-%m-%d %H:%M:%S' 1609459200)"
    assert_eq "sgt_date: offset can roll the date forward across midnight" \
        "2021-01-01" "$(sgt_date '+%Y-%m-%d' 1609430400)"  # 2020-12-31 16:00 UTC
    assert_eq "sgt_date: format string is honored" \
        "2021" "$(sgt_date '+%Y' 1609459200)"

    assert_eq "day_of_week_name: a known Monday" \
        "Monday" "$(day_of_week_name 2026-08-10)"
    assert_eq "day_of_week_name: a known Sunday" \
        "Sunday" "$(day_of_week_name 2026-08-16)"
}
