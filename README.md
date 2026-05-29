<div align="center">

# ⚒️ StageForge

**Agent-agnostic multi-stage autonomous development framework**

Plan → Build → Review → Deliver — with any AI coding agent.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](bin/stageforge)

</div>

---

## Why StageForge?

Current AI coding tools (Claude Code, Codex CLI, etc.) generate code, but lack **structured quality control**. StageForge adds a multi-stage pipeline:

| Stage | Role | What it does |
|-------|------|-------------|
| **0. Planner** | Architect | Analyzes requirements → produces technical plan |
| **1. Builder** | Developer | Implements code from the plan |
| **2. Reviewer** | QA Engineer | Reviews, tests, and fixes issues |
| **3. Consultant** | Delivery Manager | Validates quality → README + improvement proposals |

Each stage produces **verifiable artifacts** and a **signal file** for the next stage. No stage skips ahead.

## Features

- 🔌 **Agent-agnostic** — Works with Claude Code, Codex CLI, Gemini CLI, or any agent you configure
- 🔄 **Dual-path** — Greenfield (new projects) and Brownfield (iterate on existing code)
- ⚡ **Quick Track** — Simple tasks skip the full pipeline
- 🛡️ **Built-in retry + fallback** — Each stage retries 3x with model fallback
- 📋 **Signal protocol** — File-based stage coordination, no external dependencies
- 🎯 **Model routing** — Different models for different stages via config

## Quick Start

```bash
# Clone
git clone https://github.com/counterfactual5/stageforge.git
cd stageforge

# Add to PATH
export PATH="$PWD/bin:$PATH"

# Initialize a new project
stageforge init my-project

# Run the full pipeline
stageforge run my-project -t "Build a REST API with Express and TypeScript"

# Or use quick track for simple tasks
stageforge quick -t "Write a Python script to batch rename files"
```

## Requirements

- **Bash 4+**
- At least one supported agent CLI:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`claude`)
  - [OpenAI Codex CLI](https://github.com/openai/codex) (`codex`)
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`gemini`)
  - Or any custom agent (see below)

## Usage

### Initialize a Project

```bash
stageforge init my-app
# Creates: my-app/{docs,stages,src}/ + stageforge.yaml + .gitignore
```

### Run Full Pipeline (Greenfield)

```bash
stageforge run my-app -t "Build a task management CLI with SQLite storage"
```

### Iterate on Existing Project (Brownfield)

```bash
stageforge iterate my-app -t "Add user authentication with JWT"
```

### Quick Track

```bash
stageforge quick -t "Generate a Solidity ERC20 token with burning"
```

### Check Status

```bash
stageforge status my-app
# Output:
# [OK] Stage 0 (Planner): completed at 2026-05-28T12:00:00+08:00
# [OK] Stage 1 (Builder): completed at 2026-05-28T12:05:00+08:00
# [ ]  Stage 2 (Reviewer): pending
# [ ]  Stage 3 (Consultant): pending
```

### Resume Interrupted Pipeline

```bash
stageforge resume my-app
# Resumes from the last completed stage
```

### Dry Run (Plan Only)

```bash
stageforge run my-app -t "Add WebSocket support" --dry-run
# Runs only Stage 0 (Planner), then stops for you to review the plan
```

### Specify Runner & Model

```bash
# Use Codex CLI
stageforge run my-app -t "..." -r codex-cli

# Override model for all stages
stageforge run my-app -t "..." -m o3

# Per-stage models
stageforge run my-app -t "..." --planner-model sonnet --builder-model sonnet --reviewer-model o3
```

### Optional local pipeline hooks

`stageforge run` exports environment variables that **compatible CLIs may read**
when you wire them into a local pipeline. StageForge itself does not depend on
any trading repository — cloning and CI for this repo are fully standalone.

| Variable | Set when |
|----------|----------|
| `STAGEFORGE_RUN_ID` | Always — a unique id per pipeline run |
| `POLICY_FILE` | When `~/.stageforge/policy.yaml`, `policy.yml`, or `policy.json` exists |

Trading CLIs that support these variables use them for audit correlation and
risk-policy lookup. Place a `policy.yaml` in `~/.stageforge/` if you run trades
locally after a pipeline stage; see that CLI's own `RISK_POLICY.md`.

## Configuration

Each project gets a `stageforge.yaml`:

```yaml
# Agent runner: claude-code | codex-cli | /path/to/custom.sh
runner: claude-code

# Models per stage (leave empty for runner default)
models:
  planner: ""
  builder: ""
  reviewer: ""
  consultant: ""

# Fallback model on repeated failure
fallback: ""

# Retry count per stage
max_retries: 3
```

## Custom Runners

StageForge uses a plugin-based runner system. Create your own by implementing 3 functions:

```bash
#!/usr/bin/env bash
# runners/my-agent.sh

runner_name()  { echo "my-agent"; }
runner_check() { command -v my-agent &>/dev/null; }

runner_run() {
    local stage="$1"      # planner | builder | reviewer | consultant
    local prompt="$2"     # System prompt
    local workdir="$3"    # Project directory
    local model="${4:-}"  # Optional model override

    my-agent --headless --prompt "$prompt" --dir "$workdir"
}
```

Then use it:
```bash
stageforge run my-app -t "..." -r /path/to/my-agent.sh
```

## Project Structure (After Pipeline)

```
my-app/
├── docs/
│   ├── PLAN.md           # Stage 0: Technical plan
│   ├── TEST_REPORT.md    # Stage 2: QA results
│   └── README.md         # Stage 3: Final documentation
├── src/                  # Stage 1: Source code
├── stages/               # Signal files (auto-generated)
│   ├── .stage_0_done
│   ├── .stage_1_done
│   ├── .stage_2_done
│   ├── .stage_3_done
│   └── .pipeline_done
├── stageforge.yaml       # Project config
└── .gitignore
```

## How It Works

```
┌─────────┐    ┌─────────┐    ┌──────────┐    ┌────────────┐
│ Planner │ →  │ Builder │ →  │ Reviewer │ →  │ Consultant │
│ (Plan)  │    │ (Code)  │    │  (QA)    │    │  (Deliver) │
└─────────┘    └─────────┘    └──────────┘    └────────────┘
     │              │               │                │
  PLAN.md       src/*         TEST_REPORT.md    README.md
  .stage_0      .stage_1       .stage_2         .stage_3
```

Each stage:
1. **Validates** prerequisites from previous stages
2. **Runs** the agent with a specialized system prompt
3. **Creates** a signal file upon completion
4. **Fails gracefully** with retries and model fallback

## Comparison

| Feature | claude-code-harness | **StageForge** |
|---------|-------------------|----------------|
| Agent backend | Claude Code only | Plugin-based (any agent) |
| Stages | 3 (Plan/Work/Review) | 4 (Plan/Build/Review/Deliver) |
| Path modes | Single | Greenfield + Brownfield |
| Model routing | None | Per-stage config |
| Simple tasks | Full pipeline | Quick Track auto-skip |
| Retry/fallback | Basic | 3x retry + model fallback |
| Resume | No | Yes (from any stage) |
| Extensible | Low | Custom runners + prompts |

## Contributing

Contributions welcome! Areas of interest:

- New runner adapters (Gemini CLI, Aider, Continue, etc.)
- New language/framework prompts
- Bug fixes and improvements
- Documentation and examples

## License

[MIT](LICENSE)
