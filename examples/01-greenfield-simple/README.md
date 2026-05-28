# Example 01: Greenfield — New REST API

Build a REST API from scratch using Express + TypeScript.

```bash
# Initialize project
stageforge init my-api

# Run full pipeline
stageforge run my-api -t "Build a REST API with Express and TypeScript. Include CRUD endpoints for a 'tasks' resource with SQLite storage. Add input validation and error handling."

# Check status
stageforge status my-api
```

## Expected Output

```
my-api/
├── docs/
│   ├── PLAN.md          ← Stage 0
│   ├── README.md        ← Stage 3
│   └── TEST_REPORT.md   ← Stage 2
├── src/
│   ├── index.ts
│   ├── routes/
│   ├── middleware/
│   └── database.ts
├── stages/
│   ├── .stage_0_done
│   ├── .stage_1_done
│   ├── .stage_2_done
│   ├── .stage_3_done
│   └── .pipeline_done
├── package.json
├── tsconfig.json
├── stageforge.yaml
└── .gitignore
```
