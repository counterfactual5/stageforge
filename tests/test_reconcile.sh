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

# ─── run-ID trust rules (signal_trusted_on_resume via reconcile) ───
# Write a proper v0.4-style signal (timestamp line + run_id line).
write_signal() {
    local dir="$1" stage="$2" run_id="$3"
    {
        echo "2026-05-28T00:00:00Z"
        echo "run_id: $run_id"
    } > "$dir/stages/.stage_${stage}_done"
}

# 8. Explicit run_id matching stages/.run_id history → trusted (fixture
#    make_project writes 'run-test' as the only known id).
d="$(make_project 2)"
write_signal "$d" 0 "run-test"; write_signal "$d" 1 "run-test"; write_signal "$d" 2 "run-test"
check "matching run_ids → 2" "2" "$(reconcile_resume_point "$d" 2>/dev/null)"
rm -rf "$d"

# 9. Foreign run_id on stage 1 (not in history) → rewind to stage 0.
d="$(make_project 2)"
write_signal "$d" 0 "run-test"; write_signal "$d" 1 "some-other-run"
check "foreign run_id rewinds to 0" "0" "$(reconcile_resume_point "$d" 2>/dev/null)"
rm -rf "$d"

# 10. 'unknown' run_id (a malformed signal from an interrupted run) → rewind.
d="$(make_project 2)"
write_signal "$d" 1 "unknown"
check "unknown run_id rewinds to 0" "0" "$(reconcile_resume_point "$d" 2>/dev/null)"
rm -rf "$d"

# 11. Truncated run_id line → no history match → rewind to before it.
d="$(make_project 2)"
write_signal "$d" 0 "run-tes"   # partial copy of "run-test"
check "truncated run_id rewinds to -1" "-1" "$(reconcile_resume_point "$d" 2>/dev/null)"
rm -rf "$d"

# 12. Legitimate multi-run resume chain: stage 0 from an older recorded run,
#     stage 1 from the newest one (both present in .run_id history) → 1.
d="$(make_project 1)"
write_signal "$d" 0 "run-test"; write_signal "$d" 1 "run-newer"
signal_record_run "$d" "run-newer"
check "multi-run chain honored" "1" "$(reconcile_resume_point "$d" 2>/dev/null)"
check "current id is newest line" "run-newer" "$(signal_current_run_id "$d")"
rm -rf "$d"

# 13. run_id present but the .run_id history file is gone → untrustworthy.
d="$(make_project 1)"; rm -f "$d/stages/.run_id"
write_signal "$d" 0 "run-test"
check "no history file rejects id-bearing signal" "-1" "$(reconcile_resume_point "$d" 2>/dev/null)"
rm -rf "$d"

# 14. signal_verify stays strict for in-flight verification: an exact-id
#     signal verifies, a legacy empty one does not (old run must not count).
d="$(make_project 0)"
write_signal "$d" 0 "run-test"
if signal_verify 0 "$d" "run-test"; then check "signal_verify exact match" "pass" "pass"; else check "signal_verify exact match" "pass" "fail"; fi
: > "$d/stages/.stage_0_done"   # truncate: a no-id signal never verifies
if signal_verify 0 "$d" "run-test"; then check "signal_verify rejects empty signal" "fail" "pass"; else check "signal_verify rejects empty signal" "fail" "fail"; fi
rm -rf "$d"

echo
echo "Passed: $PASS  Failed: $FAIL"
[[ $FAIL -eq 0 ]]
