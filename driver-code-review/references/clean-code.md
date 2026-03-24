# Clean Code

Write readable, maintainable code following Clean Code principles.
Examples drawn from the MongoDB Java Driver.

## When to Use

- User says “clean this code” / “refactor” / “improve readability”
- Code review focusing on maintainability
- Reducing complexity
- Improving naming

* * *

## Core Principles

| Principle | Meaning | Violation Sign |
| --- | --- | --- |
| **DRY** | Don’t Repeat Yourself | Copy-pasted code blocks |
| **KISS** | Keep It Simple, Stupid | Over-engineered solutions |
| **YAGNI** | You Aren’t Gonna Need It | Features “just in case” |

* * *

## DRY - Don’t Repeat Yourself

> “Every piece of knowledge must have a single, unambiguous representation in the
> system.”

### Violation

```java
// ❌ BAD: Same null-check and exception pattern repeated everywhere
public class QueryBuilder {

    public Bson buildFindFilter(String fieldName, Object value) {
        if (fieldName == null) {
            throw new IllegalArgumentException("fieldName can not be null");
        }
        if (value == null) {
            throw new IllegalArgumentException("value can not be null");
        }
        return new BsonDocument(fieldName, toBsonValue(value));
    }

    public Bson buildUpdate(String fieldName, Object value) {
        if (fieldName == null) {
            throw new IllegalArgumentException("fieldName can not be null");
        }
        if (value == null) {
            throw new IllegalArgumentException("value can not be null");
        }
        return new BsonDocument("$set", new BsonDocument(fieldName, toBsonValue(value)));
    }
}
```

### Good Example: The Driver’s `Assertions` Utility

The driver centralizes all validation into `Assertions` — used hundreds of times across
the codebase:

```java
// ✅ GOOD: Single source of truth for null validation
public final class Assertions {

    public static <T> T notNull(final String name, final T value) {
        if (value == null) {
            throw new IllegalArgumentException(name + " can not be null");
        }
        return value;
    }

    public static void isTrueArgument(final String name, final boolean condition) {
        if (!condition) {
            throw new IllegalArgumentException("state should be: " + name);
        }
    }

    public static void isTrue(final String name, final boolean condition) {
        if (!condition) {
            throw new IllegalStateException("state should be: " + name);
        }
    }
}

// Usage throughout the driver — consistent, concise, DRY
public class MongoNamespace {
    public static void checkDatabaseNameValidity(final String databaseName) {
        notNull("databaseName", databaseName);
        isTrueArgument("databaseName is not empty", !databaseName.isEmpty());
    }
}

public class ClusterSettings {
    public Builder applySettings(final ClusterSettings clusterSettings) {
        notNull("clusterSettings", clusterSettings);
        // ...
    }
}
```

### DRY in the BsonValue Hierarchy

`BsonValue` uses `throwIfInvalidType()` to avoid repeating type-check logic across 15+
conversion methods:

```java
// ✅ GOOD: One method handles the pattern, called everywhere
public abstract class BsonValue {

    public BsonString asString() {
        throwIfInvalidType(BsonType.STRING);
        return (BsonString) this;
    }

    public BsonInt32 asInt32() {
        throwIfInvalidType(BsonType.INT32);
        return (BsonInt32) this;
    }

    public BsonDocument asDocument() {
        throwIfInvalidType(BsonType.DOCUMENT);
        return (BsonDocument) this;
    }

    // Private helper — single place for the throw logic
    private void throwIfInvalidType(BsonType expectedType) {
        if (getBsonType() != expectedType) {
            throw new BsonInvalidOperationException(...);
        }
    }
}
```

### DRY Exceptions

Not all duplication is bad.
Avoid premature abstraction:

```java
// These look similar but serve different purposes — OK to duplicate
public long getMaxConnectionLifeTime(TimeUnit timeUnit) {
    return timeUnit.convert(maxConnectionLifeTimeMS, MILLISECONDS);
}

public long getMaxConnectionIdleTime(TimeUnit timeUnit) {
    return timeUnit.convert(maxConnectionIdleTimeMS, MILLISECONDS);
}
// Don't force these into one method — they represent different concepts
```

* * *

## KISS - Keep It Simple

> “The simplest solution is usually the best.”

### Good Example: The Filters DSL

The driver provides a fluent, readable API that reads like English:

```java
// ✅ GOOD: Simple, readable query construction
import static com.mongodb.client.model.Filters.*;

// Reads naturally: "find where status equals active and age > 25"
collection.find(and(eq("status", "active"), gt("age", 25)));

// Instead of building BsonDocuments manually:
// ❌ BAD: Verbose, error-prone
collection.find(new BsonDocument("$and",
    new BsonArray(Arrays.asList(
        new BsonDocument("status", new BsonString("active")),
        new BsonDocument("age", new BsonDocument("$gt", new BsonInt32(25)))
    ))
));
```

The `Filters` class is a factory of static methods with clear names:

```java
public final class Filters {
    public static <TItem> Bson eq(String fieldName, TItem value) { ... }
    public static <TItem> Bson ne(String fieldName, TItem value) { ... }
    public static <TItem> Bson gt(String fieldName, TItem value) { ... }
    public static <TItem> Bson lt(String fieldName, TItem value) { ... }
    public static Bson and(Bson... filters) { ... }
    public static Bson or(Bson... filters) { ... }
    public static Bson not(Bson filter) { ... }
    // Each method name is the MongoDB operator — no learning curve
}
```

### KISS Checklist

- Can a junior developer understand this in 30 seconds?
- Is there a simpler way using standard libraries?
- Am I adding complexity for edge cases that may never happen?

* * *

## YAGNI - You Aren’t Gonna Need It

> “Don’t add functionality until it’s necessary.”

### Good Example: The WriteModel Hierarchy

The driver only defines the write models MongoDB actually supports — no speculative
extras:

```java
// ✅ GOOD: Only what's needed, nothing more
public abstract class WriteModel<T> { }

public final class InsertOneModel<T> extends WriteModel<T> { ... }
public class DeleteOneModel<T> extends WriteModel<T> { ... }
public final class DeleteManyModel<T> extends WriteModel<T> { ... }
public final class UpdateOneModel<T> extends WriteModel<T> { ... }
public final class UpdateManyModel<T> extends WriteModel<T> { ... }
public final class ReplaceOneModel<T> extends WriteModel<T> { ... }

// No "UpsertModel", "MergeModel", "ConditionalWriteModel"
// If MongoDB adds a new operation, a new model is added then — not before
```

### YAGNI Signs

- “We might need this later”
- “Let’s make it configurable just in case”
- “What if we need to support X in the future?”
- Abstract classes with one implementation

* * *

## Naming Conventions

### Good Naming in the Driver

The driver uses clear, domain-specific names throughout:

```java
// ✅ Classes — noun, specific responsibility
MongoNamespace          // not "Namespace" or "NameInfo"
ConnectionPoolSettings  // not "PoolConfig" or "PoolData"
ReadPreference          // not "ReadPref" or "RP"
ServerSelector          // not "Selector" or "ServerChooser"
WriteConcern            // not "WriteConfig" or "WC"

// ✅ Methods — verb + noun, descriptive
ReadPreference.primary()              // factory method, reads like English
ReadPreference.secondaryPreferred()   // not "getSecPref()"
Filters.eq("status", "active")        // not "equals()" or "isEqual()"
Updates.set("name", "Alice")          // not "update()" or "modify()"
collection.find(filter)               // not "query()" or "get()"
collection.insertOne(document)        // not "add()" or "put()"
collection.bulkWrite(operations)      // not "batch()" or "multi()"

// ✅ Booleans — is/has/can prefix
BsonValue.isNull()
BsonValue.isDocument()
BsonValue.isNumber()
ReadPreference.isSecondaryOk()
Cluster.isClosed()

// ✅ Constants — UPPER_SNAKE, domain-meaningful
WriteConcern.ACKNOWLEDGED
WriteConcern.MAJORITY
WriteConcern.UNACKNOWLEDGED
WriteConcern.W1
```

### Naming Anti-Patterns

```java
// ❌ BAD
int d;                  // What is d?
String s;               // Meaningless
List<Document> list;    // What kind of list?
Map<String, Object> m;  // What does it map?

// ✅ GOOD
int elapsedTimeInDays;
String collectionName;
List<Document> matchingDocuments;
Map<String, Object> sessionAttributes;
```

### Naming Conventions Table

| Element | Convention | Driver Example |
| --- | --- | --- |
| Class | PascalCase, noun | `MongoClientSettings` |
| Interface | PascalCase, noun/adjective | `Codec`, `Closeable` |
| Method | camelCase, verb | `selectServer()` |
| Variable | camelCase, noun | `serverSelectionTimeoutMS` |
| Constant | UPPER_SNAKE | `COMMAND_COLLECTION_NAME` |
| Package | lowercase, dot-separated | `com.mongodb.client.model` |

* * *

## Functions / Methods

### Keep Functions Small

The driver’s `MongoNamespace` validation is a good example — each check is focused:

```java
// ✅ GOOD: Focused validation methods
public static void checkDatabaseNameValidity(final String databaseName) {
    notNull("databaseName", databaseName);
    isTrueArgument("databaseName is not empty", !databaseName.isEmpty());
    for (int i = 0; i < databaseName.length(); i++) {
        if (PROHIBITED_CHARACTERS_IN_DATABASE_NAME.contains(databaseName.charAt(i))) {
            throw new IllegalArgumentException("...");
        }
    }
}

public static void checkCollectionNameValidity(final String collectionName) {
    notNull("collectionName", collectionName);
    isTrueArgument("collectionName is not empty", !collectionName.isEmpty());
}
```

### Limit Parameters — Use the Builder Pattern

The driver uses builders extensively to avoid long parameter lists:

```java
// ❌ BAD: Too many parameters
MongoClient createClient(String host, int port, int maxPoolSize,
    long connectTimeout, long socketTimeout, boolean useSsl,
    String replicaSet, String authMechanism, ...) { }

// ✅ GOOD: Builder pattern — used throughout the driver
MongoClientSettings settings = MongoClientSettings.builder()
    .applyConnectionString(new ConnectionString("mongodb://localhost"))
    .applyToConnectionPoolSettings(builder ->
        builder.maxSize(100)
               .maxWaitTime(2, TimeUnit.MINUTES))
    .applyToClusterSettings(builder ->
        builder.serverSelectionTimeout(30, TimeUnit.SECONDS))
    .applyToSslSettings(builder ->
        builder.enabled(true))
    .build();

MongoClient client = MongoClients.create(settings);
```

The pattern: immutable settings class + mutable builder + `build()`:

```java
@Immutable
public final class ClusterSettings {
    private final List<ServerAddress> hosts;
    private final ClusterConnectionMode mode;
    private final long serverSelectionTimeoutMS;
    // ... all fields final

    public static Builder builder() { return new Builder(); }

    @NotThreadSafe
    public static final class Builder {
        private long serverSelectionTimeoutMS = MILLISECONDS.convert(30, TimeUnit.SECONDS);

        public Builder hosts(List<ServerAddress> hosts) {
            this.hosts = notNull("hosts", hosts);
            return this;
        }

        public Builder serverSelectionTimeout(long timeout, TimeUnit timeUnit) {
            this.serverSelectionTimeoutMS = MILLISECONDS.convert(timeout, timeUnit);
            return this;
        }

        public ClusterSettings build() {
            return new ClusterSettings(this);
        }
    }
}
```

### Single Level of Abstraction

```java
// ❌ BAD: Mixed abstraction levels
public void processQuery(MongoCollection<Document> collection, Bson filter) {
    validateFilter(filter);  // High level

    // Low level mixed in
    BsonDocument bsonFilter = filter.toBsonDocument(
        Document.class, collection.getCodecRegistry());
    if (bsonFilter.containsKey("$and")) {
        BsonArray andClauses = bsonFilter.getArray("$and");
        for (BsonValue clause : andClauses) {
            // ...
        }
    }

    sendResults(collection.find(filter));  // High level again
}

// ✅ GOOD: Consistent abstraction level
public void processQuery(MongoCollection<Document> collection, Bson filter) {
    validateFilter(filter);
    FindIterable<Document> results = executeQuery(collection, filter);
    sendResults(results);
}
```

* * *

## Comments

### Avoid Obvious Comments

```java
// ❌ BAD: Noise comments
// Set the read preference
settings.readPreference(ReadPreference.secondary());

// Create a new MongoClient
MongoClient client = MongoClients.create(settings);

// Check if document is null
if (document != null) { ... }
```

### Good Comments — Explain WHY, Not WHAT

The driver uses comments where behavior isn’t obvious:

```java
// ✅ GOOD from WriteConcern: Explains the domain constraint
// map of the constants from above for use by fromString
private static final Map<String, WriteConcern> NAMED_CONCERNS;

// ✅ GOOD from Assertions: Explains design rationale
/**
 * Design by contract assertions.
 * The reason for not using the Java assert statements is that they are
 * not always enabled. We prefer having internal checks always done at
 * the cost of our code doing a relatively small amount of additional
 * work in production.
 */

// ✅ GOOD from MongoNamespace: Caching explanation
@BsonIgnore
private final String fullName;  // cache to avoid repeated string building
```

### Let Code Speak

```java
// ❌ BAD: Comment explaining bad code
// Check if the server is primary or secondary and can accept reads
if ((serverType == 1 || serverType == 2) && (readPref == 0 || readPref == 3)) { ... }

// ✅ GOOD: Self-documenting — how the driver actually does it
if (readPreference.isSecondaryOk() && serverDescription.isOk()) { ... }
```

* * *

## Value Objects Over Primitives

### Good Example: MongoNamespace

Instead of passing `databaseName` and `collectionName` as raw strings:

```java
// ❌ BAD: Primitive obsession — easy to mix up parameters
void executeQuery(String database, String collection, Bson filter) { ... }
executeQuery("myCollection", "myDatabase", filter);  // Wrong order, compiles!

// ✅ GOOD: The driver uses MongoNamespace as a value object
@Immutable
public final class MongoNamespace {
    private final String databaseName;
    private final String collectionName;

    public MongoNamespace(String databaseName, String collectionName) {
        checkDatabaseNameValidity(databaseName);      // Self-validating
        checkCollectionNameValidity(collectionName);   // Self-validating
        this.databaseName = databaseName;
        this.collectionName = collectionName;
        this.fullName = databaseName + '.' + collectionName;
    }
}

// Type-safe — can't mix up database and collection
void executeQuery(MongoNamespace namespace, Bson filter) { ... }
```

### More Value Objects in the Driver

| Instead of … | The driver uses … |
| --- | --- |
| `String host, int port` | `ServerAddress` |
| `String database, String collection` | `MongoNamespace` |
| `int w, int timeout, boolean journal` | `WriteConcern` |
| `String tagKey, String tagValue` | `Tag`, `TagSet` |
| `String clusterId` | `ClusterId` |

* * *

## Named Constants Over Magic Numbers

### Good Example: WriteConcern Constants

```java
// ❌ BAD: Magic values
new WriteConcern(1);        // What does 1 mean?
new WriteConcern(0);        // Unacknowledged? Or zero replicas?
new WriteConcern("majority"); // String literal scattered across code

// ✅ GOOD: Named constants with clear semantics
WriteConcern.ACKNOWLEDGED       // Wait for primary acknowledgement
WriteConcern.UNACKNOWLEDGED     // Don't wait (fire and forget)
WriteConcern.MAJORITY           // Wait for majority of data-bearing nodes
WriteConcern.W1                 // Wait for exactly one node
WriteConcern.W2                 // Wait for two nodes
WriteConcern.W3                 // Wait for three nodes
WriteConcern.JOURNALED          // Wait for journal commit
```

### Named Constants in Settings

```java
// ✅ GOOD: Defaults are named and documented in builders
public static final class Builder {
    private int maxSize = 100;                                         // Not a mystery "100"
    private long maxWaitTimeMS = 1000 * 60 * 2;                       // 2 minutes
    private long maintenanceFrequencyMS = MILLISECONDS.convert(1, MINUTES);
    private long serverSelectionTimeoutMS = MILLISECONDS.convert(30, TimeUnit.SECONDS);
    private int maxConnecting = 2;
}
```

* * *

## Common Code Smells

| Smell | Description | Driver Example of Doing It Right |
| --- | --- | --- |
| **Long Parameter List** | > 3 parameters | Builder pattern (`MongoClientSettings.builder()`) |
| **Duplicate Code** | Same code in multiple places | `Assertions.notNull()` used everywhere |
| **Magic Numbers** | Unexplained literals | `WriteConcern.MAJORITY` named constants |
| **Primitive Obsession** | Primitives instead of objects | `MongoNamespace`, `ServerAddress`, `TagSet` |
| **Dead Code** | Unused code | Clean up with `@Deprecated` → remove cycle |
| **God Class** | Class doing too much | Separate `Encoder`/`Decoder`/`Codec` |
| **Feature Envy** | Method uses another class’s data | Move method to the data class |

* * *

## Refactoring Quick Reference

| From | To | Technique | Driver Example |
| --- | --- | --- | --- |
| Long parameter list | Builder | Introduce Builder | `ClusterSettings.builder()` |
| Duplicate validation | Shared utility | Extract Method | `Assertions.notNull()` |
| Magic numbers | Named constants | Extract Constant | `WriteConcern.MAJORITY` |
| Raw strings | Value object | Introduce Value Object | `MongoNamespace` |
| Complex construction | Fluent API | Static Factory Methods | `Filters.eq()`, `Updates.set()` |
| Nested conditionals | Early return | Guard Clauses | `notNull()` at method entry |

### Guard Clauses in the Driver

```java
// ✅ GOOD: The driver validates inputs at method entry, then proceeds
public static void checkDatabaseNameValidity(final String databaseName) {
    notNull("databaseName", databaseName);                           // Guard
    isTrueArgument("databaseName is not empty", !databaseName.isEmpty()); // Guard
    // Actual logic follows — no deep nesting
    for (int i = 0; i < databaseName.length(); i++) {
        if (PROHIBITED_CHARACTERS_IN_DATABASE_NAME.contains(databaseName.charAt(i))) {
            throw new IllegalArgumentException("...");
        }
    }
}

// ✅ The notNull() method itself returns the value — enabling fluent guard clauses
public Builder applySettings(final ClusterSettings clusterSettings) {
    notNull("clusterSettings", clusterSettings);  // Fail fast, then proceed
    this.hosts = clusterSettings.hosts;
    this.mode = clusterSettings.mode;
    return this;
}
```

* * *

## Clean Code Checklist

When reviewing code, check:

- [ ] Are names meaningful and pronounceable?
- [ ] Are functions small and focused?
- [ ] Is there any duplicated code?
- [ ] Are there magic numbers or strings?
- [ ] Are comments explaining “why” not “what”?
- [ ] Is the code at consistent abstraction level?
- [ ] Can any code be simplified?
- [ ] Is there dead/unused code?
- [ ] Are primitives wrapped in value objects where appropriate?
- [ ] Are long parameter lists replaced with builders?

* * *

## Related References

- [SOLID Principles](solid-principles.md) - Design principles for class structure
- [Architecture Review Guide](architecture.md) - Package structure and module boundaries
- [Test Quality Guide](test-quality.md) - Test readability and maintainability
