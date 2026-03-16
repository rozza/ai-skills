# ai-skills
A collection of AI agent skills

## Installation

Install a skill using the Claude Code CLI:

```bash
claude skill add --name <skill-name> --path /path/to/ai-skills/<skill-name>
```

For example, to install the jira-cli skill:

```bash
claude skill add --name jira-cli --path /path/to/ai-skills/jira-cli
```

## Skills

### [jira-cli](jira-cli/)

Manage Jira projects using the [ankitpokhrel/jira-cli](jira-cli) command line tool. Covers creating, listing, searching, viewing, editing, transitioning, assigning, and commenting on issues, as well as managing epics and boards. Ensures commands use non-interactive flags (`--plain`, `--no-input`) so they work reliably in an agent context, and includes a detailed reference for JQL queries, data extraction with `jq`, and common workflow patterns.
