source "$TOOLKIT_DIR/core/version-lib.sh"

test_version_lib() {
    local scratch
    scratch="$(mktemp -d)"
    local old_course_root="${COURSE_ROOT:-}"
    COURSE_ROOT="$scratch"

    assert_eq "first build of a slot starts at 1.0" "1.0" "$(get_slot_version L4A view hashA)"
    assert_eq "same hash again: still 1.0" "1.0" "$(get_slot_version L4A view hashA)"
    assert_eq "content changed (new hash): version unchanged" "1.0" "$(get_slot_version L4A view hashB)"

    local versions_conf_lines
    versions_conf_lines="$(grep -c '^L4A\.view|' "$scratch/config/versions.conf" 2>/dev/null || echo 0)"
    assert_eq "no duplicate lines in versions.conf after repeat calls" "1" "$versions_conf_lines"

    assert_eq "a kind-agnostic slot ID tracks fine (no per-kind special-casing)" \
        "1.0" "$(get_slot_version REC3 problem recHash1)"

    assert_contains "bump moves 1.0 -> 1.1" "$(bump_slot_version L4A view hashB)" "1.0 -> 1.1"
    assert_eq "get after bump reads 1.1" "1.1" "$(get_slot_version L4A view hashB)"

    assert_failure "bumping a never-built slot errors" bump_slot_version NEVERBUILT view somehash

    COURSE_ROOT="$old_course_root"
    rm -rf "$scratch"
}
