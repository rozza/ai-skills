---
name: driver-code-review
description: Review MongoDB Java/Kotlin/Scala driver code changes for correctness, performance, concurrency, binary compatibility, and idiomatic language usage.
---

# Driver Code Review

Review **only the changed code** in a diff or pull request. Provide constructive feedback focused on what was actually modified — do not critique unchanged surrounding code.

## Scope Rule

**Review only lines that were added, modified, or deleted.** You may read unchanged context to understand the change, but all feedback must target the diff itself. Do not suggest improvements to pre-existing code unless the change makes an existing issue worse or introduces a new interaction with it.

Specifically:
- **In scope:** Changed lines, new files, deleted code (was removal correct?)
- **In scope:** Pre-existing code that now has a new bug due to the change (e.g., a rename that missed a call site)
- **Out of scope:** Style issues in unchanged lines, pre-existing tech debt not worsened by this change, unrelated code in the same file
- **Out of scope:** Suggesting refactors to code the author did not touch

## When to Use This Skill

- Reviewing pull requests and code diffs
- Conducting architecture reviews of proposed changes
- Mentoring developers through review feedback on their changes

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

## Review Process

### Phase 1: Understand the Change

1. Read PR description and linked issue
2. Identify what changed — new files, modified files, deleted files
3. Understand the intent — bug fix, feature, refactor, test?

### Phase 2: Review the Diff

For each changed file, review **only the changed lines** and their immediate context:

1. **Correctness** - Does the change do what it claims? Edge cases, off-by-one, null checks
2. **Architecture & Design** - Does the change fit? For significant structural changes, consult [Architecture Review Guide](references/architecture.md)
3. **Performance** - Does the change introduce issues? For hot path changes, consult [Performance Review Guide](references/performance.md)
4. **Security** - Does the change introduce vulnerabilities? Input validation, injection risks
5. **Tests** - Are the changed/new behaviors tested?

### Phase 3: Summary & Decision

1. Summarize key concerns about the **changed code**
2. Highlight what was done well
3. Make clear decision:
   - Approve — change is correct and complete
   - Comment — minor suggestions, not blocking
   - Request Changes — must address before merge

## Severity Labels

Use labels to indicate priority on **changed code**:

- 🔴 `[blocking]` - Must fix before merge
- 🟡 `[important]` - Should fix, discuss if disagree
- 🟢 `[nit]` - Nice to have, not blocking
- 💡 `[suggestion]` - Alternative approach to consider
- 📚 `[learning]` - Educational comment, no action needed
- 🎉 `[praise]` - Good work, keep it up!

## Language-Idiomatic Naming

The MongoDB Java Driver includes Kotlin and Scala modules. All code MUST follow the idiomatic naming conventions of its target language. Flag non-idiomatic naming as `[important]`.

### Java (`driver-core/`, `driver-sync/`, `driver-reactive-streams/`, `bson/`)

| Element | Convention | Example |
|---------|-----------|---------|
| Class | `PascalCase` | `MongoClientSettings` |
| Method | `camelCase`, verb | `selectServer()`, `getDatabase()` |
| Variable | `camelCase` | `serverSelectionTimeoutMS` |
| Constant | `UPPER_SNAKE_CASE` | `COMMAND_COLLECTION_NAME` |
| Boolean | `is`/`has`/`can` prefix | `isClosed()`, `hasWritableServer()` |
| Package | lowercase | `com.mongodb.client.model` |
| Getter/Setter | `get`/`set` prefix | `getReadPreference()`, `setMaxSize()` |

### Kotlin (`driver-kotlin-coroutine/`, `driver-kotlin-sync/`)

| Element | Convention | Example |
|---------|-----------|---------|
| Class | `PascalCase` | `MongoClient` |
| Function | `camelCase`, verb | `findOneAndUpdate()` |
| Property | `camelCase`, no `get`/`set` | `readPreference` (not `getReadPreference()`) |
| Constant | `UPPER_SNAKE_CASE` or `PascalCase` for objects | `DEFAULT_CODEC_REGISTRY` |
| Boolean property | no `is` prefix on property | `val closed: Boolean` (not `val isClosed`) |
| Extension function | `camelCase` | `Document.toBsonDocument()` |
| Coroutine/suspend | `camelCase`, no `Async` suffix | `suspend fun find()` (not `findAsync()`) |
| Lambda last param | trailing lambda convention | `withTimeout(5.seconds) { ... }` |
| Nullable | explicit `?` type | `fun find(): Document?` |

```kotlin
// BAD: Java-style in Kotlin
fun getServerDescription(): ServerDescription { ... }
fun isClosed(): Boolean { ... }
val isReady: Boolean

// GOOD: Idiomatic Kotlin
val serverDescription: ServerDescription
val closed: Boolean
val ready: Boolean
```

### Scala (`driver-scala/`)

| Element | Convention | Example |
|---------|-----------|---------|
| Class/Trait | `PascalCase` | `MongoCollection` |
| Method | `camelCase`, no `get` prefix | `readPreference` (not `getReadPreference()`) |
| Value (`val`) | `camelCase` | `val defaultRegistry` |
| Constant | `PascalCase` (Scala convention) | `val DefaultCodecRegistry` |
| Boolean | no `is` prefix on accessor | `def closed: Boolean` |
| Type parameter | single uppercase or descriptive | `[T]`, `[TResult]` |
| Package object | lowercase | `package object model` |
| Implicit | descriptive, often `*Ops` | `implicit class DocumentOps` |
| Companion object | same name as class | `object MongoClient { def apply(...) }` |

```scala
// BAD: Java-style in Scala
def getDatabase(name: String): MongoDatabase
def isClosed(): Boolean
val MAJORITY: WriteConcern

// GOOD: Idiomatic Scala
def database(name: String): MongoDatabase
def closed: Boolean
val Majority: WriteConcern
```

### Cross-Language Review Rule

When reviewing Kotlin or Scala modules, check that the public API surface feels native to the language:

1. **No Java getter/setter patterns** leaking into Kotlin properties or Scala accessors
2. **No `Async` suffixes** on Kotlin coroutine functions — `suspend` already communicates this
3. **No `is` prefix** on Kotlin/Scala boolean properties (the language conventions differ from Java)
4. **Scala constants** use `PascalCase`, not `UPPER_SNAKE_CASE`
5. **Wrapper APIs** should use language-native types (e.g., Scala `Option` not Java `Optional`, Kotlin `Flow` not reactive `Publisher`)

## Binary Compatibility (Java)

**Any change that breaks binary compatibility in public API classes MUST be flagged as `[blocking]`.** Downstream consumers compile against published artifacts — a binary-incompatible change will cause `NoSuchMethodError`, `IncompatibleClassChangeError`, or `AbstractMethodError` at runtime even without recompilation.

### Always Flag as Blocking

| Change | Runtime Error | Example |
|--------|--------------|---------|
| Remove or rename a public/protected method | `NoSuchMethodError` | Renaming `getTimeout()` to `timeout()` |
| Remove or rename a public/protected class or interface | `NoClassDefFoundError` | Moving `ServerSelector` to a different package |
| Change method signature (parameters, return type) | `NoSuchMethodError` | Changing `long getTimeout()` to `Duration getTimeout()` |
| Narrow method visibility (public to protected/private) | `IllegalAccessError` | Making a public method package-private |
| Make a class final that was non-final | `VerifyError` | Adding `final` to a class consumers extend |
| Add abstract method to non-sealed interface/class | `AbstractMethodError` | Adding a new method to `ServerSelector` without a default |
| Change field type or remove public field | `NoSuchFieldError` | Changing `public static final int MAX` type |
| Remove or reorder enum constants | Runtime logic errors | Removing or reordering values consumers switch on |

### Safe Changes (Not Breaking)

- Adding a new class, interface, or enum
- Adding a new method with a `default` implementation to an interface
- Adding a new overloaded method (existing signatures unchanged)
- Widening method visibility (protected to public)
- Adding new enum constants at the end
- Deprecating (but not removing) existing API

### Review Rule

When reviewing changes to public API classes (anything outside `internal` packages):

1. Check the diff for removed/renamed/changed method signatures
2. Check for new abstract methods on interfaces without defaults
3. Check for visibility narrowing or added `final` modifiers
4. If any are found: **mark as `[blocking]`** with a clear explanation of what breaks and for whom

## References

Only load a reference when the change touches relevant code. Skip all references for documentation-only, Javadoc, or comment-only changes.

| Reference | When to Load | Skip When |
|-----------|-------------|-----------|
| [Architecture](references/architecture.md) | New modules/packages, dependency changes, build file edits, public API surface changes | Single-file bug fixes, internal refactors within one package |
| [SOLID Principles](references/solid-principles.md) | New classes/interfaces, class hierarchy changes, refactoring design patterns | Modifying method internals without changing class structure |
| [Clean Code](references/clean-code.md) | Naming changes, method extraction, parameter list changes, new builders/value objects | Trivial one-line fixes, test-only changes |
| [Test Quality](references/test-quality.md) | New or modified test files, test infrastructure changes | Production code only, no test files in diff |
| [Performance](references/performance.md) | Hot path changes, collection/stream usage, regex, loops, buffer/pool code | Cold paths (startup, config, admin), documentation |
| [Concurrency](references/concurrency.md) | Code using locks, volatile, atomics, thread pools, shared mutable state, async callbacks | Single-threaded code, immutable data, pure functions |

