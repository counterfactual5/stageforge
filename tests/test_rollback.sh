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
    if [[ -n "$env_pair" ]]; then
        env "$env_pair" "$STAGEFORGE" run "$d" -t "rollback regression" > "$d/output.log" 2>&1
    else
        "$STAGEFORGE" run "$d" -t "rollback regression" > "$d/output.log" 2>&1
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
check "rewind case: rollback recorded" 1 "$(count_in_log "$d/stages/.rollbacks" .)"

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
check "budget exhausted: exactly one rollback" 1 "$(count_in_log "$d/stages/.rollbacks" .)"
check "budget exhausted: warn emitted" 1 "$(grep -c 'budget is exhausted' "$d/output.log" | tr -d ' ')"

# ── 5. max_rollbacks: 0 disables rollback entirely ──
d="$base/zero"; mkdir -p "$d"
VF="$d/verdict.txt"
write_verdict "$VF" needs_work 0
rc=$(run_pipeline_case "$d" "REVIEWER_VERDICT_FILE=$VF" "max_rollbacks: 0")
check "max_rollbacks 0: pipeline completes without rewinding" 0 "$rc"
check "max_rollbacks 0: planner ran once" 1 "$(count_in_log "$d/stages-invocations.log" planner)"
check "max_rollbacks 0: no .rollbacks file" no "$( [[ -f "$d/stages/.rollbacks" ]] && echo yes || echo no )"

# ── 6. Budget survives resume (durable, committed audit trail) ──
d="$base/durable"; mkdir -p "$d"
VF="$d/verdict.txt"
write_verdict "$VF" needs_work 0
rc=$(run_pipeline_case "$d" "REVIEWER_VERDICT_FILE=$VF" "max_rollbacks: 1")
check "durable: first run ok" 0 "$rc"
cd "$d" > /dev/null 2>&1 || true
"$STAGEFORGE" resume "$d" -t "durable" > "$d/resume.log" 2>&1; rc=$?
cd - > /dev/null 2>&1 || true
check "durable: resume completes" 0 "$rc"
check "durable: budget persisted across runs" 1 "$(grep -c 'Rollbacks used: 1/1' "$d/resume.log" | tr -d ' ')"

echo
echo "Passed: $PASS  Failed: $FAIL"
[[ $FAIL -eq 0 ]]
