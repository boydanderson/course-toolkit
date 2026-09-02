# Real `typst compile` + `pdfinfo` -- only run by tests/run.sh when both
# are on PATH (or --skip-typst wasn't passed). See that file's header
# comment. Built against CG2111A/EPP2's real content during the toolkit
# port proof-of-concept (boydanderson/epp2-toolkit-poc) -- see that
# repo's own templates for the `set document(title:)` convention this
# backend's extract-title.sh relies on.

test_backends_typst() {
    local backend="$TOOLKIT_DIR/backends/typst"
    local fixtures="$TOOLKIT_DIR/tests/fixtures/typst-demo"
    local scratch
    scratch="$(mktemp -d)"

    assert_success "build-slot.sh compiles a real PDF (student)" \
        "$backend/build-slot.sh" "$fixtures/handout.typ" student "$scratch/student.pdf"
    assert_success "the output is a real PDF file" \
        test -s "$scratch/student.pdf"
    assert_eq "the output starts with the PDF magic bytes" \
        "%PDF-" "$(head -c 5 "$scratch/student.pdf")"

    assert_success "build-slot.sh also compiles the instructor variant" \
        "$backend/build-slot.sh" "$fixtures/handout.typ" instructor "$scratch/instructor.pdf"

    # The instructor variant has real extra content (see the fixture's
    # own `#if is-instructor` block) -- the two PDFs must actually
    # differ, not just both "succeed" while silently ignoring the input.
    assert_ne "student and instructor variants actually differ" \
        "$(wc -c < "$scratch/student.pdf")" "$(wc -c < "$scratch/instructor.pdf")"

    assert_failure "build-slot.sh rejects an unknown variant" \
        "$backend/build-slot.sh" "$fixtures/handout.typ" bogus "$scratch/x.pdf"
    assert_failure "build-slot.sh fails on a missing source file" \
        "$backend/build-slot.sh" "$fixtures/nope.typ" student "$scratch/x.pdf"

    assert_eq "extract-title.sh reads the real document title" \
        "Demo: Demo Studio" "$("$backend/extract-title.sh" "$fixtures/handout.typ")"
    assert_eq "extract-title.sh: missing file is empty, not an error" \
        "" "$("$backend/extract-title.sh" "$fixtures/nope.typ")"

    local broken="$scratch/broken.typ"
    printf '#this is not valid typst syntax @#$%%\n' > "$broken"
    assert_eq "extract-title.sh: a file that fails to compile is empty, not an error" \
        "" "$("$backend/extract-title.sh" "$broken")"

    local h1 h2 h3 h4
    h1="$("$backend/content-hash.sh" "$fixtures/handout.typ" student)"
    h2="$("$backend/content-hash.sh" "$fixtures/handout.typ" student)"
    h3="$("$backend/content-hash.sh" "$fixtures/handout.typ" instructor)"
    assert_eq "content-hash.sh is stable for the same source+variant" "$h1" "$h2"
    assert_ne "content-hash.sh differs by variant" "$h1" "$h3"

    # content-hash.sh must follow the fixture's own local #import
    # ("shared.typ") -- a change to that shared file must invalidate the
    # hash of anything that imports it, same rationale as
    # backends/latex-beamer's preamble.tex being hashed alongside the
    # lecture body.
    cp "$fixtures/shared.typ" "$scratch/shared.typ"
    cp "$fixtures/handout.typ" "$scratch/handout.typ"
    h4="$("$backend/content-hash.sh" "$scratch/handout.typ" student)"
    printf '\n// touched\n' >> "$scratch/shared.typ"
    local h5
    h5="$("$backend/content-hash.sh" "$scratch/handout.typ" student)"
    assert_ne "content-hash.sh: a change to a #import'd file changes the hash" "$h4" "$h5"

    rm -rf "$scratch"
}
