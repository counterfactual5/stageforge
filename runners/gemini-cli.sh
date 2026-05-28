#!/usr/bin/env bash
# Runner: Gemini CLI (gemini)
# Implements the stageforge runner interface for Google Gemini CLI.

runner_name() {
    echo "gemini-cli"
}

runner_check() {
    command -v gemini &>/dev/null
}

runner_run() {
    local stage="$1"
    local prompt="$2"
    local workdir="$3"
    local model="${4:-}"
    local mode="${5:-}"
    
    if ! runner_check; then
        echo "[gemini-cli] ERROR: gemini CLI not found in PATH." >&2
        return 1
    fi
    
    local model_flag=""
    if [[ -n "$model" ]]; then
        model_flag="--model $model"
    fi
    
    echo "[gemini-cli] Running stage: $stage"
    echo "[gemini-cli] Working directory: $workdir"
    [[ -n "$model" ]] && echo "[gemini-cli] Model: $model"
    
    # Write prompt to temp file to avoid shell escaping issues
    local prompt_file
    prompt_file=$(temp_file)
    echo "$prompt" > "$prompt_file"
    
    (
        cd "$workdir"
        gemini -p "$(cat "$prompt_file")" \
            $model_flag \
            --sandbox=false \
            2>&1
    )
    
    local result=$?
    rm -f "$prompt_file"
    return $result
}
