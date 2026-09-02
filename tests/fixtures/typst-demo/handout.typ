// Minimal Typst fixture for backends/typst -- used to verify
// build-slot.sh/content-hash.sh/extract-title.sh actually compile,
// hash, and extract-title against real `typst compile`, not just
// against a mock. Deliberately as small as possible: one local
// #import (to exercise content-hash.sh's import-following), one
// input-conditional bit of content (to prove instructor/student
// variants actually differ), and a real `set document(title:)` (the
// mechanism extract-title.sh relies on).
#import "shared.typ": banner

#let is-instructor = sys.inputs.at("instructor-mode", default: "false") == "true"

#set document(title: "Demo: " + banner)

= #banner

This is the student-visible body.

#if is-instructor [
  *Instructor-only note:* this line only appears in the instructor variant.
]
