# Architecture Review

Analyze project structure at the macro level — packages, modules, layers, and
boundaries. Examples drawn from the MongoDB Java Driver.

* * *

## Quick Reference: Architecture Smells

| Smell | Symptom | Impact |
| --- | --- | --- |
| Package-by-layer bloat | `service/` with 50+ classes | Hard to find related code |
| Domain → Infra dependency | Entity imports `@Repository` | Core logic tied to framework |
| Circular dependencies | A → B → C → A | Untestable, fragile |
| God package | `util/` or `common/` growing | Dump for misplaced code |
| Leaky abstractions | Controller knows SQL | Layer boundaries violated |
| Missing API boundary | All classes public | Internal changes break consumers |

* * *

## Module Organization Strategies

### Strategy 1: Module-per-Concern (Used by the MongoDB Java Driver)

The driver organizes code into Gradle modules by concern, each with a clear
responsibility:

```
mongo-java-driver/
├── bson/                          # BSON types, codecs, serialization (zero driver deps)
│   └── org.bson/
│       ├── BsonValue, BsonDocument, ...   # Type system
│       ├── codecs/                        # Encoder/Decoder/Codec/CodecProvider
│       ├── codecs/configuration/          # CodecRegistry wiring
│       ├── codecs/pojo/                   # POJO mapping
│       ├── io/                            # Binary I/O
│       └── json/                          # JSON parsing
├── driver-core/                   # Shared infrastructure (no sync/async opinion)
│   └── com.mongodb/
│       ├── client/model/          # Public API models (Filters, Updates, WriteModel)
│       ├── connection/            # Public connection types
│       ├── event/                 # Listener interfaces & events
│       ├── selector/              # ServerSelector (public SPI)
│       └── internal/              # Internal implementation (not public API)
│           ├── connection/        # Cluster, Server, Stream, Pool
│           ├── operation/         # ReadOperation, WriteOperation impls
│           ├── binding/           # Read/WriteBinding abstractions
│           ├── authentication/    # Auth mechanisms
│           └── selector/          # ServerSelector implementations
├── driver-sync/                   # Synchronous API (depends on driver-core)
│   └── com.mongodb.client/
│       ├── MongoClient, MongoDatabase, MongoCollection  # Public interfaces
│       └── internal/              # Sync-specific implementation
├── driver-reactive-streams/       # Reactive Streams API (depends on driver-core)
├── driver-kotlin-coroutine/       # Kotlin Coroutine API
├── driver-kotlin-sync/            # Kotlin Sync API
├── driver-scala/                  # Scala API
└── driver-legacy/                 # Legacy API (deprecated)
```

**Key strengths:**
- `bson` has zero driver dependencies — usable standalone
- `driver-core` contains all shared logic; sync/async/reactive modules are thin wrappers
- Each language variant (Kotlin, Scala) is a separate module
- Adding a new API style (e.g., virtual-thread-native) means adding a module, not
  modifying core

### Strategy 2: Package-by-Layer (Traditional)

```
com.example.app/
├── controller/
│   ├── UserController.java
│   └── OrderController.java
├── service/
│   ├── UserService.java
│   └── OrderService.java
├── repository/
│   └── UserRepository.java
└── model/
    └── User.java
```

**Pros**: Familiar, simple for small projects **Cons**: Scatters related code, doesn’t
scale, hard to extract modules

### Strategy 3: Package-by-Feature (Recommended for Applications)

```
com.example.app/
├── user/
│   ├── UserController.java
│   ├── UserService.java
│   ├── UserRepository.java
│   └── User.java
├── order/
│   ├── OrderController.java
│   ├── OrderService.java
│   └── Order.java
└── shared/
    └── BaseEntity.java
```

**Pros**: Related code together, easy to extract, clear boundaries **Cons**: May need
shared kernel for cross-cutting concerns

* * *

## Dependency Direction Rules

### The Golden Rule

```
┌─────────────────────────────────────────┐
│          API Wrappers (sync/async)      │  ← Outer (volatile)
├─────────────────────────────────────────┤
│          Operations & Bindings          │
├─────────────────────────────────────────┤
│       Connection & Infrastructure       │
├─────────────────────────────────────────┤
│        Core Models & Abstractions       │  ← Inner (stable)
└─────────────────────────────────────────┘

Dependencies MUST point inward only.
Inner layers MUST NOT know about outer layers.
```

### Good Example: The Driver’s Layering

```
driver-sync  ──depends-on──►  driver-core  ──depends-on──►  bson
driver-reactive-streams ───►  driver-core  ──depends-on──►  bson
driver-kotlin-coroutine ───►  driver-core  ──depends-on──►  bson
```

- `bson` knows nothing about `driver-core` or any driver module
- `driver-core` knows nothing about `driver-sync` or `driver-reactive-streams`
- Sync and reactive modules are independent — no dependency between them

### Violations to Flag

```java
// ❌ Core module depends on API wrapper
package com.mongodb.internal.operation;

import com.mongodb.client.MongoCollection;  // Wrong direction!
// Operations should not know about the sync client API

// ❌ BSON module depends on driver-core
package org.bson.codecs;

import com.mongodb.ReadPreference;  // Wrong direction!
// BSON is a standalone module — it must not import driver types

// ✅ Correct: API wrapper depends on core
package com.mongodb.client.internal;

import com.mongodb.internal.operation.FindOperation;   // OK: outer depends on inner
import com.mongodb.internal.binding.ReadBinding;        // OK: outer depends on inner
```

* * *

## Public API vs Internal Boundary

### The MongoDB Java Driver Pattern

The driver enforces a clear **public vs internal** boundary using package structure and
annotations:

```java
// PUBLIC API — stable, versioned, subject to deprecation policy
com.mongodb.client.MongoCollection        // Interface users interact with
com.mongodb.client.model.Filters          // Query builder DSL
com.mongodb.client.model.Updates          // Update builder DSL
com.mongodb.ReadPreference                // Configuration
com.mongodb.event.CommandListener         // Extension point

// INTERNAL — can change at any time, not for consumer use
com.mongodb.internal.connection.Cluster               // Implementation detail
com.mongodb.internal.operation.FindOperation           // Wire protocol logic
com.mongodb.internal.binding.ReadBinding               // Internal abstraction
com.mongodb.internal.selector.LatencyMinimizingServerSelector  // Internal strategy
```

The `internal` package acts as a clear marker:

```java
/**
 * Signifies that a public API element is intended for internal use only.
 * It is inadvisable for applications to use Internal APIs as they are
 * intended for internal library purposes only.
 */
@Documented
@Alpha(Reason.CLIENT)
public @interface Internal {
}
```

**Why this matters for review:**
- Public API changes require deprecation cycles and semver consideration
- Internal changes can be refactored freely
- A class in `internal` being used by a consumer is a red flag

### Stability Annotations

The driver uses annotations to communicate API stability:

| Annotation | Meaning | Review Action |
| --- | --- | --- |
| `@Immutable` | Thread-safe, state never changes | Verify no mutable fields leak |
| `@ThreadSafe` | Safe for concurrent use | Verify synchronization is correct |
| `@NotThreadSafe` | Not safe for concurrent use | Verify single-thread usage |
| `@Beta` | May change in minor releases | Don’t depend on from stable code |
| `@Alpha` | May change in patch releases | Experimental only |
| `@Sealed` | No external subclassing | Don’t extend outside the library |
| `@Internal` | Not for consumer use | Flag if used outside library |

* * *

## Architecture Patterns in the Driver

### Pattern 1: Factory Hierarchies for Topology Variants

The driver uses the Abstract Factory pattern to handle different cluster topologies
without if/else sprawl in the main code:

```java
// DefaultClusterFactory creates the right Cluster implementation
// based on ClusterSettings — the caller doesn't choose
public final class DefaultClusterFactory {

    public Cluster createCluster(ClusterSettings clusterSettings, ...) {
        if (clusterSettings.getMode() == LOAD_BALANCED) {
            ClusterableServerFactory serverFactory =
                new LoadBalancedClusterableServerFactory(...);
            return new LoadBalancedCluster(clusterId, clusterSettings, serverFactory, ...);

        } else if (clusterSettings.getMode() == SINGLE) {
            ClusterableServerFactory serverFactory =
                new DefaultClusterableServerFactory(...);
            return new SingleServerCluster(clusterId, clusterSettings, serverFactory, ...);

        } else if (clusterSettings.getSrvHost() != null) {
            return new DnsMultiServerCluster(clusterId, clusterSettings, serverFactory, ...);

        } else {
            return new MultiServerCluster(clusterId, clusterSettings, serverFactory, ...);
        }
    }
}

// All variants implement the same Cluster interface
public interface Cluster extends Closeable {
    ServerTuple selectServer(ServerSelector serverSelector, OperationContext operationContext);
    ClusterDescription getCurrentDescription();
    void close();
}
```

**Cluster hierarchy:**
```
Cluster (interface)
├── BaseCluster (abstract — shared server selection logic)
│   ├── SingleServerCluster
│   ├── MultiServerCluster
│   │   └── DnsMultiServerCluster
│   └── AbstractMultiServerCluster
└── LoadBalancedCluster
```

### Pattern 2: Event-Driven Observability

The driver uses a listener/observer pattern with **immutable event objects** — cleanly
separating observability from core logic:

```java
// Listener interfaces with default no-op methods (easy to implement partially)
public interface CommandListener {
    default void commandStarted(CommandStartedEvent event) {}
    default void commandSucceeded(CommandSucceededEvent event) {}
    default void commandFailed(CommandFailedEvent event) {}
}

public interface ClusterListener extends EventListener {
    default void clusterOpening(ClusterOpeningEvent event) {}
    default void clusterClosed(ClusterClosedEvent event) {}
    default void clusterDescriptionChanged(ClusterDescriptionChangedEvent event) {}
}

// Also: ConnectionPoolListener, ServerListener, ServerMonitorListener
```

**Why this is good architecture:**
- Core code fires events without knowing who listens
- Listeners are pluggable — add monitoring, logging, metrics
- Default methods mean consumers implement only what they need
- Events are immutable — no risk of listener mutating driver state

### Pattern 3: Operation Abstraction Layer

The driver separates “what to do” (operations) from “how to talk to a server”
(bindings/connections):

```java
// ReadOperation — knows WHAT to do (build command, parse response)
public interface ReadOperation<T, R> {
    String getCommandName();
    MongoNamespace getNamespace();
    T execute(ReadBinding binding, OperationContext operationContext);
    void executeAsync(AsyncReadBinding binding, OperationContext operationContext,
                      SingleResultCallback<R> callback);
}

// WriteOperation — same pattern for writes
public interface WriteOperation<T> {
    String getCommandName();
    MongoNamespace getNamespace();
    T execute(WriteBinding binding, OperationContext operationContext);
    void executeAsync(AsyncWriteBinding binding, OperationContext operationContext,
                      SingleResultCallback<T> callback);
}

// Binding — knows HOW to get a connection
// Operations don't know about clusters, pools, or server selection
```

This separation means:
- Operations are testable without a real server (mock the binding)
- The same operation works with sync and async bindings
- Adding a new operation doesn’t touch connection management

* * *

## Architecture Review Checklist

### 1. Module/Package Structure

- [ ] Clear organization strategy (by-concern, by-feature, or hexagonal)
- [ ] Consistent naming across modules
- [ ] No `util/` or `common/` packages growing unbounded
- [ ] Feature packages are cohesive (related code together)
- [ ] Internal implementation separated from public API

### 2. Dependency Direction

- [ ] Dependencies flow in one direction (outer → inner)
- [ ] Core/domain has ZERO framework imports
- [ ] No circular dependencies between packages or modules
- [ ] Lower modules don’t import from higher modules
- [ ] Clear dependency hierarchy visible in build file

### 3. Layer Boundaries

- [ ] Public API surface is clearly defined
- [ ] Internal classes are not exposed to consumers
- [ ] DTOs/models at boundaries, domain objects inside
- [ ] Cross-cutting concerns (logging, events) use abstractions
- [ ] Operations don’t know about transport details

### 4. Module Boundaries

- [ ] Each module has a clear public API
- [ ] `internal` packages mark non-public code
- [ ] Cross-module communication through interfaces
- [ ] No “reaching across” modules for internals
- [ ] Stability annotations communicate contract to consumers

### 5. Extensibility

- [ ] Extension points via interfaces (listeners, providers, selectors)
- [ ] New implementations don’t require modifying existing code
- [ ] Factory pattern used for variant creation
- [ ] Default methods on interfaces for backward-compatible evolution

* * *

## Common Anti-Patterns

### 1. The Big Ball of Mud

```
src/main/java/com/example/
└── app/
    ├── User.java
    ├── UserController.java
    ├── UserService.java
    ├── UserRepository.java
    ├── Order.java
    ├── OrderController.java
    ├── ... (100+ files in one package)
```

**Fix**: Introduce package structure (start with by-feature)

### 2. The Util Dumping Ground

```
util/
├── StringUtils.java
├── DateUtils.java
├── ValidationUtils.java
├── SecurityUtils.java
├── EmailUtils.java      # Should be in notification module
├── OrderCalculator.java # Should be in order domain
└── UserHelper.java      # Should be in user domain
```

**Fix**: Move domain logic to appropriate modules, keep only truly generic utils

### 3. Anemic Domain Model

```java
// ❌ Domain object is just data
public class Order {
    private Long id;
    private List<OrderLine> lines;
    private BigDecimal total;
    // Only getters/setters, no behavior
}

// All logic in "service"
public class OrderService {
    public void addLine(Order order, Product product, int qty) { ... }
    public void calculateTotal(Order order) { ... }
    public void applyDiscount(Order order, Discount discount) { ... }
}
```

**Fix**: Move behavior to domain objects (rich domain model)

**Driver contrast** — `BsonDocument` is a rich domain object:

```java
// ✅ BsonDocument has behavior, not just data
BsonDocument doc = new BsonDocument();
doc.append("name", new BsonString("Alice"));
doc.getFirstKey();             // Behavior on the object
doc.containsKey("name");       // Not delegated to a "BsonDocumentService"
doc.toBsonDocument();           // Self-serialization
```

### 4. Missing API Boundary

```java
// ❌ All classes are public, consumers depend on internals
package com.example.database;

public class ConnectionPool { ... }          // Implementation detail exposed
public class QueryOptimizer { ... }          // Implementation detail exposed
public class DatabaseClient { ... }          // The actual public API
```

**Fix**: Use `internal` packages like the driver does:

```java
// ✅ Clear boundary
com.example.database.DatabaseClient          // PUBLIC: consumers use this
com.example.database.internal.ConnectionPool // INTERNAL: can refactor freely
com.example.database.internal.QueryOptimizer // INTERNAL: can refactor freely
```

### 5. Framework Coupling in Domain

```java
package com.example.domain;

@Entity  // JPA
@Data    // Lombok
@JsonIgnoreProperties(ignoreUnknown = true)  // Jackson
public class User {
    @Id @GeneratedValue
    private Long id;
}
```

**Fix**: Separate domain model from persistence/API models

**Driver contrast** — `bson` module has zero framework dependencies:

```java
// ✅ BsonValue types are pure domain — no Spring, no JPA, no Jackson
public abstract class BsonValue {
    public abstract BsonType getBsonType();
    public BsonDocument asDocument() { ... }
    public boolean isString() { ... }
}
```

* * *

## Analysis Commands

When reviewing architecture, examine:

```bash
# Module/package structure overview
find src/main/java -type d | head -30

# Largest packages (potential god packages)
find src/main/java -name "*.java" | xargs dirname | sort | uniq -c | sort -rn | head -10

# Check for framework imports in core/domain
grep -r "import org.springframework" src/main/java/*/domain/ 2>/dev/null
grep -r "import javax.persistence" src/main/java/*/domain/ 2>/dev/null

# Check internal boundary violations
grep -r "import.*\.internal\." src/main/java/com/example/api/ 2>/dev/null

# Find circular dependencies (look for bidirectional imports)
# Check if package A imports from B and B imports from A
```

* * *

## Recommendations Format

When reporting findings:

```markdown
## Architecture Review: [Project Name]

### Structure Assessment
- **Organization**: Module-per-concern / Package-by-layer / Package-by-feature
- **Clarity**: Clear / Mixed / Unclear
- **API Boundary**: Enforced / Conventional / Missing

### Findings

| Severity | Issue                              | Location                                   | Recommendation                    |
|----------|------------------------------------|--------------------------------------------|-----------------------------------|
| High     | Internal class used in public API  | `api/Service.java` imports `internal/Pool`  | Define interface in public package |
| High     | Circular dependency                | `order` ↔ `user`                           | Extract shared interface          |
| Medium   | God package                        | `util/` (23 classes)                        | Distribute to feature modules     |
| Low      | Inconsistent naming                | `service/` vs `services/`                   | Standardize to `service/`         |

### Dependency Analysis
[Describe dependency flow, violations found]

### Recommendations
1. [Highest priority fix]
2. [Second priority]
3. [Nice to have]
```

* * *

## Token Optimization

For large codebases:
1. Start with `find` to understand structure
2. Check only core/domain packages for framework imports
3. Sample 2-3 features for pattern analysis
4. Review build files for module dependencies
5. Don’t read every file — look for patterns

* * *

## Related References

- [SOLID Principles](solid-principles.md) - Class-level design principles
- [Clean Code Principles](clean-code.md) - Code-level readability and naming
- [Test Quality Guide](test-quality.md) - Test architecture and coverage patterns
- [Security Review Guide](security-review-guide.md) - Security-focused review criteria
