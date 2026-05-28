# Example 02: Brownfield — Iterate on Existing Project

Add a feature to an existing codebase.

```bash
# Iterate with a specific task
stageforge iterate my-api -t "Add JWT authentication middleware. Users should register/login and receive a token. Protect all /tasks endpoints."

# Use a different runner
stageforge iterate my-api -t "Add rate limiting: 100 req/min per IP" -r codex-cli

# Dry run — only plan, don't build yet
stageforge iterate my-api -t "Add WebSocket support for real-time task updates" --dry-run
```

## Brownfield Flow

1. **Planner** reads existing code → creates modification plan
2. **Builder** applies modifications to existing files
3. **Reviewer** verifies nothing broke
4. **Consultant** summarizes changes + proposes next improvements
