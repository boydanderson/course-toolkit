# course-toolkit

A reusable course-materials build system: a calendar-driven weekly
schedule engine, PDF version tracking, and Canvas-release/README
calendar generation. A course's weekly shape (how many
lectures/labs/recitations a week, on which days, with what PDF variants
each produces) and its slide-authoring format (LaTeX, Typst, ...) are
both configuration, not hardcoded assumptions — a course declares its
shape and picks a renderer backend, and everything else (dates, slot
IDs, versions, calendar tables) follows from that.

A consuming course repo mounts this as a **git submodule**, pinned to a
specific commit — update deliberately, never track `main`.

## Layout

```
core/                    Renderer-agnostic engine -- schedule, version
                          tracking, Canvas/README generation. Doesn't
                          know or care what format a slot's source is.
backends/
  latex-beamer/           LaTeX/Beamer renderer backend.
  test/                   Minimal reference backend -- template for a
                          new one.
```

`core/` never contains renderer-specific logic (no `pdflatex` calls, no
`.tex` parsing). `backends/*/` never contains scheduling/versioning/
Canvas-page logic. A course picks its backend via `config/course.mk`'s
`RENDERER`; `core/backend-lib.sh` dispatches into `backends/$RENDERER/`
for every renderer-specific step.

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
  as data, not code.
- **A content-to-slot map** — `SLOT_ID|SOURCE_PATH` pairs, so the build
  knows which file backs each scheduled slot. No fixed naming
  convention is assumed — lay content out however suits the course.
- **Release/label/note/holiday config** the enrichment layer reads (all
  optional, all empty-safe — pass `/dev/null` for any you don't need):
  a release allow-list (one slot ID per line), a `WEEK|KIND_ID|LABEL`
  override file for a week+kind with no real occurrence (e.g. an
  in-class-only session with no take-home sheet), a `WEEK|NOTE` file for
  maintainer notes, a `DATE|NAME` holiday calendar, and a
  `HOLIDAY_NAME|EMOJI` map (an occurrence whose date is in the holiday
  file renders as "No `<kind>` (`<emoji>` `<holiday>`)", overriding even
  an authored/released slot).
- Source content in whatever format the chosen `RENDERER` expects.

## Using it

Copy [`examples/Makefile`](examples/Makefile) into your repo root and
adjust its config-file variable overrides to match your setup. It calls
[`core/cli.sh`](core/cli.sh), the toolkit's command-line entry point:

```bash
tooling/core/cli.sh build          # walk the semester, track versions
tooling/core/cli.sh build --pdfs   # also actually compile every PDF
tooling/core/cli.sh readme          # print a markdown calendar table
tooling/core/cli.sh canvas           # print an HTML calendar table
tooling/core/cli.sh bump SLOT_ID VARIANT
```

See `cli.sh`'s own header comment for the full config-file contract
(defaults and environment-variable overrides). [`AGENTS.md`](AGENTS.md)
is a step-by-step checklist for wiring a new course repo up to this —
useful whether a human or an AI agent is doing the wiring.

For lower-level access than the CLI gives you, source the `core/*.sh`
libraries directly (set `TOOLKIT_DIR`/`COURSE_ROOT` first): `semester_weeks`
walks the teaching calendar, `week_occurrences` gives you each week's
scheduled slots, `backend_build_slot`/`backend_content_hash`/
`backend_extract_title` dispatch into the chosen renderer,
`get_slot_version`/`bump_slot_version` track versions, and
`render_markdown_calendar`/`render_html_calendar` produce the calendar
tables — see each function's own header comment for its full argument
list, or read `cli.sh` itself for a complete worked example.

## Renderer backend contract

A backend at `backends/<name>/` implements three executable scripts:

- **`build-slot.sh SOURCE_PATH VARIANT OUTPUT_PATH [SLOT_ID]`** —
  produce one variant's artifact for one slot. `VARIANT` is an opaque
  string the backend fully owns the meaning of (an extra header file, a
  compile-time flag, whatever fits the toolchain). `SLOT_ID` is optional
  — a backend that supports it can substitute the real computed slot ID
  into the source at build time (e.g. `latex-beamer` replaces a literal
  `\title{PLACEHOLDER_SLOT: ...}`), for content authored before its
  eventual week is known.
- **`content-hash.sh SOURCE_PATH VARIANT [SLOT_ID]`** — print a hash of
  every input that affects this slot/variant's output (include `SLOT_ID`
  in it if the backend's `build-slot.sh` uses it).
- **`extract-title.sh SOURCE_PATH`** — print the slot's display title
  (empty if none).

A backend *may* additionally hook into snippet-testing (see below) by
producing annotated source files in the format that toolchain expects.

## Snippet testing is a separate axis from rendering

The Python/py-slang (Source Academy) interactive-snippet-testing
toolchain lives in `core/`, not in any one backend. Its contract is "a
directory of annotated `.py` files exists for slot X" — it doesn't care
how those files were produced. A course/backend that doesn't want this
feature simply never produces that directory.

## Portability

Every script here targets bash 3.2, since macOS ships that as
`/bin/bash` by default. Use `tr`/`sed` for case conversion, not bash
4+-only parameter expansion (`${var,,}`, `${var^}`).

## Testing

```bash
tests/run.sh               # full suite, including real pdflatex compiles
tests/run.sh --skip-latex  # skip those if you don't have LaTeX installed
```

No external test framework — see `tests/assert.sh`. Runs in CI
(`.github/workflows/test.yml`) on every push and PR.
