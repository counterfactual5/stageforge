# Contributing to StageForge

StageForge is a Bash-based CLI — contributions are welcome in runners, prompts, and core pipeline improvements.

## Setup

```bash
git clone https://github.com/counterfactual5/stageforge.git
cd stageforge
export PATH="$PWD/bin:$PATH"
stageforge --version
```

No dependencies beyond Bash 4+.

## Project Structure

```
stageforge/
├── bin/stageforge         # CLI entry point
├── core/
│   ├── pipeline.sh        # Stage orchestration
│   ├── signal.sh          # File-based stage signals
│   └── validate.sh        # Prerequisite checks
├── runners/               # Agent runners (plugin system)
│   ├── claude-code.sh     # Claude Code adapter
│   └── codex-cli.sh       # OpenAI Codex adapter
├── prompts/               # Per-stage system prompts
├── templates/             # Project scaffolding
├── examples/              # Usage examples
└── config/                # Default configuration
```

## Adding a New Runner

1. Create `runners/<name>.sh`
2. Implement three functions: `runner_name`, `runner_check`, `runner_run`
3. See existing runners for the interface contract
4. Test with `stageforge run my-app -t "..." -r runners/<name>.sh`

## Before Submitting

- Run `bash -n bin/stageforge core/*.sh runners/*.sh` for syntax check
- Verify `stageforge init test-project && stageforge status test-project` works
- Keep PRs focused — one runner or feature per PR

## Pull Requests

1. Fork → feature branch → changes → PR to `main`
2. New runners must follow the plugin interface
