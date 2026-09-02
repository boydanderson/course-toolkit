# Sample Makefile for a course repo consuming course-toolkit as a git
# submodule at tooling/. Copy this into your repo's root and adjust the
# CONFIG overrides below to match your actual file names -- everything
# here just calls tooling/core/cli.sh, which does the real work (see its
# own header comment and the toolkit README for the full contract).
#
# This is deliberately NOT something you `include` -- course-toolkit
# ships a reusable engine (core/*.sh), not a generic Make layer. Each
# consuming repo owns its own Makefile and target names, customized
# however suits it; only the underlying cli.sh calls need to stay
# consistent with the toolkit's actual interface.

TOOLKIT_DIR ?= tooling
COURSE_ROOT ?= .
CLI := $(TOOLKIT_DIR)/core/cli.sh

export TOOLKIT_DIR
export COURSE_ROOT

# Uncomment and adjust any of these if your config files aren't at
# cli.sh's default generic paths (see its header comment for the full
# list and defaults) -- e.g. if you already have differently-named files
# from before adopting the toolkit:
# export ALLOWLIST_FILE := config/canvas-release.conf
# export NOTES_FILE := config/canvas-week-notes.conf

.PHONY: build
build: ## Walk the semester: extract titles, hash content, track versions
	$(CLI) build

.PHONY: build-pdfs
build-pdfs: ## Same as build, but also actually compiles every PDF (slow)
	$(CLI) build --pdfs

.PHONY: readme
readme: ## Regenerate README.md's calendar table between known markers
	$(CLI) readme > build/README-calendar.md
	@echo "Wrote build/README-calendar.md -- splice it into README.md"
	@echo "between your own <!-- CALENDAR_START --> / <!-- CALENDAR_END -->"
	@echo "markers (course-toolkit doesn't do this splicing for you -- it's"
	@echo "a one-line sed/awk step you write once for your own README)."

.PHONY: canvas
canvas: ## Render the Canvas-release-page HTML table
	$(CLI) canvas > build/canvas-table.html
	@echo "Wrote build/canvas-table.html"

.PHONY: bump-version
bump-version: ## make bump-version SLOT=L1A VARIANT=view
	@if [ -z "$(SLOT)" ] || [ -z "$(VARIANT)" ]; then \
		echo "Usage: make bump-version SLOT=<id> VARIANT=<variant>"; \
		exit 1; \
	fi
	$(CLI) bump $(SLOT) $(VARIANT)
