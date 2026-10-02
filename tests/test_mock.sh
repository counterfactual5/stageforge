#!/usr/bin/env bash
# test_mock.sh — end-to-end tests for the mock runner's failure injection.
#
# The mock runner is the public, agent-free way to exercise the pipeline;
# these tests prove each injected failure mode drives the matching
# orchestrator branch, using the real CLI and the shipped mock.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STAGEFORGE="$ROOT/bin/stageforge"

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

yes_no() { [[ -e "$1" ]] && echo yes || echo no; }

# run_mock <dir> [ENV=VALUE ...] — runs `stageforge run` with runner: mock.
run_mock() {
    local d="$1"; shift
    mkdir -p "$d"
    printf 'runner: mock\nmax_retries: 2\n' > "$d/stageforge.yaml"
    if [[ $# -gt 0 ]]; then
        env "$@" "$STAGEFORGE" run "$d" -t "mock failure injection" > "$d/output.log" 2>&1
    else
        "$STAGEFORGE" run "$d" -t "mock failure injection" > "$d/output.log" 2>&1
    fi
    echo $?
}

echo "test: mock runner failure injection"
base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT

# ── 1. Default: no injection, full pipeline completes ──
d="$base/happy"; rc=$(run_mock "$d")
check "no injection: pipeline completes" 0 "$rc"
check "no injection: all four stages done" yes "$(yes_no "$d/stages/.pipeline_done")"

# ── 2. FAIL_STAGES: retry loop runs, then failure signal + rc 1 ──
d="$base/fail"; rc=$(run_mock "$d" "STAGEFORGE_MOCK_FAIL_STAGES=builder")
check "fail: pipeline exits non-zero" 1 "$rc"
check "fail: failure signal written" yes "$(yes_no "$d/stages/.stage_1_failed")"
check "fail: no completion signal" no "$(yes_no "$d/stages/.pipeline_done")"
check "fail: retried exactly max_retries times" 2 "$(grep -c 'Stage 1 (builder) — attempt' "$d/output.log" | tr -d ' ')"
check "fail: downstream stage never ran" 0 "$(grep -c 'Stage 2 (reviewer)' "$d/output.log" | tr -d ' ')"

# ── 3. NO_SIGNAL: runner succeeds but no signal → distinct orchestrator warn ──
d="$base/nosignal"; rc=$(run_mock "$d" "STAGEFORGE_MOCK_NO_SIGNAL=builder")
check "no-signal: pipeline exits non-zero" 1 "$rc"
check "no-signal: distinct warn emitted" yes "$(grep -q 'did not write signal file' "$d/output.log" && echo yes || echo no)"
check "no-signal: failure signal written" yes "$(yes_no "$d/stages/.stage_1_failed")"

# ── 4. STALE_SIGNAL: foreign run_id → verify mismatch, stale removed, retry ──
d="$base/stale"; rc=$(run_mock "$d" "STAGEFORGE_MOCK_STALE_SIGNAL=builder")
check "stale: pipeline exits non-zero" 1 "$rc"
check "stale: stale-signal branch taken" yes "$(grep -q 'run_id mismatch' "$d/output.log" && echo yes || echo no)"
check "stale: mismatched signal removed" no "$(yes_no "$d/stages/.stage_1_done")"

# ── 5. Injection is per-stage: failing builder leaves planner intact ──
d="$base/isolation"; rc=$(run_mock "$d" "STAGEFORGE_MOCK_FAIL_STAGES=builder")
check "isolation: pipeline fails" 1 "$rc"
check "isolation: planner signal kept" yes "$(yes_no "$d/stages/.stage_0_done")"
check "isolation: resume then completes (planner reused)" 0 "$( "$STAGEFORGE" resume "$d" -t mock > "$d/resume.log" 2>&1; echo $? )"
check "isolation: resume did not re-run planner" no "$(grep -q 'attempt 1/2 (run_id=' <(grep -A0 'Stage 0 (planner)' "$d/resume.log") && echo yes || echo no)"

echo
echo "Passed: $PASS  Failed: $FAIL"
[[ $FAIL -eq 0 ]]