---
name: jira-cli
description: >
  Manage Jira projects using the ankitpokhrel/jira-cli (`jira`) command line tool. Use this skill
  whenever the user mentions Jira issues, tickets, epics, boards, or any project management
  task that involves Jira. This includes creating, listing, searching, viewing, editing, transitioning,
  assigning, or commenting on Jira issues, as well as managing epics and boards. Trigger
  even if the user just says things like "check my tickets",
  "create a bug for X", "move PROJ-123 to done", or "what am I working on".
---

# Jira CLI Skill

Use the `jira` CLI (ankitpokhrel/jira-cli) to manage Jira projects. Always use `--plain` and/or `--no-input` flags when running commands so output is machine-readable and commands don't hang waiting for interactive input.

## Key Principles

- Always add `--plain` to list/view commands so output is parseable (not interactive/TUI)
- Always add `--no-input` to create/edit commands to prevent interactive prompts
- When listing issues, default to `--plain --no-truncate` for full visibility
- When creating or editing, confirm the details with the user before running the command
- Use `jira me` to get the current user's identity when needed
- Use `--raw` when you need structured JSON data for further processing

## Command Reference

### Issues

**List/Search issues:**
```bash
# List all issues in the project
jira issue list --plain --no-truncate

# Filter by status, type, priority, assignee, labels
jira issue list --plain --no-truncate -s"In Progress" -tBug -yHigh -a"user@example.com" -lurgent

# Search with text
jira issue list "search text" --plain --no-truncate

# Use JQL for complex queries
jira issue list -q"assignee = currentUser() AND status != Done" --plain --no-truncate

# Show specific columns
jira issue list --plain --columns KEY,SUMMARY,STATUS,ASSIGNEE

# My recent issues
jira issue list --history --plain --no-truncate

# Issues I'm watching
jira issue list --watching --plain --no-truncate

# Filter by date (today, week, month, year, yyyy-mm-dd, or relative like -10d)
jira issue list --created month --plain --no-truncate
jira issue list --updated -7d --plain --no-truncate
```

**View an issue:**
```bash
jira issue view ISSUE-KEY --plain
jira issue view ISSUE-KEY --plain --comments 5
jira issue view ISSUE-KEY --raw  # JSON output
```

**Create an issue:**
```bash
jira issue create -tBug -s"Summary here" -b"Description here" -yHigh -lbug --no-input
jira issue create -tStory -s"Summary" -b"Description" -a"user@example.com" --no-input
jira issue create -tTask -s"Summary" -P EPIC-KEY --no-input  # under an epic
jira issue create -tSub-task -s"Summary" -P PARENT-KEY --no-input  # sub-task
jira issue create -tStory -s"Summary" --custom story-points=3 --no-input
```

**Edit an issue:**
```bash
jira issue edit ISSUE-KEY -s"New summary" --no-input
jira issue edit ISSUE-KEY -b"New description" -yMedium --no-input
jira issue edit ISSUE-KEY -l newlabel --no-input          # append label
jira issue edit ISSUE-KEY --label -oldlabel --no-input     # remove label
```

**Transition (move) an issue:**
```bash
jira issue move ISSUE-KEY "In Progress"
jira issue move ISSUE-KEY "Done"
jira issue move ISSUE-KEY "To Do"
```

**Assign an issue:**
```bash
jira issue assign ISSUE-KEY "user@example.com"
jira issue assign ISSUE-KEY $(jira me)      # assign to self
jira issue assign ISSUE-KEY x                # unassign
jira issue assign ISSUE-KEY default          # default assignee
```

**Comment on an issue:**
```bash
jira issue comment add ISSUE-KEY -b"Comment body here"
```

**Other issue operations:**
```bash
jira issue clone ISSUE-KEY                   # duplicate an issue
jira issue link ISSUE-KEY ISSUE-KEY2         # link two issues
jira issue delete ISSUE-KEY                  # delete (use with caution)
jira open ISSUE-KEY                          # open in browser
```

### Epics

```bash
# List epics
jira epic list --plain --no-truncate

# Create an epic
jira epic create -n"Epic Name" -s"Epic summary" --no-input

# Add issues to an epic
jira epic add EPIC-KEY ISSUE-KEY1 ISSUE-KEY2

# Remove issues from an epic
jira epic remove ISSUE-KEY1 ISSUE-KEY2
```

### Boards

```bash
jira board list --plain
```

### Project Info

```bash
jira me                  # current user
jira project list        # list projects
jira serverinfo          # Jira instance info
```

## Detailed Reference

For JQL syntax, efficient data extraction with `jq`, filter flags, user intent mappings, and troubleshooting, read `references/jira-cli-reference.md`. Consult it when you need to build complex queries, extract specific fields from JSON output, or debug auth/connection issues.

## Workflow Tips

- When the user asks "what am I working on" or "my issues", use: `jira issue list -a$(jira me) -s"In Progress" --plain --no-truncate`
- When creating issues, gather summary, type, and priority from the user before running the command. Description is optional but helpful.
- For transitions, if you don't know the valid states, try common ones: "To Do", "In Progress", "In Review", "Done". The CLI will error with available states if the transition is invalid.
- Use `-p PROJECT_KEY` flag to target a specific project if the user works across multiple projects.
- For bulk operations, run commands sequentially and report results for each.
