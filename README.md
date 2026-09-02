# course-toolkit

A reusable course-materials build system: a calendar-driven weekly
schedule engine, PDF version tracking, and Canvas-release/README
calendar generation — extracted out of
[cs1101s/course-materials](https://github.com/cs1101s/course-materials)
so more than one course can use it. A consuming course repo mounts this
as a **git submodule**, pinned to a specific commit (see "Versioning"
below — never tracked against `main`).

The core problem this solves: a course's weekly shape (how many
lectures/labs/recitations a week, on which days, with what PDF variants
each produces) and its slide-authoring format (LaTeX, Typst, ...) are
both *data and choices*, not universal facts — so neither is hardcoded
here. A course declares its shape in `config/session-kinds.conf` and
picks a renderer backend; everything else (dates, slot IDs, versions,
calendar tables) falls out of that.

## Status

`core/` is implemented and has been run against real content, not just
fixtures: `cs1101s/course-materials`' actual current semester — all 44
of its real, currently-scheduled and authored slots (lectures, studios,
reflections) — extracting real titles, computing real content hashes,
tracking real versions, and rendering a full 13-week preview calendar
correctly, including the real irregular cases (a midterm displacing one
lecture and cancelling the reflection outright in week 7, a public
holiday leaving a lecture slot scheduled-but-unauthored in week 8, a
studio kind that doesn't start until week 2). It's also been checked
against a second, differently-shaped real course
([CS2030S](https://github.com/nus-cs2030s)) and a third
([CG2111A](https://github.com/epp2/Engineering-Principles-and-Practice-II),
which uses Typst, not LaTeX) closely enough to validate the design,
without yet building everything either of those would need — see "Known
gaps" below.

**Modules**, all implemented and exercised for real:
`core/schedule-lib.sh`, `core/version-lib.sh`, `core/course-lib.sh`,
`core/backend-lib.sh`, `core/semester-lib.sh`, `core/enrich-lib.sh`,
`core/render-markdown.sh`, `core/render-html.sh`.
`backends/latex-beamer/` implements the renderer contract for real and
has actually compiled real slides to PDF via `pdflatex`.
`backends/test/` is a minimal reference implementation, not for real
use.

**Not yet done** (real, known gaps — not silent omissions):
- `core/toolkit.mk`, the intended `include`-able Make orchestration
  layer, is still a placeholder. The one real integration so far
  (`cs1101s/course-materials`' `scripts/toolkit-build.sh`) is a
  standalone bash script that sources the `core/*.sh` libraries
  directly instead — see "How a course actually integrates this" below.
- No `backends/typst/` or `backends/reveal-js/` yet. The contract is
  validated against both (see "Renderer backend contract"), just not
  implemented.
- `backends/latex-beamer` doesn't yet replicate everything
  `cs1101s/course-materials`' original `build-lecture.sh` did:
  no `PLACEHOLDER_SLOT`/`PLACEHOLDER_DATE`/etc. template substitution,
  no holiday-cancellation detection in the renderers (a semester-specific
  holiday displacing a session currently just renders as an
  unauthored/pending slot, not "No lecture (Holiday)").
- The "gated PDF release + Canvas table" model `core/render-*.sh`
  implement fits a course that ships versioned, allow-listed PDFs (true
  for CS1101S, plausible for CG2111A). It does **not** fit every
  course's distribution strategy — CS2030S's real materials are a
  continuously-published docs/slides website with no release gate and
  no week-numbered artifacts at all. Whether/how this toolkit should
  serve that shape is unresolved, not guessed at here.

## Layout

```
core/                    Renderer-agnostic engine -- schedule, version
                          tracking, Canvas/README generation. Doesn't
                          know or care what format a slot's source is.
backends/
  latex-beamer/           The first real renderer backend -- LaTeX/
                          Beamer compilation, shared preamble/theme.
  test/                   Minimal reference implementation (no real
                          rendering) -- template for a new backend.
```

`core/` never contains renderer-specific logic (no `pdflatex` calls, no
`.tex` parsing). `backends/*/` never contains scheduling/versioning/
Canvas-page logic. A course declares which backend it uses via
`config/course.mk`'s `RENDERER`; `core/backend-lib.sh` dispatches into
`backends/$RENDERER/` for every renderer-specific step.

## How a course actually integrates this, today

There's no stable, documented entry point yet (`core/toolkit.mk` is a
placeholder — see "Not yet done"). The one real, working example is
`cs1101s/course-materials`' `scripts/toolkit-build.sh`: it sets
`TOOLKIT_DIR`/`COURSE_ROOT`, sources the `core/*.sh` libraries directly,
and walks the semester itself. Read that script if you're integrating
this into a new course repo before this toolkit has its own stable
`make`-based interface — it's the closest thing to a working reference
right now.

## What a consuming course repo provides

- **`config/course.mk`** — course identity and toolkit wiring:
  `COURSE_CODE`, `COURSE_NAME`, `HOSTING_ORG` (GitHub org the public PDF
  hosting repo lives under), `CANVAS_HOST`, `RENDERER` (which
  `backends/` directory to use, e.g. `latex-beamer`).
- **`config/session-kinds.conf`** — the course's weekly schedule shape:
  one row per weekly occurrence of a session kind (a kind with N
  occurrences/week, e.g. two lectures, gets N rows sharing the same
  `KIND_ID`):

  ```
  KIND_ID|LABEL|WEEKDAY|SUFFIX|SLOT_PATTERN|VARIANTS|WEEK_START|WEEK_END|EXCLUDE_WEEKS
  ```

  | Field | Meaning |
  |---|---|
  | `KIND_ID` | short id, e.g. `lecture`, `studio`, `recitation` |
  | `LABEL` | display name, e.g. "Lecture" |
  | `WEEKDAY` | `mon`\|`tue`\|`wed`\|`thu`\|`fri`\|`sat`\|`sun` |
  | `SUFFIX` | distinguishes same-kind occurrences in one week (`A`/`B` for two lectures); `-` if there's only one |
  | `SLOT_PATTERN` | templated public ID: `{n}` → teaching week number, `{suffix}` → `SUFFIX` (empty if `-`), e.g. `L{n}{suffix}` → `L4A` |
  | `VARIANTS` | comma-separated build-artifact variants, e.g. `view,print`, `problem,solution`, or `none` for one undifferentiated PDF |
  | `WEEK_START`, `WEEK_END` | inclusive teaching-week bounds this occurrence is active for |
  | `EXCLUDE_WEEKS` | optional (omit, or `-`): comma-separated week numbers to skip within that range, e.g. `4,6,10,12` for assessment-displaced weeks |

  This is what makes "2 lectures a week" vs. "1 lecture + 1 recitation +
  1 lab a week" — and a real course's irregular exceptions — expressible
  as data, not code. See
  [cs1101s/course-materials' `config/session-kinds.conf`](https://github.com/cs1101s/course-materials/blob/main/config/session-kinds.conf)
  for a real, worked example.
- **A content-to-slot map** — `SLOT_ID|SOURCE_PATH` pairs, so the build
  knows which file backs each scheduled slot. No fixed naming
  convention is assumed (a course can lay out `src/lectures/lecture-N.tex`
  the way CS1101S does, or `Studios/N_Name/Name_handout.typ`
  directory-per-unit the way CG2111A does) — see
  [`config/content-map.conf`'s real example](https://github.com/cs1101s/course-materials/blob/main/config/content-map.conf).
- **Release/label/note config** the enrichment layer reads (all
  optional, all empty-safe): a release allow-list (one slot ID per
  line), a `WEEK|KIND_ID|LABEL` override file for a week+kind with no
  real occurrence (e.g. an in-class-only session with no take-home
  sheet), a `WEEK|NOTE` file for maintainer notes.
- Source content in whatever format the chosen `RENDERER` expects.

## Renderer backend contract

`core/backend-lib.sh` dispatches into `backends/$RENDERER/` for exactly
three operations. A backend implements them as three executable scripts:

- **`build-slot.sh SOURCE_PATH VARIANT OUTPUT_PATH`** — produce one
  variant's artifact for one slot. `VARIANT` is an opaque string the
  backend fully owns the meaning of — `latex-beamer` realizes it as an
  extra header file (`headers/<variant>.tex`); a Typst backend could
  instead realize it as a compile-time `--input` flag (confirmed against
  CG2111A's real student/instructor-variant convention — no change to
  this contract needed either way).
- **`content-hash.sh SOURCE_PATH VARIANT`** — print a hash of every
  input that affects this slot/variant's output; the backend decides
  what counts (e.g. `latex-beamer` also hashes the shared preamble, so a
  theme change invalidates every cached slot, not just edited ones).
- **`extract-title.sh SOURCE_PATH`** — print the slot's display title
  (empty if none). Note: dropped a fourth, originally-planned
  `extract_date` operation — the schedule engine already computes every
  occurrence's date authoritatively from `config/session-kinds.conf`; a
  second, backend-derived source of truth for the same fact would just
  be something that could drift.

A backend *may* additionally hook into snippet-testing (see below) by
producing annotated source files in the format that toolchain expects —
optional, orthogonal to the three operations above.

**A general rule learned the hard way while proving this against real
content**: none of these three scripts, nor any `core/` lookup function
a renderer/table generator calls, should ever let "found nothing" (an
unauthored slot, a title not yet recorded, etc.) propagate as a fatal
error under `set -e` — that's a normal, expected state, not a bug. Every
script here handles it by returning empty/success rather than exiting
nonzero.

## Snippet testing is a separate axis from rendering

The Python/py-slang (Source Academy) interactive-snippet-testing
toolchain lives in `core/`, not in any one backend. Its contract is "a
directory of annotated `.py` files exists for slot X" — it doesn't care
whether those files were extracted from LaTeX `\begin{sourcecode}`
blocks or something else. A course/backend that doesn't want this
feature simply never produces that directory.

## Versioning

Consuming repos pin this toolkit to a specific commit SHA (as a git
submodule ref), the same "never track a dependency's `main` blindly"
convention used elsewhere in this ecosystem (see
`cs1101s/course-materials`' own py-slang and inkpdf pins). Update
deliberately, one commit at a time.

## Portability

Every script here targets **bash 3.2**, not bash 4+, even though every
script has a `#!/bin/bash` shebang. This isn't a hypothetical concern:
macOS ships bash 3.2 as `/bin/bash` (a licensing-driven freeze, not
upgraded in years), and running these scripts for real on macOS hit
`${var,,}`/`${var^}`-style bash-4-only substitutions failing outright.
Don't assume a consumer has a newer bash ahead of `/bin/bash` on PATH —
use `tr`/`sed` for case conversion, not bash 4+ parameter expansion.

## Path resolution

Every script here needs two path bases, since it runs from inside a
submodule but operates on the consuming repo's files:

- `TOOLKIT_DIR` — where the script itself lives (for finding sibling
  toolkit files).
- `COURSE_ROOT` — the consuming repo's root (`config/`, `src/`,
  `build/`). Since `make` runs with CWD = the directory containing the
  invoking `Makefile`, scripts take this as the working directory (or an
  explicitly-exported `COURSE_ROOT` env var), never derived from the
  script's own location.

Both must be exported by the caller before sourcing any `core/*.sh`
file — see `cs1101s/course-materials`' `scripts/toolkit-build.sh` for a
real example.
