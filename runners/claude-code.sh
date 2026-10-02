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
    # mode is the documented-optional 5th ABI argument; claude-code's headless
    # mode is fixed by --print, so it is received but unused.
    # shellcheck disable=SC2034
    local mode="${5:-}"
    
    if ! runner_check; then
        echo "[claude-code] ERROR: claude CLI not found in PATH." >&2
        return 1
    fi
    
    # Args must survive values with spaces/globs verbatim: an unquoted
    # `$model_flag` would word-split AND pathname-expand into extra CLI
    # arguments. Use an array with the empty-array guard for bash 3.2 + set -u.
    local model_args=()
    if [[ -n "$model" ]]; then
        model_args=(--model "$model")
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
    
    # Claude Code headless mode. This CLI has no --cwd flag (verified
    # against claude 2.1.285, which rejects it with "unknown option"); it
    # operates on the current working directory, so run from inside $workdir
    # in a subshell — the same pattern the codex/gemini runners use.
    #
    # --allowedTools is a VARIADIC flag (`--allowedTools <tools...>`): in
    # space-separated form it swallows every following non-flag argument,
    # including the positional prompt, and claude then aborts with "Input
    # must be provided either through stdin or as a prompt argument".
    # The equals form passes the tool list as ONE value and the prompt
    # survives as the positional argument (verified against 2.1.285).
    local result=0
    (
        cd "$workdir" || exit 1
        claude --print \
            --system-prompt "$prompt" \
            ${model_args[@]+"${model_args[@]}"} \
            --allowedTools="$allowed_tools" \
            "Execute the $stage stage. Follow the system prompt instructions precisely. Project directory: $workdir"
    ) || result=$?
    return $result
}
