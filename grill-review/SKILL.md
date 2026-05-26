---
name: grill-review
description: Stress-test your understanding of a code change by answering questions about intent, mechanics, impact, and testing. Works for both authors and reviewers.
allowed-tools: Bash Read Grep Glob
argument-hint: "[main | #PR | branch | URL | path/to/file]"
---
# Grill Review

Stress-tests a user's understanding of a code change by asking pointed questions.
Walks through Intent, Mechanics, Impact, and Testing — one question at a time —
verifying answers against the actual code.

## Step 1: Determine the Review Mode

**STOP. Do NOT run git diff, gh pr diff, gh pr view, git log, or ANY command until you
complete this section.**

Parse the user's argument to determine whether this is a **diff review** or a
**path review**:

**Precedence rule:** Check diff patterns first. If the argument starts with `#`,
is a URL (starts with `http`), or resolves as a git ref
(`git rev-parse --verify <arg>` succeeds), treat it as a diff review — even if it
contains `/`. Only treat as a path review if none of those match.

**Path review** — argument is a file path, directory, or glob that does not match
a diff pattern:

| User invocation | Meaning | Action |
| --- | --- | --- |
| `/grill-review src/foo.java` | Single file | Read full file contents |
| `/grill-review src/module/` | Directory | Read all files in directory |
| `/grill-review src/**/*.kt` | Glob pattern | Read all matching files |
| `/grill-review path/a.java path/b.kt` | Multiple files | Read all specified files |

**Diff review** — all other arguments:

| User invocation | Meaning | Action |
| --- | --- | --- |
| `/grill-review main` | Diff against main | `git diff main...HEAD` |
| `/grill-review release/1.0` | Diff against a branch | `git diff release/1.0...HEAD` |
| `/grill-review #123` | Review PR 123 | `gh pr diff 123 -R <remote>` |
| `/grill-review https://github.com/.../pull/123` | Review PR by URL | `gh pr diff 123 -R <remote>` (extract number from URL) |
| `/grill-review <commit-sha>` | Diff against a commit | `git diff <sha>...HEAD` |
| `/grill-review` (no argument) | Auto-detect | See sequence below |

**Auto-detect sequence (no argument):**

1. **Check for an open PR** — Run
   `gh pr view --json number,baseRefName -q '.baseRefName'` (using remote resolution
   below). If this succeeds, use `git diff <baseRefName>...HEAD`.
2. **Fall back to primary branch** — Run `git rev-parse --verify main`. If `main`
   exists, use `git diff main...HEAD`. If not, try `git rev-parse --verify master`.
   If neither exists, stop and ask the user which branch to diff against.

**Remote resolution:** Check if an `upstream` remote exists
(`git remote get-url upstream`); if it does, use `-R <upstream-url>`. Otherwise use
`origin`.

Run the diff command. **If the diff is empty**, stop and report — nothing to review.

**If the diff exceeds ~3000 lines**, warn the user and suggest narrowing scope.

## Step 2: Gather Context

1. **Extract file paths under review:**
   - For diff reviews: parse `diff --git a/... b/...` headers from the diff
   - For path reviews: use the file paths provided by the user

2. **Find AGENTS.md and CLAUDE.md files** in the directory hierarchy of each file
   under review. Use: `find . \( -name "AGENTS.md" -o -name "CLAUDE.md" \) | sort`
   then filter to paths that are ancestors of files under review.

3. **Read all found AGENTS.md/CLAUDE.md files** — concatenate their contents into a
   context block (label each with its path).

4. **Follow references** — if any AGENTS.md points to reference docs (e.g.,
   `.agents/references/`), read those too.

5. **Read FULL file contents for all changed files** — not just the diff hunks.
   This enables you to verify answers against the complete code.

## Step 3: Build Risk Map (Internal)

**Do NOT show this to the user.** Analyze the change silently across four dimensions:

- **Complexity** — Non-obvious logic, deep nesting, subtle interactions between
  components, tricky control flow
- **Impact** — Shared interfaces, public APIs, critical paths, data migrations,
  breaking changes
- **Novelty** — New patterns not seen elsewhere in the codebase, deviations from
  established conventions
- **Test coverage** — Changes lacking corresponding test updates, untested edge cases

Assign relative risk (high/medium/low) to each area. This drives question weighting.

## Step 4: Ask Questions

Walk categories in this order: **Intent → Mechanics → Impact → Testing**

**Rules:**

- **ONE question per message** — wait for the user's answer before continuing
- **Reference specific code** — use line numbers, function names, variable names
- **Mix question styles:** direct ("What does X do?"), scenario-based ("What happens
  if Y fails?"), explain ("Why was Z chosen over W?"), compare ("How does this differ
  from the old approach?")
- **Weight by risk map** — ask more questions about high-risk areas, fewer about
  low-risk areas
- **Quantity by diff size:**
  - Small (<50 lines): 3-5 questions
  - Medium (50-200 lines): 5-10 questions
  - Large (200+ lines): 10-15 questions

**After each answer, verify against the code:**

| Answer quality | Response |
| --- | --- |
| **Correct** | Brief confirmation, move to next question |
| **Partially correct** | Acknowledge what's right, note what's missing or imprecise |
| **Incorrect** | Show what the code actually does (cite lines), ask a follow-up |
| **Vague** | Probe deeper — ask for specifics |

**Internal tracking** (do not show): categories covered, questions asked per category,
accuracy rate per category.

## Step 5: Termination & Verdict

End the session when **all risk areas are adequately covered** OR the user says
"stop", "enough", or "done".

Present a final assessment:

```
## Assessment

| Category | Confidence | Notes |
| --- | --- | --- |
| Intent | ✅ Strong | Clearly articulated the motivation |
| Mechanics | ⚠️ Gaps | Missed the error retry logic |
| Impact | ✅ Strong | Understood downstream effects |
| Testing | ❌ Weak | Could not identify untested paths |

**Overall:** 1-2 sentence summary of the user's understanding.
```

**Confidence levels:**
- ✅ **Strong** — Accurate answers, demonstrates deep understanding
- ⚠️ **Gaps** — Partially correct, missed important details
- ❌ **Weak** — Incorrect or unable to answer key questions
- ⬜ **Not assessed** — Category skipped (e.g., user said "stop" early)
