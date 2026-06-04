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

# ─── Artifact / state reconciliation (resume safety) ───
#
# signal_check() only proves a stage *reported* completion. A signal file can
# outlive the artifacts it vouches for (PLAN.md deleted, src/ wiped, a partial
# previous run). On resume we must reconcile the recorded state against the
# artifacts that actually exist, and rewind past any stage whose outputs are
# gone — otherwise we silently build on a missing foundation.

# Check that the OUTPUT artifacts of a completed stage are still present.
# Usage: stage_artifacts_present <stage_num> <project_dir>
# Returns 0 if the stage's artifacts exist (or the stage has no hard artifact).
stage_artifacts_present() {
    local stage_num="$1"
    local project_dir="$2"

    case "$stage_num" in
        0)
            # Planner → docs/PLAN.md (must exist and be non-empty).
            [[ -s "$project_dir/docs/PLAN.md" ]]
            ;;
        1)
            # Builder → at least one source file.
            local dir
            for dir in src lib contracts app; do
                if [[ -d "$project_dir/$dir" ]] && [[ -n "$(ls -A "$project_dir/$dir" 2>/dev/null)" ]]; then
                    return 0
                fi
            done
            return 1
            ;;
        2)
            # Reviewer → docs/TEST_REPORT.md. Soft artifact: the pipeline only
            # warns when it is missing, so treat absence as present-enough here
            # to avoid being stricter on resume than during a fresh run.
            return 0
            ;;
        3)
            # Consultant → docs/README.md (soft, same rationale as stage 2).
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Reconcile recorded completion against on-disk artifacts.
# Echoes the highest stage forming an unbroken, artifact-backed prefix
# (-1 if none). Walks 0→3 and stops at the first stage that is either not
# signalled done or whose artifacts have gone missing.
# Usage: reconcile_resume_point <project_dir>
reconcile_resume_point() {
    local project_dir="$1"

    source "$(dirname "${BASH_SOURCE[0]}")/signal.sh"

    local last=-1
    local i
    for i in 0 1 2 3; do
        if ! signal_check "$i" "$project_dir"; then
            break
        fi
        if ! stage_artifacts_present "$i" "$project_dir"; then
            echo "[VALIDATE] Stage $i marked complete but its artifacts are missing — rewinding resume point to Stage $i." >&2
            break
        fi
        last=$i
    done

    echo "$last"
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
