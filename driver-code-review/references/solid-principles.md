# SOLID Principles Reference

Review and apply SOLID principles using examples from the MongoDB Java Driver.

## When to Use

- User says “check SOLID” / “SOLID review” / “is this class doing too much?”
- Reviewing class design
- Refactoring large classes
- Code review focusing on design

* * *

## Quick Reference

| Letter | Principle | One-liner |
| --- | --- | --- |
| **S** | Single Responsibility | One class = one reason to change |
| **O** | Open/Closed | Open for extension, closed for modification |
| **L** | Liskov Substitution | Subtypes must be substitutable for base types |
| **I** | Interface Segregation | Many specific interfaces > one general interface |
| **D** | Dependency Inversion | Depend on abstractions, not concretions |

* * *

## S - Single Responsibility Principle (SRP)

> “A class should have only one reason to change.”

### Violation

```java
// ❌ BAD: MongoService does too much
public class MongoService {

    public Document findDocument(String collectionName, Bson filter) {
        // connection management
        MongoClient client = MongoClients.create("mongodb://localhost");
        MongoDatabase database = client.getDatabase("mydb");

        // query logic
        MongoCollection<Document> collection = database.getCollection(collectionName);
        Document result = collection.find(filter).first();

        // encoding logic
        BsonDocument bsonDoc = result.toBsonDocument();
        String json = bsonDoc.toJson();
        logger.info("Found: " + json);

        // audit logic
        auditLog.log("Query executed on " + collectionName);

        return result;
    }
}
```

**Problems:**
- Connection management changes?
  Modify MongoService
- Encoding format changes?
  Modify MongoService
- Audit requirements change?
  Modify MongoService
- Hard to test each concern separately

### Good Example: The MongoDB Java Driver’s Codec Architecture

The driver separates encoding, decoding, and codec discovery into distinct
responsibilities:

```java
// ✅ GOOD: Each interface has one responsibility

// Encoder.java - only responsible for encoding
public interface Encoder<T> {
    void encode(BsonWriter writer, T value, EncoderContext encoderContext);
    Class<T> getEncoderClass();
}

// Decoder.java - only responsible for decoding
public interface Decoder<T> {
    T decode(BsonReader reader, DecoderContext decoderContext);
}

// Codec.java - composes both via interface inheritance
public interface Codec<T> extends Encoder<T>, Decoder<T> {
}

// CodecProvider.java - only responsible for locating codecs
public interface CodecProvider {
    <T> Codec<T> get(Class<T> clazz, CodecRegistry registry);
}

// CodecRegistry.java - only responsible for managing codec lookup
public interface CodecRegistry extends CodecProvider {
    <T> Codec<T> get(Class<T> clazz);
}
```

Each class has exactly one reason to change:
- `Encoder` changes only when the encoding contract changes
- `Decoder` changes only when the decoding contract changes
- `CodecProvider` changes only when the discovery mechanism changes

### How to Detect SRP Violations

- Class has many `import` statements from different domains
- Class name contains “And” or “Manager” or “Handler” (often)
- Methods operate on unrelated data
- Changes in one area require touching unrelated methods
- Hard to name the class concisely

### Quick Check Questions

1. Can you describe the class purpose in one sentence without “and”?
2. Would different stakeholders request changes to this class?
3. Are there methods that don’t use most of the class fields?

* * *

## O - Open/Closed Principle (OCP)

> “Software entities should be open for extension, but closed for modification.”

### Violation

```java
// ❌ BAD: Must modify class to add new server selection strategy
public class ServerChooser {

    public ServerDescription choose(ClusterDescription cluster, String strategy) {
        if (strategy.equals("PRIMARY")) {
            return getPrimaries(cluster).get(0);
        } else if (strategy.equals("SECONDARY")) {
            return getSecondaries(cluster).get(0);
        } else if (strategy.equals("NEAREST")) {
            return getNearest(cluster);
        }
        // Every new selection strategy = modify this class
        throw new IllegalArgumentException("Unknown strategy: " + strategy);
    }
}
```

### Good Example: The ServerSelector Strategy Pattern

The driver defines a `ServerSelector` interface, and each selection strategy is a
separate implementation:

```java
// ✅ GOOD: ServerSelector interface - closed for modification
public interface ServerSelector {
    List<ServerDescription> select(ClusterDescription clusterDescription);
}

// Each strategy is a separate class - open for extension

public final class WritableServerSelector implements ServerSelector {
    @Override
    public List<ServerDescription> select(final ClusterDescription clusterDescription) {
        if (clusterDescription.getConnectionMode() == ClusterConnectionMode.SINGLE
                || clusterDescription.getConnectionMode() == ClusterConnectionMode.LOAD_BALANCED) {
            return getAny(clusterDescription);
        }
        return getPrimaries(clusterDescription);
    }
}

public class ReadPreferenceServerSelector implements ServerSelector {
    private final ReadPreference readPreference;

    public ReadPreferenceServerSelector(final ReadPreference readPreference) {
        this.readPreference = notNull("readPreference", readPreference);
    }

    @Override
    public List<ServerDescription> select(final ClusterDescription clusterDescription) {
        if (clusterDescription.getConnectionMode() == ClusterConnectionMode.SINGLE) {
            return getAny(clusterDescription);
        }
        return readPreference.choose(clusterDescription);
    }
}

public class LatencyMinimizingServerSelector implements ServerSelector {
    private final long acceptableLatencyDifferenceNanos;

    @Override
    public List<ServerDescription> select(final ClusterDescription clusterDescription) {
        if (clusterDescription.getConnectionMode() != MULTIPLE) {
            return getAny(clusterDescription);
        }
        return getServersWithAcceptableLatencyDifference(
            getAny(clusterDescription),
            getFastestRoundTripTimeNanos(clusterDescription.getServerDescriptions()));
    }
}
```

New selection strategy?
Just add a new class implementing `ServerSelector` — no existing code modified.

### How to Detect OCP Violations

- `if/else` or `switch` on type/status that grows over time
- Enum-based dispatching with frequent new values
- Changes require modifying core classes

### Common OCP Patterns

| Pattern | Use When |
| --- | --- |
| Strategy | Multiple algorithms for same operation |
| Template Method | Same structure, different steps |
| Decorator | Add behavior dynamically |
| Factory | Create objects without specifying class |

* * *

## L - Liskov Substitution Principle (LSP)

> “Subtypes must be substitutable for their base types.”

### Violation: PrimaryReadPreference breaks the contract

```java
// ❌ ISSUE: ReadPreference defines withTagSet/withMaxStalenessMS,
// but PrimaryReadPreference throws on all of them

public abstract class ReadPreference {
    public abstract ReadPreference withTagSet(TagSet tagSet);
    public abstract ReadPreference withMaxStalenessMS(Long maxStalenessMS, TimeUnit timeUnit);
    public abstract ReadPreference withTagSetList(List<TagSet> tagSet);
}

// PrimaryReadPreference violates expectations
private static final class PrimaryReadPreference extends ReadPreference {
    @Override
    public ReadPreference withTagSet(final TagSet tagSet) {
        throw new UnsupportedOperationException(
            "Primary read preference can not also specify tag sets");
    }

    @Override
    public TaggableReadPreference withMaxStalenessMS(final Long maxStalenessMS, final TimeUnit timeUnit) {
        throw new UnsupportedOperationException(
            "Primary read preference can not also specify max staleness");
    }
}

// This code compiles but fails at runtime for primary!
void configureReadPreference(ReadPreference pref) {
    pref.withTagSet(new TagSet(new Tag("dc", "east")));  // 💥 throws for primary
}
```

### Good Example: The WriteModel Hierarchy

The `WriteModel` hierarchy is properly substitutable — each subtype models a specific
bulk write operation without violating the base contract:

```java
// ✅ GOOD: WriteModel subtypes are fully substitutable

public abstract class WriteModel<T> {
    // Base class defines no operations that subtypes might not support
}

public final class InsertOneModel<T> extends WriteModel<T> {
    private final T document;

    public InsertOneModel(final T document) {
        this.document = notNull("document", document);
    }

    public T getDocument() { return document; }
}

public class DeleteOneModel<T> extends WriteModel<T> {
    private final Bson filter;
    private final DeleteOptions options;

    public DeleteOneModel(final Bson filter, final DeleteOptions options) {
        this.filter = notNull("filter", filter);
        this.options = notNull("options", options);
    }

    public Bson getFilter() { return filter; }
    public DeleteOptions getOptions() { return options; }
}

// Also: UpdateOneModel, UpdateManyModel, DeleteManyModel, ReplaceOneModel

// All subtypes are safely substitutable in bulk operations
collection.bulkWrite(List.of(
    new InsertOneModel<>(new Document("x", 1)),
    new DeleteOneModel<>(eq("x", 2)),
    new UpdateOneModel<>(eq("x", 3), set("y", 4))
));
```

### LSP Rules

| Rule | Meaning |
| --- | --- |
| Preconditions | Subclass cannot strengthen (require more) |
| Postconditions | Subclass cannot weaken (promise less) |
| Invariants | Subclass must maintain parent’s invariants |
| History | Subclass cannot modify inherited state unexpectedly |

### How to Detect LSP Violations

- Subclass throws exception parent doesn’t
- Subclass returns null where parent returns object
- Subclass ignores or overrides parent behavior unexpectedly
- `instanceof` checks before calling methods
- Empty or throwing implementations of interface methods

### Quick Check

```java
// If you see this, LSP might be violated
if (readPreference instanceof PrimaryReadPreference) {
    // don't call withTagSet()
} else {
    readPreference.withTagSet(tagSet);
}
```

* * *

## I - Interface Segregation Principle (ISP)

> “Clients should not be forced to depend on interfaces they do not use.”

### Violation

```java
// ❌ BAD: Fat interface forces unnecessary implementations
public interface MongoDataAccess<T> {
    T findById(Object id);
    List<T> findAll();
    T save(T entity);
    void delete(T entity);
    void createIndex(Bson keys);
    void dropCollection();
    void watch(ChangeStreamListener listener);
    AggregateIterable<T> aggregate(List<Bson> pipeline);
    long estimatedCount();
    void rename(String newName);
}

// A read-only reporting service can't do any of this!
public class ReportingService implements MongoDataAccess<Document> {
    @Override public Document save(Document entity) {
        throw new UnsupportedOperationException();  // Not allowed!
    }
    @Override public void delete(Document entity) {
        throw new UnsupportedOperationException();  // Not allowed!
    }
    @Override public void dropCollection() {
        throw new UnsupportedOperationException();  // Definitely not!
    }
    // ... forced to implement methods it should never use
}
```

### Good Example: Encoder / Decoder / Codec Segregation

The driver’s BSON codec system cleanly segregates read and write concerns:

```java
// ✅ GOOD: Segregated interfaces

// Only encoding - for components that write BSON
public interface Encoder<T> {
    void encode(BsonWriter writer, T value, EncoderContext encoderContext);
    Class<T> getEncoderClass();
}

// Only decoding - for components that read BSON
public interface Decoder<T> {
    T decode(BsonReader reader, DecoderContext decoderContext);
}

// Full codec - only for components that need both
public interface Codec<T> extends Encoder<T>, Decoder<T> {
}
```

This allows:
- **Write-only components** to depend only on `Encoder<T>`
- **Read-only components** to depend only on `Decoder<T>`
- **Full CRUD components** to depend on `Codec<T>`

No client is forced to implement capabilities it doesn’t use.

### How to Detect ISP Violations

- Implementations with empty methods or `throw new UnsupportedOperationException()`
- Interface has 10+ methods
- Different clients use completely different subsets of methods
- Changes to interface affect unrelated implementations

### Better Design: Split by Use Case

```java
// ✅ Split like the driver does with CodecProvider and CodecRegistry

// Simple lookup - for most consumers
public interface CodecProvider {
    <T> Codec<T> get(Class<T> clazz, CodecRegistry registry);
}

// Extended lookup with guaranteed result - for the registry itself
public interface CodecRegistry extends CodecProvider {
    <T> Codec<T> get(Class<T> clazz);
}
```

* * *

## D - Dependency Inversion Principle (DIP)

> “High-level modules should not depend on low-level modules.
> Both should depend on abstractions.”

### Violation

```java
// ❌ BAD: High-level code depends on concrete transport directly
public class MongoConnectionManager {
    private SocketStreamFactory streamFactory;  // Concrete class!

    public MongoConnectionManager() {
        this.streamFactory = new SocketStreamFactory(
            SocketSettings.builder().build(),
            SslSettings.builder().build());  // Hard dependency
    }

    public Stream connect(ServerAddress address) {
        return streamFactory.create(address);
    }
}
```

**Problems:**
- Cannot swap to Netty or TLS Channel transport
- Cannot test without real socket connections
- ConnectionManager knows about socket implementation details

### Good Example: StreamFactory Abstraction

The driver defines a `StreamFactory` interface, and the high-level connection code
depends on it:

```java
// ✅ GOOD: Depend on abstractions

// Abstraction - the contract for creating streams
public interface StreamFactory {
    Stream create(ServerAddress serverAddress);
}

// Low-level modules implement the abstraction

public class SocketStreamFactory implements StreamFactory {
    @Override
    public Stream create(ServerAddress serverAddress) {
        // Plain socket implementation
    }
}

public class NettyStreamFactory implements StreamFactory {
    @Override
    public Stream create(ServerAddress serverAddress) {
        // Netty-based implementation
    }
}

public class AsynchronousSocketChannelStreamFactory implements StreamFactory {
    @Override
    public Stream create(ServerAddress serverAddress) {
        // NIO async socket implementation
    }
}
```

Similarly, the CodecProvider/CodecRegistry pattern follows DIP — high-level code depends
on the `CodecRegistry` abstraction, while concrete providers supply the implementations:

```java
// High-level code depends on CodecRegistry abstraction
CodecRegistry registry = CodecRegistries.fromProviders(
    new BsonValueCodecProvider(),     // BSON types
    new ValueCodecProvider(),         // Java primitives
    new DocumentCodecProvider(),      // Document type
    new CollectionCodecProvider(),    // Collection types
    new MapCodecProvider(),           // Map types
    new Jsr310CodecProvider(),        // Java Time types
    new PojoCodecProvider()           // POJO mapping
);

// Adding a new type? Just add a new CodecProvider — no modification needed
```

### DIP in Practice

| Bad (Concrete) | Good (Abstract) |
| --- | --- |
| `new SocketStreamFactory()` | `StreamFactory` injected via constructor |
| `new BsonDocumentCodec()` | `CodecRegistry.get(BsonDocument.class)` |
| `new PrimaryServerSelector()` | `ServerSelector` injected via configuration |

* * *

## SOLID Review Checklist

When reviewing code, check:

| Principle | Question |
| --- | --- |
| **SRP** | Does this class have more than one reason to change? |
| **OCP** | Will adding a new type/feature require modifying this class? |
| **LSP** | Can subclasses be used wherever parent is expected? |
| **ISP** | Are there empty or throwing method implementations? |
| **DIP** | Does high-level code depend on concrete implementations? |

* * *

## Common Refactoring Patterns

| Violation | Refactoring | Driver Example |
| --- | --- | --- |
| SRP - God class | Extract Class, Move Method | `Encoder` / `Decoder` / `Codec` separation |
| OCP - Type switching | Strategy Pattern, Factory | `ServerSelector` implementations |
| LSP - Broken inheritance | Composition over Inheritance, Extract Interface | `WriteModel` hierarchy |
| ISP - Fat interface | Split Interface, Role Interface | `Encoder` / `Decoder` split |
| DIP - Hard dependencies | Dependency Injection, Abstract Factory | `StreamFactory` / `CodecProvider` |

* * *

## Related References

- [Architecture Review Guide](architecture.md) - Architectural patterns and structural
  review criteria
- [Clean Code Principles](clean-code.md) - Code-level principles (DRY, KISS, naming)
- [Test Quality Guide](test-quality.md) - Test coverage and quality practices
