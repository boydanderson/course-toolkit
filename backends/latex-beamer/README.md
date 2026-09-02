# latex-beamer backend

The LaTeX/Beamer renderer backend, implementing the [renderer backend
contract](../../README.md#renderer-backend-contract):

- `build-slot.sh` -- assembles `\documentclass{beamer}` + `preamble.tex`
  + an optional per-variant `headers/<variant>.tex` + the source file
  (expected to hold `\title{}`/`\author{}`/etc. through
  `\begin{document}...\end{document}`, same convention as
  cs1101s/course-materials' `src/lectures/lecture-N.tex` files), and
  compiles it with `pdflatex`.
- `content-hash.sh` -- hashes the source file plus the shared preamble
  and this variant's header, so a preamble/theme change invalidates
  every slot's cached version, not just the ones that edited their own
  body.
- `extract-title.sh` -- pulls `\title{...}` out of a source file.

`preamble.tex` is deliberately minimal and de-branded -- the standard
Beamer `default` theme, not a port of cs1101s/course-materials'
`beamerthemeCS1101S.sty` (custom colors, macros, nebula badge). Porting
that real visual design is course-specific polish for when
cs1101s/course-materials actually migrates onto this toolkit, not
something this generic backend bakes in.

`headers/print.tex` is a small worked example of the per-variant header
mechanism (flattens colors for a "print" variant) -- not a port of the
original's `bwheader.tex`, just proof the mechanism works.
