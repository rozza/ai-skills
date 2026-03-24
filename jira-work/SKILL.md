---
name: jira-work
description: Start working on a Jira ticket - validates workspace, creates branch, fetches ticket details, and produces an implementation plan for review.
---
# jira-work: Start Working on a Jira Ticket

Invoked as `/jira-work PROJ-XXXX` (e.g., `/jira-work JAVA-6111`). Orchestrates the full
“begin work” workflow.

**Setup:** If `JIRA_API_TOKEN` is not set, source the setup script first:
`source ../jira-cli/scripts/jira_cli_setup.sh` — this loads the token from the macOS
keychain (or prompts to create one).

## Step 1: Parse Input

Extract the project key and ticket ID from the argument:
- `JAVA-6111` → project key: `JAVA`, ticket ID: `JAVA-6111`

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

Analyze the ticket content **and** explore the codebase at `WORK_PATH` to understand the
relevant code.

**Important:** If there isn’t enough information to make a plan, ask the user clarifying
questions. Do not guess.

Write the plan to `plans/$TICKET_ID-PLAN.md` (relative to this skill's directory) with this structure:

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

Present the plan summary to the user and ask them to review it before any implementation
begins. Link to the plan file location.

* * *

## Subcommands

The following subcommands continue work on a ticket after the plan has been created.
They assume you are already on the feature branch in the correct repo.

### `/jira-work implement`

Implement the plan for the current branch’s ticket.

1. Determine the ticket ID from the current branch name
2. Read the plan from `plans/$TICKET_ID-PLAN.md`
3. **If no plan exists, STOP:** tell the user to run `/jira-work $TICKET_ID` first
4. Implement the changes described in the plan, working through each item
5. After each significant change, briefly summarize what was done
6. Run any relevant tests to verify the changes compile and pass

### `/jira-work code-review`

Run a code review on the current ticket’s changes.

1. Determine the ticket ID from the current branch name
2. Read the plan from `plans/$TICKET_ID-PLAN.md` for context on intent
3. Invoke the `/driver-code-review main` skill to review the changes against `main`

### `/jira-work commit`

Commit all changes and push the branch to origin.

1. Run `git status` to see what changed
2. Stage all relevant files (do NOT stage unrelated files or secrets)
3. Write a clear commit message summarizing the changes. The last line of the
   commit message must be the ticket ID on its own (e.g., `JAVA-6111`)
4. Commit the changes
5. Push the branch to origin: `git push -u origin $BRANCH_NAME`
6. Delete the plan file: `plans/$TICKET_ID-PLAN.md`
