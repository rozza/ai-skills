---
name: jira-work
description: Start working on a Jira ticket - validates workspace, creates branch, fetches ticket details, and produces an implementation plan for review.
argument-hint: "<PROJ-XXXX | implement | code-review | commit> [- extra context]"
disable-model-invocation: true
---
# jira-work: Start Working on a Jira Ticket

Invoked as `/jira-work PROJ-XXXX` (e.g., `/jira-work JAVA-6111`). Orchestrates the full
“begin work” workflow.

**Setup:** If `JIRA_API_TOKEN` is not set, source the setup script first:
`source ../jira-cli/scripts/jira_cli_setup.sh` — this loads the token from the macOS
keychain (or prompts to create one).

## Step 1: Parse Input

Extract the project key, ticket ID, and optional extra context from the argument:
- `JAVA-6111` → project key: `JAVA`, ticket ID: `JAVA-6111`, extra: none
- `JAVA-6111 - focus on backpressure` → project key: `JAVA`, ticket ID: `JAVA-6111`,
  extra: "focus on backpressure"

Anything after a `-` separator is extra context passed into the planning phase.

## Step 2: Resolve Working Directory

Read the config file at `config.yml` (relative to this skill's directory) to find the local repo path for the
project.

```yaml
# config.yml format
projects:
  JAVA: /Users/ross.lawley/Code/mongodb/mongo-java-driver
```

- Look up the project key (e.g., `JAVA`) to get `WORK_PATH`
- **If `config.yml` doesn’t exist or the project key is missing:** Ask the user for the
  local repo path. Validate it exists and is a git repo.
  Add the mapping to `config.yml` in this skill's directory (create the file if needed), then continue.

## Step 3: Check for Uncommitted Work

Run `git -C $WORK_PATH status --porcelain` to check for dirty state.

**If there is uncommitted work, STOP immediately:**

> CANNOT PROCEED - Work in progress.
> Please commit or stash.

List the dirty files so the user can see what needs attention.
Do not continue.

## Step 4: Update Main Branch

1. Check available remotes: `git -C $WORK_PATH remote`
2. Use `upstream` if it exists, otherwise use `origin`
3. Run:
   ```bash
   git -C $WORK_PATH checkout main && git -C $WORK_PATH pull $REMOTE main
   ```

## Step 5: Create Feature Branch

1. Check if branch already exists: `git -C $WORK_PATH branch --list $TICKET_ID`
2. **If branch exists:** Tell the user and ask “Branch $TICKET_ID already exists.
   Continue? (Y/n)”
   - If Y: `git -C $WORK_PATH checkout $TICKET_ID`
   - If n: Stop
3. **If branch doesn’t exist:** `git -C $WORK_PATH checkout -b $TICKET_ID`

## Step 6: Fetch Jira Ticket

Load the [jira-cli skill](../jira-cli/SKILL.md) and its
[reference guide](../jira-cli/reference/jira-cli-reference.md) for command syntax.
Use these patterns to fetch the full ticket.
Always use `--plain` to avoid interactive TUI and `-p PROJ` for the project flag.

```bash
jira issue view -p $PROJECT $TICKET_ID --plain --comments 50
```

Capture the full description, acceptance criteria, and all comments.

## Step 7: Create Implementation Plan

Prepare a spec from the ticket content:
- Ticket summary and description
- Acceptance criteria
- Relevant comments and context
- Extra context from the user (if provided via `-`)
- The `WORK_PATH` codebase location

**Important:** If there isn’t enough information to make a plan, ask the user clarifying
questions. Do not guess.

Invoke the `superpowers:writing-plans` skill with this spec. **Override the default plan
location** — save plans to `.claude/docs/plans/YYYY-MM-DD-$TICKET_ID.md`
(relative to `WORK_PATH`), NOT the default `docs/superpowers/plans/` path.

The writing-plans skill will:
- Explore the codebase at `WORK_PATH`
- Map out file structure and changes needed
- Produce bite-sized TDD tasks with exact file paths and code
- Self-review against the spec
- Offer execution choice (subagent-driven or inline)

## Step 8: Confirm Plan

If writing-plans did not already present the execution choice to the user, present it
now. Link to the plan file location.

* * *

## Subcommands

The following subcommands continue work on a ticket after the plan has been created.
They assume you are already on the feature branch in the correct repo.

### `/jira-work implement`

Implement the plan for the current branch’s ticket.

1. Determine the ticket ID from the current branch name
2. Find the plan at `.claude/docs/plans/*-$TICKET_ID.md` (glob for date prefix)
3. **If no plan exists, STOP:** tell the user to run `/jira-work $TICKET_ID` first
4. Execute using `superpowers:subagent-driven-development` (recommended) or
   `superpowers:executing-plans` based on user preference

### `/jira-work code-review`

Run a code review on the current ticket’s changes.

1. Determine the ticket ID from the current branch name
2. Read the plan from `.claude/docs/plans/*-$TICKET_ID.md` for context on intent
3. Invoke the `/driver-code-review` skill to review the changes (it will auto-detect the correct base branch from any open PR, falling back to `main`)

### `/jira-work commit`

Commit all changes and push the branch to origin.

1. Run `git status` to see what changed
2. Stage all relevant files (do NOT stage unrelated files or secrets)
3. Write a clear commit message summarizing the changes. The last line of the
   commit message must be the ticket ID on its own (e.g., `JAVA-6111`)
4. Commit the changes
5. Push the branch to origin: `git push -u origin $BRANCH_NAME`

---

## Workspace Convention

Strictly follow this convention: 
All temporary output (evals, plans, benchmarks, scratch files) goes in the `workspace/`
directory inside this skill's directory. The `*/workspace/` pattern is gitignored.
