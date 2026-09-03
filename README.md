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
                          know or care what format a slot's source is,
                          or which institution a course belongs to.
backends/
  latex-beamer/           LaTeX/Beamer renderer backend.
  typst/                  Typst renderer backend -- one source compiled
                          twice with a different `--input`, not two
                          header files (see its own comments).
  test/                   Minimal reference backend -- template for a
                          new one.
institutions/
  nus/                    Optional NUS/Singapore-specific data-fetching
                          utilities (real public-holiday + academic-
                          calendar data). Not sourced by core/ or by any
                          backend -- a course opts in by running it
                          itself. See its own section below.
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
  KIND_ID|LABEL|WEEKDAY|SUFFIX|SLOT_PATTERN|VARIANTS|WEEK_START|WEEK_END|EXCLUDE_WEEKS|DAY_LABEL|CANCEL_EXTRA_WEEKDAYS|AUTO_SHIFT_ON_HOLIDAY
  ```

  | Field | Meaning |
  |---|---|
  | `KIND_ID` | short id, e.g. `lecture`, `studio`, `recitation` |
  | `LABEL` | display name, e.g. "Lecture" |
  | `WEEKDAY` | `mon`\|`tue`\|`wed`\|`thu`\|`fri`\|`sat`\|`sun` |
  | `SUFFIX` | distinguishes same-kind occurrences in one week (`A`/`B` for two lectures); `-` if there's only one |
  | `SLOT_PATTERN` | templated public ID: `{n}` → teaching week number, `{suffix}` → `SUFFIX` (empty if `-`), e.g. `L{n}{suffix}` → `L4A`. A third placeholder, `{count}`, is a flat 1-based counter across every active occurrence of this `KIND_ID` so far (merged across all its rows, in week/row order) instead of a week-derived number — e.g. `Lab{count}` numbers 2-a-week labs `Lab1..LabN` straight through rather than `Lab1A`/`Lab1B`/`Lab2A`...; a row skipped via `EXCLUDE_WEEKS` doesn't consume a count, so the sequence stays gap-free |
  | `VARIANTS` | comma-separated build-artifact variants, e.g. `view,print`, `problem,solution`, or `none` for one undifferentiated PDF |
  | `WEEK_START`, `WEEK_END` | inclusive teaching-week bounds this occurrence is active for |
  | `EXCLUDE_WEEKS` | optional (omit, or `-`): comma-separated week numbers to skip within that range, e.g. `4,6,10,12` for assessment-displaced weeks |
  | `DAY_LABEL` | optional 10th field (omit entirely, or `-`): overrides the weekday name a split column's header shows for this one occurrence (see "Column splitting" below) — `WEEKDAY` still has to name one concrete day for the schedule engine's own date math, but a course whose real session isn't pinned to that exact day (e.g. "Session 1, some day Mon-Wed") can set `DAY_LABEL` to `Mon-Wed` so the header doesn't assert a precision that isn't real |
  | `CANCEL_EXTRA_WEEKDAYS` | optional 11th field (omit entirely, or `-`): comma-separated weekday names (e.g. `tue`) this same occurrence *also* spans, for a session held across more than one calendar day with the same material (e.g. a studio meeting Monday **and** Tuesday) — a holiday landing on *any* of these days, not just `WEEKDAY`'s own, still cancels the occurrence. Purely a cancellation check: these extra days don't get their own slot ID, column, or `{count}` — it's still exactly one row, one `SLOT_ID` |
  | `AUTO_SHIFT_ON_HOLIDAY` | optional 12th field (omit entirely, or `-`): when set, a holiday-colliding week (same multi-day check `CANCEL_EXTRA_WEEKDAYS` uses) isn't just cancelled for display — the occurrence is skipped entirely at placement time, so the content that would have landed there shifts to the next eligible week instead, cascading the same way an `EXCLUDE_WEEKS` week already does. Requires `{count}` in `SLOT_PATTERN` (a clear error otherwise) — shifting only makes sense for a flat, week-independent numbering; a week-derived slot ID like `L4A` names the week it's shown in by construction, so it isn't a candidate. See "Holiday-aware auto-shift" below |

  This is what makes "2 lectures a week" vs. "1 lecture + 1 recitation +
  1 lab a week" — and a real course's irregular exceptions — expressible
  as data, not code.

  **Column splitting**: a kind with only one weekly occurrence gets one
  merged calendar column (headered with its capitalized `KIND_ID`,
  unchanged from before this existed). A kind with more than one (e.g.
  two lectures/week) instead gets one column per occurrence, since
  cramming both into one cell loses which weekday each falls on — headers
  read `"Wednesday (Lecture A)"` (`WeekdayFullName (Label Suffix)`, or
  `DAY_LABEL` in place of the weekday name if that row set one). Automatic
  for `render_markdown_calendar`/`render_html_calendar`/`cli readme`/
  `cli canvas` — no separate opt-in, just however many rows a `KIND_ID`
  has in `session-kinds.conf`.

  **Recess row**: when `RECESS_AFTER_WEEK` (see `config/course.mk` below)
  is nonzero, both renderers also insert a "Recess" row (dashes in every
  column, a "🏖️ Recess Week - No classes (dates)" note) between that
  teaching week and the next — see `core/semester-lib.sh`'s
  `semester_recess_week`.

  **Holiday-aware auto-shift**: every other holiday-cancellation feature
  in this toolkit (`is_holiday`, `CANCEL_EXTRA_WEEKDAYS`, the Notes
  column) is *reactive* — it detects a collision at render time and
  shows a cancellation, but never changes what's actually scheduled.
  `AUTO_SHIFT_ON_HOLIDAY` is different: it acts at *placement* time. A
  row with it set treats a holiday-colliding week exactly like an
  `EXCLUDE_WEEKS` week — no occurrence is produced there at all, and no
  `{count}` is consumed, so the content that would have landed there
  shifts to the next eligible week instead, cascading forward past
  however many holiday weeks it takes. Pass `HOLIDAYS_FILE`/
  `START_MONDAY`/`RECESS_AFTER_WEEK` into `week_occurrences` (all three
  needed together) to activate it — `cli.sh`'s `readme`/`canvas`/`build`
  commands already do this automatically for every course, so a course
  only needs to set the config field itself. Because `{count}` is
  required, this only applies to a kind whose slot ID is a flat,
  week-independent sequence (e.g. `Studio{count}`) — a week-derived slot
  ID like `L4A` names the week it's shown in by construction, so
  shifting it would break that correspondence; `week_occurrences`
  rejects `AUTO_SHIFT_ON_HOLIDAY` on a `{count}`-less `SLOT_PATTERN`
  with a clear error rather than silently doing nothing.

  If a kind has more real content than eligible weeks (several holidays
  eating into a fixed-length term), that's a hard stop, not a silent
  drop or a silently-extended term — `core/schedule-lib.sh`'s
  `available_slot_count` reports how many eligible weeks a row actually
  has; a course's own build step compares that against its real
  authored-content count and errors out itself (the toolkit only reports
  the number, since it has no way to know how much content a course has
  authored — that's course-specific: a directory of files, a content
  map, whatever).
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

### Customizing the calendar's colors

`cli canvas`'s HTML table has a small default palette (borders, header
background, an unreleased-item grey, a holiday-cancellation red, the
Notes column's grey) baked into `core/render-html.sh`. A course
overrides any subset of it with optional `config/course.mk` keys — unset
ones keep their default, so a course only needs to specify the colors it
actually wants to change:

| Key | Controls | Default |
|---|---|---|
| `CALENDAR_BORDER_COLOR` | table/cell borders | `#dddddd` |
| `CALENDAR_HEADER_BG` | header row background | `#eeeeee` |
| `CALENDAR_LINK_COLOR` | a released item's link | *(unset — inherits the embedding page's own link color, e.g. Canvas's theme)* |
| `CALENDAR_PENDING_COLOR` | an unreleased item's text | `#888888` |
| `CALENDAR_CANCELLED_COLOR` | a holiday-cancelled occurrence's text | `#c0392b` |
| `CALENDAR_NOTES_COLOR` | the Notes column's text | `#555555` |
| `CALENDAR_CURRENT_BG` | the current teaching week's row background | *(unset — no highlight)* |
| `CALENDAR_CURRENT_BORDER_COLOR` | the current week's number-cell left-accent border | *(unset — no accent)* |
| `CALENDAR_ROW_ODD_BG` / `CALENDAR_ROW_EVEN_BG` | alternating row backgrounds | *(unset — no banding)* |

```
CALENDAR_BORDER_COLOR = #dddddd
CALENDAR_LINK_COLOR = #1a5fb4
```

Only `cli canvas` (the HTML/Canvas renderer) has this concept. `cli
readme`'s output is plain Markdown — a table meant to render correctly
wherever Markdown is read (GitHub, a plain-text viewer, ...), so it
carries no inline styling to make configurable in the first place. The
current-week/row-banding colors are likewise HTML-only for the same
reason.

### Optional presentation features

Each of these is entirely config-driven and opt-in — a course that
doesn't create the relevant file just doesn't get the feature, and every
existing course's output is completely unaffected by their existence:

- **Key Events** — a table of one-off dated events (a competition, an
  exam, a guest lecture) that don't fit the regular weekly grid.
  `config/key-events.conf`, format `DATE|START_TIME|END_TIME|NAME`, one
  per line. `cli readme`/`cli canvas` append it after the main calendar
  table automatically if the file exists and has real rows.
- **Extra Notes-column categories** (`cli readme` only) — besides real
  holidays (`week_holiday_notes`, always on if `HOLIDAYS_FILE` is set),
  the weekly Notes column can also surface a non-holiday calendar marker
  (`config/special-dates.conf`, format `DATE|NAME`) and the same one-off
  events `config/key-events.conf` already lists for the Key Events table
  above — a course populating that file for the table gets its events in
  the weekly Notes column too, at no extra config cost. All categories
  append in a fixed order (maintainer note, holidays, special dates, key
  events), not interleaved by day. See `core/enrich-lib.sh`'s
  `week_special_date_notes`/`week_key_event_notes`.
- **Source-repo links instead of built-PDF links** (`cli readme` only)
  — a course whose calendar table should link straight at its own
  source (e.g. a `.tex` file on GitHub) rather than a built PDF variant.
  `config/source-links.conf`, format `SLOT_ID|PATH`. A listed slot
  renders a single `[source](PATH)` link instead of the usual View/
  Print/Sheet variant links; a slot with no entry falls through to the
  normal variant links unaffected. Works with the extra-per-week-slots
  grouping above — each contributing slot in a merged group gets its
  own source link. See `core/enrich-lib.sh`'s `source_link_for_slot`.
- **Configurable holiday-cancellation phrase order** (`cli readme` only)
  — the default cancellation text is `"No <Kind> (<holiday>)"`; set
  `HOLIDAY_FIRST` (any non-empty value) to swap it to `"<holiday> (No
  <Kind>)"` instead. Unset preserves every existing consumer's exact
  current text.
- **Public Holidays Reference** — a plain legend table of every holiday
  in `config/holidays.conf` falling inside the semester's own span
  (±7 days). `cli readme` only (markdown; no Canvas/HTML equivalent),
  appended automatically whenever there's a real holiday in that window
  — no separate config file or opt-in beyond `HOLIDAYS_FILE` itself. See
  `core/render-holidays-reference.sh` / `core/semester-lib.sh`'s
  `semester_term_window`.
- **Resources** — a maintainer-edited block appended verbatim under a
  "Resources" heading. Two separate files since Markdown and HTML can't
  share content verbatim: `config/canvas-resources.html` (for `cli
  canvas`) and `config/readme-resources.md` (for `cli readme`).
- **A second, independently-gated link per occurrence** (e.g. a lecture
  recording that goes up on its own schedule, separate from the PDF
  release) — `config/kind-extra-links.conf` (`KIND_ID|LABEL`, e.g.
  `lecture|Recording`, declares which kinds get one) plus
  `config/extra-links.conf` (`SLOT_ID|URL`, the actual per-slot links —
  same shape as the release allow-list's sibling files, live once
  listed, a greyed pending label otherwise).
- **Occasion labels with optional links** — a week+kind label (see
  the release/label/note/holiday config above) now always shows
  alongside any real occurrences that week, not just when the kind has
  *zero* occurrences (e.g. a course with 2 lectures/week where only one
  is excluded for an assessment that week still sees the assessment
  labelled, next to the lecture that still meets). Give it up to 2
  optional links (e.g. an assessment's "Details"/"Papers") via
  `config/occasion-links.conf`, format `WEEK|KIND_ID|LINK1_LABEL|
  LINK1_URL|LINK2_LABEL|LINK2_URL` (either URL may be empty — pending,
  same convention as everywhere else). With a split column (a kind
  with more than one weekly occurrence), the label lookup also tries a
  suffix-qualified key first (`KIND_ID-SUFFIX`, e.g. `studio-A`) before
  falling back to the plain `KIND_ID` — lets two different suffixes
  excluded the same week carry two different labels (e.g. one session's
  "OT OT" vs. the other's "Trial"), not just one label shared across
  whichever suffix is empty that week.
- **Graded/important slot marking** — `config/graded-slots.conf`, one
  `SLOT_ID` per line, prefixes that occurrence's title with "🔴 " in
  both `readme`/`canvas` — for flagging a checkpoint, a graded
  deliverable, or any other session worth calling out visually. Purely
  a display marker; doesn't affect release gating, versioning, or
  anything else.
- **Extra per-week slots** (e.g. a studio's "-in-class" supplement, a
  second linked file sharing that week's already-scheduled session
  without being a distinct weekly occurrence of its own — no separate
  weekday, date, or holiday-cancellation check) — `config/kind-extra-
  slots.conf`, format `WEEK|KIND_ID|SLOT_ID`. `cli readme` groups an
  extra slot into the same cell entry as whichever real occurrence(s)
  share an *exactly matching* title that week (e.g. two slots that both
  turn out to cover "Interrupts" show as one entry, "Slot1: ... ; Slot2:
  ..."), keeping genuinely different titles as separate entries. `cli
  canvas` doesn't group at all — each extra slot gets its own
  independent stacked title+links block, matching real course-materials
  Canvas rendering. If the week's real occurrence is holiday-cancelled,
  extra slots are skipped entirely (they ride along with the session
  that didn't happen). See `core/enrich-lib.sh`'s `kind_extra_slots`.
- **An extra note line per occurrence** (`cli canvas` only — no Markdown
  equivalent exists to preserve) — generalizes the *rendering slot* a
  course-specific extraction step can occupy under a regular
  occurrence's title+links, without the toolkit needing to know how the
  text was produced (e.g. cs1101s/course-materials' own SICPy
  §-section reading list, extracted from LaTeX by a course-owned
  script — that extraction logic stays entirely course-side).
  `config/extra-notes.conf`, format `SLOT_ID|HTML` — a course feeds it
  from whatever extraction step it likes, or never creates the file for
  no extra line at all. See `core/enrich-lib.sh`'s `extra_note_for_slot`.

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

Interactive-snippet testing (e.g. running embedded code blocks through a
real interpreter like py-slang) is **not part of this toolkit** — it
stays entirely inside the consuming course repo (see
`cs1101s/course-materials`' own `package.json`/`scripts/test-with-slang.py`
for that repo's version), since it's a course/content-authoring concern
orthogonal to scheduling, versioning, and rendering.

## institutions/nus/: real holiday data for NUS courses

`core/enrich-lib.sh`'s `is_holiday`/`holiday_emoji` read a course's own
flat `config/holidays.conf` (`DATE|NAME`) and `config/holiday-emoji.conf`
(`HOLIDAY_NAME|EMOJI`) — deliberately just data as far as `core/` is
concerned, since fetching a real institution's public-holiday calendar
is out of scope for a generic toolkit. `institutions/nus/` is an
optional, pluggable way to produce that data for real — the same
"opt-in, doesn't touch core/" shape as `backends/`, just for institution
data instead of a renderer:

- **`calendar-data-lib.sh`** — `fetch_sg_holidays_dynamic` (Singapore
  public holidays from data.gov.sg), `fetch_nus_calendar_dynamic` (NUS's
  own academic-calendar PDF — recess/reading week dates, plus
  NUS-specific holidays like Well-Being Day), and
  `fetch_nusmods_exam_dynamic` (a module's final exam date/time from the
  NUSMods API). Ported from `cs1101s/course-materials`' own
  `scripts/fetch-holidays.sh`, proven there against the real APIs first.
- **`fetch-calendar-data.sh`** — the orchestrator: run it with
  `COURSE_ROOT` set to a course repo (reads that repo's
  `config/course.mk` for `COURSE_CODE`/`SEMESTER_START_MONDAY`), and it
  writes real Singapore + NUS holiday data straight to that course's
  `config/holidays.conf` — the exact file `cli.sh`'s `HOLIDAYS_FILE`
  already defaults to — plus a raw fetch cache under
  `config/calendar-data/` for reference. A course with no `COURSE_CODE`
  set just skips the (optional) NUSMods exam-date fetch with a warning,
  nothing else is affected.
- **`holiday-emoji.conf`** — a shared default `HOLIDAY_NAME|EMOJI` map
  for the common Singapore/NUS holidays; copy it into a course's own
  `config/holiday-emoji.conf` as a starting point.

```bash
COURSE_ROOT=/path/to/your-course-repo \
    tooling/institutions/nus/fetch-calendar-data.sh
```

Makes real network calls (data.gov.sg, nus.edu.sg, api.nusmods.com) —
not part of `tests/run.sh`'s offline suite, same as
`cs1101s/course-materials`' own equivalent was never part of its bash
test suite either. Re-run it whenever a course's semester dates change
or a new academic year's data is needed.

## Portability

Every script here targets bash 3.2, since macOS ships that as
`/bin/bash` by default. Use `tr`/`sed` for case conversion, not bash
4+-only parameter expansion (`${var,,}`, `${var^}`).

## Testing

```bash
tests/run.sh               # full suite, including real pdflatex/typst compiles
tests/run.sh --skip-latex  # skip pdflatex compiles if you don't have LaTeX installed
tests/run.sh --skip-typst  # same, for typst compiles
```

Both `backends/latex-beamer` and `backends/typst`'s own tests auto-skip
(no flag needed) if the real toolchain they compile with (`pdflatex`, or
`typst`+`pdfinfo`) isn't on `PATH` — CI's `texlive/texlive` container has
`pdflatex` but not `typst`, so `backends-typst.test.sh` skips there.

No external test framework — see `tests/assert.sh`. Runs in CI
(`.github/workflows/test.yml`) on every push and PR.
