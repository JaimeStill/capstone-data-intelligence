# goal · capstone.data-intelligence.foundation

- **State:** idle
- **Task:** none
- **Branch:** none

## Tasks

1. [x] chunks
2. [x] protocol
3. [x] events
4. [ ] stack
5. [ ] athena-mapping
6. [ ] demo-dataset

## Decisions

- capstone: contracts (`chunks`, `protocol`, `events`) are designed here in `.foundation`; Bunrei and Mikoshi build against them, and a task that reads one opens its summary with "Waits on".
- capstone: items join contexts by reference and a context covers its descendants; chunks and embeddings stay keyed by content and carry no context.
- capstone: `.showcase` follows this goal on this root; its `acceptance` waits on `.torii`, `.bunrei`, and `.mikoshi` having synced.
- chunks: Mikoshi's `store`, before `contexts`, creates the database, declares pgvector, and writes the migration.
- protocol: Queries and Commands are HTTP through go-web-sdk; go-messaging (NATS) carries Events only. Rejected: NATS request/reply, offered only through `Broker.Conn`, outside go-messaging's standard tier.
- protocol: the upload is draft-ietf-httpbis-resumable-upload-16, implemented on net/http in go-web-sdk's base module by `.bunrei` `upload` before `api`, at go-web-sdk's next minor (shared with `.bunrei` `sse-writer`: whichever runs first takes it). Rejected: tus 1.0.0, the draft's frozen predecessor; S3 multipart; tusd as a dependency (an interop peer only).
- protocol: the browser upload client is web-app-sdk's, built by `.mikoshi` `browser-upload` before `items`; `chunked-upload-graduation` is removed.
- protocol: go-web-sdk and web-app-sdk pin the draft revision under rolling currency, read from datatracker. Rejected: a backlog goal, and a watch-register entry, which is read by hand and never surfaces at PLAN.
- events: extraction deltas are not events. Rejected: `bunrei.job.progress` on JetStream (an ack per publish, and retention of every delta).
- events: a job's `correlationid` is the job ID Bunrei mints. Rejected: a caller-supplied correlation field on Submit and CompleteUpload (it reopens the protocol, and Bunrei never knows its caller).
- events: lineage and layer are extension attributes. Rejected: lineage in each event's data.
- events: context activity is Mikoshi's per-command events. Rejected: a separate `mikoshi.context.activity` event (a second event per command, against messaging.md).
- events: `dataschema` is a URN on the wire version. Rejected: a link to the shapes at a release tag (it changes every release while the shape doesn't).
- events: the result-batch cap is a Bunrei setting. Rejected: a fixed value in the note.

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
