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

Manage Jira projects using the [ankitpokhrel/jira-cli](jira-cli) command line tool. Covers creating, listing, searching, viewing, editing, transitioning, assigning, and commenting on issues, as well as managing epics and boards. Ensures commands use non-interactive flags (`--plain`, `--no-input`) so they work reliably in an agent context, and includes a detailed reference for JQL queries, data extraction with `jq`, and common workflow patterns.

### [jira-work](jira-work/)

Start working on a Jira ticket with a single command. Orchestrates the full "begin work" workflow:

```bash
/jira-work JAVA-6111
```

**What it does:**
1. Looks up the local repo path for the project from `jira-work/config.yml` (prompts you on first use)
2. Checks for uncommitted work — refuses to proceed if the workspace is dirty
3. Updates `main` from `upstream` (or `origin`)
4. Creates a feature branch named after the ticket (e.g., `JAVA-6111`)
5. Fetches the full Jira ticket and comments using the `jira-cli` skill
6. Explores the codebase and writes an implementation plan to `jira-work/plans/JAVA-6111-PLAN.md`
7. Asks you to review the plan before any implementation begins

**Requires:** Uses the local [jira-cli](jira-cli/) skill for all Jira commands. [ankitpokhrel/jira-cli](https://github.com/ankitpokhrel/jira-cli) must be installed and configured.

### [driver-code-review](driver-code-review/)

Review MongoDB Java/Kotlin/Scala driver code changes for correctness, performance, concurrency, binary compatibility, and idiomatic language usage. Focuses exclusively on changed code in diffs and pull requests.

**Covers:**
- Binary compatibility checks (flags breaking changes as blocking)
- Language-idiomatic naming for Java, Kotlin, and Scala modules
- Performance smell detection (regex, pooling, collections, caching)
- Concurrency review (locks, volatile, atomics, thread pools)
- Architecture, SOLID principles, clean code, and test quality

**Reference guides:** [Architecture](driver-code-review/references/architecture.md) | [SOLID](driver-code-review/references/solid-principles.md) | [Clean Code](driver-code-review/references/clean-code.md) | [Test Quality](driver-code-review/references/test-quality.md) | [Performance](driver-code-review/references/performance.md) | [Concurrency](driver-code-review/references/concurrency.md)
