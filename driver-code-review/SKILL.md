---
name: driver-code-review
description: Review MongoDB Java/Kotlin/Scala driver code changes for correctness, performance, concurrency, binary compatibility, and idiomatic language usage.
---
# Driver Code Review

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
| `/driver-code-review` (no argument) | Default branch | `git diff main...HEAD` if `main` exists, else `git diff master...HEAD` |

**Extra instructions with `-`:** Anything after a `-` is a focus area or extra
instruction for the review.
Apply it as additional emphasis on top of the standard review process.

| Example | Diff source | Extra instruction |
| --- | --- | --- |
| `/driver-code-review main - ensure concurrency` | `main` | Focus on concurrency issues |
| `/driver-code-review #123 - check binary compat` | PR 123 | Focus on binary compatibility |
| `/driver-code-review - ensure thread safety` | Default branch | Focus on thread safety |

**If no argument was provided (or the argument doesn't match the patterns above):**
default to diffing against the primary branch. Check if `main` exists
(`git rev-parse --verify main`); if it does, use `git diff main...HEAD`. Otherwise,
fall back to `git diff master...HEAD`.

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

```markdown
❌ Bad: "This is wrong."
✅ Good: "This could cause a race condition when multiple users
         access simultaneously. Consider using a mutex here."

❌ Bad: "Why didn't you use X pattern?"
✅ Good: "Have you considered the Repository pattern? It would
         make this easier to test. Here's an example: [link]"

❌ Bad: "Rename this variable." (on an unchanged line)
✅ Good: "[nit] Consider `userCount` instead of `uc` for
         clarity. Not blocking if you prefer to keep it." (on a new/changed line)
```

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

Store the diff text — you will pass it to each reviewer agent.

### Phase 1: Parallel Multi-Agent Review

Spawn **3 reviewer agents in parallel** (all in a single message with 3 Agent tool
calls). Each agent gets a different focus area and runs on a different model for diverse
perspectives.

**Every agent prompt MUST include:**
1. The full diff text captured in Step 1
2. The PR description (if available)
3. The Scope Rule (review only changed lines)
4. The Severity Labels
5. The Feedback Principles
6. Any extra instructions from the user (the `-` suffix)

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

### Phase 2: Synthesize Reviews

After all 3 agents complete, read their results and produce **one consolidated review**.

**Synthesis rules:**
1. **Deduplicate** — If multiple agents flagged the same issue, keep the best-written
   version and note agreement (e.g., "flagged by multiple reviewers")
2. **Resolve conflicts** — If agents disagree on severity, the higher severity wins.
   If they disagree on whether something is an issue, include both perspectives.
3. **Organize by file** — Group findings by file path, then by severity within each file
4. **Include praise** — Merge positive findings from all agents
5. **Preserve attributions** — Do NOT attribute findings to specific agents or models.
   Present the review as a single unified voice.

### Phase 3: Summary & Decision

After the consolidated findings, provide:

1. **Executive summary** — 2-3 sentence overview of the change and key concerns
2. **What was done well** — Highlight positive aspects from all reviewers
3. **Final decision** — One of:
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
