source "$TOOLKIT_DIR/core/backend-lib.sh"

test_backend_lib() {
    local old_renderer="${RENDERER:-}"
    RENDERER=test
    local scratch
    scratch="$(mktemp -d)"
    printf 'TITLE: A Test Title\nSome body content.\n' > "$scratch/source.txt"

    assert_eq "dispatches extract_title into backends/test" \
        "A Test Title" "$(backend_extract_title "$scratch/source.txt")"

    local h1 h2 h3
    h1="$(backend_content_hash "$scratch/source.txt" view)"
    h2="$(backend_content_hash "$scratch/source.txt" view)"
    h3="$(backend_content_hash "$scratch/source.txt" print)"
    assert_eq "content_hash is stable for the same variant" "$h1" "$h2"
    assert_ne "content_hash differs by variant" "$h1" "$h3"

    backend_build_slot "$scratch/source.txt" view "$scratch/out.txt"
    assert_success "build_slot produces an output file" test -f "$scratch/out.txt"
    assert_contains "build_slot's output contains the source content" \
        "$(cat "$scratch/out.txt")" "A Test Title"

    RENDERER=does-not-exist
    assert_failure "dispatching to a nonexistent backend fails cleanly" \
        backend_extract_title "$scratch/source.txt"

    RENDERER="$old_renderer"
    rm -rf "$scratch"
}
