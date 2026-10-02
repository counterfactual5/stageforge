#!/usr/bin/env bash
# test_config.sh — end-to-end regression tests for stageforge.yaml loading.
#
# Exercises the real CLI with temporary custom runners: the same load_config()
# and run_pipeline() path users invoke, not a copy of their parsing logic.

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

make_success_runner() {
    local path="$1"
    cat > "$path" <<'RUNNER'
#!/usr/bin/env bash
runner_name() { echo "test-success"; }
runner_check() { true; }
runner_run() {
    local stage="$1" workdir="$3" model="${4:-}"
    printf '%s=%s\n' "$stage" "$model" >> "$workdir/models.log"
    mkdir -p "$workdir/docs" "$workdir/src" "$workdir/stages"
    case "$stage" in
        planner) printf '# plan\n' > "$workdir/docs/PLAN.md" ;;
        builder) printf 'source\n' > "$workdir/src/main.txt" ;;
        reviewer) printf '# report\n' > "$workdir/docs/TEST_REPORT.md" ;;
        consultant) printf '# readme\n' > "$workdir/docs/README.md" ;;
    esac
    # Stage names are not numeric, so map them after creating artifacts.
    case "$stage" in
        planner) n=0 ;; builder) n=1 ;; reviewer) n=2 ;; consultant) n=3 ;;
    esac
    {
        date -u +"%Y-%m-%dT%H:%M:%SZ"
        echo "run_id: $STAGEFORGE_RUN_ID"
    } > "$workdir/stages/.stage_${n}_done"
}
RUNNER
    chmod +x "$path"
}

make_failing_runner() {
    local path="$1"
    cat > "$path" <<'RUNNER'
#!/usr/bin/env bash
runner_name() { echo "test-fail"; }
runner_check() { true; }
runner_run() {
    local workdir="$3"
    echo attempt >> "$workdir/attempts.log"
    return 1
}
RUNNER
    chmod +x "$path"
}

count_attempts() {
    local file="$1"
    [[ -f "$file" ]] && wc -l < "$file" | tr -d ' ' || echo 0
}

run_success_config_case() {
    local d="$1"
    local runner="$d/success-runner.sh"
    make_success_runner "$runner"
    cat > "$d/stageforge.yaml" <<EOF
# runner: ignored-comment
runner: "$runner"
models:
  planner: "planner model"
  builder: "builder model"
  reviewer: "reviewer model"
  consultant: "consultant model"
max_retries: "2"
EOF
    "$STAGEFORGE" run "$d" -t "config regression" > "$d/output.log" 2>&1
    local rc=$?
    check "quoted runner config completes" 0 "$rc"
    check "planner model loaded" "planner=planner model" "$(sed -n '1p' "$d/models.log")"
    check "builder model loaded" "builder=builder model" "$(sed -n '2p' "$d/models.log")"
    check "reviewer model loaded" "reviewer=reviewer model" "$(sed -n '3p' "$d/models.log")"
    check "consultant model loaded" "consultant=consultant model" "$(sed -n '4p' "$d/models.log")"
}

run_retry_case() {
    local d="$1" configured="$2" env_value="${3:-}"
    local runner="$d/fail-runner.sh"
    make_failing_runner "$runner"
    cat > "$d/stageforge.yaml" <<EOF
runner: "$runner"
max_retries: $configured
EOF
    if [[ -n "$env_value" ]]; then
        STAGEFORGE_MAX_RETRIES="$env_value" "$STAGEFORGE" run "$d" -t "retry regression" > "$d/output.log" 2>&1
    else
        "$STAGEFORGE" run "$d" -t "retry regression" > "$d/output.log" 2>&1
    fi
    local rc=$?
    check "retry case config=$configured env=${env_value:-unset} fails" 1 "$rc"
    check "retry count config=$configured env=${env_value:-unset}" "${env_value:-$configured}" "$(count_attempts "$d/attempts.log")"
}

echo "test: stageforge.yaml loading"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/models"
run_success_config_case "$tmp/models"

mkdir -p "$tmp/config-retries"
run_retry_case "$tmp/config-retries" 2

mkdir -p "$tmp/env-wins"
run_retry_case "$tmp/env-wins" 2 1

mkdir -p "$tmp/zero"
run_retry_case "$tmp/zero" 0

echo
echo "Passed: $PASS  Failed: $FAIL"
[[ $FAIL -eq 0 ]]
