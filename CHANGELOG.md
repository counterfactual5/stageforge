# Changelog

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

[0.3.0]: https://github.com/counterfactual5/stageforge/releases/tag/v0.3.0
[0.2.0]: https://github.com/counterfactual5/stageforge/releases/tag/v0.2.0
[0.1.1]: https://github.com/counterfactual5/stageforge/releases/tag/v0.1.1
[0.1.0]: https://github.com/counterfactual5/stageforge/releases/tag/v0.1.0
