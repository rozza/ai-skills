# ai-skills

A collection of AI agent skills

## Installation

Symlink this repo into your Claude Code skills directory:

```bash
mkdir -p ~/.claude/skills
ln -s /path/to/ai-skills/* ~/.claude/skills/
```

This makes all skills available globally across projects.

## Skills

### [jira-cli](jira-cli/)

Manage Jira projects using the [ankitpokhrel/jira-cli](jira-cli) command line tool.
Covers creating, listing, searching, viewing, editing, transitioning, assigning, and
commenting on issues, as well as managing epics and boards.
Ensures commands use non-interactive flags (`--plain`, `--no-input`) so they work
reliably in an agent context, and includes a detailed reference for JQL queries, data
extraction with `jq`, and common workflow patterns.

### [jira-work](jira-work/)

Start working on a Jira ticket with a single command.
Orchestrates the full “begin work” workflow:

```bash
/jira-work JAVA-6111
/jira-work JAVA-6111 - focus on backpressure handling
```

**What it does:**
1. Looks up the local repo path for the project from `jira-work/config.yml` (prompts you
   on first use)
2. Checks for uncommitted work — refuses to proceed if the workspace is dirty
3. Updates `main` from `upstream` (or `origin`)
4. Creates a feature branch named after the ticket (e.g., `JAVA-6111`)
5. Fetches the full Jira ticket and comments using the `jira-cli` skill
6. Delegates to superpowers' `writing-plans` to create a detailed implementation plan
   with bite-sized TDD tasks
7. Offers execution choice (subagent-driven or inline)

**Subcommands** (after a plan exists):

```bash
/jira-work implement     # execute the plan using superpowers
/jira-work code-review   # run /deep-code-review on changes against main
/jira-work commit        # commit changes and push branch to origin
```

**Requires:**
- [superpowers](https://github.com/obra/superpowers) plugin installed
  (`/plugin install superpowers@claude-plugins-official`)
- Local [jira-cli](jira-cli/) skill for all Jira commands
- [ankitpokhrel/jira-cli](https://github.com/ankitpokhrel/jira-cli) installed and
  configured

### [deep-code-review](deep-code-review/)

Portable multi-agent code review orchestrator. Captures a diff, dispatches parallel
review agents, and synthesizes their findings into a single consolidated review.

```bash
/deep-code-review main              # diff current branch against main
/deep-code-review #123              # review PR 123
/deep-code-review release/1.0       # diff against a specific branch
/deep-code-review                   # auto-detects (open PR or primary branch)
```

Add extra focus with `-`:

```bash
/deep-code-review main - ensure concurrency safety
/deep-code-review #123 - check binary compat
```

**How it works:**
1. Captures the diff (auto-detects PR vs branch, resolves remotes)
2. Dispatches parallel review agents:
   - Domain agent (reads project AGENTS.md/CLAUDE.md for rules)
   - General quality reviewer (correctness, architecture, tests)
   - Code quality reviewer (reuse, efficiency, patterns)
   - PR comment checker (if PR has existing review comments)
3. Synthesizes all findings into a single consolidated review

Carries no domain knowledge — portable across any project with AGENTS.md.

Requires [superpowers](https://github.com/obra/superpowers) plugin installed.

### [driver-code-review](driver-code-review/)

Thin wrapper around `deep-code-review` for backward compatibility.
Accepts the same arguments and delegates directly.


### [specifications](specifications/)

Look up and summarize MongoDB driver specifications from the official
[mongodb/specifications](https://github.com/mongodb/specifications) repository.

```bash
/specifications crud                  # summarize the CRUD spec
/specifications backpressure          # fuzzy matches to client-backpressure
/specifications                       # list all specs grouped by category
```

**What it does:**
1. Clones (or updates) the specifications repo locally
2. Fuzzy-matches partial spec names to the correct specification
3. Checks a local summary cache keyed by the spec file's git commit hash — serves
   cached summaries instantly when the spec hasn't changed
4. Reads the full spec and produces a structured summary (Purpose, Key Concepts,
   Driver Requirements, API Surface, Error Handling, Testing Notes, Related Specs,
   Changelog Highlights)
5. Caches the summary for future lookups
