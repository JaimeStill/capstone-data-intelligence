# goal · capstone.data-intelligence.foundation

- **State:** building
- **Task:** protocol
- **Branch:** protocol

## Tasks

1. [x] chunks
2. [ ] protocol
3. [ ] events
4. [ ] stack
5. [ ] athena-mapping
6. [ ] demo-dataset

## Task brief · protocol

**Problem**

`.bunrei` `upload` and `api`, and `.mikoshi` `browser-upload`, `items`, and `ingest`, build against
Bunrei's protocol, which exists only as a draft in docproc's working context. That draft leaves
open the transport, the small-document size, live sources, and the upload's wire form. The goal
record leaves open which message carries the input SHA-256 and the producing profile that a result
batch lacks. Without a contract, go-web-sdk's upload handler, Bunrei's routes, and Mikoshi's
clients each decide these alone, and they can drift.

**Behaviors**

1. The root's working context holds the `protocol` contract note, which states only what Bunrei
   and its callers rely on. The upload is in its own `upload` note, which `protocol` links, so
   that each note stays within the note budget.
2. Queries and Commands go over HTTP. NATS carries only Events, which `events` designs. A refusal
   is an RFC 9457 problem.
3. `protocol` names Bunrei's Queries (GetJob, GetOutput, ListProfiles) and its Commands
   (Submit, CompleteUpload, CancelJob); an upload's offset is the upload's own HEAD. It says what
   each takes, returns, and does, and gives the nested `client` module's types (`Job`, `Profile`, `Manifest`).
   It links docinfer's types at their tags rather than restating them.
4. Submit takes a whole document up to Bunrei's small-document limit. A larger one is refused and
   goes through the upload. A retried Submit with the same idempotency ID returns the first job. A
   structured record is Submit content with media type `application/json`, and it has no Command
   of its own.
5. The small-document limit and the upload's chunk size are Bunrei settings, each defaulting to
   4 MiB, a starting point that measured performance tunes.
6. A request names a versioned processing profile, never a model. ListProfiles returns each
   profile with its resolved docinfer `Profile`. The extraction spec is docinfer's `Extract`
   (name, prompt, JSON Schema); it is optional and refused past 256 KiB marshalled.
7. The note settles the goal record's decision on the input SHA-256 and the producing profile.
   A `Job` carries the input content's SHA-256 (lowercase hex), the versioned profile name, and
   the document's file name. Each attempt's `bunrei.job.started` carries the resolved `Profile` (space and chunker), which
   `events` owes. The `chunks` note links this note for both.
8. The `upload` note pins draft-ietf-httpbis-resumable-upload-16 (2026-11-23, interop version 11)
   and cites its sections for each item below:
   - A creating POST carries Upload-Complete, Upload-Length when known, the content's media type,
     the file's SHA-256 as an RFC 9530 `Repr-Digest`, and its file name in `Content-Disposition`
     (RFC 6266), which the handler keeps with the upload.
   - The server names the upload resource in Location. It sends that in a 104 (Upload Resumption
     Supported) interim response when the request's Upload-Draft-Interop-Version matches, and in
     the 201 (Created) final response when Upload-Complete is false.
   - Each append is a PATCH of `application/partial-upload` with Upload-Offset, Upload-Complete,
     and the chunk's RFC 9530 `Content-Digest`, and no Content-Encoding.
   - A HEAD returns Upload-Offset, which is how a client resumes. A DELETE cancels the upload.
   - A wrong offset is a 409 carrying the current offset.
   - Upload-Limit announces `max-append-size` at the chunk size and `max-age` at the upload's
     expiry.
   - Appends to one upload are sequential, and the server holds that across replicas.
9. The draft has no digest section of its own, so the `upload` note cites RFC 9530 for both
   fields. It states the conversion between their base64 `sha-256` and the hex every other field
   carries. A chunk whose digest mismatches is refused without moving the offset. A whole-file
   mismatch fails the upload when it completes.
10. The `upload` note states the ownership:
    - go-web-sdk's base module holds the server handler, built on net/http behind a chunk-store
      interface, and the Go append client.
    - web-app-sdk holds the browser client.
    - Bunrei mounts the handler on its API with a store over its blob storage, and its `client`
      module wraps go-web-sdk's client.
    - Mikoshi's `items` mounts the same handler with its own store.
    - Bunrei's one upload Command is CompleteUpload, which takes the completed upload, the
      profile, and the extraction, and queues the job.
    - Each library pins the draft revision it implements under rolling currency: its currency
      command reads datatracker's latest revision and RFC number and reports the pin trailing, so
      a new revision is the next task's upgrade slice, moving both libraries together.
11. The notes leave Bunrei's routes, its store, the handler's implementation, and the releases'
    version numbers to the tasks that build them. They state that live sources are not part of
    the protocol.
12. Each note names every task a change to it reaches: `.bunrei` `upload` and `api`, `.mikoshi`
    `browser-upload`, `items`, and `ingest`, `.foundation` `events`, and `.showcase`
    `presentation`.
13. The capability map lists Bunrei's protocol and the resumable upload as built, each linking
    its note. The root's check passes, with each note within lint-context's 1,500-word budget.

**Test seams**

- The root's check: lint-context (budgets, capability map) and lint-references (links resolve).
- Review against the cited sources. The spec-reviewer checks:
  - each type and field against docinfer v0.3.0's `Extract` and `Profile`, the `chunks` note, and
    docproc's Bunrei draft at the commit cited;
  - the HTTP base against go-web-sdk v0.18.0, which `upload` extends;
  - each header, media type, status, limit, and problem type against draft 16 and RFC 9530.

  Nothing here executes the contract. go-web-sdk's handler tests and `.bunrei` `api`'s client
  and tests are its executable proof, with tusd as an interop peer.

**Slices**

1. **Queries and Commands:** the `protocol` note with the transport, every Query and Command, the
   client module's types, Submit's limit and records, the profiles and extraction spec, where the
   SHA-256 and profile travel, what is left to Bunrei, and the tasks reached, plus its capability
   map entry (behaviors 1–7, 11–13).
2. **The resumable upload:** the `upload` note with draft 16's mapping, the digests, the limits,
   the concurrency rule, the ownership across go-web-sdk, web-app-sdk, Bunrei, and Mikoshi, and
   CompleteUpload, plus its capability map entry (behaviors 8–10, 12, 13).

**Out of scope**

- Any code: go-web-sdk's handler and client (`.bunrei` `upload`), the browser client
  (`.mikoshi` `browser-upload`), and Bunrei's routes and client module (`api`).
- Event shapes beyond the resolved profile on `started`, and the batch cap (`events`).
- Upload state's stores, streams, and retention (`.bunrei` `state`).
- Live sources, a future capability.
- The coordinator roadmap pull request the architect opens at this session's end: the `.bunrei`
  `upload` task, `.mikoshi` `browser-upload` and its repos, removing `chunked-upload-graduation`,
  the design page's Bunrei API, Open items, and go-web-sdk lines, the showcase presentation
  summary, and the draft-revision currency pins in `upload`'s and `browser-upload`'s summaries.
- The architecture layer's convention for an implemented standard's revision under rolling
  currency, a pending edit applied at sync.

**Door**

Two-way. The notes are prose in the root, and nothing is released. Once go-web-sdk releases the
handler and Bunrei releases `client/v0.1.0`, a change costs a release in each.

## Progress

slices 2/2 committed · standards ✓ · spec ✓ (1 round, 5 gaps closed) · editor ✓

## Decisions

- capstone: contracts (`chunks`, `protocol`, `events`) are designed here in `.foundation`; Bunrei and Mikoshi build against them, and a task that reads one opens its summary with "Waits on".
- capstone: `events` waits on `.bunrei` `metadata` for the metadata shapes it carries.
- capstone: items join contexts by reference and a context covers its descendants; chunks and embeddings stay keyed by content and carry no context.
- capstone: `.showcase` follows this goal on this root; its `acceptance` waits on `.torii`, `.bunrei`, and `.mikoshi` having synced.
- chunks: Mikoshi's `store`, before `contexts`, creates the database, declares pgvector, and writes the migration.
- protocol: Queries and Commands are HTTP through go-web-sdk; go-messaging (NATS) carries Events only. Rejected: NATS request/reply, offered only through `Broker.Conn`, outside go-messaging's standard tier.
- protocol: `events` must put the resolved docinfer `Profile` on each attempt's `bunrei.job.started` (`protocol.md`, "What a batch lacks").
- protocol: the upload is draft-ietf-httpbis-resumable-upload-16, implemented on net/http in go-web-sdk's base module by `.bunrei` `upload` before `api`, at go-web-sdk's next minor (shared with `.mikoshi` `sse-writer`: whichever runs first takes it). Rejected: tus 1.0.0, the draft's frozen predecessor; S3 multipart; tusd as a dependency (an interop peer only).
- protocol: the browser upload client is web-app-sdk's, built by `.mikoshi` `browser-upload` before `items`; `chunked-upload-graduation` is removed.
- protocol: go-web-sdk and web-app-sdk pin the draft revision under rolling currency, read from datatracker. Rejected: a backlog goal, and a watch-register entry, which is read by hand and never surfaces at PLAN.
- protocol: the coordinator's roadmap changes this task settled land in a roadmap pull request at this session's end, after `.bunrei`'s and `.mikoshi`'s (`plan-sse-foundation`) roadmap pull requests merge.

## Pending edits

- coordinator · docs/data-intelligence.md, "Embedding spaces": drop chunker and revision from the space tuple; replace "vectors partitioned by space" with one table and a partial ANN index per space; link the root's chunks contract. Under "Open items", drop `chunks` (storing chunks by identity).
- coordinator · roadmap/retrieval.toml: add per-language text-search configurations and CJK lexical search (pg_bigm or PGroonga, each a new native-tier extension) to the summary.
- coordinator · roadmap/capstone.data-intelligence.bunrei.toml, `upload`: add to the summary that go-web-sdk v0.18.0's `ReadUpload` refuses a body with no Content-Length, which a draft-16 creating POST of unknown length lacks.
- architecture · principles/rolling-currency.md: an implemented standard's revision, such as an IETF draft, is a covered surface, pinned and read from its publisher by currency.
- capstone-bunrei · context/README.md: "Protocol and client module" links the root's `protocol` note; "Chunked upload" links the root's `upload` note and says go-web-sdk's handler, mounted by Bunrei, serves it.
- docproc · context/bunrei.md: link the root's `protocol` and `upload` notes rather than restate them; drop OpenUpload, AppendChunk, GetUpload, and AbortUpload as Bunrei Commands, and the two open questions `protocol` settles.
