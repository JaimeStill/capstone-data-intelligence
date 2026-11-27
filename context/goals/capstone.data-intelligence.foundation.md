# goal · capstone.data-intelligence.foundation

- **State:** building
- **Task:** athena-mapping
- **Branch:** athena-mapping

## Tasks

1. [x] chunks
2. [x] protocol
3. [x] events
4. [x] stack
5. [ ] athena-mapping
6. [ ] demo-dataset

## Task brief · athena-mapping

**Problem**

`~/s2va/athena` runs its own ingest: Tesseract, Whisper, a summary chain, Arctic embeddings with
a document-name header, its own embedding spaces, and in-place re-embedding. Bunrei and Mikoshi
replace that layer. Nothing yet states how Athena's ingest lands on Bunrei's API, what stays
Athena's, or where the capstone falls short of Athena.

Mapping Athena exposed four gaps in the root's contracts, and the capstone must close them:

- An embedding space has no lifecycle: no status, no active marker, no re-embed rule.
- A space has no pgvector type.
- Extraction is per source text only, with no document or video-timeline scope.
- The coordinator's facts about Athena are stale, and its `sparse_rows` open item is moot.

**Behaviors**

1. `athena.md` opens by saying it states the capstone's state against Athena as suggestions.
   Athena may not adopt them, and a design review with the Athena team, outside the workspace,
   aligns the two sets of goals.
2. `athena.md` states the principle that each service owns its own data. Athena is a second
   consumer of Bunrei, relies only on Bunrei's API (Commands, Queries, events, GetOutput), never
   on Bunrei's state, and keeps its own tables.
3. `athena.md` holds one central table that maps Bunrei's fields (the Job, `bunrei.job.started`'s
   resolved Profile, and a result batch's parts, sources and chunks) onto the columns of Athena's
   `chunks`. Each row says where Athena's key or column differs from the chunk contract:
   - `<version>-<i>` against text SHA-256 plus chunker plus index;
   - no span column;
   - summary and processing metadata only on chunk 0;
   - a failed embedding dropped rather than stored with its error;
   - `english` tsvectors weighted by filename against `simple`.
4. `athena.md` states the move to multilingual-e5-large as a blue/green between two Athena spaces:
   - Athena resubmits every document through Bunrei under the e5 profile into a new space.
   - The Arctic space serves until the e5 space is ready and activated.
   - Athena's in-place re-embed command and its space worker's embedding role retire.
   - Athena's status and active-space setting map onto the contract's.
   - Athena's `halfvec` default ports directly to a space's type.
5. `athena.md` states that the contract stays keyed by bare chunk text. Athena's per-chunk
   document-name header is dropped (Athena measured 70% against 65% right-document-first), and
   its gain is expected back through docinfer's metadata source.
6. `athena.md` maps Whisper onto docinfer's transcription. It maps Tesseract onto docinfer's
   vision and suggests dropping Tesseract pending the reframed OCR spike, naming what Athena would
   lose: the confidence gate, reading on CPU alone, and verbatim text with no invented words.
7. `athena.md` maps Athena's document summary onto document-scope extraction, and its video
   summary and key moments onto video-timeline extraction. Both are planned in `.bunrei`
   `document-extraction`.
8. `athena.md` lists what stays Athena's, one line each:
   - regex and pattern entities, including MAC and MGRS;
   - `sparse_rows` places and dates;
   - TEI rerank;
   - the `ingest_jobs` queue;
   - the video pipeline's own work beyond extraction;
   - vault, ACL and version columns, and the `english` tsvectors;
   - document metadata and document vectors, which Athena computes through Torii's e5.
9. `athena.md` names its assumptions, one line each, and cites Athena by commit.
10. `chunks.md` "Embedding space" gains:
    - a status: building, ready or failed;
    - a single active space;
    - the re-embed rule: a new space fills while the active one serves and activates only when
      ready, re-embedding means resubmitting under the new profile, and the SQL stays Mikoshi's.
11. `chunks.md` makes a space's pgvector type (`vector`, `halfvec`, `bit` or `sparsevec`) part of
    its identity, in "Embedding space" and "Embedding". The storage shape is left for
    `.mikoshi` `pgvector-types` to prove.
12. `chunks.md` "Ownership" names `.mikoshi` `pgvector-types` and `space-switch` among the tasks a
    change reaches.
13. `protocol.md` "Profiles and extraction" states the extraction scope as planned at docinfer's
    next minor through `.bunrei` `document-extraction`: per source, once over a job's whole text,
    or a video's timeline of frames plus transcript by source time. Its Ownership names that
    task.
14. `events.md` states that `inference` also carries document and timeline extractions once
    docinfer's minor lands. The note stays within its word budget, with the detail in
    `protocol.md`.
15. `context/README.md`'s capability map lists the Athena mapping as built, linking
    `athena.md`.
16. `mise run check` passes. Every note is within its `lint-context` budget and every link
    resolves.

**Test seams**

- `mise run check`: `lint-context`, for kinds, budgets, the capability-map shape and relative
  links, and `lint-references`.
- A coherence read of `athena.md` against `chunks.md`, `protocol.md` and `events.md`, and against
  Athena at the cited commit.

**Slices**

No upgrade slices: the root's currency is current.

1. **Space lifecycle and type.** `chunks.md`, for behaviors 10–12.
2. **Extraction scope.** `protocol.md` and `events.md`, for behaviors 13–14, trimming `events.md`
   where needed to stay in budget.
3. **The Athena note.** `athena.md` and the capability-map line, for behaviors 1–9 and 15. It
   builds on the amended contracts.

**Out of scope**

- Any change to Athena, which is read only. Its migration and the design review sit outside the
  workspace.
- Code in Mikoshi, Bunrei, sqlate or docinfer. Their tasks are added by pending edits.
- The coordinator's edits themselves, which wait in the goal record until sync.
- The OCR spike, and any decision on an OCR tier.
- Executable proof of the mapping.

**Door**

Two-way. The task changes notes only and releases nothing. The amended contracts are planned
shapes that their building tasks prove or revise.

## Progress

slices 0/3 committed · standards — · spec — · editor —

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
- athena-mapping: each service owns its data; Athena relies only on Bunrei's API, never its
  state, and keeps its tables. Rejected: Athena adopting the contract's records.
- athena-mapping: a model change re-embeds by resubmitting through Bunrei into a new space,
  blue/green. Rejected: in-place re-embed, which keeps two chunkers.
- athena-mapping: embeddings stay keyed by bare chunk text; a document's name reaches search
  through the metadata source. Rejected: a per-document embed header.
- athena-mapping: a space's pgvector type (`vector`, `halfvec`, `bit`, `sparsevec`) is part of
  its identity. Rejected: type as an attribute; `vector` only.
- athena-mapping: `.mikoshi` builds the space switch (`pgvector-types` on sqlate, then
  `space-switch`, after `ingest`). Rejected: switches after the capstone; a sqlate goal after it.
- athena-mapping: document-scope and video-timeline extraction are built in docinfer by `.bunrei`
  `document-extraction` before `api`. Rejected: per-source only, with a backlog goal.
- athena-mapping: the capstone runs vision transcription; the OCR spike asks whether an OCR tier
  is needed at all, excludes olmOCR by model origin, and is not a capstone deliverable.
- athena-mapping: the Athena design review is stated only in the `athena` note; it runs outside
  the workspace with the Athena team. Rejected: a backlog entry.

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
  against Gemma 4 and a dense vision model; olmOCR dropped for model origin; measure fidelity,
  cost, latency, CPU throughput, and boxes and confidence). State that it is not part of the
  capstone deliverable.
