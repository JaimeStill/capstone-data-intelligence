# Bunrei's protocol

Bunrei's protocol is the Queries and Commands that Mikoshi and other callers send Bunrei, and the
types they exchange. It states only what Bunrei and its callers rely on. It takes its shapes from
docproc's Bunrei draft at
[fab8e70](https://github.com/standards-lab/docproc/blob/fab8e70fe0a85f08cbfdffc738944bcf63f58117/context/bunrei.md),
except where this note settles otherwise. The [`upload`](upload.md) note covers the resumable
upload, and the [`events`](events.md) note the job's events.

## Transport

Queries and Commands go over HTTP, served through go-web-sdk's base module. NATS carries only
Events, which [`events`](events.md) covers. A refusal is an RFC 9457 problem, go-web-sdk's
[`Problem`](https://github.com/standards-lab/go-web-sdk/blob/v0.18.0/problem.go#L22).
go-web-sdk mints no type URIs, so Bunrei names its own, and `.bunrei` `api` chooses them.

## The client module

Bunrei's nested `client` module holds these types and a Go `Client` with one method per Query and
Command, each taking a `context.Context`. Bunrei imports none of its callers.

```go
package client // capstone-bunrei/client

// Commands
type Submit struct {
    ID         string // the caller's idempotency ID
    Profile    string // a versioned processing profile
    Name, MIME string // the document's file name and media type
    Content    []byte // at most the small-document limit
    Extraction *docinfer.Extract
}
type CompleteUpload struct { Upload, Profile string; Extraction *docinfer.Extract }
type CancelJob struct { Job string }

// Queries
type GetJob struct { Job string }       // -> Job
type GetOutput struct { SHA256 string } // -> the content, streamed
type ListProfiles struct{}              // -> []Profile

type Profile struct { Name string; Resolved docinfer.Profile }
type Job struct {
    ID, Profile, Name string; Size int64; SHA256 string
    State    State  // queued, running, completed, failed, cancelled
    Attempt  int    // the work queue's delivery, from 1
    Sequence uint64 // the job's last event
    Manifest *Manifest
    Error    string
}
type Manifest struct {
    Batches  int
    Chunks   int
    Digest   string
    Attempts []Attempt // one per attempt, in order
}
type Attempt struct{ Done *job.Done }
```

`docinfer.Extract` is docinfer's
[`Extract`](https://github.com/standards-lab/docinfer/blob/v0.3.0/capability.go#L138),
`docinfer.Profile` its
[`Profile`](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go#L53), and `job.Done`
its [`Done`](https://github.com/standards-lab/docinfer/blob/v0.3.0/job/job.go#L249), all at
v0.3.0.

A job covers one input and is the unit of retry. Its ID is a UUIDv7. `Job.SHA256` is the input
content's SHA-256 in lowercase hex. `Name` is the document's file name, from Submit's `Name` or
the upload's `Content-Disposition`. `Manifest` is set once the job completes.
[`events.md`](events.md), "The manifest", defines what it counts and how a consumer checks it.

The module also holds the prompt override Queries and Commands. `.bunrei` `prompts` chooses their
shapes.

## Commands

- **Submit** takes a whole document, its file name and media type, a profile, an optional
  extraction, and the caller's idempotency ID. It returns the job, queued, once the input is
  durable. A retried Submit with the same ID returns the first job. A document past the
  small-document limit is refused with a 413 problem and goes through the upload instead. A
  structured record is Submit content with the media type `application/json`; it has no Command
  of its own.
- **CompleteUpload** takes a completed upload, a profile, and an optional extraction, and returns
  the job, queued. It is Bunrei's one upload Command. The [`upload`](upload.md) note covers the
  upload itself, including its offset, which a client reads from the upload's own HEAD.
- **CancelJob** takes a job's ID and requests its cancellation. It returns nothing but an error;
  the outcome is read through GetJob. The job ends `cancelled` unless it has already ended.
- **CreatePromptOverride** takes a profile, a stage, and a prompt, and stores them as an
  override.
- **ActivatePromptOverride** makes an override the active one for its profile and stage,
  replacing any override active there before.
- **DeactivatePromptOverride** deactivates an override, so its profile and stage return to the
  profile's default prompt.

## Queries

- **GetJob** takes a job's ID and returns its `Job`.
- **GetOutput** takes the SHA-256 of an output a job's event names and streams that content. An
  event carries an output's SHA-256, never the content.
- **ListProfiles** returns each profile Bunrei serves, with its resolved docinfer `Profile`.
- **ListPromptOverrides** returns the stored prompt overrides, each with its profile, stage, and
  whether it is active.
- **GetPromptOverride** returns one stored prompt override.

## Settings

The small-document limit, which is the largest document Submit takes, and the upload's chunk size
are Bunrei settings, each 4 MiB by default. The default is a starting point that measured
performance tunes.

## Profiles and extraction

A request names a versioned processing profile from Bunrei's configuration, never a model. Each
profile resolves to a docinfer pipeline, and ListProfiles returns that pipeline's `Profile`.

A profile's vision and transcription prompts in Bunrei's configuration are defaults. An active
prompt override replaces each one, per profile and per stage: the stages are `vision` and
`transcription`, and each pair has at most one active override. Only the prompts are
overridable, not the sampling. Each attempt of a job uses the prompts active when that attempt
starts, so a profile's name doesn't fix its prompts. A consumer that needs the prompts an attempt
ran reads the resolved `Profile` in that attempt's `bunrei.job.started`
([`events.md`](events.md), "Bunrei's job types").

The extraction spec is docinfer's `Extract`, and it is optional. It is the caller's, per
request, and no prompt override replaces it. Bunrei refuses one that marshals past 256 KiB, so
the queued event that carries it stays within NATS's 1 MB `max_payload`.

The extraction runs per source: once on each output text, image description, and transcript,
never on metadata. `.bunrei` `document-extraction` plans two more scopes at docinfer's next
minor: once over a job's whole text, and once over a video's timeline, which orders its frames'
descriptions and its transcript by source time. `.bunrei` `api` and `.mikoshi` `ingest` read the
shapes these scopes produce.

## What a batch lacks

A result batch carries neither its input content's SHA-256 nor the producing profile
([`chunks.md`](chunks.md), "Fields" and "Space and chunker"). A consumer takes the SHA-256, the
versioned profile name, and the file name from the `Job`. It takes the resolved `Profile`, which
names the space and the chunker, from each attempt's `bunrei.job.started`
([`events.md`](events.md), "Bunrei's job types").

## What the protocol leaves out

Bunrei's routes and wire encoding, its stores, the implementation, and the version numbers of
the releases are left to the tasks that build them. Live sources, read as they arrive, are not
part of the protocol.

## Ownership

`.bunrei` `api` builds the `client` module and Bunrei's routes against this note, and its client
tests are the note's executable proof. A change to the protocol reaches:

- `.bunrei`: `upload`, `document-extraction`, `api`, and `prompts`.
- `.mikoshi`: `browser-upload`, `items`, and `ingest`.
- `.foundation`: [`events`](events.md), whose `started` carries the resolved `Profile`.
- `.showcase`: `presentation`.
