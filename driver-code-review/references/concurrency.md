# Concurrency Review

Review Java concurrent code for correctness, safety, and modern best practices. Examples drawn from the MongoDB Java Driver.

## Why This Matters

> Nearly 60% of multithreaded applications encounter issues due to improper management of shared resources. - ACM Study

Concurrency bugs are:
- **Hard to reproduce** - timing-dependent
- **Hard to test** - may only appear under load
- **Hard to debug** - non-deterministic behavior

This helps catch issues **before** they reach production.

## When to Use
- Reviewing code with `synchronized`, `volatile`, `Lock`
- Checking `CompletableFuture`, `ExecutorService`
- Validating thread safety of shared state
- Reviewing Virtual Threads / Structured Concurrency code
- Any code accessed by multiple threads

---

## Lock Utility Pattern

### Centralizing Lock Management

The driver centralizes all lock acquisition into a `Locks` utility, ensuring unlock always happens in a `finally` block and interrupts are handled consistently:

```java
// From Locks — centralizes safe lock usage
public final class Locks {

    public static void withLock(final Lock lock, final Runnable action) {
        withLock(lock, () -> {
            action.run();
            return null;
        });
    }

    public static <V> V withLock(final Lock lock, final Supplier<V> supplier) {
        return checkedWithLock(lock, supplier::get);
    }

    public static <V, E extends Exception> V checkedWithLock(
            final Lock lock, final CheckedSupplier<V, E> supplier) throws E {
        lock.lock();
        try {
            return supplier.get();
        } finally {
            lock.unlock();  // Always in finally — never forgotten
        }
    }

    // Interruptible variant — wraps InterruptedException
    public static <V, E extends Exception> V checkedWithInterruptibleLock(
            final Lock lock, final CheckedSupplier<V, E> supplier)
            throws MongoInterruptedException, E {
        lockInterruptibly(lock);
        try {
            return supplier.get();
        } finally {
            lock.unlock();
        }
    }

    public static void lockInterruptibly(final Lock lock)
            throws MongoInterruptedException {
        try {
            lock.lockInterruptibly();
        } catch (InterruptedException e) {
            throw interruptAndCreateMongoInterruptedException(
                "Interrupted waiting for lock", e);
        }
    }
}
```

**Why this matters:**
- `unlock()` is always in `finally` — no forgotten unlocks
- Interrupted handling is standardized — wraps `InterruptedException` consistently
- Lambda-based API prevents misuse — no way to forget the unlock
- Used across the entire driver codebase

### Violation

```java
// BAD: Manual lock/unlock — easy to forget or miss on exception
lock.lock();
doWork();
lock.unlock();  // Never reached if doWork() throws!

// GOOD: Use the withLock utility
withLock(lock, () -> doWork());
```

---

## Volatile for Visibility

### The Driver's Volatile Pattern

The driver uses `volatile` extensively for state flags that are written by one thread and read by many:

```java
// From BaseCluster — volatile for cluster state visibility
abstract class BaseCluster implements Cluster {
    private final ReentrantLock lock = new ReentrantLock();
    private final AtomicReference<CountDownLatch> phase =
        new AtomicReference<>(new CountDownLatch(1));

    private volatile boolean isClosed;
    private volatile ClusterDescription description;

    @Override
    public ServerTuple selectServer(final ServerSelector serverSelector,
            final OperationContext operationContext) {
        isTrue("open", !isClosed());  // Read volatile — sees latest state

        while (true) {
            CountDownLatch currentPhaseLatch = phase.get();
            ClusterDescription currentDescription = description;  // Read volatile

            ServerTuple serverTuple = createCompleteSelectorAndSelectServer(
                    serverSelector, currentDescription, ...);
            if (serverTuple != null) {
                return serverTuple;
            }
            // Wait for cluster state to change
            heartbeatLimitedTimeout.awaitOn(currentPhaseLatch, ...);
        }
    }

    @Override
    public void close() {
        if (!isClosed()) {
            isClosed = true;  // Write volatile — visible to all threads
            phase.get().countDown();
            // ...
        }
    }
}
```

**Key pattern:** `volatile boolean isClosed` is written once and read many times across threads. The monitor thread sets it, and the server selection thread reads it — `volatile` guarantees the read thread sees the update.

### From DefaultServerMonitor — Volatile for Monitoring State

```java
@ThreadSafe
class DefaultServerMonitor implements ServerMonitor {
    private final Lock lock = new ReentrantLock();
    private final Condition condition = lock.newCondition();
    private volatile boolean isClosed;

    class ServerMonitor extends Thread implements AutoCloseable {
        private volatile InternalConnection connection = null;
        private volatile boolean currentCheckCancelled;
        private volatile long lookupStartTimeNanos;

        @Override
        public void run() {
            ServerDescription currentServerDescription = ...;
            while (!isClosed) {    // Read volatile — monitor thread checks
                currentServerDescription = lookupServerDescription(...);
                if (currentCheckCancelled) {  // Read volatile — another thread can cancel
                    waitForNext();
                    currentCheckCancelled = false;
                    continue;
                }
                // ...
            }
        }
    }
}
```

### From CursorResourceManager — Volatile State Machine

```java
// From CursorResourceManager — volatile state with lock-protected transitions
@ThreadSafe
abstract class CursorResourceManager<CS, C> {
    private final Lock lock;
    private volatile State state;                    // Volatile for reads
    @Nullable
    private volatile CS connectionSource;
    @Nullable
    private volatile ServerCursor serverCursor;

    boolean tryStartOperation() throws IllegalStateException {
        return withLock(lock, () -> {                // State transition under lock
            State localState = state;
            if (!localState.operable()) {
                return false;
            } else if (localState == State.IDLE) {
                state = State.OPERATION_IN_PROGRESS;  // Write under lock
                return true;
            } else if (localState == State.OPERATION_IN_PROGRESS) {
                throw new IllegalStateException(MESSAGE_IF_CONCURRENT_OPERATION);
            } else {
                throw fail(state.toString());
            }
        });
    }

    void close(final OperationContext operationContext) {
        boolean doClose = withLock(lock, () -> {     // Lock for state transition
            State localState = state;
            if (localState.isOperationInProgress()) {
                state = State.CLOSE_PENDING;          // Deferred close
            } else if (localState != State.CLOSED) {
                state = State.CLOSED;
                return true;
            }
            return false;
        });
        if (doClose) {
            doClose(operationContext);                // Close outside lock
        }
    }

    enum State {
        IDLE(true, false),
        OPERATION_IN_PROGRESS(true, true),
        CLOSE_PENDING(false, true),                   // Close deferred until op completes
        CLOSED(false, false);
        // ...
    }
}
```

**Key insight:** State reads are `volatile` (fast, no lock), but state transitions are lock-protected. This gives maximum concurrency for reads while keeping transitions safe. Close is deferred when an operation is in progress — never interrupts mid-operation.

---

## Lock + Condition Pattern

### Permit-Based Pool with Condition Signaling

The driver's `ConcurrentPool` uses `ReentrantLock` with `Condition` for wait/signal semantics:

```java
// From ConcurrentPool.StateAndPermits — lock + condition for pool permits
@ThreadSafe
private static final class StateAndPermits {
    private final ReentrantLock lock;
    private final Condition permitAvailableOrClosedOrPausedCondition;
    private volatile boolean paused;
    private volatile boolean closed;
    private volatile int permits;

    StateAndPermits(final int maxPermits, ...) {
        lock = new ReentrantLock();
        permitAvailableOrClosedOrPausedCondition = lock.newCondition();
        permits = maxPermits;
    }

    boolean acquirePermit(final long timeout, final TimeUnit unit) {
        long remainingNanos = unit.toNanos(timeout);
        lockInterruptibly(lock);
        try {
            while (permits == 0
                    // non-short-circuiting '&' ensures throwIfClosedOrPaused is called
                    & !throwIfClosedOrPaused()) {
                if (timeout < 0) {
                    permitAvailableOrClosedOrPausedCondition.await();
                } else if (remainingNanos >= 0) {
                    remainingNanos =
                        permitAvailableOrClosedOrPausedCondition.awaitNanos(remainingNanos);
                } else {
                    return false;  // Timed out
                }
            }
            permits--;
            return true;
        } finally {
            lock.unlock();
        }
    }

    void releasePermit() {
        withLock(lock, () -> {
            permits++;
            permitAvailableOrClosedOrPausedCondition.signal();  // Wake one waiter
        });
    }

    void pause(final Supplier<MongoException> causeSupplier) {
        withLock(lock, () -> {
            if (!paused) {
                paused = true;
                permitAvailableOrClosedOrPausedCondition.signalAll();  // Wake ALL waiters
            }
        });
    }
}
```

**Why `signal()` vs `signalAll()`:**
- `releasePermit` uses `signal()` — one permit, one waiter
- `pause` uses `signalAll()` — all waiters need to wake and throw

### Violation

```java
// BAD: Using Object.wait/notify (error-prone)
synchronized (pool) {
    while (pool.isEmpty()) {
        pool.wait();  // Requires synchronized block, hard to manage timeout
    }
}

// GOOD: Use Lock + Condition (explicit, multiple conditions possible)
lockInterruptibly(lock);
try {
    while (permits == 0 & !throwIfClosedOrPaused()) {
        remainingNanos = condition.awaitNanos(remainingNanos);
    }
} finally {
    lock.unlock();
}
```

---

## Lock-Free Atomic Updates

### AtomicLong with accumulateAndGet

The driver uses `AtomicLong.accumulateAndGet` for lock-free exponential moving average:

```java
// From ExponentiallyWeightedMovingAverage — lock-free updates
class ExponentiallyWeightedMovingAverage {
    private static final long EMPTY = -1;
    private final double alpha;
    private final AtomicLong average;

    ExponentiallyWeightedMovingAverage(final double alpha) {
        isTrueArgument("alpha >= 0.0 and <= 1.0", alpha >= 0.0 && alpha <= 1.0);
        this.alpha = alpha;
        average = new AtomicLong(EMPTY);
    }

    long addSample(final long sample) {
        // accumulateAndGet: atomic read-modify-write without locks
        return average.accumulateAndGet(sample, (avg, givenSample) -> {
            if (avg == EMPTY) {
                return givenSample;
            }
            return (long) (alpha * givenSample + (1 - alpha) * avg);
        });
    }

    long getAverage() {
        long average = this.average.get();
        return average == EMPTY ? 0 : average;
    }
}
```

### AtomicInteger for Thread-Safe Naming

```java
// From DaemonThreadFactory — AtomicInteger for unique thread/pool names
public class DaemonThreadFactory implements ThreadFactory {
    private static final AtomicInteger POOL_NUMBER = new AtomicInteger(1);
    private final AtomicInteger threadNumber = new AtomicInteger(1);
    private final String namePrefix;

    public DaemonThreadFactory(final String prefix) {
        namePrefix = prefix + "-" + POOL_NUMBER.getAndIncrement() + "-thread-";
    }

    @Override
    public Thread newThread(final Runnable runnable) {
        Thread t = new Thread(runnable, namePrefix + threadNumber.getAndIncrement());
        t.setDaemon(true);  // Daemon threads don't prevent JVM shutdown
        return t;
    }
}
```

### AtomicBoolean for One-Time Close

```java
// From DefaultConnectionPool.StateAndGeneration — atomic close
@ThreadSafe
private final class StateAndGeneration {
    private final AtomicBoolean closed;

    boolean close() {
        return closed.compareAndSet(false, true);  // Exactly once
    }
}
```

### LongAdder for High-Contention Counters

```java
// From DefaultConnectionPool.PinnedStatsManager — LongAdder for concurrent stats
private static final class PinnedStatsManager {
    private final LongAdder numPinnedToCursor = new LongAdder();
    private final LongAdder numPinnedToTransaction = new LongAdder();

    void increment(final Connection.PinningMode pinningMode) {
        switch (pinningMode) {
            case CURSOR:
                numPinnedToCursor.increment();
                break;
            case TRANSACTION:
                numPinnedToTransaction.increment();
                break;
        }
    }
}
```

**Why LongAdder over AtomicLong?** `LongAdder` maintains internal striped cells to reduce contention. When many threads increment concurrently, it outperforms `AtomicLong` significantly. Use for write-heavy counters where the exact value is only needed occasionally.

---

## CountDownLatch for Phase Coordination

### Phase-Based Server Selection

The driver uses `CountDownLatch` with `AtomicReference` to coordinate between the server selection thread and the monitoring thread:

```java
// From BaseCluster — CountDownLatch for topology change notification
abstract class BaseCluster implements Cluster {
    private final AtomicReference<CountDownLatch> phase =
        new AtomicReference<>(new CountDownLatch(1));

    @Override
    public ServerTuple selectServer(final ServerSelector serverSelector, ...) {
        while (true) {
            CountDownLatch currentPhaseLatch = phase.get();
            ClusterDescription currentDescription = description;

            ServerTuple serverTuple = createCompleteSelectorAndSelectServer(...);
            if (serverTuple != null) {
                return serverTuple;
            }
            // Wait for a topology change
            heartbeatLimitedTimeout.awaitOn(currentPhaseLatch,
                () -> "waiting for a server that matches " + serverSelector);
        }
    }

    // Called when topology changes — creates a new latch, counts down the old one
    private void updatePhase() {
        withLock(() -> phase.getAndSet(new CountDownLatch(1)).countDown());
    }
}
```

**How it works:** Each topology change creates a **new** latch and counts down the **old** one. Server selection threads waiting on the old latch wake up and re-evaluate. This avoids missed signals — if the topology changes between checking and waiting, the latch is already counted down.

### CountDownLatch for Async-to-Sync Bridge

```java
// From FutureAsyncCompletionHandler — bridging async to sync
class FutureAsyncCompletionHandler<T> implements AsyncCompletionHandler<T> {
    private final CountDownLatch latch = new CountDownLatch(1);
    private volatile T result;
    private volatile Throwable error;

    @Override
    public void completed(@Nullable final T result) {
        this.result = result;
        latch.countDown();  // Signal completion
    }

    @Override
    public void failed(final Throwable t) {
        this.error = t;
        latch.countDown();  // Signal even on failure
    }

    private T get(final String prefix) throws IOException {
        try {
            latch.await();  // Block until async operation completes
        } catch (InterruptedException e) {
            throw interruptAndCreateMongoInterruptedException(
                prefix + " the AsynchronousSocketChannelStream failed", e);
        }
        if (error != null) {
            // Re-throw the async error on the calling thread
            if (error instanceof IOException) throw (IOException) error;
            if (error instanceof MongoException) throw (MongoException) error;
            throw new MongoInternalException(prefix + " failed", error);
        }
        return result;
    }
}
```

**Why `volatile` + `CountDownLatch`?** The `CountDownLatch` provides the happens-before guarantee for the `volatile` writes. When `latch.await()` returns, the `result`/`error` values are guaranteed visible.

---

## Thread Safety Annotations

### Documenting Thread Safety Contracts

The driver uses annotations to communicate thread safety expectations:

```java
// From DefaultConnectionPool — class-level @ThreadSafe
@ThreadSafe
final class DefaultConnectionPool implements ConnectionPool { ... }

// From DefaultSdamServerDescriptionManager — all access is cluster-locked
@ThreadSafe
final class DefaultSdamServerDescriptionManager
    implements SdamServerDescriptionManager {

    private volatile ServerDescription description;

    @Override
    public void monitorUpdate(final ServerDescription candidateDescription) {
        cluster.withLock(() -> {
            // All state mutations happen inside the cluster lock
            updateDescription(candidateDescription);
        });
    }
}

// From DefaultServerMonitor — @ThreadSafe on the class
@ThreadSafe
class DefaultServerMonitor implements ServerMonitor {
    /**
     * Must be guarded by {@link #lock}.
     */
    @Nullable
    private RoundTripTimeMonitor roundTripTimeMonitor;
    // ...
}
```

**Annotation contract:**
- `@ThreadSafe` — safe for concurrent use, callers don't need external synchronization
- `@NotThreadSafe` — not safe for concurrent use, used for builders, iterators
- `@GuardedBy("lock")` (Javadoc-level) — field access requires holding the named lock

---

## ReadWriteLock for Read-Heavy Workloads

### StampedLock as ReadWriteLock

The driver uses `StampedLock.asReadWriteLock()` in the connection pool's state management:

```java
// From DefaultConnectionPool.StateAndGeneration — StampedLock as ReadWriteLock
@ThreadSafe
private final class StateAndGeneration {
    private final ReadWriteLock lock;
    private volatile boolean paused;
    private final AtomicBoolean closed;
    private volatile int generation;

    StateAndGeneration() {
        lock = new StampedLock().asReadWriteLock();
        paused = true;
        closed = new AtomicBoolean();
    }

    // Write lock for state changes
    boolean pauseAndIncrementGeneration(@Nullable final Throwable cause) {
        return withLock(lock.writeLock(), () -> {
            if (!paused) {
                paused = true;
                pool.pause(() -> new MongoConnectionPoolClearedException(serverId, cause));
            }
            generation++;
            // ...
        });
    }

    // Read lock for checking state
    boolean throwIfClosedOrPaused() {
        if (closed.get()) {
            throw pool.poolClosedException();
        }
        if (paused) {
            withLock(lock.readLock(), () -> {    // Read lock — allows concurrent checks
                if (paused) {
                    throw new MongoConnectionPoolClearedException(serverId, cause);
                }
            });
        }
        return false;
    }
}
```

**Why StampedLock?** `StampedLock.asReadWriteLock()` provides better throughput than `ReentrantReadWriteLock` for read-heavy scenarios. The state check (`throwIfClosedOrPaused`) is called on every connection checkout — far more often than state changes.

---

## Thread Pool Management

### Daemon Thread Pools

The driver always uses daemon threads to prevent blocking JVM shutdown:

```java
// From BackgroundMaintenanceManager — scheduled daemon thread pool
private final class BackgroundMaintenanceManager implements AutoCloseable {
    @Nullable
    private final ScheduledExecutorService maintainer;

    private BackgroundMaintenanceManager() {
        maintainer = Executors.newSingleThreadScheduledExecutor(
            new DaemonThreadFactory("MaintenanceTimer"));
    }

    void start() {
        cancellationHandle = maintainer.scheduleAtFixedRate(
            DefaultConnectionPool.this::doMaintenance,
            settings.getMaintenanceInitialDelay(MILLISECONDS),
            settings.getMaintenanceFrequency(MILLISECONDS), MILLISECONDS);
    }

    @Override
    public void close() {
        if (maintainer != null) {
            maintainer.shutdownNow();  // Clean shutdown
        }
    }
}
```

### Async Work Manager with BlockingQueue

```java
// From AsyncWorkManager — single worker thread consuming tasks
private static class AsyncWorkManager implements AutoCloseable {
    private volatile State state;
    private volatile BlockingQueue<Task> tasks;
    private final Lock lock;
    @Nullable
    private ExecutorService worker;

    void enqueue(final Task task) {
        boolean closed = withLock(lock, () -> {
            if (initUnlessClosed()) {         // Lazy initialization under lock
                tasks.add(task);
                return false;
            }
            return true;
        });
        if (closed) {
            task.failAsClosed();              // Fail fast if pool is closed
        }
    }

    private boolean initUnlessClosed() {
        if (state == State.NEW) {
            worker = Executors.newSingleThreadExecutor(
                new DaemonThreadFactory("AsyncGetter"));
            worker.execute(() -> workerRun());
            state = State.INITIALIZED;
        } else if (state == State.CLOSED) {
            return false;
        }
        return true;
    }

    @Override
    public void close() {
        withLock(lock, () -> {
            if (state != State.CLOSED) {
                state = State.CLOSED;
                if (worker != null) {
                    worker.shutdownNow();     // Interrupt the worker
                }
            }
        });
    }
}
```

**Key patterns:**
- Lazy initialization — worker thread created on first `enqueue`, not at construction
- `shutdownNow()` on close — interrupts the blocked `take()` call
- Remaining tasks failed after close — ensures no task is silently dropped

---

## Cluster Lock Pattern

### Scoped Locking via Interface

The driver uses `Cluster.withLock()` to ensure all topology updates happen under the cluster lock:

```java
// From Cluster interface — lock scope for topology updates
public interface Cluster extends Closeable {
    void withLock(Runnable action);
    // ...
}

// From DefaultSdamServerDescriptionManager — all mutations under cluster lock
@ThreadSafe
final class DefaultSdamServerDescriptionManager
    implements SdamServerDescriptionManager {

    private volatile ServerDescription description;

    @Override
    public void monitorUpdate(final ServerDescription candidateDescription) {
        cluster.withLock(() -> {
            if (TopologyVersionHelper.newer(
                    description.getTopologyVersion(),
                    candidateDescription.getTopologyVersion())) {
                return;  // Stale update — discard
            }
            // Pool ready BEFORE updating description (prevents using paused pool)
            if (ServerTypeHelper.isDataBearing(candidateDescription.getType())) {
                connectionPool.ready();
            }
            updateDescription(candidateDescription);
            // Pool invalidate AFTER updating description
            if (candidateDescription.getException() != null) {
                connectionPool.invalidate(candidateDescription.getException());
            }
        });
    }
}
```

**Why this ordering matters:** `connectionPool.ready()` is called **before** `updateDescription`, and `connectionPool.invalidate()` **after**. This ensures a paused pool is never exposed through an updated description. The cluster lock makes this ordering atomic.

---

## Modern Java (21/25): Virtual Threads

### When to Use Virtual Threads

```java
// Perfect for I/O-bound tasks (HTTP, DB, file I/O)
try (ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor()) {
    for (Request request : requests) {
        executor.submit(() -> callExternalApi(request));
    }
}

// Not beneficial for CPU-bound tasks
// Use platform threads / ForkJoinPool instead
```

**Rule of thumb**: If your app never has 10,000+ concurrent tasks, virtual threads may not provide significant benefit.

### Java 25: Synchronized Pinning Fixed

In Java 21-23, virtual threads became "pinned" when entering `synchronized` blocks with blocking operations. **Java 25 fixes this** (JEP 491).

```java
// In Java 21-23: Could cause pinning
synchronized (lock) {
    blockingIoCall();  // Virtual thread pinned to carrier
}

// In Java 25: No longer an issue
// But the driver uses ReentrantLock for explicit control anyway
```

**The driver's approach**: The driver uses `ReentrantLock` instead of `synchronized` throughout its connection and pooling code. This was a forward-looking decision that also avoids the pinning issue.

### ScopedValue Over ThreadLocal

```java
// ThreadLocal problematic with virtual threads
private static final ThreadLocal<User> currentUser = new ThreadLocal<>();

// ScopedValue (Java 21+ preview, improved in 25)
private static final ScopedValue<User> CURRENT_USER = ScopedValue.newInstance();

ScopedValue.where(CURRENT_USER, user).run(() -> {
    // CURRENT_USER.get() available here and in child virtual threads
    processRequest();
});
```

### Structured Concurrency (Java 25 Preview)

```java
// Structured concurrency - tasks tied to scope lifecycle
try (var scope = new StructuredTaskScope.ShutdownOnFailure()) {
    Subtask<User> userTask = scope.fork(() -> fetchUser(id));
    Subtask<Orders> ordersTask = scope.fork(() -> fetchOrders(id));

    scope.join();            // Wait for all
    scope.throwIfFailed();   // Propagate exceptions

    return new Profile(userTask.get(), ordersTask.get());
}
// All subtasks automatically cancelled if scope exits
```

---

## Classic Concurrency Issues

### Race Conditions: Check-Then-Act

```java
// BAD: Race condition
if (!map.containsKey(key)) {
    map.put(key, computeValue());  // Another thread may have added it
}

// GOOD: Atomic operation
map.computeIfAbsent(key, k -> computeValue());

// BAD: Race condition with counter
if (count < MAX) {
    count++;  // Read-check-write is not atomic
}

// GOOD: Atomic counter
AtomicInteger count = new AtomicInteger();
count.updateAndGet(c -> c < MAX ? c + 1 : c);
```

### Non-Atomic long/double

```java
// BAD: 64-bit read/write is non-atomic on 32-bit JVMs
private long counter;

public void increment() {
    counter++;  // Not atomic!
}

// GOOD: Use AtomicLong (as the driver does)
private AtomicLong counter = new AtomicLong();

// GOOD: Or volatile (for single-writer scenarios)
private volatile long counter;
```

### Double-Checked Locking

```java
// BAD: Broken without volatile
private static Singleton instance;

public static Singleton getInstance() {
    if (instance == null) {
        synchronized (Singleton.class) {
            if (instance == null) {
                instance = new Singleton();  // May be seen partially constructed
            }
        }
    }
    return instance;
}

// GOOD: The driver uses volatile + lock check (StateAndGeneration.ready())
// See the ReadWriteLock section for a real example

// GOOD: Holder class idiom
private static class Holder {
    static final Singleton INSTANCE = new Singleton();
}
public static Singleton getInstance() {
    return Holder.INSTANCE;
}
```

### Deadlocks: Lock Ordering

```java
// BAD: Potential deadlock
// Thread 1: lock(A) -> lock(B)
// Thread 2: lock(B) -> lock(A)

public void transfer(Account from, Account to, int amount) {
    synchronized (from) {
        synchronized (to) { /* Transfer logic */ }
    }
}

// GOOD: Consistent lock ordering
public void transfer(Account from, Account to, int amount) {
    Account first = from.getId() < to.getId() ? from : to;
    Account second = from.getId() < to.getId() ? to : from;

    synchronized (first) {
        synchronized (second) { /* Transfer logic */ }
    }
}
```

---

## Thread-Safe Collections

### Choose the Right Collection

| Use Case | Wrong | Right |
|----------|-------|-------|
| Concurrent reads/writes | `HashMap` | `ConcurrentHashMap` |
| Frequent iteration | `ConcurrentHashMap` | `CopyOnWriteArrayList` |
| Producer-consumer | `ArrayList` | `BlockingQueue` |
| Sorted concurrent | `TreeMap` | `ConcurrentSkipListMap` |
| Lock-free queue | `LinkedList` | `ConcurrentLinkedDeque` |

### The Driver's Collection Choices

```java
// From ConcurrentPool — ConcurrentLinkedDeque for lock-free access
private final Deque<T> available = new ConcurrentLinkedDeque<>();

// From BaseCluster — ConcurrentLinkedDeque for wait queue
private final Deque<ServerSelectionRequest> waitQueue = new ConcurrentLinkedDeque<>();

// From AsyncWorkManager — BlockingQueue for producer-consumer
private volatile BlockingQueue<Task> tasks = new LinkedBlockingQueue<>();
```

### ConcurrentHashMap Pitfalls

```java
// BAD: Non-atomic compound operation
if (!map.containsKey(key)) {
    map.put(key, value);
}

// GOOD: Atomic
map.putIfAbsent(key, value);
map.computeIfAbsent(key, k -> createValue());

// BAD: Nested compute can deadlock
map.compute(key1, (k, v) -> {
    return map.compute(key2, ...);  // Deadlock risk!
});
```

---

## Concurrency Review Checklist

### High Severity (Likely Bugs)
- [ ] No check-then-act on shared state without synchronization
- [ ] No `synchronized` calling external/unknown code (deadlock risk)
- [ ] `volatile` present for double-checked locking
- [ ] Non-volatile fields not read in loops waiting for updates
- [ ] `ConcurrentHashMap.compute()` doesn't call other map operations
- [ ] Lock `unlock()` always in `finally` block (or using `Locks.withLock()`)

### Medium Severity (Potential Issues)
- [ ] Thread pools properly sized and named (use `DaemonThreadFactory`)
- [ ] `ExecutorService` properly shut down (use `shutdownNow()`)
- [ ] `CountDownLatch` / `Condition` handle `InterruptedException`
- [ ] Thread-safe collections used for shared data
- [ ] State transitions protected by lock, state reads via `volatile`
- [ ] Lock ordering documented for nested locks

### Modern Patterns (Java 21/25)
- [ ] Virtual threads used for I/O-bound concurrent tasks
- [ ] `ScopedValue` considered over `ThreadLocal`
- [ ] Structured concurrency for related subtasks
- [ ] `ReentrantLock` preferred over `synchronized` (avoids pinning in Java 21-23)

### Documentation
- [ ] Thread safety documented on shared classes (`@ThreadSafe`, `@NotThreadSafe`)
- [ ] `@GuardedBy` or Javadoc documents which lock guards which field
- [ ] Each `volatile` usage justified

---

## Analysis Commands

```bash
# Find synchronized blocks
grep -rn "synchronized" --include="*.java"

# Find volatile fields
grep -rn "volatile" --include="*.java"

# Find thread pool creation
grep -rn "Executors\.\|ThreadPoolExecutor\|ExecutorService" --include="*.java"

# Find Lock usage
grep -rn "ReentrantLock\|StampedLock\|ReadWriteLock" --include="*.java"

# Find CountDownLatch/Semaphore
grep -rn "CountDownLatch\|Semaphore" --include="*.java"

# Find ThreadLocal (consider ScopedValue in Java 21+)
grep -rn "ThreadLocal" --include="*.java"

# Find potential check-then-act races on ConcurrentHashMap
grep -rn "containsKey\|contains(" --include="*.java" | grep -i "concurrent"
```

---

## Related References

- [Performance Review Guide](performance.md) - Lock-free atomics, object pooling
- [Architecture Review Guide](architecture.md) - Module boundaries and thread safety
- [SOLID Principles](solid-principles.md) - Interface design for concurrent components
