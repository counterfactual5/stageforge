#!/usr/bin/env bash
# signal.sh — Stage signal file protocol for stageforge
#
# Each stage creates a signal file `stages/.stage_<N>_done` upon completion.
# A signal file is considered "valid" only if it matches the current run-ID.
# Run-IDs are recorded in `stages/.run_id` at the start of every pipeline run:
# one id per line, oldest first, the LAST line being the current id. Keeping
# the recent ids lets resume trust a legitimate chain of runs while still
# rejecting foreign/truncated/unknown ids from elsewhere.
#
# Signal file format (line 1 = ISO timestamp, line 2 = run_id, the rest is optional summary):
#   2026-05-28T07:30:00Z
#   run_id: 1716889800-12345-678
#   <optional stage-specific summary lines>

# ─── Run-ID Management ───

# Append a run-ID to the known-runs history in stages/.run_id.
# The file holds one run-ID per line, oldest first; the LAST line is the
# current run-ID. Keeping a short history lets resume trust signals from
# earlier runs in a legitimate resume chain (stage 0 from run A, stage 1 from
# resume run B) while still rejecting foreign ids. Ten is deliberately a small,
# bounded history: a run with a signal older than ten subsequent runs rewinds
# conservatively rather than trusting an unbounded state file.
# Single-writer contract: callers must hold the per-project run lock. The
# temp-file + rename makes publication atomic for readers, but concurrent
# read/modify/write callers could otherwise lose one another's appended IDs.
# Usage: signal_record_run <project_dir> <run_id>
signal_record_run() {
    local project_dir="$1"
    local run_id="$2"
    mkdir -p "$project_dir/stages"

    local ids_file="$project_dir/stages/.run_id"
    # Publish via mktemp + mv in the SAME directory: the rename is atomic, so
    # a concurrent signal_current_run_id reader never sees a truncated file
    # (a cross-device mv would copy in place). temp_file gives a randomized,
    # unpredictable name — a fixed `$$` suffix can collide after PID reuse
    # and races between writers.
    local tmp
    tmp=$(temp_file "$project_dir/stages") || return 1
    {
        [[ -f "$ids_file" ]] && cat "$ids_file"
        echo "$run_id"
    } | tail -n 10 > "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$ids_file" || { rm -f "$tmp"; return 1; }
}

# Initialize a fresh run-ID for this pipeline run.
# Usage: signal_init_run <project_dir>
# Prints the new run-ID to stdout and records it in stages/.run_id.
signal_init_run() {
    local project_dir="$1"
    local run_id
    run_id="$(date +%s)-$$-${RANDOM}${RANDOM}"
    signal_record_run "$project_dir" "$run_id"
    echo "$run_id"
}

# Read the current (most recent) run-ID (empty if not yet initialized).
# Usage: signal_current_run_id <project_dir>
signal_current_run_id() {
    local project_dir="$1"
    local run_id_file="$project_dir/stages/.run_id"
    [[ -f "$run_id_file" ]] && tail -n 1 "$run_id_file" || true
}

# ─── Signal File Creation ───

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

# Read the optional verdict lines from a done-signal.
# Prints "<verdict>|<return_to>"; either side may be empty. verdict is
# ok|needs_work when well-formed; return_to is an integer when present.
# Callers MUST treat every other shape as malformed (fail-open: warn and
# continue) — this function only reports what is written, it does not judge.
# Usage: signal_read_verdict <stage_num> <project_dir>
signal_read_verdict() {
    local stage_num="$1"
    local project_dir="$2"
    local signal_file="$project_dir/stages/.stage_${stage_num}_done"
    local v="" r=""
    if [[ -f "$signal_file" ]]; then
        v=$(grep -m1 '^verdict:' "$signal_file" 2>/dev/null | sed -E 's/^verdict:[[:space:]]*//' || true)
        r=$(grep -m1 '^return_to:' "$signal_file" 2>/dev/null | sed -E 's/^return_to:[[:space:]]*//' || true)
    fi
    printf '%s|%s\n' "$v" "$r"
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

# Whether a stage's done-signal can be trusted on resume, based on its
# embedded run_id (complements the artifact checks in validate.sh):
#   - signal has no `run_id:` line at all  -> legacy signal (pre run-ID
#     protocol): accepted here; reconciliation still verifies its artifacts.
#   - run_id line present                  -> value must be non-empty, not
#     "unknown", and match one line of the stages/.run_id history.
# A truncated or foreign run_id therefore rewinds the resume point instead of
# silently skipping a stage that no known run vouched for.
# Usage: signal_trusted_on_resume <stage_num> <project_dir>
signal_trusted_on_resume() {
    local stage_num="$1"
    local project_dir="$2"
    local signal_file="$project_dir/stages/.stage_${stage_num}_done"
    local run_id_file="$project_dir/stages/.run_id"

    [[ -f "$signal_file" ]] || return 1

    local line
    line=$(grep -m1 '^run_id:' "$signal_file" 2>/dev/null || true)
    if [[ -z "$line" ]]; then
        # Legacy signal (pre run-ID protocol) with no run_id line. Accepted on
        # artifact checks alone — but this is also the shape anyone can fake
        # with `touch stages/.stage_3_done`, so make the trust basis visible
        # instead of deciding silently. [VALIDATE] prefix: same resume-reason
        # stream as reconcile_resume_point's rewind messages (stderr).
        echo "[VALIDATE] WARN: Stage $stage_num signal has no run_id line (legacy v0.3 format) — trusting it on artifact checks only, it was never run-ID verified." >&2
        return 0
    fi

    local id="${line#run_id:}"
    id="${id#"${id%%[![:space:]]*}"}"   # ltrim
    id="${id%"${id##*[![:space:]]}"}"   # rtrim

    [[ -n "$id" && "$id" != "unknown" ]] || return 1
    [[ -f "$run_id_file" ]] || return 1
    grep -Fxq -- "$id" "$run_id_file"
}

# Get the highest stage number whose signal file exists (existence only —
# NOT run-id verified; callers that must trust the signal use
# signal_verify / signal_trusted_on_resume instead).
# Returns -1 if none. Used by resume to describe recorded (unreconciled) state.
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
