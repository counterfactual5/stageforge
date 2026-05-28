#!/usr/bin/env bash
# Runner: Claude Code CLI (claude --print)
# Implements the stageforge runner interface for Claude Code.

# Return the runner name
runner_name() {
    echo "claude-code"
}

# Check if the runner is available
runner_check() {
    command -v claude &>/dev/null
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
        echo "[claude-code] ERROR: claude CLI not found in PATH." >&2
        return 1
    fi
    
    local model_flag=""
    if [[ -n "$model" ]]; then
        model_flag="--model $model"
    fi
    
    # Map stage name to system prompt behavior
    local allowed_tools="Write,Edit,Bash,Read,Glob,Grep,LS"
    
    case "$stage" in
        planner)
            allowed_tools="Write,Read,Bash,LS,Glob,Grep"
            ;;
        builder)
            allowed_tools="Write,Edit,Bash,Read,Glob,Grep,LS"
            ;;
        reviewer)
            allowed_tools="Write,Edit,Bash,Read,Glob,Grep,LS"
            ;;
        consultant)
            allowed_tools="Write,Read,Bash,LS,Glob,Grep"
            ;;
    esac
    
    echo "[claude-code] Running stage: $stage"
    echo "[claude-code] Working directory: $workdir"
    [[ -n "$model" ]] && echo "[claude-code] Model: $model"
    
    # Claude Code headless mode
    claude --print \
        --system-prompt "$prompt" \
        $model_flag \
        --allowedTools "$allowed_tools" \
        --cwd "$workdir" \
        "Execute the $stage stage. Follow the system prompt instructions precisely. Project directory: $workdir"
    
    return $?
}
