# goal · capstone.data-intelligence.foundation

- **State:** building
- **Task:** demo-dataset
- **Branch:** demo-dataset

## Tasks

1. [x] chunks
2. [x] protocol
3. [x] events
4. [x] stack
5. [x] athena-mapping
6. [ ] demo-dataset

## Task brief · demo-dataset

**Problem**

The presentation and `.showcase` need a dataset that loads into Mikoshi the same way every time.
It should be an organization's file share organized by context, plus a tour of the platform's
capabilities. Today nothing defines that dataset, collects its files, or builds its context tree
repeatably. Mikoshi's contexts API exists, but its items API doesn't yet. So this task defines
and checks the whole dataset, collects and verifies every file, and builds only the context tree.
Items, records, and references load in `.showcase`.

**Behaviors**

1. One command, `dataset <group> <verb>`, runs every dataset operation. With no arguments it
   lists each command with its one-line summary. An unknown command or usage error writes to
   stderr and exits 2.
2. One JSON definition declares the dataset in three top-level explicit contexts:
   - `tour`: 10 docs-corpus files, with one context per capability. The capabilities are EUR-Lex
     in four languages including a non-Latin script; the signed 3D portfolio over 4 MiB;
     old_scans-70; 05-japanese.msg; heic; .one; and zip-in-zip.
   - The share: 27 files in five branches (psyops, operations planning, intelligence, information
     operations, admin).
   - `views`: the dataset's query contexts.
3. Each file has one entry, which lists every context path it joins. Four share files sit in
   more than one branch.
4. Each file has exactly one of these provenances:
   - URL, sha256, byte size, and credit;
   - a manual flag with how-to steps, for a file no script can download;
   - a docs-corpus path, with the sha256 from that file's v0.2.0 MANIFEST entry;
   - for an authored office file, its generator and the pinned sha256.
5. A file flagged `live` is added in the client during the presentation. There are two: Ghost
   Tape No. 10, and OPORD v2. A new version is a new entry that names the entry it supersedes
   (OPORD v2 supersedes v1). No entry changes another.
6. The definition lists the context changes made live in the client, and each must be valid
   against the tree at the point it runs.
7. The definition holds eight authored JSON records. Each annotates one or more files and lists
   its context paths.
8. Every query-context filter follows Mikoshi's filter rules: a non-empty list of AND-ed
   conditions, using only the operators and value shapes the contexts API accepts, on fields
   drawn only from `route`, `kind`, and `duration`. There are no date filters. A filter selects
   from every item, not only from those its parent covers.
9. The check, run by `mise run check`, refuses any definition where:
   - a context path doesn't resolve;
   - something sits under a query context;
   - two siblings share a name;
   - a filter is malformed;
   - a file lacks exactly one valid provenance or has a malformed sha256;
   - a `supersedes`, a record's target, or a live change names something that doesn't exist.

   Each refusal names the entry that broke the rule. The check writes nothing. It also
   shellchecks every dataset script, found by shebang rather than by extension.
10. A PEP 723 uv script generates the four authored office files (docx, pptx, xlsx) into the
    gitignored cache, using python-docx, python-pptx, and openpyxl. It fixes the core properties
    and zip timestamps, so every run is byte-identical and matches its pinned sha256.
11. Fetch fills the gitignored cache, keyed by sha256:
    - It downloads URL files, copies docs-corpus files from the checkout `DOCS_CORPUS` names, and
      runs the generator for authored files.
    - It skips any file already cached.
    - It refuses, and doesn't keep, a file whose sha256 or size doesn't match.
    - It lists each missing manual file with its how-to steps and exits non-zero.
12. Load builds the context tree through Mikoshi's contexts API, at the base URL the environment
    names:
    - It matches contexts by name path, creates the missing ones, and leaves existing ones alone,
      so a second load creates nothing.
    - It skips contexts that are only made live.
    - It reports a context that exists with a different kind or filter and exits non-zero. It
      never edits a context.
13. Reset deletes the dataset's three top-level contexts through the API, confirming each with
    the descendant count the API returns. It leaves every other context alone, and the next load
    rebuilds the tree.
14. A live run passes against Mikoshi on the host, using the root stack's PostgreSQL
    (`MIKOSHI_DATABASE_PORT=5442`): load, load again with no change, reset, load.

**Test seams**

- The `dataset` command, run by the tests against a stub of Mikoshi's contexts API, and against
  fixture definitions for the check.
- The live run against Mikoshi's contexts API.

**Slices**

1. Dispatcher: `dataset` lists commands, routes them, and refuses unknown ones. The check
   shellchecks by shebang and runs the tests.
2. Definition and check: the definition's structure, and a refusal for each rule, with fixtures.
3. Dataset: the full tour, share, views, provenance, live entries, and eight records, passing the
   check.
4. Generator: the four office files, byte-reproducible against their pins.
5. Fetch: the cache filled and verified, with manual files reported.
6. Load: the tree converges by name path against the stub.
7. Reset: the dataset's subtrees deleted against the stub, with other contexts kept.
8. Live run: load, load, reset, load against Mikoshi on the root stack.

**Out of scope**

- Loading items, records, and references, and the live adds (`.showcase` `demo-load`).
- Filter evaluation and field-name checks (`.mikoshi` `items`).
- Acquiring manual files (the architect).
- Date filters.
- The final review of the share, tour, and authored lists (`.showcase`).
- Bunrei processing, search, and the presentation.

**Door**

Two-way. All work is in the root. Fetched files stay in a gitignored cache and are never
committed. Load and reset touch only a local Mikoshi database that can be dropped.

## Progress

slices 0/8 committed · standards — · spec — · editor —

## Decisions

- capstone: contracts (`chunks`, `protocol`, `events`) are designed here in `.foundation`; Bunrei and Mikoshi build against them, and a task that reads one opens its summary with "Waits on".
- capstone: `.showcase` follows this goal on this root; its `acceptance` waits on `.torii`, `.bunrei`, and `.mikoshi` having synced.
- protocol: Queries and Commands are HTTP through go-web-sdk; go-messaging (NATS) carries Events only. Rejected: NATS request/reply, offered only through `Broker.Conn`, outside go-messaging's standard tier.
- protocol: the upload is draft-ietf-httpbis-resumable-upload-16, implemented on net/http in go-web-sdk's base module by `.bunrei` `upload` before `api`, at go-web-sdk's next minor (shared with `.bunrei` `sse-writer`: whichever runs first takes it). Rejected: tus 1.0.0, the draft's frozen predecessor; S3 multipart; tusd as a dependency (an interop peer only).
- protocol: the browser upload client is web-app-sdk's, built by `.mikoshi` `browser-upload` before `items`.
- protocol: go-web-sdk and web-app-sdk pin the draft revision under rolling currency, read from datatracker. Rejected: a backlog goal, and a watch-register entry, which is read by hand and never surfaces at PLAN.
- events: extraction deltas are not events. Rejected: `bunrei.job.progress` on JetStream (an ack per publish, and retention of every delta).
- events: a job's `correlationid` is the job ID Bunrei mints. Rejected: a caller-supplied correlation field on Submit and CompleteUpload (it reopens the protocol, and Bunrei never knows its caller).
- events: lineage and layer are extension attributes. Rejected: lineage in each event's data.
- events: context activity is Mikoshi's per-command events. Rejected: a separate `mikoshi.context.activity` event (a second event per command, against messaging.md).
- events: `dataschema` is a URN on the wire version. Rejected: a link to the shapes at a release tag (it changes every release while the shape doesn't).
- events: the result-batch cap is a Bunrei setting. Rejected: a fixed value in the note.
- stack: services reach SeaweedFS through go-storage's `s3` provider. Rejected as the object
  store: Azurite (`docproc/storage` untested against it), MinIO (no workspace repo tests against
  it).
- stack: the root's pgvector Dockerfile is a copy of Mikoshi's, pinned under the root's currency.
  Rejected: building from Mikoshi's checkout.
- stack: each service has its own PostgreSQL server. Rejected: one server with a database per
  service.
- athena-mapping: `.mikoshi` builds the space switch (`pgvector-types` on sqlate, then
  `space-switch`, after `ingest`). Rejected: switches after the capstone; a sqlate goal after it.
- athena-mapping: document-scope and video-timeline extraction are built in docinfer by `.bunrei`
  `document-extraction` before `api`. Rejected: per-source only, with a backlog goal.
- athena-mapping: the capstone runs vision transcription; the OCR spike asks whether an OCR tier
  is needed at all, excludes olmOCR by model origin, and is not a capstone deliverable.
- athena-mapping: the Athena design review is stated only in the `athena` note; it runs outside
  the workspace with the Athena team. Rejected: a backlog entry.

- demo-dataset: `.foundation` builds the definition, the check, fetch, and the context-tree
  load. Items, records, and references load in `.showcase` `demo-load`. Rejected: loading items
  before `.mikoshi` `items` exists.
- demo-dataset: the share is the main body, beside `tour` and `views`, as three sibling top-level
  explicit contexts. Rejected: query contexts inside the share's branches; limiting a filter to
  its parent's coverage.
- demo-dataset: query-context filter fields are `route`, `kind`, and `duration`, all extracted
  from the file. Rejected: date filters, because PDF CreationDate is the export or scan date.
- demo-dataset: one entry per file, listing its context paths. A version is a new entry that
  supersedes the old. Live files and live context changes are declared in the definition and
  made in the client.
- demo-dataset: `dataset/` holds the JSON, and the gitignored `dataset/.cache/` is keyed by
  sha256. Rejected: `demo/` and `seeds/`.
- demo-dataset: a bash, curl, and jq `dataset <group> <verb>` suite, laid out like ai-hosting's
  `bin/`. Rejected: Hurl, go-database's Seeder, a Go program.
- demo-dataset: a rerun converges by name path, and `tree reset` deletes through the API.
  Rejected: `stack:reset`, which drops Bunrei's cache.
- demo-dataset: the office files come from a byte-reproducible PEP 723 uv script, with sha256
  pinned. Rejected: pandoc, LibreOffice, hand-written OOXML.
- demo-dataset: a looser admission rule (files are never committed). Provenance is url, sha256,
  bytes, and credit, or manual with how-to steps, or a docs-corpus path with its v0.2.0 MANIFEST
  sha256. Rejected: docs-corpus's admission rule.
- demo-dataset: the share, tour, and authored lists are reviewed again in `.showcase`
  `demo-load`.

## Pending edits

- architecture · principles/rolling-currency.md: an implemented standard's revision, such as an IETF draft, is a covered surface, pinned and read from its publisher by currency.
- capstone-bunrei · context/README.md: "Protocol and client module" links the root's `protocol` note; "Chunked upload" links the root's `upload` note and says go-web-sdk's handler, mounted by Bunrei, serves it.
- docproc · context/bunrei.md:
  - Link the root's `protocol` and `upload` notes rather than restate them; drop OpenUpload, AppendChunk, GetUpload, and AbortUpload as Bunrei Commands, and the two open questions `protocol` settles.
  - Drop `bunrei.job.progress`, replace `sequence` with `jobsequence`, add the lineage and `layer` extensions, and link the root's `events` note for the event table, the manifest, and the batch cap.
- coordinator · roadmap/capstone.data-intelligence.mikoshi.toml:
  - Add task `event-relay`, which waits on `.bunrei` `sse-writer` and comes before `signal-flow`: Mikoshi's SSE relay of its JetStream stream to the browser, stateless per replica, its cursor the stream sequence.
  - Add task `sse-event-sequence` (repos: web-app-sdk), before `event-relay`'s client: web-app-sdk's SSE `EventSequence` adapter, released in its next minor.
- coordinator · roadmap/capstone.data-intelligence.bunrei.toml: add the go-core task `event-extensions`, which lets `Raise` set extension attributes, released in go-core's next minor (shared with `sse-codec` if they run together). `.mikoshi` `ingest`'s summary gains a "Waits on" for it.
- coordinator · docs/data-intelligence.md:
  - "Open items": drop `events`'s batch cap and `dataschema` form.
  - Record evidence 15 as decided, Mikoshi's SSE relay, linking the root's `events` note.
- coordinator · context/data-intelligence.md: mark evidence 15 decided, Mikoshi's SSE relay, linking the root's `events` note.
- capstone-mikoshi · context/goals/capstone.data-intelligence.mikoshi.md: the evidence-15 Decision points at the root's `events` note.
- capstone-mikoshi · goal record: a Decision for `items`: Mikoshi's blob storage is go-storage's
  `s3` provider against the root stack's SeaweedFS, its bucket created on start.
- coordinator · roadmap/capstone.data-intelligence.bunrei.toml: `jobs` adds Bunrei's `fnox.toml`
  and issues Bunrei's bulk Torii key with `hosting key issue`.
- coordinator · roadmap/capstone.data-intelligence.mikoshi.toml: `hybrid-search` adds Mikoshi's
  `fnox.toml` and issues its interactive Torii key.
- coordinator · context/data-intelligence.md: the root's stack sentence becomes "the compose stack
  (NATS with JetStream, a PostgreSQL with pgvector per service, and SeaweedFS), against Torii on
  gb10-2, which Bunrei and Mikoshi join in `.showcase` `services`".
- coordinator · docs/data-intelligence.md:
  - "Athena onto Bunrei" becomes a link to the root's `athena` note.
  - "Open items": drop `athena-mapping`'s typed cells for `sparse_rows`.
  - "Embedding spaces": a model change adds a space and fills it by resubmitting the items through
    Bunrei, while the active space serves until the new one is ready, linking the root's `chunks`
    note, "Embedding space", in place of "re-embeds the stored chunks (blue/green, switched after a
    recall evaluation)".
- coordinator · context/data-intelligence.md: its pointer to "Athena onto Bunrei" links the
  root's `athena` note.
- coordinator · roadmap/capstone.data-intelligence.mikoshi.toml:
  - Add sqlate to `repos`.
  - After `ingest`, add `pgvector-types` (repos: sqlate): every pgvector type and metric, with
    live tests per type, released as `postgres/pgvector/v0.2.0`.
  - Then add `space-switch`, which waits on `pgvector-types`: status, the active marker,
    re-embed by resubmission, rollback, and the per-space type migration.
  - `hybrid-search`'s summary gains "reads the active space".
- coordinator · roadmap/capstone.data-intelligence.bunrei.toml: before `api`, add
  `document-extraction` (repos: docinfer): document-scope and video-timeline extraction at
  docinfer's next minor.
- coordinator · roadmap/experiment.ocr.spike-scanned-documents.toml and docs/ai-strategy.md:
  reframe the spike as "is an OCR tier needed at all beside self-hosted vision" (Tesseract
  against Gemma 4 and a dense vision model; olmOCR's model dropped for model origin, the
  olmOCR-bench dataset kept; measure fidelity, cost, latency, CPU throughput, and boxes and
  confidence). State that it is not part of the capstone deliverable.
- coordinator · roadmap/capstone.data-intelligence.showcase.toml: add `demo-load` after
  `services` and before `presentation`, with the summary "Waits on: `.mikoshi` `items` and
  `ingest`." It loads the items, authored records, and references into the tree that `.foundation`
  `demo-dataset` builds, and reviews the share, tour, and authored lists.
- coordinator · roadmap/capstone.data-intelligence.mikoshi.toml: `items`'s projection declares
  `route` and `kind` (docproc's sniffed content type) and `duration` as filter fields, which the
  contexts domain checks filter field names against.
- coordinator · roadmap/capstone.data-intelligence.foundation.toml: the `demo-dataset` summary
  names the share from public government and open-source sources, the docs-corpus tour, the
  authored records, and the `views` query contexts.
