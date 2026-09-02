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

    # LaTeX-escaped punctuation in a \title{} must come back unescaped --
    # regression: a real title ("Recursion \& Iteration") used to come
    # back with the backslash still attached, which is meaningless once
    # it lands in a rendered Markdown table or an already-HTML-escaped
    # Canvas cell.
    local escaped_title="$scratch/escaped-title.tex"
    printf '%s\n' '\title{R2: Recursion \& Iteration}' > "$escaped_title"
    assert_eq "extract-title.sh un-escapes \\& in a title" \
        "R2: Recursion & Iteration" "$("$backend/extract-title.sh" "$escaped_title")"

    local escaped_psetheader="$scratch/escaped-psetheader.tex"
    printf '%s\n' '\psetheader{AY2627S1}{3}{50\% Off \& Rising}' > "$escaped_psetheader"
    assert_eq "extract-title.sh un-escapes \\% and \\& in a \\psetheader{} title" \
        "50% Off & Rising" "$("$backend/extract-title.sh" "$escaped_psetheader")"

    local h1 h2 h3
    h1="$("$backend/content-hash.sh" "$body" view L1A)"
    h2="$("$backend/content-hash.sh" "$body" view L1A)"
    h3="$("$backend/content-hash.sh" "$body" view L5A)"
    assert_eq "content-hash.sh is stable for the same SLOT_ID" "$h1" "$h2"
    assert_ne "content-hash.sh differs by SLOT_ID (the compiled output would too)" "$h1" "$h3"

    rm -rf "$scratch"
}
