# Performance Smell Detection

Identify **potential** code-level performance issues in Java code. Examples drawn from the MongoDB Java Driver.

## Philosophy

> "Premature optimization is the root of all evil" - Donald Knuth

This skill helps you **notice** potential performance smells, not blindly "fix" them. Modern JVMs (Java 21/25) are highly optimized. Always:

1. **Measure first** — Use JMH, profilers, or production metrics
2. **Focus on hot paths** — 90% of time spent in 10% of code
3. **Consider readability** — Clear code often matters more than micro-optimizations

## When to Use
- Reviewing performance-critical code paths
- Investigating measured performance issues
- Learning about Java performance patterns
- Code review with performance awareness

## Scope

**This skill:** Code-level performance (strings, collections, objects, concurrency)
**For architecture:** Use [Architecture Review Guide](architecture.md)
**For design:** Use [SOLID Principles](solid-principles.md)

---

## Quick Reference: Potential Smells

| Smell | Severity | Context |
|-------|----------|---------|
| Regex compile in loop | 🔴 High | Always worth fixing |
| String concat in loop | 🟡 Medium | Still valid in Java 21/25 |
| Missing object pooling | 🟡 Medium | High-allocation hot paths |
| Boxing in hot path | 🟡 Medium | Measure first |
| Unbounded collection | 🔴 High | Memory risk |
| Wrong concurrent structure | 🔴 High | Correctness + performance |
| Missing collection capacity | 🟢 Low | Minor, measure if critical |

---

## Pre-Compiled Regex Patterns

### Always Pre-Compile — This Advice Is Not Outdated

`Pattern.compile` is expensive. The driver consistently pre-compiles patterns as static finals:

```java
// ✅ GOOD: From DomainNameUtils — pre-compiled as static final
public class DomainNameUtils {
    private static final Pattern DOMAIN_PATTERN =
        Pattern.compile("^(?=.{1,255}$)((([a-zA-Z0-9]" +
            "([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,63}|localhost))$");

    static boolean isDomainName(final String domainName) {
        return DOMAIN_PATTERN.matcher(domainName).matches();
    }
}

// ✅ GOOD: From JsonDoubleHelper — compiled once, used on every double
final class JsonDoubleHelper {
    private static final Pattern POSITIVE_EXPONENT_PATTERN = Pattern.compile("E(\\d+)");
    private static final String POSITIVE_EXPONENT_REPLACER = "E+$1";

    static String toString(final double value) {
        String doubleString = Double.toString(value);
        return POSITIVE_EXPONENT_PATTERN.matcher(doubleString)
            .replaceAll(POSITIVE_EXPONENT_REPLACER);
    }
}
```

### Violation

```java
// 🔴 BAD: Compiles pattern every iteration
for (String host : hosts) {
    if (host.matches("^(?=.{1,255}$).*$")) {  // Pattern.compile called every time!
        validHosts.add(host);
    }
}

// ✅ GOOD: Pre-compile
private static final Pattern HOST_PATTERN = Pattern.compile("^(?=.{1,255}$).*$");

for (String host : hosts) {
    if (HOST_PATTERN.matcher(host).matches()) {
        validHosts.add(host);
    }
}
```

---

## String Operations

### StringBuilder in Loops — Still Valid

```java
// ✅ GOOD: From HexUtils — StringBuilder for byte-to-hex loop
public static String toHex(final byte[] bytes) {
    StringBuilder sb = new StringBuilder();
    for (final byte b : bytes) {
        String s = Integer.toHexString(0xff & b);
        if (s.length() < 2) {
            sb.append("0");
        }
        sb.append(s);
    }
    return sb.toString();
}
```

### Simple Concatenation — Fine in Java 9+

```java
// ✅ Fine in Java 9+ — JVM optimizes with invokedynamic
return "ReadPreferenceServerSelector{readPreference=" + readPreference + '}';

// ✅ Also fine
return "LatencyMinimizingServerSelector{"
    + "acceptableLatencyDifference="
    + MILLISECONDS.convert(acceptableLatencyDifferenceNanos, NANOSECONDS)
    + " ms" + '}';
```

### Avoid in Hot Paths: String.format

```java
// 🟡 String.format has parsing overhead
log.debug(String.format("Processing %s with id %d", name, id));

// ✅ Parameterized logging
log.debug("Processing {} with id {}", name, id);
```

---

## Object Pooling and Buffer Management

### The PowerOfTwoBufferPool Pattern

The driver pools `ByteBuffer` objects to avoid repeated allocation/GC. This is a real-world example of pooling done right:

```java
// ✅ GOOD: Buffer pooling — avoids allocation in hot path
public class PowerOfTwoBufferPool implements BufferProvider {

    // Pools organized by buffer size (powers of two)
    private final Map<Integer, BufferPool> powerOfTwoToPoolMap = new HashMap<>();

    @Override
    public ByteBuf getBuffer(final int size) {
        return new PooledByteBufNIO(getByteBuffer(size));
    }

    public ByteBuffer getByteBuffer(final int size) {
        // Round up to next power of two, find the right pool
        BufferPool pool = powerOfTwoToPoolMap.get(
            log2(roundUpToNextHighestPowerOfTwo(size)));
        ByteBuffer buffer = (pool == null) ? createNew(size) : pool.get().getBuffer();
        buffer.clear();
        buffer.limit(size);
        return buffer;
    }

    public void release(final ByteBuffer buffer) {
        // Return to pool instead of GC
        BufferPool pool = powerOfTwoToPoolMap.get(
            log2(roundUpToNextHighestPowerOfTwo(buffer.capacity())));
        if (pool != null) {
            pool.release(new IdleTrackingByteBuffer(buffer));
        }
    }

    // Pruning: idle buffers cleaned up after 1 minute
    PowerOfTwoBufferPool enablePruning() {
        pruner.scheduleAtFixedRate(this::prune,
            maxIdleTimeNanos, maxIdleTimeNanos / 2, TimeUnit.NANOSECONDS);
        return this;
    }
}
```

**Why this pattern matters:**
- ByteBuffers are expensive to allocate (especially direct buffers)
- Connection-heavy workloads allocate thousands per second
- Pooling + pruning balances reuse vs memory footprint
- Power-of-two sizing minimizes internal fragmentation

### Connection Pooling

```java
// ✅ GOOD: ConcurrentPool — lock-free reads from available pool
public class ConcurrentPool<T> implements Pool<T> {

    private final Deque<T> available = new ConcurrentLinkedDeque<>();
    // ConcurrentLinkedDeque: lock-free, thread-safe, O(1) add/remove from both ends
    // Not ArrayList — which would need external synchronization
}
```

---

## Efficient Bit Operations

The driver uses bit manipulation for performance-critical size calculations:

```java
// ✅ GOOD: From PowerOfTwoBufferPool — bit tricks instead of Math.log
static int log2(final int powerOfTwo) {
    return 31 - Integer.numberOfLeadingZeros(powerOfTwo);
}

static int roundUpToNextHighestPowerOfTwo(final int size) {
    int v = size;
    v--;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    v++;
    return v;
}
```

**Why:** These are called on every buffer allocation — `Math.log` would be significantly slower in this hot path.

---

## Lock-Free Concurrent Patterns

### AtomicLong for Thread-Safe Counters

```java
// ✅ GOOD: From ExponentiallyWeightedMovingAverage — lock-free updates
class ExponentiallyWeightedMovingAverage {
    private static final long EMPTY = -1;
    private final double alpha;
    private final AtomicLong average;

    long addSample(final long sample) {
        // accumulateAndGet: atomic read-modify-write without locks
        return average.accumulateAndGet(sample, (avg, givenSample) -> {
            if (avg == EMPTY) {
                return givenSample;
            }
            return (long) (alpha * givenSample + (1 - alpha) * avg);
        });
    }
}
```

### Bounded Collections

```java
// ✅ GOOD: From RoundTripTimeSampler — bounded window of samples
private static final class RecentSamples {
    private static final int MAX_SIZE = 10;  // Bounded!
    private final Deque<Long> samples;

    void add(final long sample) {
        if (samples.size() == MAX_SIZE) {
            samples.removeFirst();  // Evict oldest
        }
        samples.add(sample);
    }

    long min() {
        // Only compute min when enough samples gathered
        return samples.size() < 2 ? 0
            : samples.stream().min(Long::compareTo).orElse(0L);
    }
}
```

### Violation: Unbounded Collections

```java
// 🔴 BAD: Unbounded collection — memory risk
List<ServerDescription> allServersEverSeen = new ArrayList<>();

void onServerDiscovered(ServerDescription server) {
    allServersEverSeen.add(server);  // Grows forever!
}

// ✅ GOOD: Bounded with eviction (like RecentSamples above)
// or use ConcurrentHashMap with bounded size
```

---

## Right Collection for the Job

### Use Set for Membership Tests

```java
// 🟡 O(n) lookup per check — the Set in MongoNamespace
private static final Set<Character> PROHIBITED_CHARACTERS_IN_DATABASE_NAME =
    new HashSet<>(asList('\0', '/', '\\', ' ', '"', '.'));

// O(1) lookup per character
for (int i = 0; i < databaseName.length(); i++) {
    if (PROHIBITED_CHARACTERS_IN_DATABASE_NAME.contains(databaseName.charAt(i))) {
        throw new IllegalArgumentException("...");
    }
}
```

### Use Immutable Collections at Boundaries

```java
// ✅ GOOD: The driver wraps collections as unmodifiable at boundaries
public class CompositeServerSelector implements ServerSelector {
    private final List<ServerSelector> serverSelectors;

    public CompositeServerSelector(List<ServerSelector> selectors) {
        this.serverSelectors = Collections.unmodifiableList(mergedServerSelectors);
        // Prevents external mutation; no defensive copy cost on reads
    }
}
```

### Collection Capacity Hints

```java
// 🟢 Low severity but free — when size is known
Map<BsonType, Class<?>> map = new HashMap<>(20);  // Known size: 20 BSON types
// Avoids resize from default capacity of 16

// ✅ From BsonValueCodecProvider: pre-sized map for known BSON types
static {
    Map<BsonType, Class<?>> map = new HashMap<>();
    map.put(BsonType.NULL, BsonNull.class);
    map.put(BsonType.ARRAY, BsonArray.class);
    map.put(BsonType.BINARY, BsonBinary.class);
    // ... 20 entries — default capacity triggers resize
}
```

---

## Caching Computed Values

### Cache to Avoid Repeated Computation

```java
// ✅ GOOD: From MongoNamespace — cache the fullName string
@Immutable
public final class MongoNamespace {
    private final String databaseName;
    private final String collectionName;
    private final String fullName;  // Cached — avoids repeated concatenation

    public MongoNamespace(String databaseName, String collectionName) {
        this.databaseName = databaseName;
        this.collectionName = collectionName;
        this.fullName = databaseName + '.' + collectionName;  // Compute once
    }

    public String getFullName() {
        return fullName;  // O(1) — no allocation
    }
}
```

### Static Final Constants

```java
// ✅ GOOD: From PowerOfTwoBufferPool — pre-computed singleton
public static final PowerOfTwoBufferPool DEFAULT =
    new PowerOfTwoBufferPool().enablePruning();
// One instance shared globally — no per-client allocation

// ✅ GOOD: From WriteConcern — shared immutable constants
public static final WriteConcern ACKNOWLEDGED = new WriteConcern(null, null, null);
public static final WriteConcern MAJORITY = new WriteConcern("majority");
// No object creation at usage sites
```

---

## Boxing/Unboxing

### Still a Real Issue in Hot Paths

```java
// 🔴 BAD: Boxing in tight loop
Long sum = 0L;
for (int i = 0; i < 1_000_000; i++) {
    sum += i;  // Unbox, add, box — millions of objects
}

// ✅ GOOD: Primitive
long sum = 0L;
for (int i = 0; i < 1_000_000; i++) {
    sum += i;
}
```

### Use Primitive Streams

```java
// 🟡 Boxing overhead with streams
int sum = values.stream()
    .reduce(0, Integer::sum);

// ✅ Primitive stream
int sum = values.stream()
    .mapToInt(Integer::intValue)
    .sum();
```

---

## Stream API — Nuanced View

### When Streams Are Fine

```java
// ✅ From RoundTripTimeSampler — small collection, not a tight loop
long min() {
    return samples.size() < 2 ? 0
        : samples.stream().min(Long::compareTo).orElse(0L);
}

// ✅ From LatencyMinimizingServerSelector — server list is small
// Readable stream over a few server descriptions is fine
```

### When Streams Are Problematic

```java
// 🔴 Stream in tight loop — avoid
for (int i = 0; i < 1_000_000; i++) {
    boolean found = servers.stream()
        .anyMatch(s -> s.getPort() == i);
}

// ✅ Pre-compute lookup structure
Set<Integer> ports = servers.stream()
    .map(ServerDescription::getPort)
    .collect(Collectors.toSet());

for (int i = 0; i < 1_000_000; i++) {
    boolean found = ports.contains(i);
}
```

---

## Performance Review Checklist

### 🔴 High Severity (Usually Worth Fixing)
- [ ] Regex `Pattern.compile` in loops (pre-compile as `static final`)
- [ ] Unbounded collections without eviction
- [ ] String concatenation in loops (use `StringBuilder`)
- [ ] Wrong concurrent data structure (e.g., `ArrayList` shared across threads)

### 🟡 Medium Severity (Measure First)
- [ ] Streams in tight loops (>100K iterations)
- [ ] Boxing in hot paths (use primitives)
- [ ] Missing object pooling for expensive allocations (buffers, connections)
- [ ] Repeated computation of immutable values (cache them)
- [ ] `List.contains()` in loops (use `Set`)

### 🟢 Low Severity (Nice to Have)
- [ ] Collection initial capacity when size is known
- [ ] `Collections.unmodifiableList` at API boundaries
- [ ] Minor stream optimizations

---

## When NOT to Optimize

- **Not a hot path** — Setup code, config, admin operations
- **No measured problem** — "Looks slow" is not a measurement
- **Readability suffers** — Clear code > micro-optimization
- **Small collections** — 100 items processed in microseconds
- **One-time cost** — Startup initialization, factory creation

The driver itself demonstrates this: `DefaultClusterFactory.createCluster()` has a long parameter list and does multiple allocations — but it runs once per `MongoClient` lifetime, so optimizing it would be premature.

---

## Analysis Commands

```bash
# Find regex in loops (potential compile overhead)
grep -rn "\.matches(\|\.split(" --include="*.java"

# Find potential boxing (Long/Integer as loop variables)
grep -rn "Long\s\|Integer\s\|Double\s" --include="*.java" | grep "= 0\|+="

# Find ArrayList without capacity hint
grep -rn "new ArrayList<>()" --include="*.java"

# Find pre-compiled patterns (good practice)
grep -rn "static final Pattern" --include="*.java"

# Find ConcurrentLinkedDeque usage (check if bounded)
grep -rn "ConcurrentLinkedDeque\|ConcurrentHashMap" --include="*.java"
```

---

## Related References

- [Architecture Review Guide](architecture.md) — System-level performance (module boundaries, I/O patterns)
- [Clean Code Principles](clean-code.md) — Readability vs optimization trade-offs
- [SOLID Principles](solid-principles.md) — Design for testability and extensibility
