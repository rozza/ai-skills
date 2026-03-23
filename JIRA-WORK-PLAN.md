# jira-work Skill Plan

## Overview

A Claude Code skill invoked as `/jira-work PROJ-XXXX` that automates the "start working on a ticket" workflow: validates the workspace, sets up a branch, fetches the Jira ticket, and produces an implementation plan for review.

## File Structure

```
jira-work/
├── SKILL.md          # Skill definition (triggers on /jira-work)
├── CLAUDE.md         # Workspace convention
├── config.yml        # Project → local repo path mapping (gitignored)
├── plans/            # Generated implementation plans (gitignored)
│   └── JAVA-6111-PLAN.md
└── evals/
    └── evals.json
```

## config.yml Format

```yaml
projects:
  JAVA: /Users/ross.lawley/Code/mongodb/mongo-java-driver
  SERVER: /Users/ross.lawley/Code/mongodb/mongo
```

- Listed in `.gitignore` (machine-specific paths)
- If a project prefix (e.g., `JAVA`) is not found in config, the skill prompts the user for the path, validates it exists, and appends it to the file
- If `config.yml` doesn't exist at all, create it with the first mapping

## Workflow Steps (what SKILL.md encodes)

Given `/jira-work JAVA-6111`:

### 1. Parse Input
- Extract project key (`JAVA`) and full ticket ID (`JAVA-6111`) from the argument

### 2. Resolve Working Directory
- Read `./jira-work/config.yml`
- Look up `JAVA` → get `WORK-PATH` (e.g., `/Users/ross.lawley/Code/mongodb/mongo-java-driver`)
- **If not found:** Ask user for the path, validate it's a git repo, add to config.yml, then continue

### 3. Check for Uncommitted Work
- Run `git -C $WORK_PATH status --porcelain`
- **If output is non-empty:** Stop with message:
  > CANNOT PROCEED - Work in progress. Please commit or stash.
- List the dirty files so the user can see what's pending

### 4. Update Main Branch
- Determine remote: check if `upstream` exists (`git -C $WORK_PATH remote`), fall back to `origin`
- Run:
  ```bash
  git -C $WORK_PATH checkout main && git -C $WORK_PATH pull $REMOTE main
  ```

### 5. Create Feature Branch
- Check if branch `JAVA-6111` already exists (`git -C $WORK_PATH branch --list JAVA-6111`)
- **If exists:** Ask user "Branch JAVA-6111 already exists. Continue? (Y/n)" — if `n`, stop
- **If doesn't exist:** `git -C $WORK_PATH checkout -b JAVA-6111`
- **If exists and user says Y:** `git -C $WORK_PATH checkout JAVA-6111`

### 6. Fetch Jira Ticket
- Use the `jira-cli` skill patterns to fetch the ticket:
  ```bash
  jira issue view -p JAVA JAVA-6111 --plain
  jira issue comment list JAVA-6111 --plain
  ```
- Capture the full ticket description, acceptance criteria, and all comments

### 7. Create Implementation Plan
- Analyze the ticket content and the codebase at `WORK-PATH`
- If there isn't enough information to plan, ask the user clarifying questions — do not guess
- Write plan to `./jira-work/plans/JAVA-6111-PLAN.md` with:
  - Ticket summary
  - Key requirements / acceptance criteria
  - Proposed approach (files to change, new files, tests)
  - Open questions (if any)
  - Risks / considerations

### 8. Request Review
- Present the plan to the user and ask them to review before any implementation begins

## .gitignore Additions

Add to the project `.gitignore`:
```
jira-work/config.yml
jira-work/plans/
```

## Implementation Approach

This is best implemented as a **single SKILL.md** file that encodes the full workflow as instructions for Claude Code to follow step-by-step. It doesn't need to be a shell script — the skill describes the procedure, and Claude executes each step using its tools (Bash for git/jira commands, Read/Write for config and plan files).

The skill should reference the `jira-cli` skill for Jira command patterns (flags like `--plain`, `--no-input`, using `-p PROJ`).

## Key Design Decisions

1. **SKILL.md as orchestrator** — Claude follows the steps, making decisions at each gate (dirty repo, existing branch). This is more flexible than a shell script because Claude can handle edge cases conversationally.
2. **config.yml not config.json** — YAML is more readable for a simple key-value mapping and easier to hand-edit.
3. **Plans in `jira-work/plans/`** — Centralized, gitignored, easy to find later. Named by ticket ID for uniqueness.
4. **No auto-implementation** — The skill stops at plan review. Implementation is a separate step the user initiates.
5. **Leverages existing jira-cli skill** — Reuses its patterns rather than duplicating jira command knowledge.

## Resolved Decisions

- **Plan includes raw ticket content** — The plan file will contain the full Jira ticket + comments for reference, followed by the synthesized implementation plan.
- **No companion close-out skill** — No `/jira-done` skill. Close-out is manual.
- **Branch name is ticket ID only** — e.g., `JAVA-6111`, no title slug.
