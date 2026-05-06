---
name: driver-code-review
description: Review MongoDB Java/Kotlin/Scala driver code changes for correctness, performance, concurrency, binary compatibility, and idiomatic language usage.
allowed-tools: Bash Read Agent Grep Glob
argument-hint: "[main | #PR | branch | URL] [- focus area]"
---
# Driver Code Review

Review **only the changed code** in a diff or pull request.
Provide constructive feedback focused on what was actually modified.

## Determine and Capture the Diff

**STOP. Do NOT run git diff, gh pr diff, gh pr view, git log, or ANY command until you
complete this section.**

Parse the user's argument:

| User invocation | Meaning | Action |
| --- | --- | --- |
| `/driver-code-review main` | Diff against main | `git diff main...HEAD` |
| `/driver-code-review release/1.0` | Diff against a specific branch | `git diff release/1.0...HEAD` |
| `/driver-code-review #123` | Review PR 123 | `gh pr diff 123 -R <remote>` (see remote resolution below) |
| `/driver-code-review https://github.com/.../pull/123` | Review PR by URL | `gh pr diff 123 -R <remote>` (extract number from URL) |
| `/driver-code-review` (no argument) | Auto-detect | Check for an open PR first, else diff against primary branch (see below) |

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

## Parallel Review

**Small diff fast-path:** If the diff is under ~50 lines, skip Phase 2 (general review
agent). The domain review alone is sufficient for small changes.

Run phases **in parallel** (single message). Always run Phase 1. Run Phase 2 for diffs
over ~50 lines. Run Phase 3 only for PR reviews that have existing comments.

### Phase 1: Domain Review (you, directly)

Apply the full Review Checklist below against the diff. Use the Scope Rule. Load
reference guides inline with each checklist area as needed. Produce findings in the
Output Format.

### Phase 2: General Code Review (Agent, model: sonnet)

Dispatch one Agent as a general code reviewer following the superpowers
`requesting-code-review` pattern. The agent prompt MUST include:

1. The full diff text
2. The PR description (if available)
3. Any extra instructions from the user (the `-` suffix)
4. The Scope Rule and Severity Labels (copied below)
5. This instruction set:

> You are a code reviewer. Review the diff for:
> - Correctness: logic errors, edge cases, off-by-one, null safety, resource leaks
> - Architecture: does the change fit existing patterns? dependency direction, coupling
> - Test quality: are new/changed behaviors tested? assertions, edge cases
> - Production readiness: error handling, logging, observability
>
> Focus only on changed lines. Do not critique unchanged code.
> Group findings by file. Use the severity labels provided.
> End with a 2-3 sentence summary and a decision: Approve | Comment | Request Changes.

### Phase 3: PR Comment Review (Agent, model: sonnet) — PR reviews only

**Only spawn this agent when reviewing a PR that has existing review comments.** Before
spawning, check: `gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments | jq length`.
If the count is 0, skip this phase. Skip entirely for branch diffs.

This agent checks whether existing PR review comments have been addressed. The agent
prompt MUST include the PR number, remote, Scope Rule, and Severity Labels, plus these
instructions:

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

## Synthesize

After all phases complete, produce **one consolidated review**:

1. **Deduplicate** — If multiple phases flagged the same issue, keep the better-written
   version and note agreement
2. **Resolve conflicts** — If phases disagree on severity, higher severity wins
3. **Incorporate PR comments** (PR reviews only) — Add a **"Prior Review Comments"**
   section after per-file findings. Addressed comments listed briefly as resolved.
   Unaddressed/partially addressed comments included at their assigned severity.
   If an unaddressed comment overlaps with another finding, merge them.
4. **Organize by file** — Group all findings by file path, then severity within each file
5. **Include praise** — Merge positive findings from all phases
6. **Present as a single voice** — Do NOT attribute findings to specific phases

## Scope Rule

**Review only lines that were added, modified, or deleted.**

- **In scope:** Changed lines, new files, deleted code, pre-existing code made worse by the change
- **Out of scope:** Style in unchanged lines, pre-existing tech debt, unrelated code

## Review Checklist

Work through each area systematically for every file in the diff.

### Correctness & Edge Cases
- Does the change do what it claims? Off-by-one, null checks, error handling, resource leaks

### Binary Compatibility

Any change that breaks binary compatibility in public API classes (anything outside
`internal` packages) MUST be flagged as `[blocking]`.

Always flag as blocking:
- Remove or rename a public/protected method → `NoSuchMethodError`
- Remove or rename a public/protected class or interface → `NoClassDefFoundError`
- Change method signature (parameters, return type) → `NoSuchMethodError`
- Narrow method visibility (public → protected/private) → `IllegalAccessError`
- Make a class final that was non-final → `VerifyError`
- Add abstract method to non-sealed interface/class without default → `AbstractMethodError`
- Change field type or remove public field → `NoSuchFieldError`
- Remove or reorder enum constants → Runtime logic errors

Safe changes: new classes, default methods on interfaces, new overloads, widening
visibility, new enum constants at end, deprecation without removal.

### Architecture & Design
- Does the change fit the existing structure? Dependency direction, public API surface
- Reference: [Architecture](references/architecture.md) — load when: new modules/packages,
  dependency changes, build files, public API changes

### Performance
- Hot path changes, collection/stream usage, regex compilation, loops, buffer/pool code
- Reference: [Performance](references/performance.md) — load when: hot paths, collections,
  regex, loops, buffers

### Concurrency
- Locks, volatile, atomics, thread pools, shared mutable state, async callbacks
- Race conditions, deadlocks, visibility issues
- Reference: [Concurrency](references/concurrency.md) — load when: locks, volatile,
  atomics, thread pools, shared state

### Code Quality & Naming
- Naming clarity, method extraction, parameter lists, DRY/KISS/YAGNI
- Reference: [Clean Code](references/clean-code.md) — load when: naming changes, method
  extraction, parameter lists, builders
- Reference: [SOLID Principles](references/solid-principles.md) — load when: new
  classes/interfaces, hierarchy changes, design patterns

### Language-Idiomatic Usage

Code MUST follow idiomatic conventions for its target language.

**Java** (`driver-core/`, `driver-sync/`, `driver-reactive-streams/`, `bson/`):
- Class: `PascalCase` — `MongoClientSettings`
- Method: `camelCase`, verb — `selectServer()`, `getDatabase()`
- Constant: `UPPER_SNAKE_CASE`
- Boolean: `is`/`has`/`can` prefix — `isClosed()`
- Getter/Setter: `get`/`set` prefix

**Kotlin** (`driver-kotlin-coroutine/`, `driver-kotlin-sync/`):
- Property: `camelCase`, NO `get`/`set` — `readPreference` not `getReadPreference()`
- Boolean property: NO `is` prefix — `val closed: Boolean`
- Coroutine/suspend: NO `Async` suffix — `suspend fun find()`
- Trailing lambda convention, explicit nullable types

**Scala** (`driver-scala/`):
- Method: `camelCase`, NO `get` prefix — `readPreference`
- Boolean: NO `is` prefix — `def closed: Boolean`
- Constant: `PascalCase` — `val Majority`
- Companion objects, implicits, native types (`Option` not `Optional`)

**Cross-language rule:** Check that no Java getter/setter patterns leak into Kotlin or
Scala public API surfaces.

### Test Coverage
- Are changed/new behaviors tested? Test structure, assertions, edge case coverage
- Reference: [Test Quality](references/test-quality.md) — load when: new/modified test
  files, test infrastructure changes

## Severity Labels

- 🔴 `[blocking]` - Must fix before merge
- 🟡 `[important]` - Should fix, discuss if disagree
- 🟢 `[nit]` - Nice to have, not blocking
- 💡 `[suggestion]` - Alternative approach to consider
- 📚 `[learning]` - Educational comment, no action needed
- 🎉 `[praise]` - Good work, keep it up!

## Output Format

Group findings by file, then by severity within each file:

```
## Findings

### `path/to/File.java`

- 🔴 `[blocking]` **L42-48:** One-line summary
  Detail: explanation and suggested fix

- 🟡 `[important]` **L15:** One-line summary
  Detail: explanation

### `path/to/Other.kt`

- 🟢 `[nit]` **L7:** One-line summary

## Summary

2-3 sentence overview of the change quality and key concerns.

**Decision:** Approve | Comment | Request Changes
```
