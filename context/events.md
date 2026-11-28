# The event protocol

The event protocol is the events Bunrei and Mikoshi publish: their envelope and lineage,
Bunrei's job events, and the manifest that proves a job's results arrived whole. It states only
what Bunrei, Mikoshi, and the browser rely on. The envelope is go-core's
[`event`](https://github.com/standards-lab/go-core/blob/v0.13.0/event/doc.go) at v0.13.0, and the
data are the shapes of [docproc v0.10.0](https://github.com/standards-lab/docproc/blob/v0.10.0/dispatch/shapes.go)
and [docinfer v0.3.0](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go), linked
where a type carries one. [`protocol.md`](protocol.md) holds the Queries and Commands and the
`Manifest` type.

## Envelope

Every event is a CloudEvents 1.0 event in binary content mode, a go-core
[`Event`](https://github.com/standards-lab/go-core/blob/v0.13.0/event/event.go#L18) mapped by
[`Encode`](https://github.com/standards-lab/go-core/blob/v0.13.0/event/codec.go#L22) and
[`Decode`](https://github.com/standards-lab/go-core/blob/v0.13.0/event/codec.go#L56).

- `id` is a UUIDv7.
- `source` is the service, `bunrei` or `mikoshi`, never a replica's.
- `subject`, on a job's event, is the job's ID.
- `datacontenttype`, on an event with data, is `application/json`.

Consumers de-duplicate on `source` and `id`. Bunrei's job appends also carry `Nats-Msg-Id`, so the
broker drops a retried append.

## Lineage and layer

Every event carries three extension attributes:

- `correlationid` and `causationid`, from the CloudEvents
  [correlation extension](https://github.com/cloudevents/spec/blob/5391e18c64aafafddcf7ba078e40e07d48352fb1/cloudevents/extensions/correlation.md):
  the flow the event belongs to, and the `id` of the event that caused it.
- `layer`, the layer that produced it: `bunrei`, `docproc`, or `docinfer` on Bunrei's events, as
  "Bunrei's job types" gives each, and `mikoshi` on Mikoshi's.

On every event of a job, `correlationid` is the job's ID, which Bunrei mints. Each type's
`causationid` lets a consumer trace a citation back to the source bytes:

- `started` is caused by the job's `queued`.
- A part's own event is caused by its parent part's own event, and the input's own event by its
  attempt's `started`.
- An output, warning, or inference is caused by its part's own event.
- `batch`, `checkpoint`, `completed`, `attempt.failed`, and `failed` are caused by their attempt's
  `started`.
- `cancelled` is caused by `cancel_requested`.
- `queued` and `cancel_requested`, which Commands cause, carry no `causationid`.

docproc yields a part's own event after its outputs, warnings, and the parts found in it
([`dispatch.Event`](https://github.com/standards-lab/docproc/blob/v0.10.0/dispatch/dispatch.go#L82)),
so a `causationid` can name a later event. Bunrei mints a part's event ID when its attempt first
sees the part, and a consumer resolves a `causationid` by ID, never by order.

## The job sequence

Each of a job's events carries `jobsequence`, a Bunrei extension: its sequence on the job's
subject, gap-free, as a plain decimal from 1. The CloudEvents
[`sequence`](https://github.com/cloudevents/spec/blob/5391e18c64aafafddcf7ba078e40e07d48352fb1/cloudevents/extensions/sequence.md)
extension isn't used: its values compare as strings within the one `source` every job shares.

## Bunrei's job types

Each type is `bunrei.job.` followed by its name below. Bunrei's own data are types of its
`client` module.

| Type | Data | Layer | Package |
|---|---|---|---|
| `queued` | the job's profile, file name, media type, size, SHA-256, and extraction | `bunrei` | `client` |
| `started` | the attempt, the replica, and the resolved docinfer `Profile` | `bunrei` | `client` |
| `part` | a part's own [`dispatch.Event`](https://github.com/standards-lab/docproc/blob/v0.10.0/dispatch/dispatch.go#L82) | `docproc` | `dispatch` |
| `output` | an output's `dispatch.Event`, its [`Output`](https://github.com/standards-lab/docproc/blob/v0.10.0/dispatch/stage.go#L231) set | `docproc` | `dispatch` |
| `warning` | a warning's `dispatch.Event`, its `Warning` set | `docproc` | `dispatch` |
| `inference` | [`docinfer.Inference`](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go#L87) | `docinfer` | `docinfer` |
| `batch` | [`docinfer.Batch`](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go#L117) | `docinfer` | `docinfer` |
| `checkpoint` | [`job.Checkpoint`](https://github.com/standards-lab/docinfer/blob/v0.3.0/job/job.go#L242) | `docinfer` | docinfer's `job` |
| `cancel_requested` | none | `bunrei` | `client` |
| `completed` | the `Manifest` | `bunrei` | `client` |
| `attempt.failed` | the attempt and its error | `bunrei` | `client` |
| `failed` | the attempt and its error | `bunrei` | `client` |
| `cancelled` | none | `bunrei` | `client` |

- **`started`** comes before every batch of its attempt. Its
  [`Profile`](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go#L53) names the
  embedding space and the chunker that a batch lacks ([`chunks.md`](chunks.md), "Space and
  chunker").
- **Bunrei carries docinfer's updates** with their JSON unchanged. docinfer's
  [`job.Done`](https://github.com/standards-lab/docinfer/blob/v0.3.0/job/job.go#L249) is no event:
  it goes into its attempt's manifest entry.
- **`inference` also carries document and timeline extractions** once docinfer's next minor
  lands ([`protocol.md`](protocol.md), "Profiles and extraction").
- **Extraction deltas are not events.** docinfer's
  [`Progress`](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go#L111) stays inside
  the request that asked for it, and live views read events.
- **Terminal events.** `completed`, `failed`, and `cancelled` end a job; `attempt.failed` ends an
  attempt that has deliveries left.

## Metadata outputs

A metadata record is a `bunrei.job.output` whose output's `media_type` is one of docproc's four
[`metadata`](https://github.com/standards-lab/docproc/blob/v0.10.0/metadata/doc.go) media types
([`MediaOfficeMetadata` and the rest](https://github.com/standards-lab/docproc/blob/v0.10.0/dispatch/shapes.go#L221)),
[`MediaMail`](https://github.com/standards-lab/docproc/blob/v0.10.0/dispatch/shapes.go#L207), or
[`MediaOneNote`](https://github.com/standards-lab/docproc/blob/v0.10.0/dispatch/shapes.go#L210).
The event carries the record's SHA-256, never its content, which GetOutput streams. A mail
message's output carries [`in_reply_to`](https://github.com/standards-lab/docproc/blob/v0.10.0/dispatch/shapes.go#L173) and
[`references`](https://github.com/standards-lab/docproc/blob/v0.10.0/dispatch/shapes.go#L176) in
its `meta` when the message has them.

## Data schema

`dataschema` is a URN on the wire version of the package that produces the data:

- `urn:standards-lab:docproc:dispatch:1` for docproc's, under
  [`dispatch.Version`](https://github.com/standards-lab/docproc/blob/v0.10.0/dispatch/shapes.go#L23).
- `urn:standards-lab:docinfer:1` for docinfer's and its `job` package's, under
  [`docinfer.Version`](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go#L21).
- `urn:standards-lab:bunrei:client:1` for Bunrei's own, under the wire version its `client`
  module declares.

A URN changes with its wire version, never with a release alone. An event without data
has no `dataschema`.

## Result batches

A `bunrei.job.batch` carries docinfer's `Batch` and two extensions, so a fold over headers alone
yields the manifest:

- `batchdigest`, the batch's
  [`Digest()`](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go#L125).
- `batchchunks`, its chunk count, as a plain decimal.

A batch is identified by its job and `jobsequence`, which no attempt reuses.

The cap on a batch's marshalled JSON is a Bunrei setting, 768 KiB by default, which Bunrei passes
to docinfer as
[`Config.BatchBytes`](https://github.com/standards-lab/docinfer/blob/v0.3.0/pipeline.go#L28). The
cap plus the event's headers stays under NATS's 1 MB `max_payload`, so the headers have 256 KiB. A
chunk that alone takes a batch past the cap is a batch of one
([`run.go:179`](https://github.com/standards-lab/docinfer/blob/v0.3.0/run.go#L179)).

## The manifest

`completed` carries the `Manifest` ([`protocol.md`](protocol.md), "The client module"):

- Its range is every `jobsequence` from 1 through `completed`'s own.
- `Batches` counts the batch events in the range, every attempt's, and `Chunks` sums their
  `batchchunks`.
- `Digest` is the lowercase hex SHA-256 over those batches' `batchdigest` values in sequence order,
  each prefixed by its length as an 8-byte big-endian integer.
- `Attempts` has one entry per `started` in the range, in order. An entry's `Done` is its
  attempt's `job.Done`, absent when the attempt ended without one.

A consumer checks completeness by holding every sequence through `completed`'s and recomputing the
manifest over what it committed, every attempt's batches, since a redelivery replays content. The
digest covers the chunks' digests, so it proves which chunk texts arrived, not their vectors.

## Mikoshi's events

Mikoshi's commands emit their events as `standards-lab/context/messaging.md`, "Which commands emit
events", gives. An item's event has the item's id as `subject`, and the others the context they
changed. Context activity has no event of its own.

| Type | Command |
|---|---|
| `mikoshi.context.created` | create |
| `mikoshi.context.renamed` | rename |
| `mikoshi.context.moved` | move, optionally renaming |
| `mikoshi.context.deleted` | delete, with its confirmed subtree |
| `mikoshi.context.item.added` | add an item by reference |
| `mikoshi.context.item.removed` | remove an item's reference |
| `mikoshi.item.created` | create an item |
| `mikoshi.item.deleted` | delete an item |
| `mikoshi.database.reset` | the admin reset |

- **A delete is one event**, on the named context or item; the subtree and references it
  withdraws raise none.
- **`mikoshi.item.created` covers every item type**, its data carrying the `type`.
  `context-events` names it; `context-tools`' analyses emit it and add no type.
- **Query contexts** check each `mikoshi.context.item.added` against their filters, and **standing
  analyses** rerun on the events whose `subject` lies in their context's subtree.
- **A committed batch's event**, written in the batch's transaction, has the `id` of its
  `bunrei.job.batch` as `causationid`, joining Mikoshi's lineage to the job's.
- **At `mikoshi.database.reset`** a consumer drops its copy of Mikoshi's data; the stream stays.

## How the extensions are set

Bunrei sets the extensions on each job `Event` it appends. Mikoshi sets them in go-core's
[`RaiseOptions`](https://github.com/standards-lab/go-core/blob/v0.13.0/event/kind.go#L35), which
`.mikoshi` `event-extensions` added to `EventKind.Raise` at v0.13.0.

## The browser's transport

The browser reads Mikoshi's stream; Bunrei's events stay service-to-service. Mikoshi's SSE relay
serves its JetStream stream as a web-app-sdk
[`EventSequence`](https://github.com/standards-lab/web-app-sdk/blob/v0.1.0/dist/events.d.ts#L81)
whose cursor is the stream sequence, so any replica resumes any read.

This settles evidence 15 against NATS over WebSocket through web-app-sdk's
[`natsSequence`](https://github.com/standards-lab/web-app-sdk/blob/v0.1.0/dist/events/nats.d.ts#L36),
as [spike-html-apps built it](https://github.com/JaimeStill/spike-html-apps/blob/2883d78767970d5e33bc8607c2d3503311ae4168/context/README.md#nats-over-websocket-for-spike-ai-pipeline):

| | Mikoshi's SSE relay | NATS over WebSocket |
|---|---|---|
| Ordering and resume | the stream sequence as cursor | the same |
| Auth | Mikoshi's HTTP auth | one static NATS token in the browser; the spike calls real auth a gap |
| Ports | none beyond HTTP's | a WebSocket listener (4223) and its origin check |
| Native-tier use | none | browsers as NATS clients |
| Latency | unmeasured, one hop more; `.mikoshi` `signal-flow` measures it | unmeasured |

## What the note leaves out

Stream names, retentions, consumers, and the relay's routes are left to their tasks.

## Ownership

`.bunrei` `event-stream` and `.mikoshi` `ingest` build against this note, and their tests are its
executable proof. A change to the event protocol reaches:

- `.bunrei`: `state`, `jobs`, `event-stream`, and `document-extraction`.
- `.mikoshi`: `items`, `event-extensions`, `context-events`, `ingest`, `context-tools`,
  `standing-analyses`, `lineage`, `signal-flow`, and `event-relay`.
- `.showcase`: `presentation`.
