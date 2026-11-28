# The resumable upload

The resumable upload carries a document too large for Bunrei's Submit, or any file a browser sends
Mikoshi, in chunks that survive a dropped connection. It is
[draft-ietf-httpbis-resumable-upload-16](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16)
(23 November 2026, interop version 11), pinned at that revision. This note states what the
handler and its clients rely on and cites the draft's sections rather than restating them.
[`protocol.md`](protocol.md) says what a completed upload becomes in Bunrei.

A client sends Upload-Draft-Interop-Version: 11 on every request to the upload, the creating POST
and each PATCH, HEAD, and DELETE
([Appendix B](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#appendix-B)).

## Creation

A creating POST
([§6.1](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-6.1))
carries:

- Upload-Complete
  ([§4.2.1](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-4.2.1)).
- Upload-Length
  ([§4.3.1](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-4.3.1)),
  when the length is known.
- Content-Type, the file's media type.
- Repr-Digest, the file's SHA-256 (see "Digests").
- Content-Disposition, the file's name
  ([RFC 6266](https://www.rfc-editor.org/rfc/rfc6266)).

The handler keeps the media type, the digest, and the file name with the upload.

The server names the upload resource in Location
([§6.2](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-6.2)).
It sends Location, with Upload-Limit, in a 104 (Upload Resumption Supported) interim response
([§12](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-12))
only when the request's Upload-Draft-Interop-Version is 11, and that 104 echoes
Upload-Draft-Interop-Version (Appendix B). When the request's Upload-Complete is ?0, the final
response is a 201 (Created) with Location, Upload-Limit, and Upload-Complete: ?0. The target resource, not the upload protocol,
defines a final response carrying Upload-Complete: ?1
([§4.2.1](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-4.2.1)).

## Append

Each append
([§8](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-8)) is
a PATCH to the upload resource with Content-Type `application/partial-upload`
([§13](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-13)),
Upload-Offset
([§4.1.1](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-4.1.1)),
Upload-Complete, and the chunk's Content-Digest, and never a Content-Encoding
([§8.1](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-8.1)).
The append that ends the file carries Upload-Complete: ?1.

An append whose Upload-Offset is not the upload's offset is a 409 (Conflict) with Upload-Complete:
?0 and the current offset in Upload-Offset
([§8.2](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-8.2)).
Its body is an RFC 9457 problem of the type
`https://iana.org/assignments/http-problem-types#mismatching-upload-offset`, with its
`expected-offset` and `provided-offset` members filled in
([§14.1](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-14.1)).

## Resumption and cancellation

A HEAD to the upload resource returns its offset in Upload-Offset, its Upload-Limit, and
Cache-Control: no-store
([§7.2](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-7.2)).
A client resumes by reading that offset and appending from it; it never reads the offset while
one of its own requests to the upload is in flight
([§7.1](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-7.1)).
A DELETE cancels the upload
([§9](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-9)).

## Limits

Upload-Limit
([§5.1](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-5.1))
announces `max-append-size` at the server's chunk size
([§5.1.3](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-5.1.3))
and `max-age` as the seconds left until the upload expires
([§5.1.5](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-5.1.5)).
A client sends no chunk larger than `max-append-size`. Bunrei's chunk size is a Bunrei setting
([`protocol.md`](protocol.md), "Settings").

## Concurrency

Appends to one upload are sequential
([§10](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-10)):
a client never sends an append while its creation or another append is in progress. The server
enforces this across its replicas: two requests to one upload never append at once, whichever
replica serves each.

## Digests

The draft has no digest section of its own, so both fields are
[RFC 9530](https://www.rfc-editor.org/rfc/rfc9530)'s, each with the `sha-256` algorithm:
Repr-Digest ([§3](https://www.rfc-editor.org/rfc/rfc9530#section-3)) on the creating POST covers
the whole file, and Content-Digest ([§2](https://www.rfc-editor.org/rfc/rfc9530#section-2)) on an
append covers that chunk.

Each field is a Structured Field Dictionary whose `sha-256` member is a Byte Sequence
([RFC 9651 §3.2](https://www.rfc-editor.org/rfc/rfc9651#section-3.2),
[§3.3.5](https://www.rfc-editor.org/rfc/rfc9651#section-3.3.5)), as in
`sha-256=:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=:`. Every other field carries a SHA-256 in
lowercase hex, `Job.SHA256` among them. The conversion decodes the base64 to the 32 bytes and
writes them as lowercase hex, and the reverse encodes the bytes from the hex as base64.

An append whose chunk mismatches its Content-Digest is refused, and the offset doesn't move. The
handler appends a chunk only once its digest matches, so an interrupted append, whose digest can't
be checked, appends nothing, departing deliberately from the SHOULD in
[§8.2](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-8.2).
When the upload completes, the handler checks the whole file against
the creation's Repr-Digest. A mismatch fails the upload: the completing request's final response
is an error with Upload-Complete: ?1, which resuming cannot fix
([§8.1](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-8.1)).

## What the note leaves out

The routes, the stores, and the handler's implementation are left to the tasks that build them:
`.mikoshi` `upload` and `browser-upload`.

## Ownership

- go-web-sdk's base module holds the server handler, built on net/http behind a chunk-store
  interface, and the Go append client, released alone as v0.19.0; `sse-writer` comes at a later
  minor. The handler reads bodies of unknown length itself and builds on v0.19.0's
  [`Transfer`](https://github.com/standards-lab/go-web-sdk/blob/v0.19.0/transfer.go#L29).
- go-web-sdk holds the in-memory store and `uploadtest`, the store conformance suite; each
  service's store, shared across its replicas, is its own.
- web-app-sdk holds the browser client in `./upload.js`, from v0.2.0. tusd is no interop peer: it
  speaks interop versions 3–6 only, and draft-16's is 11.
- Bunrei mounts the handler on its API with a store over its blob storage, and its `client` module
  wraps go-web-sdk's client.
- Mikoshi's `items` mounts the same handler with its own store, which keeps the chunks in
  PostgreSQL.
- Bunrei's one upload Command is CompleteUpload ([`protocol.md`](protocol.md), "Commands").

go-web-sdk pins the draft revision it implements as `DraftRevision`, and web-app-sdk as
`DRAFT_REVISION`, under rolling currency (`architecture/principles/rolling-currency.md`). Each
library's currency command compares its pin with datatracker's latest revision of the draft and
its RFC number, if it has one, and reports the pin trailing. A new revision becomes the next task's upgrade slice, which moves both libraries
together.

A change to the upload reaches:

- `.bunrei`: `api`.
- `.mikoshi`: `upload`, `browser-upload`, `items`, and `ingest`.
- `.foundation`: [`events`](events.md).
- `.showcase`: `presentation`.
