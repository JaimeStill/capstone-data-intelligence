# Bunrei's protocol

Bunrei's protocol is the Queries and Commands that Mikoshi and other callers send Bunrei, and the
types they exchange. It states only what Bunrei and its callers rely on. It takes its shapes from
docproc's Bunrei draft at
[fab8e70](https://github.com/standards-lab/docproc/blob/fab8e70fe0a85f08cbfdffc738944bcf63f58117/context/bunrei.md),
except where this note settles otherwise. The resumable upload is the [`upload`](upload.md)
note's, and the job's events are `.foundation` `events`'.

## Transport

Queries and Commands go over HTTP, served through go-web-sdk's base module. NATS carries only
Events, which `events` designs. A refusal is an RFC 9457 problem, go-web-sdk's
[`Problem`](https://github.com/standards-lab/go-web-sdk/blob/v0.18.0/problem.go#L22).
go-web-sdk mints no type URIs, so Bunrei names its own; which ones is `.bunrei` `api`'s.

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

A job is one input, the unit of retry, and its ID is a UUIDv7. `Job.SHA256` is the input
content's SHA-256 in lowercase hex. `Name` is the document's file name, from Submit's `Name` or
the upload's `Content-Disposition`. `Manifest` is set once the job completes; what its batches,
chunks, and digest count, and how a consumer checks them, is `events`'.

## Commands

- **Submit** takes a whole document, its file name and media type, a profile, an optional
  extraction, and the caller's idempotency ID. It returns the job, queued, once the input is
  durable. A retried Submit with the same ID returns the first job. A document past the
  small-document limit is refused with a 413 problem and goes through the upload instead. A
  structured record is Submit content with the media type `application/json`; it has no Command
  of its own.
- **CompleteUpload** takes a completed upload, a profile, and an optional extraction, and returns
  the job, queued. It is Bunrei's one upload Command; the upload itself, its offset included,
  which a client reads from the upload's own HEAD, is the [`upload`](upload.md) note's.
- **CancelJob** takes a job's ID and requests its cancellation. The job ends `cancelled` unless it
  has already ended.

## Queries

- **GetJob** takes a job's ID and returns its `Job`.
- **GetOutput** takes the SHA-256 of an output a job's event names and streams that content. An
  event carries an output's SHA-256, never the content.
- **ListProfiles** returns each profile Bunrei serves, with its resolved docinfer `Profile`.

## Settings

The small-document limit, Submit's largest document, and the upload's chunk size are Bunrei
settings, each 4 MiB by default. The default is a starting point; measured performance tunes it.

## Profiles and extraction

A request names a versioned processing profile from Bunrei's configuration, never a model. Each
profile resolves to a docinfer pipeline, and ListProfiles returns that pipeline's `Profile`.

The extraction spec is docinfer's `Extract`, and it is optional. Bunrei refuses one that marshals
past 256 KiB, so the queued event that carries it stays within NATS's 1 MB `max_payload`.

## What a batch lacks

A result batch carries neither its input content's SHA-256 nor the producing profile
([`chunks.md`](chunks.md), "Fields" and "Space and chunker"). A consumer takes the SHA-256, the
versioned profile name, and the file name from the `Job`, and the resolved `Profile`, which names
the space and the chunker, from each attempt's `bunrei.job.started`, which `events` owes.

## What the protocol leaves out

Bunrei's routes and wire encoding, its stores, the implementation, and the version numbers of
the releases are the tasks' that build them. Live sources, read as they arrive, are not part of
the protocol.

## Ownership

`.bunrei` `api` builds the `client` module and Bunrei's routes against this note, and its client
tests are the note's executable proof. A change to the protocol reaches:

- `.bunrei`: `upload` and `api`.
- `.mikoshi`: `browser-upload`, `items`, and `ingest`.
- `.foundation`: `events`, which carries the resolved `Profile` on `started`.
- `.showcase`: `presentation`.
