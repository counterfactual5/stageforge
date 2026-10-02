#!/usr/bin/env bash
# test_rollback.sh — end-to-end tests for the verdict/rollback contract.
#
# Runs the real CLI with throwaway runners whose reviewer stage emits verdict
# lines. Covers: pass-through (verdict ok / no verdict), a valid rewind,
# malformed return_to fail-open, budget exhaustion, and max_rollbacks: 0.

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

count_in_log() {
    local file="$1" needle="$2"
    [[ -f "$file" ]] && grep -c "^$needle" "$file" | tr -d ' ' || echo 0
}

# .rollbacks is a human-read, committed file; count only real entries (they
# start with an ISO timestamp) so a future header comment cannot skew counts.
count_rollbacks() {
    local file="$1"
    [[ -f "$file" ]] && grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$file" | tr -d ' ' || echo 0
}

# Success runner whose reviewer reads $REVIEWER_VERDICT_FILE (a file the test
# rewrites between invocations) to decide its verdict lines.
make_runner() {
    local path="$1"
    cat > "$path" <<'RUNNER'
#!/usr/bin/env bash
runner_name() { echo "test-rollback"; }
runner_check() { true; }
runner_run() {
    local stage="$1" workdir="$3" model="${4:-}"
    printf '%s\n' "$stage" >> "$workdir/stages-invocations.log"
    mkdir -p "$workdir/docs" "$workdir/src" "$workdir/stages"
    case "$stage" in
        planner) printf '# plan\n' > "$workdir/docs/PLAN.md" ;;
        builder) printf 'source\n' > "$workdir/src/main.txt" ;;
        reviewer)
            printf '# report\n' > "$workdir/docs/TEST_REPORT.md"
            ;;
        consultant) printf '# readme\n' > "$workdir/docs/README.md" ;;
    esac
    local n
    case "$stage" in
        planner) n=0 ;; builder) n=1 ;; reviewer) n=2 ;; consultant) n=3 ;;
    esac
    {
        date -u +"%Y-%m-%dT%H:%M:%SZ"
        echo "run_id: $STAGEFORGE_RUN_ID"
        if [[ "$stage" == "reviewer" && -n "${REVIEWER_VERDICT_FILE:-}" && -f "$REVIEWER_VERDICT_FILE" ]]; then
            cat "$REVIEWER_VERDICT_FILE"
        fi
    } > "$workdir/stages/.stage_${n}_done"
}
RUNNER
    chmod +x "$path"
}

write_verdict() {
    local file="$1" verdict="$2" return_to="${3:-}"
    {
        echo "verdict: $verdict"
        [[ -n "$return_to" ]] && echo "return_to: $return_to"
    } > "$file"
}

run_pipeline_case() {
    local d="$1" env_pair="${2:-}"
    shift 2
    local runner="$d/runner.sh"
    make_runner "$runner"
    cat > "$d/stageforge.yaml" <<EOF
runner: "$runner"
$@
EOF
    # env -u: the harness must not inherit a budget override, or an ambient
    # STAGEFORGE_MAX_ROLLBACKS silently decides these cases.
    if [[ -n "$env_pair" ]]; then
        env -u STAGEFORGE_MAX_ROLLBACKS "$env_pair" "$STAGEFORGE" run "$d" -t "rollback regression" > "$d/output.log" 2>&1
    else
        env -u STAGEFORGE_MAX_ROLLBACKS "$STAGEFORGE" run "$d" -t "rollback regression" > "$d/output.log" 2>&1
    fi
    echo $?
}

echo "test: verdict / rollback contract"
base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT

# ── 1. Plain pass-through: no verdict file at all (runner writes nothing) ──
d="$base/passthrough"; mkdir -p "$d"
rc=$(run_pipeline_case "$d")
check "no verdict lines: pipeline completes" 0 "$rc"
check "no verdict lines: planner ran once" 1 "$(count_in_log "$d/stages-invocations.log" planner)"

# ── 2. needs_work + return_to 0: the runner always escalates, so the first
# ──    rewind consumes the default budget (3)... use an explicit small case:
# ──    rewind happens, re-run escalates again, budget allows it, etc. With
# ──    defaults (3) planner would run 4x; assert the rewind actually fired.
d="$base/rewind"; mkdir -p "$d"
VF="$d/verdict.txt"
write_verdict "$VF" needs_work 0
rc=$(run_pipeline_case "$d" "REVIEWER_VERDICT_FILE=$VF" "max_rollbacks: 1")
check "rewind case: completes after budget exhaustion (rc 0)" 0 "$rc"
check "rewind case: planner re-ran after needs_work" 2 "$(count_in_log "$d/stages-invocations.log" planner)"
check "rewind case: rollback recorded" 1 "$(count_rollbacks "$d/stages/.rollbacks")"

# ── 3. Malformed return_to fails open with a warning ──
d="$base/malformed"; mkdir -p "$d"
VF="$d/verdict.txt"
printf 'verdict: needs_work\nreturn_to: 9\n' > "$VF"
rc=$(run_pipeline_case "$d" "REVIEWER_VERDICT_FILE=$VF")
check "malformed return_to: pipeline completes" 0 "$rc"
check "malformed return_to: no rewind (planner ran once)" 1 "$(count_in_log "$d/stages-invocations.log" planner)"
check "malformed return_to: warn emitted" 1 "$(grep -c 'invalid return_to' "$d/output.log" | tr -d ' ')"

# ── 4. Budget exhaustion: always needs_work with max_rollbacks: 1 ──
d="$base/budget"; mkdir -p "$d"
VF="$d/verdict.txt"
write_verdict "$VF" needs_work 0
rc=$(run_pipeline_case "$d" "REVIEWER_VERDICT_FILE=$VF" "max_rollbacks: 1")
check "budget exhausted: pipeline still completes" 0 "$rc"
check "budget exhausted: exactly one rollback" 1 "$(count_rollbacks "$d/stages/.rollbacks")"
check "budget exhausted: warn emitted" 1 "$(grep -c 'budget is exhausted' "$d/output.log" | tr -d ' ')"

# ── 5. Non-canonical integer return_to (e.g. "01") fails open, not crash ──
d="$base/zero-padded"; mkdir -p "$d"
VF="$d/verdict.txt"
printf 'verdict: needs_work\nreturn_to: 01\n' > "$VF"
rc=$(run_pipeline_case "$d" "REVIEWER_VERDICT_FILE=$VF" "max_rollbacks: 1")
check "zero-padded return_to: pipeline completes" 0 "$rc"
check "zero-padded return_to: normalized to stage 1 (builder re-runs, planner does not)" 2 "$(count_in_log "$d/stages-invocations.log" builder)"
check "zero-padded return_to: one rollback recorded" 1 "$(count_rollbacks "$d/stages/.rollbacks")"

# ── 6. Unknown verdict value fails open with a visible warning ──
d="$base/unknown-verdict"; mkdir -p "$d"
VF="$d/verdict.txt"
printf 'verdict: NEEDS_WORK\nreturn_to: 0\n' > "$VF"
rc=$(run_pipeline_case "$d" "REVIEWER_VERDICT_FILE=$VF")
check "unknown verdict: pipeline completes" 0 "$rc"
check "unknown verdict: no rewind" 1 "$(count_in_log "$d/stages-invocations.log" planner)"
check "unknown verdict: warn names the raw value" 1 "$(grep -c "unrecognized verdict 'NEEDS_WORK'" "$d/output.log" | tr -d ' ')"

# ── 6. Trailing whitespace / CR in the verdict value still escalates ──
d="$base/dirty-verdict"; mkdir -p "$d"
VF="$d/verdict.txt"
printf 'verdict: needs_work \r\nreturn_to: 0 \r\n' > "$VF"
rc=$(run_pipeline_case "$d" "REVIEWER_VERDICT_FILE=$VF" "max_rollbacks: 1")
check "CRLF/trailing-space verdict: pipeline completes" 0 "$rc"
check "CRLF/trailing-space verdict: still recognized as needs_work" 2 "$(count_in_log "$d/stages-invocations.log" planner)"
check "CRLF/trailing-space verdict: one rollback recorded" 1 "$(count_rollbacks "$d/stages/.rollbacks")"

# ── 7. max_rollbacks: 0 disables rollback entirely ──
d="$base/zero"; mkdir -p "$d"
VF="$d/verdict.txt"
write_verdict "$VF" needs_work 0
rc=$(run_pipeline_case "$d" "REVIEWER_VERDICT_FILE=$VF" "max_rollbacks: 0")
check "max_rollbacks 0: pipeline completes without rewinding" 0 "$rc"
check "max_rollbacks 0: planner ran once" 1 "$(count_in_log "$d/stages-invocations.log" planner)"
check "max_rollbacks 0: no .rollbacks file" no "$( [[ -f "$d/stages/.rollbacks" ]] && echo yes || echo no )"

# ── 8. Budget survives resume (durable, committed audit trail) ──
d="$base/durable"; mkdir -p "$d"
VF="$d/verdict.txt"
write_verdict "$VF" needs_work 0
rc=$(run_pipeline_case "$d" "REVIEWER_VERDICT_FILE=$VF" "max_rollbacks: 1")
check "durable: first run ok" 0 "$rc"
# Re-open the pipeline after its completion signal: the reviewer escalates
# again, and the *persisted* budget (not a per-run counter) must block it.
rm -f "$d/stages/.stage_2_done" "$d/stages/.stage_3_done" "$d/stages/.pipeline_done"
env REVIEWER_VERDICT_FILE="$VF" "$STAGEFORGE" resume "$d" -t "durable" > "$d/resume.log" 2>&1; rc=$?
check "durable: resume completes" 0 "$rc"
check "durable: persisted budget blocks the new escalation" 1 "$(grep -c 'budget is exhausted' "$d/resume.log" | tr -d ' ')"
check "durable: no second rollback recorded" 1 "$(count_rollbacks "$d/stages/.rollbacks")"
check "durable: status reports lifetime budget" 1 "$(grep -c 'Rollbacks used: 1/1 (lifetime per project' "$d/resume.log" | tr -d ' ')"

# ── 9. Rollback crossing this run's start boundary warns loudly ──
d="$base/cross-start"; mkdir -p "$d"
VF="$d/verdict.txt"
# First run: no verdict file yet, so the reviewer passes and stages 0-1
# complete. The budget must stay untouched here, otherwise resume cannot
# exercise the escalation path at all.
rc=$(run_pipeline_case "$d" "" "max_rollbacks: 5")
check "cross-start: setup run completes" 0 "$rc"
# Re-open the pipeline at stage 2, and escalate only from there.
rm -f "$d/stages/.stage_2_done" "$d/stages/.stage_3_done" "$d/stages/.pipeline_done"
write_verdict "$VF" needs_work 0
env -u STAGEFORGE_MAX_ROLLBACKS REVIEWER_VERDICT_FILE="$VF" "$STAGEFORGE" resume "$d" -t "cross" > "$d/resume.log" 2>&1; rc=$?
check "cross-start: resume completes" 0 "$rc"
check "cross-start: resumed from stage 2" yes "$(grep -q 'Resuming from Stage 2' "$d/resume.log" && echo yes || echo no)"
# The reviewer escalates on every re-run, so the warning appears once per
# rollback until the budget is spent — assert presence, not an exact count.
check "cross-start: overwrite warning emitted" yes "$(grep -q "crosses this run's start" "$d/resume.log" && echo yes || echo no)"

echo
echo "Passed: $PASS  Failed: $FAIL"
[[ $FAIL -eq 0 ]]
