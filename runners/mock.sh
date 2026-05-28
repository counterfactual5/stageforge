#!/usr/bin/env bash
# Runner: Mock (for testing stageforge orchestration without a real agent)
# Simulates each stage by creating expected artifacts.

runner_name()  { echo "mock"; }
runner_check() { true; }

# Resolve the mock's "run_id line" to whatever the orchestrator set, so the
# signal-verification step in bin/stageforge accepts the mock's signal files.
_mock_run_id_line() {
    echo "run_id: ${STAGEFORGE_RUN_ID:-mock-run}"
}

runner_run() {
    local stage="$1"
    local prompt="$2"
    local workdir="$3"
    local model="${4:-}"

    # Normalize to absolute path so later `cd "$workdir"` calls do not break
    # subsequent file writes that use "$workdir/..." as a relative path.
    workdir="$(cd "$workdir" && pwd)"

    echo "[mock] Simulating stage: $stage in $workdir"
    
    case "$stage" in
        planner)
            mkdir -p "$workdir/docs" "$workdir/stages"
            cat > "$workdir/docs/PLAN.md" <<'PLAN'
# Plan: Task Manager CLI

## Directory Structure
```
task-cli/
├── src/
│   └── main.py
├── tests/
│   └── test_main.py
└── requirements.txt
```

## Files
1. `src/main.py` — CLI entry point with argparse, CRUD operations
2. `tests/test_main.py` — Unit tests for all operations
3. `requirements.txt` — Dependencies (none needed, stdlib only)

## Key Interfaces
- `add_task(title, description) -> int` — Create task, return ID
- `list_tasks(filter=None) -> list` — List all/filtered tasks
- `complete_task(task_id) -> bool` — Mark task done
- `delete_task(task_id) -> bool` — Remove task

## Implementation Notes
- Use SQLite via stdlib sqlite3
- CLI via argparse
PLAN
            {
                date_iso
                _mock_run_id_line
            } > "$workdir/stages/.stage_0_done"
            echo "[mock] Stage 0 (Planner) done."
            ;;
            
        builder)
            mkdir -p "$workdir/src" "$workdir/tests"
            cat > "$workdir/src/main.py" <<'PYTHON'
#!/usr/bin/env python3
"""Task Manager CLI — A simple task tracker with SQLite storage."""

import argparse
import sqlite3
import sys
import os

DB_PATH = os.path.expanduser("~/.taskcli/tasks.db")


def get_connection():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("""
        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT DEFAULT '',
            completed BOOLEAN DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    return conn


def add_task(title, description=""):
    conn = get_connection()
    cursor = conn.execute(
        "INSERT INTO tasks (title, description) VALUES (?, ?)",
        (title, description)
    )
    conn.commit()
    task_id = cursor.lastrowid
    conn.close()
    return task_id


def list_tasks(filter_completed=None):
    conn = get_connection()
    if filter_completed is None:
        rows = conn.execute("SELECT * FROM tasks ORDER BY created_at DESC").fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM tasks WHERE completed = ? ORDER BY created_at DESC",
            (int(filter_completed),)
        ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def complete_task(task_id):
    conn = get_connection()
    cursor = conn.execute(
        "UPDATE tasks SET completed = 1 WHERE id = ?", (task_id,)
    )
    conn.commit()
    success = cursor.rowcount > 0
    conn.close()
    return success


def delete_task(task_id):
    conn = get_connection()
    cursor = conn.execute("DELETE FROM tasks WHERE id = ?", (task_id,))
    conn.commit()
    success = cursor.rowcount > 0
    conn.close()
    return success


def main():
    parser = argparse.ArgumentParser(description="Task Manager CLI")
    subparsers = parser.add_subparsers(dest="command")

    # add
    add_parser = subparsers.add_parser("add", help="Add a new task")
    add_parser.add_argument("title", help="Task title")
    add_parser.add_argument("-d", "--description", default="", help="Task description")

    # list
    list_parser = subparsers.add_parser("list", help="List tasks")
    list_parser.add_argument("--completed", action="store_true", help="Show only completed")
    list_parser.add_argument("--pending", action="store_true", help="Show only pending")

    # complete
    complete_parser = subparsers.add_parser("complete", help="Mark task as completed")
    complete_parser.add_argument("id", type=int, help="Task ID")

    # delete
    delete_parser = subparsers.add_parser("delete", help="Delete a task")
    delete_parser.add_argument("id", type=int, help="Task ID")

    args = parser.parse_args()

    if args.command == "add":
        task_id = add_task(args.title, args.description)
        print(f"Task #{task_id} created: {args.title}")
    elif args.command == "list":
        if args.completed:
            tasks = list_tasks(filter_completed=True)
        elif args.pending:
            tasks = list_tasks(filter_completed=False)
        else:
            tasks = list_tasks()
        if not tasks:
            print("No tasks found.")
        for t in tasks:
            status = "x" if t["completed"] else " "
            print(f"  [{status}] #{t['id']} {t['title']} - {t['description']}")
    elif args.command == "complete":
        if complete_task(args.id):
            print(f"Task #{args.id} completed.")
        else:
            print(f"Task #{args.id} not found.")
    elif args.command == "delete":
        if delete_task(args.id):
            print(f"Task #{args.id} deleted.")
        else:
            print(f"Task #{args.id} not found.")
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
PYTHON
            chmod +x "$workdir/src/main.py"

            cat > "$workdir/tests/test_main.py" <<'TEST'
#!/usr/bin/env python3
"""Unit tests for task-cli."""
import unittest
import tempfile
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

import main

class TestTaskCLI(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        main.DB_PATH = os.path.join(self.tmp, "test.db")
    
    def test_add_task(self):
        task_id = main.add_task("Test task", "A description")
        self.assertIsInstance(task_id, int)
        self.assertGreater(task_id, 0)
    
    def test_list_tasks(self):
        main.add_task("Task 1")
        main.add_task("Task 2")
        tasks = main.list_tasks()
        self.assertEqual(len(tasks), 2)
    
    def test_complete_task(self):
        task_id = main.add_task("To complete")
        self.assertTrue(main.complete_task(task_id))
        tasks = main.list_tasks(filter_completed=True)
        self.assertEqual(len(tasks), 1)
    
    def test_delete_task(self):
        task_id = main.add_task("To delete")
        self.assertTrue(main.delete_task(task_id))
        tasks = main.list_tasks()
        self.assertEqual(len(tasks), 0)
    
    def test_delete_nonexistent(self):
        self.assertFalse(main.delete_task(9999))

if __name__ == "__main__":
    unittest.main()
TEST

            cat > "$workdir/requirements.txt" <<'DEPS'
# No external dependencies — uses Python stdlib only
DEPS

            # Run tests
            cd "$workdir" && python3 -m pytest tests/ -v 2>&1 || python3 tests/test_main.py 2>&1 || true
            
            {
                date_iso
                _mock_run_id_line
                echo "Files: src/main.py, tests/test_main.py, requirements.txt"
            } > "$workdir/stages/.stage_1_done"
            echo "[mock] Stage 1 (Builder) done."
            ;;
            
        reviewer)
            mkdir -p "$workdir/docs"
            cat > "$workdir/docs/TEST_REPORT.md" <<'REPORT'
# Test Report

**Date**: $(date_iso)
**Reviewer**: stageforge-mock

## Checklist
| # | Check | Status | Notes |
|---|-------|--------|-------|
| 1 | Security | PASS | No hardcoded secrets |
| 2 | Loops | PASS | No infinite loops |
| 3 | Logic | PASS | Control flow correct |
| 4 | Error Handling | PASS | DB operations handled |
| 5 | Completeness | PASS | All plan files present |
| 6 | Runnable | PASS | Tests passing |

## Test Results
All 5 unit tests passed.

## Issues Found & Fixed
None.

## Summary
Code quality is good. All tests pass. No security issues detected.
REPORT
            
            {
                date_iso
                _mock_run_id_line
                echo "Issues found: 0"
                echo "Issues fixed: 0"
            } > "$workdir/stages/.stage_2_done"
            echo "[mock] Stage 2 (Reviewer) done."
            ;;
            
        consultant)
            mkdir -p "$workdir/docs"
            cat > "$workdir/docs/README.md" <<'README'
# Task Manager CLI

A simple command-line task manager with SQLite storage.

## Installation
```bash
# No dependencies needed — uses Python stdlib
python3 src/main.py --help
```

## Usage
```bash
# Add a task
python3 src/main.py add "Buy groceries" -d "Milk, eggs, bread"

# List all tasks
python3 src/main.py list

# Complete a task
python3 src/main.py complete 1

# Delete a task
python3 src/main.py delete 2
```
README
            
            {
                date_iso
                _mock_run_id_line
                echo "README: ok"
                echo "TestReport: ok"
            } > "$workdir/stages/.stage_3_done"
            echo "[mock] Stage 3 (Consultant) done."
            ;;
    esac
    
    return 0
}
