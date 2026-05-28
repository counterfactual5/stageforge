#!/usr/bin/env bash
# signal.sh — Stage signal file protocol for stageforge
# Each stage creates a signal file upon completion for orchestration.

# Create a stage completion signal
# Usage: signal_complete <stage_num> <project_dir> [summary]
signal_complete() {
    local stage_num="$1"
    local project_dir="$2"
    local summary="${3:-}"
    
    mkdir -p "$project_dir/stages"
    
    local signal_file="$project_dir/stages/.stage_${stage_num}_done"
    local timestamp
    timestamp=$(date -Iseconds)
    
    {
        echo "$timestamp"
        [[ -n "$summary" ]] && echo "$summary"
    } > "$signal_file"
    
    echo "[SIGNAL] Stage $stage_num complete at $timestamp"
}

# Check if a stage is complete
# Usage: signal_check <stage_num> <project_dir>
# Returns 0 if complete, 1 if not
signal_check() {
    local stage_num="$1"
    local project_dir="$2"
    
    [[ -f "$project_dir/stages/.stage_${stage_num}_done" ]]
}

# Mark a stage as failed
# Usage: signal_fail <stage_num> <project_dir> <error_message>
signal_fail() {
    local stage_num="$1"
    local project_dir="$2"
    local error_msg="$3"
    
    mkdir -p "$project_dir/stages"
    
    local signal_file="$project_dir/stages/.stage_${stage_num}_failed"
    local timestamp
    timestamp=$(date -Iseconds)
    
    {
        echo "$timestamp"
        echo "ERROR: $error_msg"
    } > "$signal_file"
    
    echo "[SIGNAL] Stage $stage_num FAILED at $timestamp: $error_msg" >&2
}

# Clean all signals (for re-running pipeline)
# Usage: signal_clean <project_dir>
signal_clean() {
    local project_dir="$1"
    
    rm -f "$project_dir"/stages/.stage_*_done
    rm -f "$project_dir"/stages/.stage_*_failed
    rm -f "$project_dir"/stages/.pipeline_done
    
    echo "[SIGNAL] All signals cleaned."
}

# Get the last completed stage number
# Usage: signal_last_complete <project_dir>
# Prints the stage number (or -1 if none)
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
