---
name: jira-work
description: Start working on a Jira ticket - validates workspace, creates branch, fetches ticket details, and produces an implementation plan for review.
---

# jira-work: Start Working on a Jira Ticket

Invoked as `/jira-work PROJ-XXXX` (e.g., `/jira-work JAVA-6111`). Orchestrates the full "begin work" workflow.

**Setup:** If `JIRA_API_TOKEN` is not set, source the setup script first: `source ../jira-cli/scripts/jira_cli_setup.sh` — this loads the token from the macOS keychain (or prompts to create one).

## Step 1: Parse Input

Extract the project key and ticket ID from the argument:
- `JAVA-6111` → project key: `JAVA`, ticket ID: `JAVA-6111`

## Step 2: Resolve Working Directory

Read the config file at `./jira-work/config.yml` to find the local repo path for the project.

```yaml
# config.yml format
projects:
  JAVA: /Users/ross.lawley/Code/mongodb/mongo-java-driver
```

- Look up the project key (e.g., `JAVA`) to get `WORK_PATH`
- **If `config.yml` doesn't exist or the project key is missing:** Ask the user for the local repo path. Validate it exists and is a git repo. Add the mapping to `config.yml` (create the file if needed), then continue.

## Step 3: Check for Uncommitted Work

Run `git -C $WORK_PATH status --porcelain` to check for dirty state.

**If there is uncommitted work, STOP immediately:**
> CANNOT PROCEED - Work in progress. Please commit or stash.

List the dirty files so the user can see what needs attention. Do not continue.

## Step 4: Update Main Branch

1. Check available remotes: `git -C $WORK_PATH remote`
2. Use `upstream` if it exists, otherwise use `origin`
3. Run:
   ```bash
   git -C $WORK_PATH checkout main && git -C $WORK_PATH pull $REMOTE main
   ```

## Step 5: Create Feature Branch

1. Check if branch already exists: `git -C $WORK_PATH branch --list $TICKET_ID`
2. **If branch exists:** Tell the user and ask "Branch $TICKET_ID already exists. Continue? (Y/n)"
   - If Y: `git -C $WORK_PATH checkout $TICKET_ID`
   - If n: Stop
3. **If branch doesn't exist:** `git -C $WORK_PATH checkout -b $TICKET_ID`

## Step 6: Fetch Jira Ticket

Load the [jira-cli skill](../jira-cli/SKILL.md) and its [reference guide](../jira-cli/reference/jira-cli-reference.md) for command syntax. Use these patterns to fetch the full ticket. Always use `--plain` to avoid interactive TUI and `-p PROJ` for the project flag.

```bash
jira issue view -p $PROJECT $TICKET_ID --plain
jira issue comment list $TICKET_ID --plain
```

Capture the full description, acceptance criteria, and all comments.

## Step 7: Create Implementation Plan

Analyze the ticket content **and** explore the codebase at `WORK_PATH` to understand the relevant code.

**Important:** If there isn't enough information to make a plan, ask the user clarifying questions. Do not guess.

Write the plan to `./jira-work/plans/$TICKET_ID-PLAN.md` with this structure:

```markdown
# $TICKET_ID: [Ticket Summary]

## Ticket Details
[Full raw ticket content and comments from Jira]

## Implementation Plan

### Requirements
[Key requirements and acceptance criteria extracted from the ticket]

### Proposed Approach
[Files to change, new files to create, tests to add/modify]

### Open Questions
[Anything unclear that needs user input]

### Risks / Considerations
[Edge cases, backwards compatibility, performance, etc.]
```

## Step 8: Request Review

Present the plan summary to the user and ask them to review it before any implementation begins. Link to the plan file location.
