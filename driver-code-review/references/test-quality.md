# Test Quality

Write high-quality, maintainable tests for Java projects using modern best practices.
Examples drawn from the MongoDB Java Driver.

Prefer JUnit 5 to Spock tests — do not add new Spock specification files.

## Framework Preferences

### JUnit 5 (Jupiter)

```java
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import static org.junit.jupiter.api.Assertions.*;
```

* * *

## Test Structure (AAA Pattern)

Always use Arrange-Act-Assert pattern:

```java
@Test
void shouldSelectServersByLatencyThreshold() {
    // Arrange — setup test data and dependencies
    LatencyMinimizingServerSelector selector =
        new LatencyMinimizingServerSelector(20, TimeUnit.MILLISECONDS);

    ServerDescription primary = ServerDescription.builder()
        .state(CONNECTED).address(new ServerAddress())
        .ok(true).type(REPLICA_SET_PRIMARY)
        .roundTripTime(10, TimeUnit.MILLISECONDS)
        .build();

    ServerDescription fastSecondary = ServerDescription.builder()
        .state(CONNECTED).address(new ServerAddress("localhost:27018"))
        .ok(true).type(REPLICA_SET_SECONDARY)
        .roundTripTime(15, TimeUnit.MILLISECONDS)
        .build();

    ServerDescription slowSecondary = ServerDescription.builder()
        .state(CONNECTED).address(new ServerAddress("localhost:27019"))
        .ok(true).type(REPLICA_SET_SECONDARY)
        .roundTripTime(31, TimeUnit.MILLISECONDS)  // 21ms slower than primary
        .build();

    ClusterDescription cluster = new ClusterDescription(
        MULTIPLE, REPLICA_SET, Arrays.asList(primary, fastSecondary, slowSecondary));

    // Act — execute the behavior being tested
    List<ServerDescription> selected = selector.select(cluster);

    // Assert — verify results
    assertEquals(Arrays.asList(primary, fastSecondary), selected);
    // slowSecondary excluded: 31ms - 10ms = 21ms > 20ms threshold
}
```

* * *

## Naming Conventions

### Test Class Names

```java
// Class under test: ClusterDescription
ClusterDescriptionTest      // ✅ Standard, used by the driver
DocumentCodecTest           // ✅ Clear what it tests
ObjectIdTest                // ✅ Simple, direct

TestClusterDescription      // ❌ Avoid "Test" prefix
```

### Test Method Names

**Option 1: Descriptive camelCase** (driver pattern)
```java
@Test
void testLatencyDifferentialMinimization() { }

@Test
void testZeroLatencyDifferentialTolerance() { }

@Test
void connectTimeoutThrowsIfArgumentIsTooLarge() { }
```

**Option 2: should_when pattern** (more descriptive)
```java
@Test
void shouldSelectFastestServers_whenLatencyThresholdIsExceeded() { }

@Test
void shouldReturnEmptyList_whenNoServersAreOk() { }

@Test
void shouldThrowException_whenDatabaseNameContainsSlash() { }
```

* * *

## Builder-Based Test Fixtures

The driver uses builders extensively in tests to create readable, customizable test
data:

```java
// ✅ GOOD: Builders make test data clear and configurable
public class ClusterDescriptionTest {

    private ServerDescription primary, secondary, otherSecondary;
    private ClusterDescription cluster;

    @Before
    public void setUp() {
        TagSet tags1 = new TagSet(asList(new Tag("foo", "1"), new Tag("bar", "2")));
        TagSet tags2 = new TagSet(asList(new Tag("foo", "1"), new Tag("bar", "3")));

        primary = ServerDescription.builder()
            .state(CONNECTED)
            .address(new ServerAddress("localhost", 27017))
            .ok(true)
            .type(REPLICA_SET_PRIMARY)
            .tagSet(tags1)
            .build();

        secondary = ServerDescription.builder()
            .state(CONNECTED)
            .address(new ServerAddress("localhost", 27018))
            .ok(true)
            .type(REPLICA_SET_SECONDARY)
            .tagSet(tags2)
            .build();

        cluster = new ClusterDescription(MULTIPLE, REPLICA_SET,
            asList(primary, secondary, otherSecondary));
    }
}
```

### Extract Common Setup to Helper Methods

```java
// ✅ GOOD: Reusable test data factory
private ServerDescription createServer(String host, ServerType type, long roundTripMs) {
    return ServerDescription.builder()
        .state(CONNECTED)
        .address(new ServerAddress(host))
        .ok(true)
        .type(type)
        .roundTripTime(roundTripMs, TimeUnit.MILLISECONDS)
        .build();
}

// Usage in tests — concise and readable
@Test
void shouldSelectServersWithinLatencyWindow() {
    ServerDescription fast = createServer("host1:27017", REPLICA_SET_PRIMARY, 10);
    ServerDescription medium = createServer("host2:27018", REPLICA_SET_SECONDARY, 25);
    ServerDescription slow = createServer("host3:27019", REPLICA_SET_SECONDARY, 50);
    // ...
}
```

* * *

## Parameterized Tests

Use `@ParameterizedTest` with `@MethodSource` to test multiple inputs without
duplicating test logic:

```java
// ✅ GOOD: From WriteConcernHelperTest — tests all WriteConcern variants
class WriteConcernHelperTest {

    static WriteConcern[] shouldRemoveWtimeout() {
        return new WriteConcern[]{
            WriteConcern.ACKNOWLEDGED,
            WriteConcern.MAJORITY,
            WriteConcern.W1,
            WriteConcern.W2,
            WriteConcern.W3,
            WriteConcern.UNACKNOWLEDGED,
            WriteConcern.JOURNALED,
            WriteConcern.ACKNOWLEDGED.withWTimeout(100, TimeUnit.MILLISECONDS),
            WriteConcern.MAJORITY.withWTimeout(100, TimeUnit.MILLISECONDS),
            WriteConcern.W1.withWTimeout(100, TimeUnit.MILLISECONDS),
        };
    }

    @MethodSource
    @ParameterizedTest
    void shouldRemoveWtimeout(final WriteConcern writeConcern) {
        // when
        WriteConcern clonedWithoutTimeout = WriteConcernHelper.cloneWithoutTimeout(writeConcern);

        // then
        assertEquals(writeConcern.getWObject(), clonedWithoutTimeout.getWObject());
        assertEquals(writeConcern.getJournal(), clonedWithoutTimeout.getJournal());
        assertNull(clonedWithoutTimeout.getWTimeout(TimeUnit.MILLISECONDS));
    }
}
```

### From ObjectIdTest — Multiple ByteBuffer Variants

```java
public static List<ByteBuffer> validOutputBuffers() {
    List<ByteBuffer> result = new ArrayList<>();
    result.add(ByteBuffer.allocate(12));
    result.add(ByteBuffer.allocate(12).order(ByteOrder.LITTLE_ENDIAN));
    result.add(ByteBuffer.allocate(24).put(new byte[12]));
    result.add(ByteBuffer.allocateDirect(12));
    result.add(ByteBuffer.allocateDirect(12).order(ByteOrder.LITTLE_ENDIAN));
    return result;
}

@MethodSource("validOutputBuffers")
@ParameterizedTest
void testToBytes(final ByteBuffer output) {
    byte[] expectedBytes = {81, 6, -4, -102, -68, -126, 55, 85, -127, 54, -46, -119};
    ObjectId objectId = new ObjectId(expectedBytes);

    objectId.putToByteBuffer(output);
    // ... verify bytes written correctly

    assertArrayEquals(expectedBytes, result);
    assertEquals(originalPosition + 12, output.position());
    assertEquals(originalOrder, output.order());
}
```

* * *

## Nested Test Classes

Use `@Nested` to group related tests and improve organization:

```java
// ✅ GOOD: From ExceptionUtilsTest — groups related test cases
final class ExceptionUtilsTest {

    @Nested
    final class MongoCommandExceptionUtilsTest {

        @Test
        void redacted() {
            MongoCommandException original = new MongoCommandException(
                new BsonDocument("ok", BsonBoolean.FALSE)
                    .append("code", new BsonInt32(26))
                    .append("codeName", new BsonString("TimeoutError"))
                    .append("errorLabels", new BsonArray(
                        asList(new BsonString("label"), new BsonString("label2"))))
                    .append("errmsg", new BsonString("err msg")),
                new ServerAddress());

            MongoCommandException redacted = MongoCommandExceptionUtils.redacted(original);

            assertArrayEquals(original.getStackTrace(), redacted.getStackTrace());
            assertTrue(redacted.getMessage().contains("26"));
            assertTrue(redacted.getMessage().contains("TimeoutError"));
            assertFalse(redacted.getMessage().contains("err msg"));
            assertTrue(redacted.getErrorMessage().isEmpty());
            assertEquals(26, redacted.getErrorCode());
            assertEquals("TimeoutError", redacted.getErrorCodeName());
        }
    }
}
```

* * *

## Codec Round-Trip Tests

A common pattern in the driver: encode → decode → assert equality:

```java
// ✅ GOOD: From DocumentCodecTest — verifies full encode/decode cycle
public class DocumentCodecTest {
    private BasicOutputBuffer buffer;
    private BsonBinaryWriter writer;

    @BeforeEach
    public void setUp() {
        buffer = new BasicOutputBuffer();
        writer = new BsonBinaryWriter(buffer);
    }

    @AfterEach
    public void tearDown() {
        writer.close();
    }

    @Test
    void testPrimitiveBSONTypeCodecs() {
        DocumentCodec documentCodec = new DocumentCodec();

        // Arrange — build a document with all primitive types
        Document doc = new Document();
        doc.put("oid", new ObjectId());
        doc.put("integer", 1);
        doc.put("long", 2L);
        doc.put("string", "hello");
        doc.put("double", 3.2);
        doc.put("decimal", Decimal128.parse("0.100"));
        doc.put("date", new Date(1000));
        doc.put("boolean", true);
        doc.put("null", null);

        // Act — encode then decode
        documentCodec.encode(writer, doc, EncoderContext.builder().build());
        BsonInput bsonInput = createInputBuffer();
        Document decoded = documentCodec.decode(
            new BsonBinaryReader(bsonInput), DecoderContext.builder().build());

        // Assert — round-trip preserves all values
        assertEquals(doc, decoded);
    }
}
```

* * *

## Exception Testing

### Use assertThrows (JUnit 5)

```java
// ✅ GOOD: Clean exception verification
@Test
void connectTimeoutThrowsIfArgumentIsTooLarge() {
    assertThrows(IllegalArgumentException.class, () ->
        SocketSettings.builder().connectTimeout(Integer.MAX_VALUE / 2, TimeUnit.SECONDS));
}

@Test
void readTimeoutThrowsIfArgumentIsTooLarge() {
    assertThrows(IllegalArgumentException.class, () ->
        SocketSettings.builder().readTimeout(Integer.MAX_VALUE / 2, TimeUnit.SECONDS));
}
```

### Verify Exception Message Content

```java
// ✅ GOOD: Check both type and message
@Test
void shouldRejectNullDatabaseName() {
    IllegalArgumentException ex = assertThrows(
        IllegalArgumentException.class,
        () -> new MongoNamespace(null, "collection"));
    assertTrue(ex.getMessage().contains("can not be null"));
}

@Test
void shouldRejectInvalidObjectIdBytes() {
    IllegalArgumentException ex = assertThrows(
        IllegalArgumentException.class,
        () -> new ObjectId(new byte[11]));
    assertTrue(ex.getMessage().contains("11"));
}
```

### Avoid Try-Catch for Expected Exceptions

```java
// ❌ BAD: Verbose, easy to forget fail()
@Test
void shouldRejectNullValue() {
    try {
        new ObjectId((byte[]) null);
        fail("Expected IllegalArgumentException");
    } catch (IllegalArgumentException e) {
        assertEquals("bytes can not be null", e.getMessage());
    }
}

// ✅ GOOD: assertThrows is concise and clear
@Test
void shouldRejectNullValue() {
    IllegalArgumentException ex = assertThrows(
        IllegalArgumentException.class,
        () -> new ObjectId((byte[]) null));
    assertEquals("bytes can not be null", ex.getMessage());
}
```

* * *

## Assertion Best Practices

### Use Specific Assertions

```java
// ❌ BAD: Generic assertTrue with manual comparison
assertTrue(cluster.getConnectionMode() == MULTIPLE);
assertTrue(result.size() == 4);
assertTrue(result.contains(primary));

// ✅ GOOD: Specific assertions give better failure messages
assertEquals(MULTIPLE, cluster.getConnectionMode());
assertEquals(4, result.size());
assertTrue(result.contains(primary));
```

### Assert One Concept Per Test

```java
// ✅ GOOD: Focused tests from ClusterDescriptionTest

@Test
void testMode() {
    ClusterDescription description = new ClusterDescription(MULTIPLE, UNKNOWN, emptyList());
    assertEquals(MULTIPLE, description.getConnectionMode());
}

@Test
void testHasReadableServer() {
    assertTrue(cluster.hasReadableServer(ReadPreference.primary()));
    assertFalse(
        new ClusterDescription(MULTIPLE, REPLICA_SET, asList(secondary))
            .hasReadableServer(ReadPreference.primary()));
}

@Test
void testHasWritableServer() {
    assertTrue(cluster.hasWritableServer());
    assertFalse(
        new ClusterDescription(MULTIPLE, REPLICA_SET, asList(secondary))
            .hasWritableServer());
}
```

### Use Static Imports for Readability

```java
// ✅ GOOD: The driver uses static imports extensively
import static com.mongodb.connection.ClusterConnectionMode.MULTIPLE;
import static com.mongodb.connection.ClusterType.REPLICA_SET;
import static com.mongodb.connection.ServerConnectionState.CONNECTED;
import static com.mongodb.connection.ServerDescription.builder;
import static java.util.Arrays.asList;
import static org.junit.jupiter.api.Assertions.*;

// Results in clean, readable test code:
cluster = new ClusterDescription(MULTIPLE, REPLICA_SET, asList(primary, secondary));
assertEquals(asList(primary, secondary), getAnyPrimaryOrSecondary(cluster));
```

* * *

## Token Optimization

When writing tests:

### 1. Generate Test Skeleton First

```java
// Phase 1: List test cases as comments
// @Test void shouldSelectPrimaryFromReplicaSet() { }
// @Test void shouldReturnEmptyForUnknownCluster() { }
// @Test void shouldFilterByLatencyThreshold() { }
// @Test void shouldHandleZeroLatencyTolerance() { }
```

### 2. Implement Incrementally

- One test at a time
- Verify compilation after each
- Run tests to validate
- Refactor if needed

### 3. Reuse Patterns

```java
// Extract common setup to @BeforeEach or helper methods
@BeforeEach
void setUp() {
    buffer = new BasicOutputBuffer();
    writer = new BsonBinaryWriter(buffer);
}
```

* * *

## Code Coverage Guidelines

- **Aim for**: 80%+ line coverage on core logic
- **Focus on**: Business logic, complex algorithms, edge cases
- **Skip**: Trivial getters/setters, POJOs, generated code
- **Test**: Happy paths + error conditions + boundary cases

### What to Test

**High priority:**
- Public APIs (MongoCollection operations, Filters, Updates)
- Complex logic (server selection, codec encode/decode, connection pooling)
- Error handling (invalid inputs, timeout conditions, connection failures)
- Edge cases and boundaries (empty collections, null values, max sizes)

**Low priority:**
```java
// Simple getters on immutable objects
public String getDatabaseName() { return databaseName; }
public String getCollectionName() { return collectionName; }

// toString() methods
@Override
public String toString() {
    return "MongoNamespace{" + fullName + "}";
}
```

* * *

## Anti-Patterns

### Avoid These

```java
// ❌ 1. Generic test names
@Test void test1() { }
@Test void testServer() { }

// ❌ 2. Testing implementation details
assertEquals("localhost:27017", cluster.internalServerMap.keySet().iterator().next());

// ❌ 3. Brittle assertions with timestamps
assertEquals("Error at 2024-01-26 10:30:15", message);

// ❌ 4. Multiple unrelated assertions in one test
@Test void testEverything() {
    assertEquals(MULTIPLE, cluster.getConnectionMode());  // Cluster state
    assertEquals(100, poolSettings.getMaxSize());          // Pool config
    assertTrue(sslSettings.isEnabled());                   // SSL config
    // Mixing unrelated concerns
}

// ❌ 5. Swallowing exception details
@Test void shouldFail() {
    try {
        loader.load(invalidPath);
        fail("Should have thrown exception");
    } catch (Exception e) {
        // Not checking anything about the exception!
    }
}

// ❌ 6. Test depends on execution order
// Tests must be independent — don't share mutable state between test methods
```

### Prefer These

```java
// ✅ Focused, well-named test
@Test
void shouldRejectDatabaseNameWithSlash() {
    IllegalArgumentException ex = assertThrows(
        IllegalArgumentException.class,
        () -> MongoNamespace.checkDatabaseNameValidity("invalid/name"));
    assertTrue(ex.getMessage().contains("/"));
}

// ✅ Clean round-trip test
@Test
void shouldRoundTripDocumentThroughCodec() {
    Document original = new Document("key", "value").append("count", 42);

    codec.encode(writer, original, EncoderContext.builder().build());
    Document decoded = codec.decode(createReader(), DecoderContext.builder().build());

    assertEquals(original, decoded);
}
```

* * *

## Test Checklist

When reviewing tests, check:

- [ ] Do tests follow AAA (Arrange-Act-Assert) pattern?
- [ ] Are test names descriptive of the scenario?
- [ ] Is each test independent (no shared mutable state)?
- [ ] Are assertions specific (assertEquals over assertTrue)?
- [ ] Are exceptions tested with assertThrows?
- [ ] Is test data created with builders for readability?
- [ ] Are parameterized tests used for multiple input variants?
- [ ] Is common setup in @BeforeEach or helper methods?
- [ ] Does each test verify one concept?
- [ ] Are there tests for edge cases and error conditions?

* * *

## Related References

- [SOLID Principles](solid-principles.md) - Design principles (testable code follows
  SOLID)
- [Clean Code Principles](clean-code.md) - Naming and readability (applies to tests too)
- [Architecture Review Guide](architecture.md) - Test architecture and module boundaries
