#!/usr/bin/env bash
# test_reconcile.sh — unit tests for resume-point reconciliation (validate.sh)
#
# Verifies that reconcile_resume_point() rewinds past stages that are marked
# complete (signal file present) but whose artifacts have gone missing.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../core/compat.sh
source "$ROOT/core/compat.sh"
# shellcheck source=../core/signal.sh
source "$ROOT/core/signal.sh"
# shellcheck source=../core/validate.sh
source "$ROOT/core/validate.sh"

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  ok: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected=$expected got=$actual)" >&2
        FAIL=$((FAIL + 1))
    fi
}

# Build a temp project where every stage 0..max is signalled done with all
# artifacts present.
make_project() {
    local max="$1"
    local dir
    dir="$(mktemp -d)"
    mkdir -p "$dir/docs" "$dir/src" "$dir/stages"
    echo "run-test" > "$dir/stages/.run_id"

    [[ $max -ge 0 ]] && { echo "# plan" > "$dir/docs/PLAN.md"; touch "$dir/stages/.stage_0_done"; }
    [[ $max -ge 1 ]] && { echo "code" > "$dir/src/main.py"; touch "$dir/stages/.stage_1_done"; }
    [[ $max -ge 2 ]] && { echo "# tests" > "$dir/docs/TEST_REPORT.md"; touch "$dir/stages/.stage_2_done"; }
    [[ $max -ge 3 ]] && { echo "# readme" > "$dir/docs/README.md"; touch "$dir/stages/.stage_3_done"; }

    echo "$dir"
}

echo "test: reconcile_resume_point"

# 1. Nothing done → -1
d="$(mktemp -d)"; mkdir -p "$d/stages"
check "empty project → -1" "-1" "$(reconcile_resume_point "$d" 2>/dev/null)"
rm -rf "$d"

# 2. Fully consistent through stage 2 → 2
d="$(make_project 2)"
check "consistent through stage 2 → 2" "2" "$(reconcile_resume_point "$d" 2>/dev/null)"
rm -rf "$d"

# 3. Stage 0 done but PLAN.md deleted → rewind to -1
d="$(make_project 2)"; rm -f "$d/docs/PLAN.md"
check "missing PLAN.md rewinds to -1" "-1" "$(reconcile_resume_point "$d" 2>/dev/null)"
rm -rf "$d"

# 4. Stage 1 done but src/ wiped → stop after stage 0 → 0
d="$(make_project 2)"; rm -rf "$d/src"
check "wiped src rewinds to 0" "0" "$(reconcile_resume_point "$d" 2>/dev/null)"
rm -rf "$d"

# 5. Empty PLAN.md is treated as missing (non-empty required)
d="$(make_project 1)"; : > "$d/docs/PLAN.md"
check "empty PLAN.md rewinds to -1" "-1" "$(reconcile_resume_point "$d" 2>/dev/null)"
rm -rf "$d"

# 6. Soft artifacts (stage 2/3) absent do not block — full chain still valid
d="$(make_project 3)"; rm -f "$d/docs/TEST_REPORT.md" "$d/docs/README.md"
check "soft artifacts absent → still 3" "3" "$(reconcile_resume_point "$d" 2>/dev/null)"
rm -rf "$d"

# 7. Gap in signals: stage 0 done, stage 1 NOT done, stage 2 done → prefix stops at 0
d="$(make_project 2)"; rm -f "$d/stages/.stage_1_done"
check "signal gap stops at 0" "0" "$(reconcile_resume_point "$d" 2>/dev/null)"
rm -rf "$d"

echo
echo "Passed: $PASS  Failed: $FAIL"
[[ $FAIL -eq 0 ]]
