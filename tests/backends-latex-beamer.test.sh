# Real pdflatex compiles -- only run by tests/run.sh when pdflatex is on
# PATH (or --skip-latex wasn't passed). See that file's header comment.

test_backends_latex_beamer() {
    local backend="$TOOLKIT_DIR/backends/latex-beamer"
    local scratch
    scratch="$(mktemp -d)"
    local body="$TOOLKIT_DIR/tests/fixtures/demo101/L1A-body.tex"

    assert_success "build-slot.sh actually compiles a real PDF (view)" \
        "$backend/build-slot.sh" "$body" view "$scratch/view.pdf" L1A
    assert_success "the output is a real PDF file" \
        test -s "$scratch/view.pdf"
    assert_eq "the output starts with the PDF magic bytes" \
        "%PDF-" "$(head -c 5 "$scratch/view.pdf")"

    assert_success "build-slot.sh also compiles the 'print' variant (uses headers/print.tex)" \
        "$backend/build-slot.sh" "$body" print "$scratch/print.pdf" L1A

    assert_eq "extract-title.sh, no SLOT_ID: raw, unsubstituted placeholder" \
        "PLACEHOLDER_SLOT: Sample Topic" "$("$backend/extract-title.sh" "$body")"
    assert_eq "extract-title.sh, with SLOT_ID: substituted" \
        "L1A: Sample Topic" "$("$backend/extract-title.sh" "$body" L1A)"

    local h1 h2 h3
    h1="$("$backend/content-hash.sh" "$body" view L1A)"
    h2="$("$backend/content-hash.sh" "$body" view L1A)"
    h3="$("$backend/content-hash.sh" "$body" view L5A)"
    assert_eq "content-hash.sh is stable for the same SLOT_ID" "$h1" "$h2"
    assert_ne "content-hash.sh differs by SLOT_ID (the compiled output would too)" "$h1" "$h3"

    rm -rf "$scratch"
}
