# Example 03: Quick Track — Simple Script

For tasks that don't need the full four-stage pipeline.

```bash
# Quick one-shot task
stageforge quick -t "Write a Python script that renames all .jpeg files to .jpg in a directory recursively"

# With a specific model
stageforge quick -t "Generate a Solidity ERC20 token with burnable and mintable features" -r claude-code

# Quick task with Codex CLI
stageforge quick -t "Create a bash script to monitor disk usage and send alerts over 90%" -r codex-cli
```

## When to Use Quick Track

- Estimated code < 100 lines
- Single-file project
- No external dependencies
- Template/boilerplate generation
- User said "simple", "quick", "just a script"

## When NOT to Use Quick Track

- Multi-file projects → use `run`
- Complex architecture decisions → use `run`
- Modifying existing code → use `iterate`
- When in doubt → use the full pipeline
