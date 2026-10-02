#!/usr/bin/env bash
# compat.sh — Cross-platform compatibility helpers for stageforge
# Provides date, mktemp, and grep-oP that work on both macOS and Linux.

is_macos() {
    [[ "$(uname)" == "Darwin" ]]
}

# ISO timestamp, same format on every platform.
# BSD `date` has no -Iseconds, and GNU -Iseconds emits local offsets while
# BSD %z formatting varies — hardcode UTC so signal files look identical
# regardless of host OS. Nothing parses line 1; it is display-only.
# Usage: timestamp=$(date_iso)
date_iso() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Cross-platform temp file creation.
# Usage: file=$(temp_file [dir])   dir defaults to ${TMPDIR:-/tmp}.
# Callers that publish atomically via rename MUST pass the destination's
# directory so the temp file lives on the same filesystem (a cross-device
# mv copies in place and re-exposes the truncated-file window).
# The X's MUST be at the end of the template: BSD mktemp silently creates a
# *fixed-name* file (no randomization) when they are not, and GNU mktemp
# support for a trailing suffix is version-dependent.
temp_file() {
    local dir="${1:-${TMPDIR:-/tmp}}"
    mktemp "$dir/stageforge-XXXXXX"
}

# Cross-platform grep with PCRE-style patterns
# Usage: value=$(grep_oP "pattern" "$file")
grep_oP() {
    local pattern="$1"
    local file="$2"
    if is_macos && ! echo "" | grep -oP '' 2>/dev/null; then
        # macOS grep: no -P support, use perl.
        # Print $& (the full match), not $1: these patterns use \K to drop the
        # prefix and have no capture group, so $1 would print empty even when
        # the pattern matches. \K is honored for $& in perl too.
        perl -nle "print \$& if /$pattern/" "$file"
    else
        grep -oP "$pattern" "$file" 2>/dev/null
    fi
}
