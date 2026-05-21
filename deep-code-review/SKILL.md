---
name: deep-code-review
description: Multi-agent code review orchestrator. Captures a diff, dispatches parallel review agents (domain, general quality, reuse/efficiency, PR comments), and synthesizes findings into a consolidated review. Portable - uses project AGENTS.md for domain rules.
allowed-tools: Bash Read Agent Grep Glob Skill
argument-hint: "[main | #PR | branch | URL] [- focus area]"
---
# Deep Code Review

A portable, multi-agent code review orchestrator. Reviews **only changed code** in a
diff or pull request. Carries no domain knowledge — relies on the project's AGENTS.md
and CLAUDE.md for rules.

## Step 1: Determine and Capture the Diff

**STOP. Do NOT run git diff, gh pr diff, gh pr view, git log, or ANY command until you
complete this section.**

Parse the user's argument:

| User invocation | Meaning | Action |
| --- | --- | --- |
| `/deep-code-review main` | Diff against main | `git diff main...HEAD` |
| `/deep-code-review release/1.0` | Diff against a specific branch | `git diff release/1.0...HEAD` |
| `/deep-code-review #123` | Review PR 123 | `gh pr diff 123 -R <remote>` (see remote resolution below) |
| `/deep-code-review https://github.com/.../pull/123` | Review PR by URL | `gh pr diff 123 -R <remote>` (extract number from URL) |
| `/deep-code-review` (no argument) | Auto-detect | Check for an open PR first, else diff against primary branch (see below) |

**Extra instructions with `-`:** Anything after a `-` is a focus area.
Apply it as additional emphasis on top of the standard review.

**Auto-detect sequence (no argument):**

1. **Check for an open PR** — Run
   `gh pr view --json number,baseRefName -q '.baseRefName'` (using remote resolution
   below). If this succeeds, use `git diff <baseRefName>...HEAD`.
2. **Fall back to primary branch** — Run `git rev-parse --verify main`. If `main`
   exists, use `git diff main...HEAD`. If `main` does not exist, try
   `git rev-parse --verify master`; if that exists, use `git diff master...HEAD`.
   If neither exists, stop and ask the user which branch to diff against.

**Remote resolution:** Check if an `upstream` remote exists
(`git remote get-url upstream`); if it does, use `-R <upstream-url>`. Otherwise use
`origin`.

Run the diff command. Also capture the PR description if reviewing a PR
(`gh pr view <number> --json body`).

**If the diff is empty**, stop and report — no changes to review.

**If the diff exceeds ~3000 lines**, warn the user and suggest narrowing scope.

## Step 1.5: Gather Context for Agents

Before dispatching agents, gather context they'll need:

1. **Extract changed file paths** from the diff (parse `diff --git a/... b/...` headers)
2. **Find all AGENTS.md and CLAUDE.md files** in the directory hierarchy of each changed
   file. For a change in `driver-kotlin-sync/src/main/kotlin/Foo.kt`, collect:
   - `./AGENTS.md`, `./CLAUDE.md` (root)
   - `./driver-kotlin-sync/AGENTS.md`, `./driver-kotlin-sync/CLAUDE.md` (module)
   - Any deeper AGENTS.md/CLAUDE.md files along the path
   
   Use: `find . -name "AGENTS.md" -o -name "CLAUDE.md" | sort` then filter to paths
   that are ancestors of changed files.
3. **Read all found AGENTS.md/CLAUDE.md files** and concatenate their contents into a
   single context block (label each with its path).
4. **Follow references** — if any AGENTS.md points to reference docs (e.g.,
   `.agents/references/`), read those too and include them.

This context block is passed to ALL agents below as `**Project Context:**`.

## Step 2: Dispatch Parallel Review Agents

**Small diff fast-path:** If the diff is under ~50 lines, skip the
`/requesting-code-review` agent. The domain agent + `/code-review` agent are
sufficient for small changes.

Run agents **in parallel** (single message with multiple Agent calls). Always run
the Domain Agent and `/code-review` Agent. Run the `/requesting-code-review` Agent
for diffs over ~50 lines. Run the PR Comment Check agent only for PR reviews with
existing comments.

**Every agent receives:**
- The full diff text
- PR description (if available)
- User's focus area (the `- focus` suffix)
- The project context block (all AGENTS.md/CLAUDE.md content gathered in Step 1.5)
- The severity labels and scope rule (defined at bottom of this skill)

### Domain Agent

Dispatch one Agent with these instructions:

> You are a domain-specific code reviewer. Your job is to review the diff using this
> project's own coding standards and guidelines.
>
> **Steps:**
> 1. Read the Project Context below carefully — it contains all AGENTS.md, CLAUDE.md,
>    and reference documents relevant to the changed files
> 2. If any referenced documents were not included (e.g., a module AGENTS.md references
>    a file not shown), read it yourself
> 3. Apply ALL rules from these documents to review the diff
> 4. Focus only on changed lines — do not critique unchanged code
> 5. Report findings using the severity labels and output format provided
>
> **Project Context:**
> (include the full context block from Step 1.5)
>
> **Diff:**
> (include full diff text)
>
> **PR Description:** (if available)
>
> **Focus area:** (if provided by user)
>
> **Scope Rule:**
> - In scope: Changed lines, new files, deleted code, pre-existing code made worse
>   by the change
> - Out of scope: Style in unchanged lines, pre-existing tech debt, unrelated code
>
> **Severity Labels:**
> - `[blocking]` — Must fix before merge
> - `[important]` — Should fix, discuss if disagree
> - `[nit]` — Nice to have, not blocking
> - `[suggestion]` — Alternative approach to consider
> - `[learning]` — Educational comment, no action needed
> - `[praise]` — Good work, keep it up!
>
> **Output format:** Group findings by file path. For each finding include severity,
> line numbers, one-line summary, and detail/suggested fix.

### `/requesting-code-review` Agent

Dispatch one Agent and instruct it to invoke the `/requesting-code-review` skill.
The agent's prompt must include:

> You are performing a code review. Invoke the `/requesting-code-review` skill to
> guide your review process.
>
> **Project Context:**
> (include the full context block from Step 1.5 — the agent needs project rules
> to assess whether changes fit existing patterns and architecture)
>
> **Diff:**
> (include full diff text)
>
> **PR Description:** (if available)
>
> **Focus area:** (if provided by user)
>
> **Scope Rule:**
> - In scope: Changed lines, new files, deleted code, pre-existing code made worse
>   by the change
> - Out of scope: Style in unchanged lines, pre-existing tech debt, unrelated code
>
> **Severity Labels:**
> - `[blocking]` — Must fix before merge
> - `[important]` — Should fix, discuss if disagree
> - `[nit]` — Nice to have, not blocking
> - `[suggestion]` — Alternative approach to consider
> - `[learning]` — Educational comment, no action needed
> - `[praise]` — Good work, keep it up!
>
> **Output format:** Group findings by file path. For each finding include severity,
> line numbers, one-line summary, and detail/suggested fix.
> End with a 2-3 sentence summary and a decision: Approve | Comment | Request Changes.

### `/code-review` Agent

Dispatch one Agent and instruct it to invoke the `/code-review` skill.
The agent's prompt must include:

> You are performing a code quality review. Invoke the `/code-review` skill to
> guide your review process.
>
> **Project Context:**
> (include the full context block from Step 1.5 — the agent needs this to check
> whether code follows or deviates from existing project patterns)
>
> **Diff:**
> (include full diff text)
>
> **PR Description:** (if available)
>
> **Focus area:** (if provided by user)
>
> **Scope Rule:**
> - In scope: Changed lines, new files, deleted code, pre-existing code made worse
>   by the change
> - Out of scope: Style in unchanged lines, pre-existing tech debt, unrelated code
>
> **Severity Labels:**
> - `[blocking]` — Must fix before merge
> - `[important]` — Should fix, discuss if disagree
> - `[nit]` — Nice to have, not blocking
> - `[suggestion]` — Alternative approach to consider
> - `[learning]` — Educational comment, no action needed
> - `[praise]` — Good work, keep it up!
>
> **Output format:** Group findings by file path. For each finding include severity,
> line numbers, one-line summary, and detail/suggested fix.
> End with a 2-3 sentence summary and a decision: Approve | Comment | Request Changes.

### PR Comment Check Agent (PR reviews only)

**Only spawn this agent when reviewing a PR that has existing review comments.** Before
spawning, check: `gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments | jq length`.
If the count is 0, skip this agent. Skip entirely for branch diffs.

Dispatch one Agent with these instructions:

> You are checking whether prior PR review comments have been addressed.
>
> **Steps:**
> 1. Fetch PR comments:
>    - `gh pr view <PR_NUMBER> --json comments,reviews -R <remote>`
>    - `gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments`
>
> 2. Dismiss outdated comments (resolved conversations, references to deleted code,
>    purely conversational messages like "thanks" or "LGTM").
>
> 3. For each remaining comment, check the current diff:
>    - **Addressed** — code satisfies the concern
>    - **Partially addressed** — some aspects handled, not all
>    - **Unaddressed** — concern remains in current code
>    - **Disputed** — code intentionally takes a different approach
>
> 4. Format output:
>    - Addressed comments: list briefly as resolved (use `[praise]`)
>    - Partially addressed / Unaddressed: use `[blocking]` or `[important]` based on
>      the original comment's urgency
>    - Disputed: use `[suggestion]` with context for the reviewer
>
> Group findings by file. Use the severity labels provided.
>
> **PR Number:** <PR_NUMBER>
> **Remote:** <remote>
> **Diff:**
> (include full diff text)

## Step 3: Synthesize

After all agents complete, produce **one consolidated review**:

1. **Deduplicate** — If multiple agents flagged the same issue, keep the better-written
   version and note agreement
2. **Resolve conflicts** — If agents disagree on severity, higher severity wins
3. **Incorporate PR comments** (PR reviews only) — Add a **"Prior Review Comments"**
   section after per-file findings. Addressed comments listed briefly as resolved.
   Unaddressed/partially addressed comments included at their assigned severity.
   If an unaddressed comment overlaps with another finding, merge them.
4. **Organize by file** — Group all findings by file path, then severity within each file
5. **Include praise** — Merge positive findings from all agents
6. **Present as a single voice** — Do NOT attribute findings to specific agents

## Output Template

```
## Findings

### `path/to/File.java`

- 🔴 `[blocking]` **L42-48:** One-line summary
  Detail: explanation and suggested fix

- 🟡 `[important]` **L15:** One-line summary
  Detail: explanation

### `path/to/Other.kt`

- 🟢 `[nit]` **L7:** One-line summary

## Prior Review Comments (PR reviews only)

- ✅ Addressed: brief list
- ⚠️ Unaddressed: with severity and detail

## Summary

2-3 sentence overview of the change quality and key concerns.

**Decision:** Approve | Comment | Request Changes
```

## Severity Labels

- 🔴 `[blocking]` — Must fix before merge
- 🟡 `[important]` — Should fix, discuss if disagree
- 🟢 `[nit]` — Nice to have, not blocking
- 💡 `[suggestion]` — Alternative approach to consider
- 📚 `[learning]` — Educational comment, no action needed
- 🎉 `[praise]` — Good work, keep it up!
