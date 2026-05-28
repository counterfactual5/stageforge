#!/usr/bin/env bash
# signal.sh — Stage signal file protocol for stageforge
#
# Each stage creates a signal file `stages/.stage_<N>_done` upon completion.
# A signal file is considered "valid" only if it matches the current run-ID,
# which is stored in `stages/.run_id` at the start of every pipeline run.
#
# Signal file format (line 1 = ISO timestamp, line 2 = run_id, the rest is optional summary):
#   2026-05-28T15:30:00+08:00
#   run_id: 1716889800-12345-678
#   <optional stage-specific summary lines>

# ─── Run-ID Management ───

# Initialize a fresh run-ID for this pipeline run.
# Usage: signal_init_run <project_dir>
# Prints the new run-ID to stdout and persists it to stages/.run_id.
signal_init_run() {
    local project_dir="$1"
    mkdir -p "$project_dir/stages"

    local run_id
    run_id="$(date +%s)-$$-${RANDOM}${RANDOM}"
    echo "$run_id" > "$project_dir/stages/.run_id"
    echo "$run_id"
}

# Read the current run-ID (empty if not yet initialized).
# Usage: signal_current_run_id <project_dir>
signal_current_run_id() {
    local project_dir="$1"
    local run_id_file="$project_dir/stages/.run_id"
    [[ -f "$run_id_file" ]] && cat "$run_id_file" || true
}

# ─── Signal File Creation ───

# Create a stage completion signal that embeds the current run-ID.
# Usage: signal_complete <stage_num> <project_dir> [summary]
signal_complete() {
    local stage_num="$1"
    local project_dir="$2"
    local summary="${3:-}"

    mkdir -p "$project_dir/stages"

    local signal_file="$project_dir/stages/.stage_${stage_num}_done"
    local timestamp
    timestamp=$(date_iso)
    local run_id
    run_id="${STAGEFORGE_RUN_ID:-$(signal_current_run_id "$project_dir")}"

    {
        echo "$timestamp"
        echo "run_id: ${run_id:-unknown}"
        [[ -n "$summary" ]] && echo "$summary"
    } > "$signal_file"

    echo "[SIGNAL] Stage $stage_num complete at $timestamp (run_id=${run_id:-unknown})"
}

# Mark a stage as failed.
# Usage: signal_fail <stage_num> <project_dir> <error_message>
signal_fail() {
    local stage_num="$1"
    local project_dir="$2"
    local error_msg="$3"

    mkdir -p "$project_dir/stages"

    local signal_file="$project_dir/stages/.stage_${stage_num}_failed"
    local timestamp
    timestamp=$(date_iso)
    local run_id
    run_id="${STAGEFORGE_RUN_ID:-$(signal_current_run_id "$project_dir")}"

    {
        echo "$timestamp"
        echo "run_id: ${run_id:-unknown}"
        echo "ERROR: $error_msg"
    } > "$signal_file"

    echo "[SIGNAL] Stage $stage_num FAILED at $timestamp: $error_msg" >&2
}

# ─── Signal File Inspection ───

# Existence check only (legacy semantics — used by status/resume).
# Usage: signal_check <stage_num> <project_dir>
signal_check() {
    local stage_num="$1"
    local project_dir="$2"
    [[ -f "$project_dir/stages/.stage_${stage_num}_done" ]]
}

# Extract the run_id stored inside a signal file (empty if absent).
# Usage: signal_read_run_id <stage_num> <project_dir>
signal_read_run_id() {
    local stage_num="$1"
    local project_dir="$2"
    local signal_file="$project_dir/stages/.stage_${stage_num}_done"
    [[ -f "$signal_file" ]] || return 1
    grep -m1 '^run_id:' "$signal_file" 2>/dev/null \
        | sed -E 's/^run_id:[[:space:]]*//'
}

# Verify that a signal file exists AND was produced by the expected run.
# Usage: signal_verify <stage_num> <project_dir> [expected_run_id]
# If expected_run_id is omitted, uses $STAGEFORGE_RUN_ID, else falls back to .run_id.
signal_verify() {
    local stage_num="$1"
    local project_dir="$2"
    local expected="${3:-${STAGEFORGE_RUN_ID:-$(signal_current_run_id "$project_dir")}}"

    signal_check "$stage_num" "$project_dir" || return 1
    [[ -n "$expected" ]] || return 1

    local actual
    actual=$(signal_read_run_id "$stage_num" "$project_dir" || true)
    [[ "$actual" == "$expected" ]]
}

# Get the highest stage number whose signal file exists (existence only).
# Returns -1 if none. Used by resume / status.
# Usage: signal_last_complete <project_dir>
signal_last_complete() {
    local project_dir="$1"
    local last=-1
    for i in 0 1 2 3; do
        if signal_check "$i" "$project_dir"; then
            last=$i
        fi
    done
    echo "$last"
}

# ─── Signal File Cleanup ───

# Clean ALL stage signals plus .pipeline_done and .run_id.
# Usage: signal_clean <project_dir>
signal_clean() {
    local project_dir="$1"
    rm -f "$project_dir"/stages/.stage_*_done
    rm -f "$project_dir"/stages/.stage_*_failed
    rm -f "$project_dir"/stages/.pipeline_done
    rm -f "$project_dir"/stages/.run_id
    echo "[SIGNAL] All signals cleaned."
}

# Clean signals from a given stage onwards (preserve completed earlier stages).
# Also always removes .pipeline_done because the pipeline is no longer "done".
# Usage: signal_clean_from <project_dir> <start_stage>
signal_clean_from() {
    local project_dir="$1"
    local start_stage="${2:-0}"

    mkdir -p "$project_dir/stages"

    local removed=()
    for i in 0 1 2 3; do
        if [[ $i -ge $start_stage ]]; then
            if [[ -f "$project_dir/stages/.stage_${i}_done" ]]; then
                rm -f "$project_dir/stages/.stage_${i}_done"
                removed+=("$i")
            fi
            rm -f "$project_dir/stages/.stage_${i}_failed"
        fi
    done
    rm -f "$project_dir/stages/.pipeline_done"

    if [[ ${#removed[@]} -gt 0 ]]; then
        echo "[SIGNAL] Cleaned stale signals for stages: ${removed[*]}"
    fi
}
