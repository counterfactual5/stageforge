#!/usr/bin/env bash
# Runner: OpenAI Codex CLI (codex)
# Implements the stageforge runner interface for Codex CLI.

# Return the runner name
runner_name() {
    echo "codex-cli"
}

# Check if the runner is available
runner_check() {
    command -v codex &>/dev/null
}

# Run a stage
# Usage: runner_run <stage> <prompt> <workdir> <model> [mode]
runner_run() {
    local stage="$1"
    local prompt="$2"
    local workdir="$3"
    local model="${4:-}"
    local mode="${5:-}"
    
    if ! runner_check; then
        echo "[codex-cli] ERROR: codex CLI not found in PATH." >&2
        return 1
    fi
    
    local model_flag=""
    if [[ -n "$model" ]]; then
        model_flag="--model $model"
    fi
    
    # Codex CLI full-auto mode
    local approval_mode="full-auto"
    
    # Restrict tools for planner/consultant (no editing)
    local instruction="$prompt"
    
    echo "[codex-cli] Running stage: $stage"
    echo "[codex-cli] Working directory: $workdir"
    [[ -n "$model" ]] && echo "[codex-cli] Model: $model"
    
    # Write prompt to temp file to avoid shell escaping issues
    local prompt_file
    prompt_file=$(temp_file)
    echo "$instruction" > "$prompt_file"
    
    (
        cd "$workdir"
        codex $model_flag \
            --approval-mode "$approval_mode" \
            --quiet \
            "Read and follow ALL instructions in this file: $prompt_file\n\nStage: $stage\nProject directory: $workdir"
    )
    
    local result=$?
    rm -f "$prompt_file"
    return $result
}
