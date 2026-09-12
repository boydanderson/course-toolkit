#!/bin/bash
# Shared _md5 helper for every backends/*/content-hash.sh -- macOS's BSD
# `md5` has no `md5sum`; GNU coreutils' `md5sum` has no `-q`, hence the
# branch. Sourced (never executed directly) by each backend's own
# content-hash.sh, since all three need this exact same platform check
# and none of it is renderer-specific.
_md5() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum | cut -d' ' -f1
    else
        md5 -q
    fi
}
