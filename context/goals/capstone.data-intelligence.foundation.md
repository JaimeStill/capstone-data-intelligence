# goal · capstone.data-intelligence.foundation

- **State:** building
- **Task:** stack
- **Branch:** stack

## Tasks

1. [x] chunks
2. [x] protocol
3. [x] events
4. [ ] stack
5. [ ] athena-mapping
6. [ ] demo-dataset

## Task brief · stack

**Problem**

The capstone has its contracts but nowhere to run them together. Bunrei and Mikoshi need a shared
broker, their own databases, and an object store before `.bunrei` `state` and `jobs` and
`.mikoshi` `items` and `ingest` can run against real infrastructure. The `.showcase`
`acceptance` run needs the same stack. The root has no compose stack and no currency command, so
no image pin it adds would ever be reported as trailing. The two services have no images yet, so
this task builds the infrastructure only. The services run on the host against it until
`.showcase` `services` adds them.

**Behaviors**

1. **Currency.** `mise run currency` reports every root pin that trails its latest release: the
   mise tools, each stack service's base image, and pgvector's source version. It exits 0 when
   nothing trails. `mise run upgrade` moves every trailing pin that isn't held. The root's
   marathon configuration names `mise run currency` as its currency command. The script is the
   workspace's shared currency script, unchanged, with an empty Go module list.
2. **One project.** The stack is one compose project named for the root. Each service builds from
   its own Dockerfile, whose base image is that service's one pin. No compose file names an
   image. Each Dockerfile carries the service's configuration, command and health check, so
   compose mounts no configuration. The check's compose validation passes.
3. **NATS.** NATS 2 runs with JetStream on file storage, in a named volume. It reports healthy only
   once JetStream is enabled, not merely once the listener is up. It keeps NATS's default 1 MB
   maximum payload, which the `events` and `protocol` notes rely on. It opens no WebSocket
   listener, and its monitoring endpoint stays inside the container. The stack creates no
   stream; each service creates its own.
4. **PostgreSQL.** Two servers, one for Bunrei and one for Mikoshi, run from one image: PostgreSQL
   19 with pgvector 0.8.7 built from source.
   - Each server has user, password and database `app`, its own named volume and its own port.
   - Each reports healthy through `pg_isready` over TCP.
   - pgvector is available on both servers, and the stack installs it on neither.
5. **Object store.** SeaweedFS's S3 gateway runs with bucket auto-creation off and the published
   development credentials admin/secret. It reports healthy only once a signed request succeeds.
   Its data sits in a named volume. The stack creates no bucket; each service creates its own on
   start.
6. **Ports.** Every published port binds to 127.0.0.1. Every default collides with no other
   workspace stack's default, and an environment variable overrides each one.
7. **Lifecycle.**
   - `up` builds and waits until every service is healthy, and prints the stack's logs if it
     fails.
   - `down` stops the stack and keeps its volumes, so data survives a restart.
   - `reset` stops the stack and drops its volumes.
8. **Smoke.** A smoke task runs against the running stack, using only the containers' own tools,
   so it needs no client on the host. It proves:
   - JetStream accepts a stream on file storage.
   - `CREATE EXTENSION vector` succeeds on each PostgreSQL server, then is rolled back.
   - An object put through the S3 gateway into a new bucket reads back after a restart.
9. **Stack note.** The root's context gains a note on the stack, and the README and the capability
   map's "Compose stack" entry link to it. The note gives:
   - each service, its port and override variable, and its credentials, marked as published
     development values;
   - how a service running on the host reaches each one;
   - Torii's base URL for each alias on gb10-2, the key class each service holds (Bunrei bulk,
     Mikoshi interactive), and the tasks that issue the keys (`.bunrei` `jobs`, `.mikoshi`
     `hybrid-search`);
   - that the services join in `.showcase` `services`.

**Test seams**

- The stack through its mise tasks: `up`, `down`, `reset`, smoke, and the check's compose
  validation.
- The currency command.

**Slices**

1. **Root currency.** The shared currency script, the `currency` and `upgrade` tasks, the crane
   pin, an empty Go module list, and the marathon currency command. Done when currency exits 0
   and the check passes.
2. **NATS.** The compose project, the NATS service, the lifecycle tasks, and the smoke's JetStream
   proof. Currency covers NATS's pin.
3. **PostgreSQL.** The pgvector image, copied from Mikoshi's, and its two servers, with the smoke's
   extension proof on each. Currency covers the base image and pgvector's source.
4. **SeaweedFS.** The S3 gateway and the smoke's put, restart and read proof. Currency covers its
   pin.
5. **Stack note.** The note, the README, and the capability map entry marked built, matching what
   the slices built.

**Out of scope**

- Bunrei's and Mikoshi's service containers (`.showcase` `services`), and Mikoshi's image
  (`.mikoshi` `image`).
- Torii itself, and issuing either consumer key.
- Stream, bucket and database schemas, retentions, and S3 lifecycle rules: the services' tasks
  own them.
- An observability profile (backlog: `cross-service-tracing`).
- An integration profile on tmpfs.
- CI.

**Door**

Two-way. Nothing is released, no consumer depends on the stack yet, and every pin and port can
move.

## Progress

slices 5/5 committed · standards — · spec — · editor —

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

- stack: the object store is SeaweedFS's S3 gateway; services reach it through go-storage's `s3`
  provider and create their own buckets on start. Rejected: Azurite (`docproc/storage` untested
  against it), MinIO (no workspace repo tests against it).
- stack: one PostgreSQL server per service, both from the root's pgvector image, each with
  database and user `app`. Rejected: one server with a database per service.
- stack: the root copies Mikoshi's pgvector Dockerfile and pins it under its own currency.
  Rejected: building from Mikoshi's checkout.
- stack: the root's currency is the shared currency script, unchanged, with an empty Go module
  list.
- stack: Torii keys are issued by `.bunrei` `jobs` (bulk) and `.mikoshi` `hybrid-search`
  (interactive), each into its own repository's `fnox.toml`; the root records only endpoints
  and classes.
- stack: the services join the root's stack in `.showcase` `services`, before `acceptance`;
  Mikoshi's image is `.mikoshi` `image`, after `signal-flow`. Until then they run on the host
  against the stack's loopback ports.
- stack: the services create their own JetStream streams; the stack keeps NATS's default 1 MB
  maximum payload.

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
