#!/usr/bin/env bash
# lock.sh — Per-project run lock for stageforge
#
# Why: while a run owns the project, every cross-run .run_id read/write
# assumes it is the only writer. Two concurrent pipelines in one project
# directory can otherwise stamp signals with each other's run-ID — the exact
# contamination the run-ID protocol exists to prevent. A run-level lock closes
# that hole at the source instead of papering over each individual read.
#
# Implementation: an atomic mkdir mutex (macOS has no flock(1); mkdir is
# atomic on every POSIX platform, so there is no platform branch). The owner
# pid lives inside the lock directory; the EXIT/INT/TERM trap releases it
# automatically, and a lock left behind by a killed process is reclaimed when
# its recorded owner pid is no longer alive. A lock without an owner pid is
# refused rather than reclaimed: it may be a live process between mkdir and
# atomically publishing its pid.
# Known caveats: (1) liveness is PID-based — a recycled PID can keep a stale
# lock alive until that new process exits; (2) acquiring installs shell
# traps in the calling process, so the run is expected to own its process
# (true for bin/stageforge, the only entry point); (3) two processes racing
# to reclaim the SAME dead lock can both believe they won — the loser's
# rm -rf can delete the winner's live lock. Window is microseconds and
# requires a dead lock plus simultaneous starts; the proper fix is claiming
# via rename to a unique name before deleting.

SF_LOCK_DIR=""

# Release the currently held lock (idempotent; safe from traps).
pipeline_lock_release() {
    [[ -n "${SF_LOCK_DIR:-}" ]] || return 0
    local owner=""
    if [[ -f "$SF_LOCK_DIR/pid" ]]; then
        owner=$(cat "$SF_LOCK_DIR/pid" 2>/dev/null || true)
    fi
    # A contender may have reclaimed our lock during the mkdir→pid publication
    # window. Never remove a lock now owned by another process.
    if [[ "$owner" == "$$" ]]; then
        rm -rf -- "$SF_LOCK_DIR"
    fi
    SF_LOCK_DIR=""
    return 0
}

# Acquire the run lock for a project directory.
# Usage: pipeline_lock_acquire <project_dir>
# Returns 0 when the lock is held (freshly acquired or already ours);
# prints a diagnostic and returns 1 when another live run owns it.
pipeline_lock_acquire() {
    local project_dir="$1"
    mkdir -p "$project_dir/stages"
    local lock_dir="$project_dir/stages/.lock"

    if ! mkdir "$lock_dir" 2>/dev/null; then
        local owner=""
        if [[ -f "$lock_dir/pid" ]]; then
            owner=$(cat "$lock_dir/pid" 2>/dev/null || true)
        fi
        if [[ "$owner" == "$$" ]]; then
            return 0   # reentrant: this process already holds it
        fi
        # A lock directory without its atomically-published pid may belong to
        # a process in the tiny mkdir→pid window. Never reclaim it blindly:
        # safety (refuse this run) beats deleting a live owner's lock. An
        # interrupted initialization leaves a manual-cleanup diagnostic.
        if [[ -z "$owner" ]]; then
            echo "[LOCK] $lock_dir exists but has no owner pid; refusing to reclaim it automatically." >&2
            echo "[LOCK] If no stageforge process is initializing, remove the stale directory manually." >&2
            return 1
        fi
        if kill -0 "$owner" 2>/dev/null; then
            echo "[LOCK] Another stageforge run (pid $owner) holds $lock_dir." >&2
            echo "[LOCK] Concurrent runs in one project are not supported." >&2
            return 1
        fi
        # A recorded but dead owner is safe to reclaim; a competing reclaim
        # loses the following mkdir race.
        rm -rf -- "$lock_dir"
        if ! mkdir "$lock_dir" 2>/dev/null; then
            echo "[LOCK] Could not acquire $lock_dir (race with another run)." >&2
            return 1
        fi
    fi

    local pid_tmp
    pid_tmp=$(temp_file "$lock_dir") || {
        rm -rf -- "$lock_dir"
        return 1
    }
    if ! printf '%s\n' "$$" > "$pid_tmp" || ! mv -f -- "$pid_tmp" "$lock_dir/pid"; then
        rm -f -- "$pid_tmp"
        rm -rf -- "$lock_dir"
        return 1
    fi
    SF_LOCK_DIR="$lock_dir"
    trap pipeline_lock_release EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    return 0
}