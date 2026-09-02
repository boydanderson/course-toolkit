# course-toolkit

A reusable course-materials build system: a calendar-driven weekly
schedule engine, PDF version tracking, and a Canvas release-page
generator, extracted so more than one course can use it. Consumed by a
course repo as a **git submodule**, pinned to a specific commit (never
tracked against `main` — see "Versioning" below).

Status: `core/` is implemented and verified against synthetic fixtures
for two real target courses (CS1101S's shape and CS2030S's) --
`core/schedule-lib.sh`, `core/version-lib.sh`, `core/course-lib.sh`,
`core/backend-lib.sh`, `core/semester-lib.sh`, `core/enrich-lib.sh`,
`core/render-markdown.sh`, `core/render-html.sh`. `backends/latex-beamer/`
implements the renderer contract for real and has actually compiled a
test slide to PDF via `pdflatex`. `backends/test/` is a minimal
reference implementation, not for real use.

Not yet done: wiring an actual consuming repo (starting with
[cs1101s/course-materials](https://github.com/cs1101s/course-materials),
which is also the first real consumer) up to this toolkit as a
submodule, and a `backends/typst/` implementation (a real second course,
CG2111A, uses Typst with a student/instructor variant realized via a
compile-time `--input` flag rather than separate source files -- the
contract already accommodates this, just not yet implemented).

## Layout

```
core/                    Renderer-agnostic engine -- schedule, version
                          tracking, Canvas/README generation. Doesn't
                          know or care what format a slot's source is.
backends/
  latex-beamer/           The first (and so far only) renderer backend --
                          LaTeX/Beamer compilation, shared preamble/
                          theme/macros. A future Typst or reveal.js
                          backend would be a sibling directory here,
                          implementing the same contract.
```

`core/` never contains renderer-specific logic (no `pdflatex` calls, no
`.tex` parsing). `backends/*/` never contains scheduling/versioning/
Canvas-page logic. A course declares which backend it uses; `core/`
dispatches into `backends/$(RENDERER)/` for every renderer-specific step.

## What a consuming course repo provides

A course repo mounts this toolkit as a submodule (conventionally at
`tooling/`) and provides:

- **`config/course.mk`** -- course identity and toolkit wiring:
  `COURSE_CODE`, `COURSE_NAME`, `HOSTING_ORG` (GitHub org the public PDF
  hosting repo lives under), `CANVAS_HOST`, `RENDERER` (which
  `backends/` directory to use, e.g. `latex-beamer`).
- **`config/session-kinds.conf`** -- the course's weekly schedule shape,
  as a list of session kinds. Each kind declares:
  - `id` / `label` -- e.g. `lecture`/"Lecture", `recitation`/"Recitation"
  - `occurrences` -- one or more `(weekday, suffix)` pairs per week, e.g.
    two lectures/week = `(wed,A) (fri,B)`; one lecture/week = `(mon,-)`
  - `slot_pattern` -- templated public ID, e.g. `L{n}{suffix}`, `R{n}`
  - `variants` -- artifact variant set: `view,print` / `problem,solution`
    / `none`
  - `week_range` -- optional start/end week bounds

  This is what makes "2 lectures a week" vs. "1 lecture + 1 recitation +
  1 lab a week" both expressible without touching any script.
- **A lecture-mapping-equivalent config** -- maps each content source to
  a teaching week (format TBD in Stage 2, generalizing today's
  `config/lecture-mapping.conf`).
- **`src/<kind-id>/`** content directories, in whatever format the
  chosen `RENDERER` expects (LaTeX `.tex` files for `latex-beamer`).
- A thin top-level `Makefile`:
  ```make
  TOOLKIT_DIR := tooling
  include $(TOOLKIT_DIR)/core/toolkit.mk
  ```

## Renderer backend contract

`core/` calls into `backends/$(RENDERER)/` for exactly these operations
(signatures finalized in Stage 2, alongside the first implementation in
`backends/latex-beamer/`):

- `build_slot(source_path, variant, output_path)` -- produce one
  variant's artifact for one slot
- `content_hash(slot_id, variant)` -- for the incremental-build/version
  cache; the backend decides what inputs affect a slot's output
- `extract_title(source_path)`, `extract_date(source_path)` -- for
  calendar/Canvas display text

A backend *may* additionally hook into snippet-testing (see below) by
producing annotated source files in the format that toolchain expects --
this is optional and orthogonal to the three required operations above.

## Snippet testing is a separate axis from rendering

The Python/py-slang (Source Academy) interactive-snippet-testing
toolchain lives in `core/`, not in any one backend. Its contract is "a
directory of annotated `.py` files exists for slot X" -- it doesn't care
whether those files were extracted from LaTeX `\begin{sourcecode}` blocks
or something else. A course/backend that doesn't want this feature simply
never produces that directory.

## Versioning

Consuming repos pin this toolkit to a specific commit SHA (as a git
submodule ref), the same "never track a dependency's `main` blindly"
convention used elsewhere in this ecosystem (see cs1101s/course-materials'
own py-slang and inkpdf pins). Update deliberately, one commit at a time.

## Path resolution

Every script here needs two path bases, since it runs from inside a
submodule but operates on the consuming repo's files:

- `TOOLKIT_DIR` -- where the script itself lives (for finding sibling
  toolkit files)
- `COURSE_ROOT` -- the consuming repo's root (`config/`, `src/`,
  `build/`). Since `make` runs with CWD = the directory containing the
  invoking `Makefile`, scripts take this as the working directory (or an
  explicitly-exported `COURSE_ROOT` env var), never derived from the
  script's own location.
