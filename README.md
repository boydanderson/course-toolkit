# course-toolkit

A reusable course-materials build system: a calendar-driven weekly
schedule engine, PDF version tracking, and Canvas/README calendar
generation. A course's weekly shape and slide-authoring format are both
configuration, not hardcoded — a course declares its shape, picks a
renderer backend, and everything else (dates, slot IDs, versions,
calendar tables) follows from that.

Consuming repos mount this as a **git submodule**, pinned to a specific
commit — update deliberately, never track `main`.

## Layout

```
core/                    Renderer-agnostic engine: schedule, version
                          tracking, Canvas/README generation.
backends/
  latex-beamer/           LaTeX/Beamer renderer backend.
  typst/                  Typst backend (one source, compiled twice
                          with a different --input, not two headers).
  test/                   Minimal reference backend / template.
institutions/
  nus/                    Optional NUS/Singapore holiday + academic-
                          calendar data-fetching. Opt-in only.
```

`core/` has no renderer-specific logic; `backends/*/` has no
scheduling/versioning/Canvas logic. A course picks its backend via
`config/course.mk`'s `RENDERER`; `core/backend-lib.sh` dispatches into
`backends/$RENDERER/`.

## Quick start

```bash
tooling/core/cli.sh build          # walk the semester, track versions
tooling/core/cli.sh build --pdfs   # also compile every PDF
tooling/core/cli.sh readme         # print a markdown calendar table
tooling/core/cli.sh canvas         # print an HTML calendar table
tooling/core/cli.sh bump SLOT_ID VARIANT
```

Copy [`examples/Makefile`](examples/Makefile) into your repo and adjust
its config paths. See `cli.sh`'s header comment for the full config/env
contract, and [`AGENTS.md`](AGENTS.md) for a step-by-step new-course
checklist.

For lower-level access, source `core/*.sh` directly (set
`TOOLKIT_DIR`/`COURSE_ROOT` first): `semester_weeks` walks the calendar,
`week_occurrences` lists a week's scheduled slots, `backend_build_slot`/
`backend_content_hash`/`backend_extract_title` dispatch into the
renderer, `get_slot_version`/`bump_slot_version` track versions,
`render_markdown_calendar`/`render_html_calendar` build the tables. Each
function's header comment has its full argument list; `cli.sh` is a
complete worked example.

`core/splice-lib.sh`'s `splice_markers FILE START END CONTENT_FILE`
replaces everything between two marker lines in a hand-maintained file
with generated content, leaving the markers themselves in place — the
usual way a course's own regeneration script updates a README in place.

## What a course repo provides

- **`config/course.mk`** — `COURSE_CODE`, `COURSE_NAME`, `HOSTING_ORG`,
  `CANVAS_HOST`, `RENDERER` (which `backends/` dir to use).
- **`config/session-kinds.conf`** — the weekly schedule shape, one row
  per weekly occurrence of a kind (a kind with N occurrences/week gets N
  rows sharing the same `KIND_ID`):

  ```
  KIND_ID|LABEL|WEEKDAY|SUFFIX|SLOT_PATTERN|VARIANTS|WEEK_START|WEEK_END|EXCLUDE_WEEKS|DAY_LABEL|CANCEL_EXTRA_WEEKDAYS|AUTO_SHIFT_ON_HOLIDAY|HOLIDAY_CONFLICT_WEEKS|CONTENT_LIST_FILE|PUBLIC_VARIANTS|HEADER_LABEL
  ```

  | Field | Meaning |
  |---|---|
  | `KIND_ID` | short id, e.g. `lecture`, `studio` |
  | `LABEL` | display name, e.g. "Lecture" |
  | `WEEKDAY` | `mon`..`sun` |
  | `SUFFIX` | distinguishes same-kind occurrences in one week (`A`/`B`); `-` if only one |
  | `SLOT_PATTERN` | templated public ID: `{n}` = teaching week, `{suffix}` = `SUFFIX`, `{count}` = flat 1-based counter across every active occurrence of this `KIND_ID` (merged across its rows) instead of week-derived — e.g. `Lab{count}` → `Lab1..LabN` straight through. A row skipped by `EXCLUDE_WEEKS` doesn't consume a count |
  | `VARIANTS` | comma-separated build variants (`view,print`, `problem,solution`, or `none`) — everything *built and version-tracked*; see `PUBLIC_VARIANTS` for what's *linked* |
  | `WEEK_START`/`WEEK_END` | inclusive teaching-week bounds |
  | `EXCLUDE_WEEKS` | optional, `-` for none: comma-separated weeks to skip within range |
  | `DAY_LABEL` | optional, `-` for none: overrides the weekday name a split column's header shows (e.g. `Mon-Wed` when the real day isn't fixed) |
  | `CANCEL_EXTRA_WEEKDAYS` | optional, `-` for none: comma-separated extra weekdays this occurrence also spans (e.g. a studio meeting Mon+Tue) — a holiday on any of them cancels it. Still one row, one `SLOT_ID` |
  | `AUTO_SHIFT_ON_HOLIDAY` | optional, `-` for none: a holiday-colliding week is skipped at placement time (like `EXCLUDE_WEEKS`), so content shifts to the next eligible week, cascading. Requires `{count}` in `SLOT_PATTERN` |
  | `HOLIDAY_CONFLICT_WEEKS` | optional, `-` for none: weeks where a collision is already known/accepted (e.g. a take-home replaces the session) — held in place instead of shifted/cancelled, rendered with a `⚠️` prefix |
  | `CONTENT_LIST_FILE` | optional, `-` for none: path to a file of content identifiers in curriculum order. Unlike `{count}`, `SLOT_ID` stays week-derived while the *content index* shifts past a holiday |
  | `PUBLIC_VARIANTS` | optional, `-` for none: subset of `VARIANTS` that gets linked on a rendered page (the rest are still built/tracked, just never linked) |
  | `HEADER_LABEL` | optional, `-` for none: fully overrides a column's header text instead of the computed `"Weekday (Label Suffix)"` default |

  **Column splitting**: one occurrence/week → one merged column headered
  by `KIND_ID`. More than one → one column per occurrence, headered
  `"Wednesday (Lecture A)"`. **Column order** follows the file's own row
  order (by first appearance of each `KIND_ID`+`SUFFIX`), so a course can
  put e.g. Reflection's column between two Lecture columns just by
  writing the rows in that order. **Recess row**: when
  `RECESS_AFTER_WEEK` is nonzero, both renderers insert a dashed "Recess"
  row with a "🏖️ Recess Week (24 Aug – 28 Aug)" note between the two
  surrounding teaching weeks.

  **Holiday handling, in short**: `AUTO_SHIFT_ON_HOLIDAY` moves content
  forward past a collision (only valid with `{count}`);
  `HOLIDAY_CONFLICT_WEEKS` holds it in place instead, for a collision
  already accounted for; `CONTENT_LIST_FILE` gets the same forward-shift
  behavior but for a week-derived (`{n}`) slot, by shifting a separate
  content index rather than the slot itself. `available_slot_count` (in
  `schedule-lib.sh`) reports how many eligible weeks a kind has through a
  given week, merged across its rows, so a course's own build step can
  hard-fail when it has more content than room rather than silently
  dropping or shifting content past the end of term.

- **A content-to-slot map** — `SLOT_ID|SOURCE_PATH` pairs.
- **Release/label/note/holiday config** (all optional, empty-safe — pass
  `/dev/null` for any you don't need): a release allow-list (one slot ID
  per line), a `WEEK|KIND_ID|LABEL[|COLOR]` override file for a
  week+kind with no real occurrence (the optional 4th field colors that
  one label in HTML, overriding `CALENDAR_OCCASION_COLOR`), a
  `WEEK|NOTE` file, a `DATE|NAME` holiday calendar, and a
  `HOLIDAY_NAME|EMOJI` map.
- Source content in whatever format `RENDERER` expects.

## Calendar colors (`cli canvas` only)

Optional `config/course.mk` keys; unset keeps the default. `cli readme`
is plain Markdown and has no equivalent.

| Key | Controls | Default |
|---|---|---|
| `CALENDAR_BORDER_COLOR` | table/cell borders | `#dddddd` |
| `CALENDAR_HEADER_BG` | header row background | `#eeeeee` |
| `CALENDAR_LINK_COLOR` | a released item's link | *(unset — inherits the page's own link color)* |
| `CALENDAR_PENDING_COLOR` | an unreleased item's text | `#888888` |
| `CALENDAR_CANCELLED_COLOR` | a holiday-cancelled occurrence's text | `#c0392b` |
| `CALENDAR_NOTES_COLOR` | the Notes column's text | `#555555` |
| `CALENDAR_CURRENT_BG` | current week's row background | *(unset)* |
| `CALENDAR_CURRENT_BORDER_COLOR` | current week's left-accent border | *(unset)* |
| `CALENDAR_ROW_ODD_BG` / `CALENDAR_ROW_EVEN_BG` | alternating row backgrounds | *(unset)* |
| `CALENDAR_OCCASION_COLOR` | an occasion label's text, unless its own row sets a color | *(unset)* |
| `CALENDAR_CURRENT_WEEK_BG` | current week's number-cell background | *(unset — falls back to `CALENDAR_CURRENT_BG`)* |
| `CALENDAR_WEEK_BG` | non-current week-number cell background | *(unset)* |
| `CALENDAR_RECESS_BG` | Recess row's background (text is `CALENDAR_NOTES_COLOR`) | *(unset)* |
| `CALENDAR_SHOW_WEEK_DATES` | shows a "10 Aug – 14 Aug" sub-line under each week number | *(unset)* |
| `CALENDAR_COLUMN_WIDTHS` | comma-separated CSS widths (Week, kind columns, Notes) — emits a `<colgroup>` | *(unset)* |
| `CALENDAR_CANCELLED_NEWLINE` | splits a cancellation cell across two lines instead of one | *(unset)* |

Setting `CALENDAR_CURRENT_BG` or `CALENDAR_CURRENT_BORDER_COLOR` also
adds a "📍 This week" sub-label to the current week's number cell
(not separately configurable).

## Optional presentation features

All config-driven and opt-in — omitting a file just omits the feature.

- **Key Events** — `config/key-events.conf`
  (`DATE|START_TIME|END_TIME|NAME`), appended as a table after the
  calendar. Dates shown as "10 Aug 2026" (`format_date_long`).
- **Extra Notes-column categories** — `config/special-dates.conf`
  (`DATE|NAME`) and Key Events both also surface in the weekly Notes
  column, alongside holidays and the maintainer note, in that fixed
  order. Holiday notes are filtered to days some kind actually meets
  *that specific week* (`class_weekdays`); special dates/key events are
  not filtered this way.
- **Source-repo links** (`cli readme` only) — `config/source-links.conf`
  (`SLOT_ID|PATH`) renders `[source](PATH)` instead of the usual variant
  links for a listed slot.
- **Holiday-cancellation phrase order** (`cli readme` only) — set
  `HOLIDAY_FIRST` to swap `"No <Kind> (<holiday>)"` to `"<holiday> (No
  <Kind>)"`.
- **Public Holidays Reference** (`cli readme` only) — a legend table of
  every holiday within ±7 days of the semester, appended automatically.
- **Resources** — a verbatim block under a "Resources" heading:
  `config/canvas-resources.html` / `config/readme-resources.md`.
- **A second per-occurrence link** (e.g. a recording) —
  `config/kind-extra-links.conf` (`KIND_ID|LABEL`) +
  `config/extra-links.conf` (`SLOT_ID|URL`).
- **Occasion labels with optional links** — a week+kind label now always
  shows alongside any real occurrences that week (not just when the
  kind has zero). `config/occasion-links.conf`
  (`WEEK|KIND_ID|LINK1_LABEL|LINK1_URL|LINK2_LABEL|LINK2_URL`, either
  URL may be empty). A split column tries a suffix-qualified key first
  (`KIND_ID-SUFFIX`) before falling back to the plain `KIND_ID`.
- **Graded/important slot marking** — `config/graded-slots.conf` (one
  `SLOT_ID` per line) prefixes a title with "🔴 ".
- **Extra per-week slots** — a second linked file sharing a week's
  already-scheduled session without its own weekday/date/cancellation
  check: `config/kind-extra-slots.conf` (`WEEK|KIND_ID|SLOT_ID`). `cli
  readme` groups a slot into an existing entry when the titles match
  exactly, else keeps it separate; `cli canvas` never groups. Skipped
  entirely if the week's real occurrence is holiday-cancelled.
- **An extra note line per occurrence** (`cli canvas` only) —
  `config/extra-notes.conf` (`SLOT_ID|HTML`), rendered under a regular
  occurrence's title+links. The toolkit doesn't care how the HTML was
  produced (e.g. a course-owned LaTeX-section extractor).

## Renderer backend contract

A backend at `backends/<name>/` implements three scripts:

- **`build-slot.sh SOURCE_PATH VARIANT OUTPUT_PATH [SLOT_ID]`** —
  produce one variant's artifact. `VARIANT` is opaque, backend-owned.
  `SLOT_ID`, if supported, lets the backend substitute the real slot ID
  into a placeholder in the source.
- **`content-hash.sh SOURCE_PATH VARIANT [SLOT_ID]`** — a hash of every
  input affecting this slot/variant's output.
- **`extract-title.sh SOURCE_PATH`** — the slot's display title (empty
  if none).

This fits a course whose compile step is "one source file + a shared
preamble + an optional variant header" (`latex-beamer`, `typst`,
`test`). A course with materially more complex build orchestration
(custom preambles, multi-stage placeholder injection, diagram
generation, its own parallel-build job isolation) is expected to keep
that as its own bespoke build script, sourcing whichever narrower
`core/*.sh` primitives it needs (`sgt_date`, `get_slot_version`,
`splice_markers`, ...) instead of forcing it through this contract —
`cs1101s/course-materials`' own `build-lecture.sh`/`build-studio.sh` do
this and never call `backend_build_slot`/`backend_content_hash` at all.

Interactive-snippet testing (e.g. running embedded code through a real
interpreter) is not part of this toolkit — it's a course/content
concern, kept entirely in the consuming repo.

## institutions/nus/: real holiday data for NUS courses

`core/enrich-lib.sh`'s `is_holiday`/`holiday_emoji` just read a course's
own flat `config/holidays.conf`/`config/holiday-emoji.conf` — fetching a
real calendar is out of scope for `core/`. `institutions/nus/` is an
optional, pluggable way to produce that data:

- **`calendar-data-lib.sh`** — `fetch_sg_holidays_dynamic` (data.gov.sg),
  `fetch_nus_calendar_dynamic` (NUS's academic-calendar PDF: recess/
  reading week, NUS-specific holidays), `fetch_nusmods_exam_dynamic`
  (a module's exam date via the NUSMods API).
- **`fetch-calendar-data.sh`** — orchestrator: run with `COURSE_ROOT` set
  to a course repo, writes real holiday data to that repo's
  `config/holidays.conf` plus a raw cache under `config/calendar-data/`.
- **`holiday-emoji.conf`** — a default `HOLIDAY_NAME|EMOJI` map to copy
  into a course's own config as a starting point.

```bash
COURSE_ROOT=/path/to/your-course-repo \
    tooling/institutions/nus/fetch-calendar-data.sh
```

Makes real network calls — not part of `tests/run.sh`'s offline suite.
Re-run whenever semester dates change or a new academic year is needed.

## Portability

Every script targets bash 3.2 (macOS's default `/bin/bash`): use
`tr`/`sed` for case conversion, not bash 4+ parameter expansion
(`${var,,}`, `${var^}`).

## Testing

```bash
tests/run.sh               # full suite, including real pdflatex/typst compiles
tests/run.sh --skip-latex  # skip pdflatex compiles if not installed
tests/run.sh --skip-typst  # skip typst compiles if not installed
```

Backend tests auto-skip if their toolchain (`pdflatex`, or
`typst`+`pdfinfo`) isn't on `PATH`. No external test framework — see
`tests/assert.sh`. Runs in CI on every push and PR.
