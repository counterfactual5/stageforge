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
    # mode is the documented-optional 5th ABI argument; received but unused.
    # shellcheck disable=SC2034
    local mode="${5:-}"
    
    if ! runner_check; then
        echo "[gemini-cli] ERROR: gemini CLI not found in PATH." >&2
        return 1
    fi
    
    # Keep CLI args verbatim even for values with spaces/globs (see
    # claude-code.sh for rationale); guard empty array for bash 3.2 + set -u.
    local model_args=()
    if [[ -n "$model" ]]; then
        model_args=(--model "$model")
    fi
    
    echo "[gemini-cli] Running stage: $stage"
    echo "[gemini-cli] Working directory: $workdir"
    [[ -n "$model" ]] && echo "[gemini-cli] Model: $model"
    
    # Write prompt to temp file to avoid shell escaping issues
    local prompt_file
    prompt_file=$(temp_file)
    echo "$prompt" > "$prompt_file"
    
    (
        cd "$workdir" || exit 1
        gemini -p "$(cat "$prompt_file")" \
            ${model_args[@]+"${model_args[@]}"} \
            --sandbox=false \
            2>&1
    )
    
    local result=$?
    rm -f "$prompt_file"
    return $result
}
