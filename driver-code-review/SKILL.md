---
name: driver-code-review
description: Review MongoDB Java/Kotlin/Scala driver code changes for correctness, performance, concurrency, binary compatibility, and idiomatic language usage.
allowed-tools: Bash Read Agent Grep Glob
argument-hint: "[main | #PR | branch | URL] [- focus area]"
disable-model-invocation: true
---
# Driver Code Review

> **Convention**: HTML comments (`<!-- ... -->`) are human-readable notes explaining
> design decisions. Claude should skip them — they contain no instructions.

Review **only the changed code** in a diff or pull request or branch.
Provide constructive feedback focused on what was actually modified — do not critique
unchanged surrounding code.

## Step 0: Determine the Diff (MANDATORY — before any other action)

**STOP. Do NOT run git diff, gh pr diff, gh pr view, git log, or ANY command until you
complete this step.**

The user may pass an argument after the skill invocation.
Parse it as follows:

| User invocation | Meaning | Action |
| --- | --- | --- |
| `/driver-code-review main` | Diff against main | `git diff main...HEAD` |
| `/driver-code-review release/1.0` | Diff against a specific branch | `git diff release/1.0...HEAD` |
| `/driver-code-review #123` | Review PR 123 | `gh pr diff 123 -R <remote>` (see remote resolution below) |
| `/driver-code-review https://github.com/.../pull/123` | Review PR by URL | `gh pr diff 123 -R <remote>` (extract number from URL) |
| `/driver-code-review` (no argument) | Auto-detect | Check for an open PR first (see auto-detect below), else `git diff main...HEAD`, else `git diff master...HEAD` |

**Extra instructions with `-`:** Anything after a `-` is a focus area or extra
instruction for the review.
Apply it as additional emphasis on top of the standard review process.

| Example | Diff source | Extra instruction |
| --- | --- | --- |
| `/driver-code-review main - ensure concurrency` | `main` | Focus on concurrency issues |
| `/driver-code-review #123 - check binary compat` | PR 123 | Focus on binary compatibility |
| `/driver-code-review - ensure thread safety` | Default branch | Focus on thread safety |

**If no argument was provided (or the argument doesn't match the patterns above):**
auto-detect the base branch using this sequence:

1. **Check for an open PR on the current branch** — Run
   `gh pr view --json number,baseRefName -q '.baseRefName'` (using remote resolution
   below). If this succeeds and returns a base branch name, use
   `git diff <baseRefName>...HEAD`. This correctly handles PRs targeting feature
   branches (e.g., a PR against `backpressure` instead of `main`).
2. **Fall back to primary branch** — If no open PR exists for the current branch,
   check if `main` exists (`git rev-parse --verify main`); if it does, use
   `git diff main...HEAD`. Otherwise, fall back to `git diff master...HEAD`.

**Remote resolution for PRs:** When using `gh pr diff` or `gh pr view`, determine the
correct remote repo. Check if an `upstream` remote exists
(`git remote get-url upstream`); if it does, use `-R <upstream-url>`. Otherwise, fall
back to `origin` (`-R <origin-url>`).

## Scope Rule

**Review only lines that were added, modified, or deleted.** You may read unchanged
context to understand the change, but all feedback must target the diff itself.
Do not suggest improvements to pre-existing code unless the change makes an existing
issue worse or introduces a new interaction with it.

Specifically:
- **In scope:** Changed lines, new files, deleted code (was removal correct?)
- **In scope:** Pre-existing code that now has a new bug due to the change (e.g., a
  rename that missed a call site)
- **Out of scope:** Style issues in unchanged lines, pre-existing tech debt not worsened
  by this change, unrelated code in the same file
- **Out of scope:** Suggesting refactors to code the author did not touch

## Feedback Principles

**Good Feedback is:**
- Specific and actionable, referencing the changed line
- Educational, not judgmental
- Focused on the code, not the person
- Prioritized (critical vs nice-to-have)

## Severity Labels

Use labels to indicate priority on **changed code**:

- 🔴 `[blocking]` - Must fix before merge
- 🟡 `[important]` - Should fix, discuss if disagree
- 🟢 `[nit]` - Nice to have, not blocking
- 💡 `[suggestion]` - Alternative approach to consider
- 📚 `[learning]` - Educational comment, no action needed
- 🎉 `[praise]` - Good work, keep it up!

## Review Process

### Step 1: Capture the Diff

Run the diff command determined in Step 0 and capture the full output.
Also capture the PR description if reviewing a PR (`gh pr view <number> --json body`).

**If the diff is empty** (no output, or only whitespace), stop here. Report to the user
that there are no changes to review and suggest checking the base branch or PR number.
Do not spawn any reviewer agents.

**If the diff exceeds ~3000 lines**, warn the user that the review may be incomplete due
to context limits. Suggest narrowing the scope (e.g., reviewing by directory, specific
files, or commit range). Proceed only if the user confirms.

Store the diff text — you will pass it to Agents 1-3.

### Phase 1: Parallel Multi-Agent Review

<!-- Model rationale:
| Agent | Focus                      | Model      | Rationale                                            |
|-------|----------------------------|------------|------------------------------------------------------|
| 1     | Correctness & Architecture | Opus       | Deepest reasoning for subtle bugs, binary compat     |
| 2     | Performance & Concurrency  | Sonnet     | Strong technical analysis, good cost/quality balance |
| 3     | Code Quality & Tests       | Haiku      | More pattern-based, mechanical checks                |
| 4     | Copilot Validation         | Sonnet     | Judgment-heavy validation, structured input          |
| 5     | PR Comment Review          | Sonnet     | Interpreting human intent + code cross-reference     |
-->

Spawn reviewer agents **in parallel** (all in a single message). Always spawn Agents
1-4. If reviewing a PR (not a branch diff), also spawn Agent 5. Each agent gets a
different focus area and runs on a different model for diverse perspectives.

**Agents 1-3 prompts MUST include:**
1. The full diff text captured in Step 1
2. The PR description (if available)
3. The Scope Rule (review only changed lines)
4. The Severity Labels
5. The Feedback Principles
6. Any extra instructions from the user (the `-` suffix)

Agents 4 and 5 have their own context requirements listed in their sections below.

**Every agent MUST structure its output as follows:**

```
## Findings

- **File:** `path/to/File.java:L42-L48`
- **Severity:** [blocking] | [important] | [nit] | [suggestion] | [learning] | [praise]
- **Finding:** One-line summary
- **Detail:** Explanation, suggested fix, or rationale

(repeat for each finding, separated by a blank line)
```

If no findings, output `No findings.`

#### Agent 1: Correctness & Architecture (model: opus)

**Focus areas:**
- **Correctness** — Does the change do what it claims? Edge cases, off-by-one, null
  checks, error handling
- **Architecture & Design** — Does the change fit the existing structure? New
  modules/packages, dependency direction, public API surface
- **Binary Compatibility** — Any change that breaks binary compatibility in public API
  classes MUST be flagged as `[blocking]`

**Reference guides to load** (only if relevant files are in the diff):
- [Architecture Review Guide](references/architecture.md) — when: new modules/packages,
  dependency changes, build file edits, public API surface changes
- [SOLID Principles](references/solid-principles.md) — when: new classes/interfaces,
  class hierarchy changes, refactoring design patterns

**Binary Compatibility rules to include in the prompt:**

Any change that breaks binary compatibility in public API classes (anything outside
`internal` packages) MUST be flagged as `[blocking]`. Downstream consumers compile
against published artifacts — a binary-incompatible change will cause
`NoSuchMethodError`, `IncompatibleClassChangeError`, or `AbstractMethodError` at runtime.

Always flag as blocking:
- Remove or rename a public/protected method → `NoSuchMethodError`
- Remove or rename a public/protected class or interface → `NoClassDefFoundError`
- Change method signature (parameters, return type) → `NoSuchMethodError`
- Narrow method visibility (public → protected/private) → `IllegalAccessError`
- Make a class final that was non-final → `VerifyError`
- Add abstract method to non-sealed interface/class without default → `AbstractMethodError`
- Change field type or remove public field → `NoSuchFieldError`
- Remove or reorder enum constants → Runtime logic errors

Safe changes (not breaking): new classes, default methods on interfaces, new overloads,
widening visibility, new enum constants at end, deprecation without removal.

#### Agent 2: Performance & Concurrency (model: sonnet)

**Focus areas:**
- **Performance** — Does the change introduce performance issues? Hot path changes,
  collection/stream usage, regex, loops, buffer/pool code
- **Concurrency** — Code using locks, volatile, atomics, thread pools, shared mutable
  state, async callbacks — check for race conditions, deadlocks, visibility issues
- **Security** — Input validation, injection risks, credential handling

**Reference guides to load** (only if relevant files are in the diff):
- [Performance Review Guide](references/performance.md) — when: hot path changes,
  collection/stream usage, regex, loops, buffer/pool code
- [Concurrency Review Guide](references/concurrency.md) — when: code using locks,
  volatile, atomics, thread pools, shared mutable state, async callbacks

#### Agent 3: Code Quality & Tests (model: haiku)

**Focus areas:**
- **Clean Code** — Naming, method extraction, parameter lists, DRY/KISS/YAGNI,
  builders, value objects
- **Test Quality** — Are changed/new behaviors tested? Test structure, assertions,
  edge case coverage, test naming
- **Language-Idiomatic Usage** — Code must follow idiomatic conventions for its target
  language (Java, Kotlin, or Scala). Flag non-idiomatic naming as `[important]`.

**Reference guides to load** (only if relevant files are in the diff):
- [Clean Code Guide](references/clean-code.md) — when: naming changes, method
  extraction, parameter list changes, new builders/value objects
- [Test Quality Guide](references/test-quality.md) — when: new or modified test files,
  test infrastructure changes

**Language-idiomatic naming rules to include in the prompt:**

The MongoDB Java Driver includes Kotlin and Scala modules. All code MUST follow the
idiomatic naming conventions of its target language.

**Java** (`driver-core/`, `driver-sync/`, `driver-reactive-streams/`, `bson/`):
- Class: `PascalCase` — `MongoClientSettings`
- Method: `camelCase`, verb — `selectServer()`, `getDatabase()`
- Variable: `camelCase` — `serverSelectionTimeoutMS`
- Constant: `UPPER_SNAKE_CASE` — `COMMAND_COLLECTION_NAME`
- Boolean: `is`/`has`/`can` prefix — `isClosed()`, `hasWritableServer()`
- Getter/Setter: `get`/`set` prefix — `getReadPreference()`, `setMaxSize()`

**Kotlin** (`driver-kotlin-coroutine/`, `driver-kotlin-sync/`):
- Property: `camelCase`, NO `get`/`set` — `readPreference` not `getReadPreference()`
- Boolean property: NO `is` prefix — `val closed: Boolean` not `val isClosed`
- Coroutine/suspend: NO `Async` suffix — `suspend fun find()` not `findAsync()`
- Use trailing lambda convention, explicit nullable types

**Scala** (`driver-scala/`):
- Method: `camelCase`, NO `get` prefix — `readPreference` not `getReadPreference()`
- Boolean: NO `is` prefix — `def closed: Boolean`
- Constant: `PascalCase` — `val Majority` not `val MAJORITY`
- Use companion objects, implicits, native types (`Option` not `Optional`)

**Cross-language rule:** When reviewing Kotlin or Scala modules, check that no
Java getter/setter patterns leak into the public API surface.

#### Agent 4: GitHub Copilot Review (model: sonnet) — experimental

> **Experimental:** This agent is a best-effort additional signal. If `gh copilot`
> is unavailable, times out, returns an error, or produces no usable output, skip it
> and continue to Phase 2 with findings from the other agents. Do not retry and do not
> delay the review. Report the failure reason so Phase 3 can note it.

This agent runs GitHub Copilot's code review as an independent signal, then validates
its output to filter out incorrect or low-quality suggestions before passing findings
to Phase 2.

**The agent MUST follow these steps:**

1. **Run Copilot review** — The command depends on the diff source:
   - **PR review:** `gh copilot -p "Please review #<PR_NUMBER> and output any suggestions"`
     (Copilot fetches the PR diff itself — no need to pass it)
   - **Branch diff:** `gh copilot -p "Please codereview the changes in this branch and output any suggestions"`
     (Copilot accesses the local repo context directly)
   
   Capture the full output.

2. **Validate each suggestion** — For every suggestion Copilot produces, the agent must:
   - **Check relevance** — Is the suggestion about code actually in the diff? Discard
     suggestions about unchanged code (same Scope Rule as other agents).
   - **Check correctness** — Is the suggestion technically accurate? Cross-reference
     against the diff to verify the claim is true. Discard suggestions based on
     misunderstanding the code (e.g., flagging a null check that already exists,
     claiming a method doesn't exist when it does).
   - **Check actionability** — Is the suggestion specific and actionable? Discard vague
     or generic advice (e.g., "consider adding more tests" without specifying what).
   - **Check for false positives** — Discard suggestions that are clearly wrong, such as
     flagging correct code as buggy or recommending patterns that conflict with the
     project's established conventions.

3. **Format valid findings** — For each suggestion that passes validation, reformat it
   using the standard severity labels (`[blocking]`, `[important]`, `[nit]`,
   `[suggestion]`, `[learning]`, `[praise]`) and include:
   - The file path and relevant line(s)
   - The finding description
   - Why it was deemed valid
   
4. **Report discarded suggestions** — At the end of the output, include a brief summary
   of discarded suggestions and why they were rejected (one line each). This helps the
   synthesis phase understand what was filtered.

**The agent prompt MUST include:**
1. The PR number (for PR reviews) or branch name (for branch diffs)
2. The Scope Rule
3. The Severity Labels
4. Any extra instructions from the user (the `-` suffix)

#### Agent 5: PR Comment Review (model: sonnet) — PR reviews only

**This agent is only spawned when reviewing a PR** (i.e., the diff source is
`gh pr diff`). Skip this agent entirely for branch diffs.

This agent fetches existing PR review comments and checks whether they have been
addressed in the current code.

**The agent MUST follow these steps:**

1. **Fetch PR comments** — Run both commands to capture top-level conversation
   comments AND inline code review comments:
   ```
   gh pr view <PR_NUMBER> --json comments,reviews -R <remote>
   gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments
   ```
   The first returns top-level discussion and review summaries. The second returns
   inline code review comments (the most actionable feedback). Use the same remote
   resolution as Step 0. Extract `{owner}/{repo}` from the remote URL.

2. **Dismiss outdated comments** — For each comment, determine if it is outdated:
   - The comment references code that no longer exists in the diff (file deleted,
     lines removed or completely rewritten)
   - The comment was on a previous revision and the relevant code has since changed
     in a way that makes the comment no longer applicable
   - The comment is a resolved conversation or has been explicitly marked as resolved
   - The comment is purely conversational (e.g., "thanks", "LGTM", questions that
     were answered) with no actionable feedback

   Dismiss outdated comments silently — do not include them in the output.

3. **Check remaining comments against the diff** — Fetch the current diff with
   `gh pr diff <PR_NUMBER> -R <remote>`. For each non-dismissed comment:
   - **Identify what the comment requested** — Extract the specific feedback, suggestion,
     or concern raised
   - **Check if it was addressed** — Cross-reference the current diff to determine if the
     code change addresses the comment's concern. Look for:
     - Code changes that directly implement the suggestion
     - Refactoring that resolves the concern in a different but valid way
     - Test additions that cover the flagged scenario
   - **Classify the comment** as one of:
     - **Addressed** — The current code satisfies the comment's concern
     - **Partially addressed** — Some aspects were addressed but not all
     - **Unaddressed** — The concern remains in the current code
     - **Disputed** — The code intentionally takes a different approach (note this for
       the reviewer to evaluate)

4. **Format findings** — Use the shared output format. For each non-dismissed comment:
   - **File:** the file and line(s) it pertains to
   - **Severity:** For unaddressed or partially addressed comments, assign
     `[blocking]`, `[important]`, or `[nit]` based on the original comment's urgency.
     For addressed comments, use `[praise]`. For disputed comments, use `[suggestion]`.
   - **Finding:** One-line summary of the original comment + classification
     (addressed / partially addressed / unaddressed / disputed)
   - **Detail:** What was or wasn't done to address it

**The agent prompt MUST include:**
1. The PR number and remote for the `gh pr view` and `gh api` commands
2. The Scope Rule
3. The Severity Labels

### Phase 2: Synthesize Reviews

After all agents complete, read their results and produce **one consolidated review**.

**Synthesis rules:**
1. **Deduplicate** — If multiple agents flagged the same issue, keep the best-written
   version and note agreement (e.g., "flagged by multiple reviewers")
2. **Resolve conflicts** — If agents disagree on severity, the higher severity wins.
   If they disagree on whether something is an issue, include both perspectives.
3. **Incorporate Copilot findings** — Merge validated Copilot suggestions (from Agent 4)
   into the consolidated review alongside findings from other agents. If a Copilot
   finding duplicates an existing finding, treat it as corroboration. If it surfaces a
   novel issue not caught by other agents, include it at the severity Agent 4 assigned.
4. **Incorporate PR comment review** (PR reviews only) — If Agent 5 ran, add a
   **"Prior Review Comments"** section after the per-file findings. For each comment:
   - **Addressed** comments: list briefly as resolved (no severity label needed)
   - **Partially addressed** / **Unaddressed** comments: include in the review findings
     at the severity Agent 5 assigned, grouped by file. If an unaddressed comment
     overlaps with a finding from another agent, merge them and note the prior comment.
   - **Disputed** comments: include with context so the reviewer can make a judgment call
5. **Organize by file** — Group findings by file path, then by severity within each file
6. **Include praise** — Merge positive findings from all agents
7. **Preserve attributions** — Do NOT attribute findings to specific agents or models.
   Present the review as a single unified voice.

### Phase 3: Summary & Decision

After the consolidated findings, provide:

1. **Executive summary** — 2-3 sentence overview of the change and key concerns
2. **What was done well** — Highlight positive aspects from all reviewers
3. **Copilot note** — If Agent 4 (Copilot) failed or was skipped, add a brief note:
   _"Note: GitHub Copilot review was skipped ({reason})."_
4. **Final decision** — One of:
   - **Approve** — change is correct and complete
   - **Comment** — minor suggestions, not blocking
   - **Request Changes** — must address before merge

## References

Reference guides are loaded by each agent only when relevant. Skip all references for
documentation-only, Javadoc, or comment-only changes.

| Reference | When to Load | Skip When |
| --- | --- | --- |
| [Architecture](references/architecture.md) | New modules/packages, dependency changes, build file edits, public API surface changes | Single-file bug fixes, internal refactors within one package |
| [SOLID Principles](references/solid-principles.md) | New classes/interfaces, class hierarchy changes, refactoring design patterns | Modifying method internals without changing class structure |
| [Clean Code](references/clean-code.md) | Naming changes, method extraction, parameter list changes, new builders/value objects | Trivial one-line fixes, test-only changes |
| [Test Quality](references/test-quality.md) | New or modified test files, test infrastructure changes | Production code only, no test files in diff |
| [Performance](references/performance.md) | Hot path changes, collection/stream usage, regex, loops, buffer/pool code | Cold paths (startup, config, admin), documentation |
| [Concurrency](references/concurrency.md) | Code using locks, volatile, atomics, thread pools, shared mutable state, async callbacks | Single-threaded code, immutable data, pure functions |

---

## Workspace Convention

All temporary output (evals, benchmarks, scratch files) goes in the `workspace/`
directory inside this skill's directory. The `*/workspace/` pattern is gitignored.
