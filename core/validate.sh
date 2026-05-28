#!/usr/bin/env bash
# validate.sh — Pre-stage validation for stageforge
# Each stage validates that prerequisites from previous stages exist.

# Validate prerequisites for a given stage
# Usage: validate_prerequisites <stage_num> <project_dir>
# Returns 0 if valid, exits with error if not
validate_prerequisites() {
    local stage_num="$1"
    local project_dir="$2"
    
    source "$(dirname "${BASH_SOURCE[0]}")/signal.sh"
    
    case "$stage_num" in
        0)
            # Planner: just need project dir
            if [[ ! -d "$project_dir" ]]; then
                echo "[VALIDATE] ERROR: Project directory not found: $project_dir" >&2
                return 1
            fi
            mkdir -p "$project_dir"/{docs,stages}
            ;;
        1)
            # Builder: need stage 0 signal + PLAN.md
            if ! signal_check "0" "$project_dir"; then
                echo "[VALIDATE] ERROR: Stage 0 (Planner) not complete." >&2
                return 1
            fi
            if [[ ! -f "$project_dir/docs/PLAN.md" ]]; then
                echo "[VALIDATE] ERROR: docs/PLAN.md not found." >&2
                return 1
            fi
            if [[ ! -s "$project_dir/docs/PLAN.md" ]]; then
                echo "[VALIDATE] ERROR: docs/PLAN.md is empty." >&2
                return 1
            fi
            ;;
        2)
            # Reviewer: need stage 1 signal + at least 1 source file
            if ! signal_check "1" "$project_dir"; then
                echo "[VALIDATE] ERROR: Stage 1 (Builder) not complete." >&2
                return 1
            fi
            local has_source=false
            for dir in src lib contracts app; do
                if [[ -d "$project_dir/$dir" ]] && [[ -n "$(ls -A "$project_dir/$dir" 2>/dev/null)" ]]; then
                    has_source=true
                    break
                fi
            done
            if [[ "$has_source" == "false" ]]; then
                echo "[VALIDATE] ERROR: No source files found in src/, lib/, contracts/, or app/." >&2
                return 1
            fi
            ;;
        3)
            # Consultant: need stage 2 signal + TEST_REPORT.md
            if ! signal_check "2" "$project_dir"; then
                echo "[VALIDATE] ERROR: Stage 2 (Reviewer) not complete." >&2
                return 1
            fi
            if [[ ! -f "$project_dir/docs/TEST_REPORT.md" ]]; then
                echo "[VALIDATE] WARN: docs/TEST_REPORT.md not found. Proceeding anyway." >&2
            fi
            ;;
        *)
            echo "[VALIDATE] ERROR: Unknown stage number: $stage_num" >&2
            return 1
            ;;
    esac
    
    echo "[VALIDATE] Stage $stage_num prerequisites OK."
    return 0
}

# Check if project has existing code (for brownfield detection)
# Usage: validate_is_brownfield <project_dir>
# Returns 0 if brownfield, 1 if greenfield
validate_is_brownfield() {
    local project_dir="$1"
    
    for dir in src lib contracts app; do
        if [[ -d "$project_dir/$dir" ]] && [[ -n "$(ls -A "$project_dir/$dir" 2>/dev/null)" ]]; then
            return 0
        fi
    done
    
    return 1
}
