#!/usr/bin/env bash
# test_lock.sh — unit tests for the per-project run lock (core/lock.sh)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../core/compat.sh
source "$ROOT/core/compat.sh"
# shellcheck source=../core/lock.sh
source "$ROOT/core/lock.sh"

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  ok: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected=$expected got=$actual)" >&2
        FAIL=$((FAIL + 1))
    fi
}

exists() { [[ -e "$1" ]] && echo yes || echo no; }

echo "test: pipeline_lock"

d="$(mktemp -d)"; mkdir -p "$d/stages"

# 1. Acquire creates the lock dir and records our pid.
pipeline_lock_acquire "$d"; rc=$?
check "acquire → rc 0" "0" "$rc"
check "lock dir created" "yes" "$(exists "$d/stages/.lock")"
check "pid file is ours" "$$" "$(cat "$d/stages/.lock/pid")"

# 2. Re-acquire in the same process is reentrant.
pipeline_lock_acquire "$d"; rc=$?
check "reentrant re-acquire → rc 0" "0" "$rc"

# 3. Release removes it and is idempotent.
pipeline_lock_release
check "release removes lock dir" "no" "$(exists "$d/stages/.lock")"
pipeline_lock_release; rc=$?
check "double release → rc 0" "0" "$rc"

# 4. A foreign LIVE owner blocks acquisition, without claiming ownership.
mkdir -p "$d/stages/.lock"
sleep 30 & child=$!
echo "$child" > "$d/stages/.lock/pid"
pipeline_lock_acquire "$d" 2>/dev/null; rc=$?
check "live foreign owner → rc 1" "1" "$rc"
check "failed acquire claims nothing" "" "${SF_LOCK_DIR:-}"
kill "$child" 2>/dev/null
wait "$child" 2>/dev/null

# 5. A lock whose owner pid is dead is reclaimed.
echo 2147483647 > "$d/stages/.lock/pid"
pipeline_lock_acquire "$d"; rc=$?
check "stale lock reclaimed → rc 0" "0" "$rc"
check "reclaimed lock is ours" "$$" "$(cat "$d/stages/.lock/pid")"
pipeline_lock_release

# 6. An ownerless lock is not reclaimed automatically: it may belong to a
#    process in the mkdir→pid publication window. Safety beats recovery.
mkdir -p "$d/stages/.lock"
pipeline_lock_acquire "$d" 2>/dev/null; rc=$?
check "pid-less lock is refused → rc 1" "1" "$rc"
check "pid-less lock remains untouched" "yes" "$(exists "$d/stages/.lock")"
rm -rf "$d/stages/.lock"

rm -rf "$d"

echo
echo "Passed: $PASS  Failed: $FAIL"
[[ $FAIL -eq 0 ]]