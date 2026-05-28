#!/usr/bin/env bash
# pipeline.sh — Core pipeline orchestration for stageforge
# Orchestrates the four-stage development loop with retry and fallback.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/compat.sh"

source "$SCRIPT_DIR/signal.sh"
source "$SCRIPT_DIR/validate.sh"

# ─── Pipeline Configuration ───
MAX_RETRIES=3
FALLBACK_MODEL=""

# ─── Run a single stage with retry ───
# Usage: run_stage <stage_num> <stage_name> <runner_path> <project_dir> <prompt> <model> [mode]
run_stage() {
    local stage_num="$1"
    local stage_name="$2"
    local runner_path="$3"
    local project_dir="$4"
    local prompt="$5"
    local model="$6"
    local mode="${7:-greenfield}"
    
    source "$runner_path"
    
    local attempt=1
    local success=false
    
    while [[ $attempt -le $MAX_RETRIES ]]; do
        echo "[PIPELINE] Stage $stage_num ($stage_name) — attempt $attempt/$MAX_RETRIES"
        
        # Validate prerequisites
        if ! validate_prerequisites "$stage_num" "$project_dir"; then
            echo "[PIPELINE] Prerequisites not met for stage $stage_num."
            return 1
        fi
        
        # Run the stage
        if runner_run "$stage_name" "$prompt" "$project_dir" "$model" "$mode"; then
            # Verify signal file was created
            if signal_check "$stage_num" "$project_dir"; then
                echo "[PIPELINE] Stage $stage_num ($stage_name) — SUCCESS"
                success=true
                break
            else
                echo "[PIPELINE] Stage $stage_num ran but no signal file created. Retrying..."
            fi
        else
            echo "[PIPELINE] Stage $stage_num ($stage_name) — FAILED (attempt $attempt)"
        fi
        
        attempt=$((attempt + 1))
        
        # On last retry, try fallback model if configured
        if [[ $attempt -gt $MAX_RETRIES ]] && [[ -n "$FALLBACK_MODEL" ]]; then
            echo "[PIPELINE] Trying fallback model: $FALLBACK_MODEL"
            model="$FALLBACK_MODEL"
            attempt=$((MAX_RETRIES))  # One more try with fallback
            MAX_RETRIES=$((MAX_RETRIES + 1))
        fi
    done
    
    if [[ "$success" == "false" ]]; then
        signal_fail "$stage_num" "$project_dir" "Failed after $MAX_RETRIES attempts"
        return 1
    fi
    
    return 0
}

# ─── Full Pipeline ───
# Usage: run_full_pipeline <project_dir> <runner_path> <task> [start_stage] [mode]
run_full_pipeline() {
    local project_dir="$1"
    local runner_path="$2"
    local task="$3"
    local start_stage="${4:-0}"
    local mode="${5:-greenfield}"
    
    local planner_model builder_model reviewer_model consultant_model
    # Models are set by the caller via environment or config
    planner_model="${SF_PLANNER_MODEL:-}"
    builder_model="${SF_BUILDER_MODEL:-}"
    reviewer_model="${SF_REVIEWER_MODEL:-}"
    consultant_model="${SF_CONSULTANT_MODEL:-}"
    FALLBACK_MODEL="${SF_FALLBACK_MODEL:-}"
    
    echo "[PIPELINE] Starting pipeline: mode=$mode, start_stage=$start_stage"
    echo "[PIPELINE] Project: $project_dir"
    echo "[PIPELINE] Task: $task"
    
    # Stage 0: Planner
    if [[ $start_stage -le 0 ]]; then
        local planner_prompt
        planner_prompt=$(cat "$PROJECT_ROOT/prompts/planner.md")
        
        if [[ "$mode" == "brownfield" ]]; then
            planner_prompt="$planner_prompt\n\n## Mode: BROWNFIELD (Existing Code)\nThe project already has code. Analyze it and create a modification plan."
        fi
        
        if ! run_stage "0" "planner" "$runner_path" "$project_dir" \
            "$planner_prompt\n\n## Task\n$task\n\n## Project Directory\n$project_dir" \
            "$planner_model" "$mode"; then
            echo "[PIPELINE] Pipeline aborted at Stage 0."
            return 1
        fi
    fi
    
    # Stage 1: Builder
    if [[ $start_stage -le 1 ]]; then
        local builder_prompt
        builder_prompt=$(cat "$PROJECT_ROOT/prompts/builder.md")
        
        if ! run_stage "1" "builder" "$runner_path" "$project_dir" \
            "$builder_prompt\n\n## Plan Location\n$project_dir/docs/PLAN.md\n\n## Project Directory\n$project_dir" \
            "$builder_model" "$mode"; then
            echo "[PIPELINE] Pipeline aborted at Stage 1."
            return 1
        fi
    fi
    
    # Stage 2: Reviewer
    if [[ $start_stage -le 2 ]]; then
        local reviewer_prompt
        reviewer_prompt=$(cat "$PROJECT_ROOT/prompts/reviewer.md")
        
        if ! run_stage "2" "reviewer" "$runner_path" "$project_dir" \
            "$reviewer_prompt\n\n## Project Directory\n$project_dir" \
            "$reviewer_model" "$mode"; then
            echo "[PIPELINE] Pipeline aborted at Stage 2."
            return 1
        fi
    fi
    
    # Stage 3: Consultant
    if [[ $start_stage -le 3 ]]; then
        local consultant_prompt
        consultant_prompt=$(cat "$PROJECT_ROOT/prompts/consultant.md")
        
        if ! run_stage "3" "consultant" "$runner_path" "$project_dir" \
            "$consultant_prompt\n\n## Project Directory\n$project_dir" \
            "$consultant_model" "$mode"; then
            echo "[PIPELINE] Pipeline aborted at Stage 3."
            return 1
        fi
    fi
    
    # Mark pipeline complete
    echo "$(date_iso)" > "$project_dir/stages/.pipeline_done"
    echo ""
    echo "[PIPELINE] ✅ All stages complete!"
    echo "[PIPELINE] Review deliverables in: $project_dir/docs/"
    
    return 0
}
