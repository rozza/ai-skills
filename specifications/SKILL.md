---
name: specifications
description: Look up and summarize MongoDB driver specifications from the official mongodb/specifications repo. Use this skill when the user wants to read, review, understand, or get an overview of a MongoDB specification — e.g., "what does the CRUD spec say about find?", "summarize the retryable writes spec", or "/specifications client-side-encryption". Also trigger when the user references a MongoDB spec by name during driver development work.
disable-model-invocation: true
---

# specifications: MongoDB Specification Lookup & Summary

Invoked as `/specifications` (interactive) or `/specifications <name>` (direct lookup).

Provides a human-readable summary of any MongoDB driver specification from the official
[mongodb/specifications](https://github.com/mongodb/specifications) repository.

## Step 1: Ensure Local Spec Repository

The specs live in a local checkout at `./workspace/specifications` (relative to this
skill's directory).

**If `./workspace/specifications` does not exist:**

```bash
git clone --depth 1 https://github.com/mongodb/specifications.git ./workspace/specifications
```

**If it already exists**, pull latest:

```bash
git -C ./workspace/specifications pull --ff-only
```

If the pull fails (e.g., detached HEAD), just carry on with what's there — the specs
don't change frequently enough to block the user over a stale checkout.

## Step 2: Identify the Specification

List the available specs by scanning `./workspace/specifications/source/`:

```bash
ls ./workspace/specifications/source/
```

Specs appear as either top-level `.md`/`.rst` files or as directories (which contain
a primary `.md` or `.rst` file inside).

### If the user provided a name (e.g., `/specifications crud`)

Match their input against the available spec names. Use fuzzy/substring matching:

- Exact match → use it
- Substring match (e.g., `backpressure` → `client-backpressure`) → if there's exactly
  one match, use it; if multiple, show them and ask the user to pick
- No match → list the closest options and ask the user to choose

### If no name was provided (`/specifications`)

List all available specifications grouped by category and ask the user which one
they'd like to review. Group them logically:

- **Connection & Topology**: connection-monitoring-and-pooling, server-discovery-and-monitoring, load-balancers, etc.
- **CRUD & Operations**: crud, find_getmore_killcursors_commands, run-command, bulk-write, etc.
- **Resilience**: retryable-reads, retryable-writes, transactions, sessions, etc.
- **Security**: auth, client-side-encryption, etc.
- **Observability**: command-logging-and-monitoring, logging, server-discovery-and-monitoring, etc.
- **Data Types & Encoding**: bson-binary-encrypted, bson-decimal128, bson-corpus, compression, etc.
- **Other**: anything that doesn't fit neatly above

## Step 3: Check the Summary Cache

Summaries are cached in `./workspace/cache/` (relative to this skill's directory) to
avoid re-reading and re-summarizing specs that haven't changed. Each cached summary is
a markdown file named `<spec-name>.md` with a commit hash on the first line.

**How caching works:**

1. Get the latest commit hash for the spec's primary file:
   ```bash
   git -C ./workspace/specifications log -1 --format="%H" -- source/<spec-path>
   ```
   For directory specs, use the primary `.md`/`.rst` file path (e.g.,
   `source/crud/crud.md`). For top-level file specs, use the file directly.

2. Check if a cached summary exists at `./workspace/cache/<spec-name>.md`.

3. If the cache file exists, read its first line — it contains the commit hash from
   when the summary was generated (format: `<!-- commit: <hash> -->`).

4. **Cache hit** — if the hashes match, the spec hasn't changed. Read and return the
   cached summary (skip everything after the first line's hash comment). Done.

5. **Cache miss** — if the file doesn't exist or the hashes differ, proceed to Step 4
   to generate a fresh summary. If the hashes differ, also read the diff to understand
   what changed:
   ```bash
   git -C ./workspace/specifications diff <old-hash>..<new-hash> -- source/<spec-path>
   ```
   Use this diff to focus your summary update — you don't necessarily need to re-read
   the entire spec if the changes are small. For large diffs or if the old summary
   doesn't exist, read the full spec.

## Step 4: Read the Specification (on cache miss)

Locate the primary spec file within the matched directory or file:

1. If the spec is a directory, look for the main file — typically `<spec-name>.md` or
   `<spec-name>.rst` inside it. Some directories contain multiple `.md` files (e.g.,
   CRUD has `crud.md` and `bulk-write.md`). Read the primary one first; mention the
   others in case the user wants those too.
2. If the spec is a top-level file, read it directly.

These files can be very long (3,000–8,000+ lines). Read the full file — you need to
understand the complete specification to produce an accurate summary.

## Step 5: Summarize the Specification

Produce a clear, human-readable summary using the template below. The goal is to give
a driver developer everything they need to understand the spec's intent and key
requirements without reading thousands of lines of specification text.

Adapt the template to fit the spec — not every section will apply to every spec, and
some specs may warrant additional sections. Use your judgment.

---

### Summary Template

```
# [Spec Name] — Specification Summary

## Purpose
One or two sentences: what problem does this spec solve and why does it exist?

## Key Concepts
Define the essential terms and abstractions introduced by the spec.
Keep it brief — just enough that the rest of the summary makes sense.

## How It Works
The core behavior described by the spec, in plain language. Cover the main
flow: what happens when, what the driver is expected to do, and how the
pieces fit together. Use short paragraphs or bullet points.

## Driver Requirements
The important MUST/SHOULD/MAY rules that a driver implementer needs to
know. Group related requirements together. Don't list every single one —
focus on the ones that shape implementation decisions.

## API Surface
If the spec defines user-facing API (classes, methods, options), summarize
it here. Include key method signatures or option names, but skip exhaustive
parameter lists — point the reader to the full spec for details.

## Error Handling
How the spec says to handle failures, edge cases, and error conditions.

## Testing Notes
If the spec includes a test suite or specific test requirements, briefly
describe what's covered and where the test files live.

## Related Specifications
List any specs that this one depends on or interacts with (e.g., "Builds
on the Server Discovery and Monitoring spec for topology events").

## Changelog Highlights
If the spec has a notable changelog, mention the most recent or impactful
changes (last 2-3 entries). This helps developers know if something changed
recently that might affect their implementation.
```

---

Omit any section that doesn't apply (e.g., a spec with no API surface
shouldn't include an empty "API Surface" section). If the spec has companion
files in its directory (like `bulk-write.md` alongside `crud.md`), mention
them at the end so the user knows they can ask for those too.

## Step 6: Save to Cache

After generating or updating a summary, write it to `./workspace/cache/<spec-name>.md`.
The first line must be the commit hash comment so future lookups can check freshness:

```
<!-- commit: <hash> -->
# [Spec Name] — Specification Summary

## Purpose
...
```

Create the `./workspace/cache/` directory if it doesn't exist. This cache persists
across sessions — the next time someone asks about the same spec, it'll be served
instantly if the spec hasn't been updated upstream.

---

## Workspace Convention

All temporary output (evals, benchmarks, scratch files, the cloned specs repo, and
the summary cache) goes in the `workspace/` directory inside this skill's directory.
The `*/workspace/` pattern is gitignored.
