# AGENTS.md

Guidance for an AI coding agent wiring a course repo up to consume this
toolkit. Read the main [README.md](README.md) first for the concepts
(session kinds, the renderer backend contract, path resolution) — this
file is the *task checklist*, not a second copy of that explanation.

If you're modifying the toolkit itself (not just integrating a course
into it), run `tests/run.sh` before and after — it's the regression
suite for exactly the bugs in the "Gotchas" section below, all of which
were real and all of which it now catches.

## The integration task, in order

1. **Add the submodule.**
   ```bash
   git submodule add https://github.com/boydanderson/course-toolkit.git tooling
   ```
   Use the HTTPS URL, not SSH — CI runners don't have your SSH key.
   Pin to a specific commit deliberately (that's what adding it does by
   default); don't track `main`.

2. **Write `config/course.mk`.** Every key below is real and read by
   `core/cli.sh` — this isn't a partial list:
   ```make
   COURSE_CODE = CS1101S
   COURSE_NAME = Programming Methodology
   HOSTING_ORG = cs1101s
   CANVAS_HOST = canvas.nus.edu.sg
   RENDERER = latex-beamer

   SEMESTER_START_MONDAY = 2026-08-10
   NUM_WEEKS = 13
   RECESS_AFTER_WEEK = 6
   PDF_BASE_URL = https://your-hosting-repo.github.io/pdfs
   ```
   `RECESS_AFTER_WEEK = 0` if there's no mid-semester recess.
   `RENDERER` must be a directory under `backends/` — right now only
   `latex-beamer` is real (see step 5 if the course needs something
   else).

3. **Write `config/session-kinds.conf`** — the course's actual weekly
   shape. Ask the user for it rather than guessing; get concrete
   answers to: how many of each session type per week, which weekdays,
   what PDF variants each produces (or "none" for a single PDF), and
   any *structural* exceptions (an assessment that displaces a session
   on the same weeks every semester — not a one-off holiday, see step 6).
   Format (see README for the full field table):
   ```
   KIND_ID|LABEL|WEEKDAY|SUFFIX|SLOT_PATTERN|VARIANTS|WEEK_START|WEEK_END|EXCLUDE_WEEKS
   ```
   Worked example (two lectures/week, one displaced by a midterm every
   semester):
   ```
   lecture|Lecture|wed|A|L{n}{suffix}|view,print|1|13|7
   lecture|Lecture|fri|B|L{n}{suffix}|view,print|1|13|-
   ```
   Verify it parses correctly before moving on:
   ```bash
   source tooling/core/schedule-lib.sh
   source tooling/core/semester-lib.sh
   while IFS='|' read -r week monday; do
       echo "=== week $week ($monday) ==="
       week_occurrences config/session-kinds.conf "$monday" "$week"
   done < <(semester_weeks 2026-08-10 13 6)
   ```
   Check the output against what the user actually expects, week by
   week, including the exception weeks — this is the step most worth
   getting the user to eyeball before continuing, since everything else
   depends on it being right.

4. **Write `config/content-map.conf`** — `SLOT_ID|SOURCE_PATH` pairs.
   If the course already has some other mapping (a spreadsheet, a
   different config file, a naming convention you can glob), generate
   this file from it programmatically rather than typing it by hand,
   and verify every referenced path actually exists:
   ```bash
   grep -vE '^#|^$' config/content-map.conf | while IFS='|' read -r slot path; do
       [ -f "$path" ] || echo "MISSING: $slot -> $path"
   done
   ```
   No output from that loop means every entry is real.

5. **Confirm the renderer backend.** If `RENDERER = latex-beamer`, check
   that source files exist and follow its convention: everything from
   `\title{...}` through `\begin{document}...\end{document}` (no
   `\documentclass`, no preamble — the backend supplies those). If the
   course needs a different toolchain (Typst, reveal.js, plain HTML
   slides), there's no backend for it yet — you'd need to write one at
   `backends/<name>/` implementing exactly `build-slot.sh`,
   `content-hash.sh`, `extract-title.sh` (see `backends/test/` for the
   minimal template and `backends/latex-beamer/` for a real one). Don't
   build this speculatively — confirm with the user first, since it's
   real new work, not config.

6. **Optional config, add only what's actually needed** (every one of
   these is empty-safe — omit, or point at `/dev/null`, if unused):
   - A release allow-list (one slot ID per line) if the course gates
     what's publicly visible.
   - `config/session-kind-labels.conf` (`WEEK|KIND_ID|LABEL`) for a
     week+kind with no real occurrence that still needs a label (e.g.
     an in-class-only session with no take-home sheet — see this file's
     own real example in `cs1101s/course-materials`).
   - `config/week-notes.conf` (`WEEK|NOTE`) for maintainer notes.
   - `config/holidays.conf` (`DATE|NAME`) + `config/holiday-emoji.conf`
     (`HOLIDAY_NAME|EMOJI`) for holiday-cancellation rendering — this is
     for a *specific semester's* real dates, not the structural
     exceptions from step 3. If the institution already has a holiday
     feed elsewhere in the repo, generate this from it; don't invent
     dates.

7. **Copy `examples/Makefile`** into the repo root, and set any
   `..._FILE` environment variable overrides the Makefile documents for
   config files that aren't at the default generic paths (e.g. if the
   course already had a differently-named allow-list before adopting
   this toolkit).

## Verifying before you consider this done

```bash
make build          # walks the semester, tracks versions, no PDFs yet
make readme          # check the output for real titles, no "-" where
                      # content should be, no literal placeholder text
make canvas           # same check, HTML output
make build-pdfs      # slow -- actually compiles everything once, confirms
                      # the renderer backend genuinely works end to end
```

Specifically look for, in the `readme`/`canvas` output:
- Every week that should have content shows it, with real extracted
  titles (not the slot ID standing in for a missing title, unless that
  content genuinely isn't authored yet).
- The structural exception weeks (step 3) show the right thing —
  usually a missing occurrence, possibly filled by a
  `session-kind-labels.conf` override if you added one.
- If you configured holidays, a slot on a holiday date renders as
  cancelled, not as a normal pending/authored slot.

## Gotchas already hit once each — don't re-discover these

- **macOS ships bash 3.2 as `/bin/bash`.** No `${var,,}`, no `${var^}`.
  Use `tr`/`sed` for case conversion. Every script here targets 3.2;
  test with `/bin/bash script.sh`, not just `bash script.sh` (which may
  resolve to a newer bash on your PATH and hide the problem).
- **A `grep` that finds nothing exits 1** — under `set -e`, a plain
  `x=$(cmd | grep ... )` assignment where the pipeline legitimately
  finds nothing (an unauthored slot, a title not yet recorded — a
  normal state, not a bug) will silently kill the whole script unless
  guarded with `|| true` or the exit status is otherwise absorbed.
  Every lookup in `core/enrich-lib.sh` and the `latex-beamer` backend
  already handles this — if you add a new one, guard it the same way.
- **`${arr[*]}` with a multi-character `IFS` only uses `IFS`'s first
  character**, silently. If you need to join with `"; "` or similar,
  write an explicit loop (see `render-markdown.sh`'s variant-link
  joining or `enrich-lib.sh`'s `week_note` for the pattern) — don't use
  `local IFS='; '; echo "${arr[*]}"`.
- **A version-tracking test run against the real repo root writes into
  the real, tracked `config/versions.conf`.** If you're dry-running or
  testing against a course repo that already has a real ledger, point
  `COURSE_ROOT` at a scratch directory (with its own `config/course.mk`
  copy, since `cli.sh` reads course identity from
  `$COURSE_ROOT/config/course.mk`) instead of the real repo root, or be
  prepared to `git checkout -- config/versions.conf` afterward.
- **`TOOLKIT_DIR` and `COURSE_ROOT` must both be set (and exported)
  before sourcing any `core/*.sh` file.** `cli.sh` handles this itself;
  if you're sourcing the libraries directly instead (see README's
  "Using it"), set both first.

## A real, working example

`cs1101s/course-materials` is the first real consumer — its
`config/course.mk`, `config/session-kinds.conf`, and
`config/content-map.conf` are real, verified-against-real-content
examples, not fixtures. Read those before inventing your own approach
to something this checklist doesn't cover.
