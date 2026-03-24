# AI Skills Project

## Workspace Convention

When running evals or benchmarks for a skill, always use a `workspace/` directory
**inside** the skill’s directory (e.g., `jira-cli/workspace/`), not a sibling
`<skill-name>-workspace/` directory.
This keeps all skill-related files self-contained.

The `*/workspace/` pattern is in `.gitignore` — workspace directories should never be
committed.
