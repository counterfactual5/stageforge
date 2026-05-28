#!/usr/bin/env bash
# compat.sh — Cross-platform compatibility helpers for stageforge
# Provides date, mktemp, and grep-oP that work on both macOS and Linux.

is_macos() {
    [[ "$(uname)" == "Darwin" ]]
}

# Cross-platform ISO timestamp
# Usage: timestamp=$(date_iso)
date_iso() {
    if is_macos; then
        # macOS date doesn't support -Iseconds
        date -u +"%Y-%m-%dT%H:%M:%S%z"
    else
        date -Iseconds
    fi
}

# Cross-platform temp file creation
# Usage: file=$(temp_file)
temp_file() {
    if is_macos; then
        mktemp /tmp/stageforge-XXXXXXXX
    else
        mktemp /tmp/stageforge-prompt-XXXXXX.md
    fi
}

# Cross-platform grep with PCRE-style patterns
# Usage: value=$(grep_oP "pattern" "$file")
grep_oP() {
    local pattern="$1"
    local file="$2"
    if is_macos && ! echo "" | grep -oP '' 2>/dev/null; then
        # macOS grep: no -P support, use perl
        perl -nle "print \$1 if /$pattern/" "$file"
    else
        grep -oP "$pattern" "$file" 2>/dev/null
    fi
}
