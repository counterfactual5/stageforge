# Changelog

## [Unreleased]

### Fixed
- **Config file was never read** — `load_config` used `\\K` inside a single-quoted
  pattern, so PCRE matched a literal `\K` and every lookup returned empty. The
  patterns were also unanchored, so comment lines matched. `runner:`, the
  per-stage `models:` block and `max_retries:` in `stageforge.yaml` were all
  silently ignored; `max_retries` is now resolved as env > config > built-in 3.
- **Concurrent runs could cross-contaminate run-IDs** — `run_pipeline` re-read
  `stages/.run_id` from disk right after writing it, so a second run in the same
  project directory could stamp its signals with the other run's ID.
- **Signal trust on resume** — `reconcile_resume_point` now rejects signals whose
  embedded run_id matches no known run (foreign / `unknown` / truncated) and
  rewinds instead of skipping the stage. Legacy v0.3 signals without a `run_id`
  line are still accepted for compatibility, but now emit a warning: an empty
  `stages/.stage_N_done` is trivially forgeable.
- **`claude-code` runner could not run** — Claude Code CLI 2.1.285 has no
  `--cwd` flag, and space-separated `--allowedTools <tools...>` consumed the
  positional prompt. The runner now changes directory in a subshell and uses
  `--allowedTools=<tools>` so the prompt reaches the CLI.
- **Per-project run lock** (`core/lock.sh`) — `mkdir`-based, no `flock`, no
  platform branch. A second run in the same project is refused; stale locks from
  dead processes are reclaimed.
- **macOS portability** — `mktemp` template had the X's mid-string, which BSD
  turns into a *fixed* filename (predictable, and the second call aborts the
  runner under `set -e`); `grep_oP`'s perl fallback printed `$1` for patterns
  using `\K` (no capture group) and so always output empty; `cmd_status`'s
  `cat | head -1` could die of SIGPIPE under `pipefail` + `set -e`.
- **Argument injection** — runners expanded `$model_flag` unquoted, so a model
  name containing spaces or globs word-split into extra CLI arguments.
- Timestamps in signal files and the four `prompts/*.md` snippets are now UTC
  ISO-8601 on every platform (BSD `date` has no `-Iseconds`; GNU emits local
  offsets, so the same signal file had two different time bases).
- `.run_id` and `.lock/` added to the `init` .gitignore template.

### Removed
- **`core/pipeline.sh`** — dead code, never sourced by `bin/stageforge` since
  it was written. It carried a second, independent retry loop, so fixes to one
  did not apply to the other. v0.4.0's changelog described the two paths as
  "unified"; they were only ever aligned by duplication. Its duplicated retry
  implementation was removed with it.
- **`skip_stages`** from `config/stageforge.yaml` — a commented-out key that was
  never implemented, but shipped in the template that every `init` project
  receives.

## [0.5.0] — 2026-06-05

### Added
- **Resume reconciliation**: `reconcile_resume_point()` rewinds past stages marked
  done whose artifacts are missing (PLAN.md, src/, etc.); `cmd_resume` warns when
  recorded progress is ahead of intact outputs.
- Unit tests in `tests/test_reconcile.sh` (7 cases), wired into `make test`.

## [0.4.0] — 2026-05-28

### Fixed
- Stale signal file false positive — run-ID protocol prevents old signals from
  falsely satisfying prerequisite checks between pipeline runs
- AI agent signal verification — runner executes, orchestrator verifies signal
  file exists and matches the current run-ID, retries on failure
- Two diverging code paths aligned — `core/pipeline.sh` and `bin/stageforge`
  were brought onto the same run-ID + signal_verify protocol. They remain two
  independent implementations; `core/pipeline.sh` was later removed as dead
  code (see [Unreleased]).
- Relative path corruption in mock runner — path normalized to absolute

## [0.3.0] — 2026-05-28

### Added
- Gemini CLI runner (`gemini-cli`)
- GitHub Actions CI: shellcheck + syntax + smoke test

## [0.2.0] — 2026-05-28

### Added
- Mock runner for testing
- End-to-end pipeline integration test

## [0.1.1] — 2026-05-28

### Added
- CI: GitHub Actions with shellcheck, syntax validation, and CLI smoke test
- CONTRIBUTING.md

## [0.1.0] — 2026-05-28

### Added
- Multi-stage pipeline: Planner → Builder → Reviewer → Consultant
- Agent-agnostic runner system (Claude Code + Codex CLI)
- Dual-path: Greenfield (new projects) and Brownfield (iterate existing)
- Quick Track: skip full pipeline for simple tasks
- Signal protocol: file-based stage coordination
- Built-in retry (3x) with model fallback
- Per-stage model configuration
- Dry-run mode (Planner only)
- Resume from any stage
- Project templates and examples
- Custom runner plugin interface
- Makefile for convenience
- MIT License

[0.4.0]: https://github.com/counterfactual5/stageforge/releases/tag/v0.4.0
[0.3.0]: https://github.com/counterfactual5/stageforge/releases/tag/v0.3.0
[0.2.0]: https://github.com/counterfactual5/stageforge/releases/tag/v0.2.0
[0.1.1]: https://github.com/counterfactual5/stageforge/releases/tag/v0.1.1
[0.1.0]: https://github.com/counterfactual5/stageforge/releases/tag/v0.1.0
