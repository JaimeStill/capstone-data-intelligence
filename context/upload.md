# The resumable upload

The resumable upload carries a document too large for Bunrei's Submit, or any file a browser sends
Mikoshi, in chunks that survive a dropped connection. It is
[draft-ietf-httpbis-resumable-upload-16](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16)
(23 November 2026, interop version 11), pinned at that revision. This note states what the
handler and its clients rely on and cites the draft's sections rather than restating them. What a
completed upload becomes in Bunrei is [`protocol.md`](protocol.md)'s.

## Creation

A creating POST
([§6.1](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-6.1))
carries:

- Upload-Complete
  ([§4.2.1](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-4.2.1)),
  an sf-Boolean.
- Upload-Length
  ([§4.3.1](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-4.3.1)),
  an sf-Integer, when the length is known.
- Content-Type, the file's media type.
- Repr-Digest, the file's SHA-256 (see "Digests").
- Content-Disposition, the file's name
  ([RFC 6266](https://www.rfc-editor.org/rfc/rfc6266)).
- Upload-Draft-Interop-Version: 11
  ([Appendix B](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#appendix-B)).

The handler keeps the media type, the digest, and the file name with the upload.

The server names the upload resource in Location
([§6.2](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-6.2)).
It sends Location, with Upload-Limit, in a 104 (Upload Resumption Supported) interim response
([§12](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-12))
only when the request's Upload-Draft-Interop-Version is 11, and that 104 carries the field back
(Appendix B). When the request's Upload-Complete is ?0, the final response is a 201 (Created) with
Location, Upload-Limit, and Upload-Complete: ?0. A final response to a request carrying ?1 is the
target resource's
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
Its body is an RFC 9457 problem of the type `mismatching-upload-offset`, with `expected-offset`
and `provided-offset`
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
holds that across its replicas, so two requests to one upload never append at once, whichever
replica serves each.

## Digests

The draft has no digest section of its own, so both fields are
[RFC 9530](https://www.rfc-editor.org/rfc/rfc9530)'s, each with the `sha-256` algorithm:
Repr-Digest ([§3](https://www.rfc-editor.org/rfc/rfc9530#section-3)) on the creating POST covers
the whole file, and Content-Digest ([§2](https://www.rfc-editor.org/rfc/rfc9530#section-2)) on an
append covers that chunk.

Each value is a Structured Field Byte Sequence
([RFC 9651 §3.3.5](https://www.rfc-editor.org/rfc/rfc9651#section-3.3.5)): the 32-byte digest in
base64 between colons, as in `sha-256=:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=:`. Every other
field carries a SHA-256 in lowercase hex, `Job.SHA256` among them. The conversion decodes the
base64 to the 32 bytes and writes them as lowercase hex, and the reverse encodes the bytes from
the hex as base64.

An append whose chunk mismatches its Content-Digest is refused, and the offset doesn't move. The
handler appends a chunk only once its digest matches, so an interrupted append, whose digest can't
be checked, appends nothing. When the upload completes, the handler checks the whole file against
the creation's Repr-Digest. A mismatch fails the upload: the completing request's final response
is an error with Upload-Complete: ?1, which resuming cannot fix
([§8.1](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-16#section-8.1)).

## Ownership

- go-web-sdk's base module holds the server handler, built on net/http behind a chunk-store
  interface, and the Go append client. The handler extends the module's
  [`ReadUpload`](https://github.com/standards-lab/go-web-sdk/blob/v0.18.0/request.go#L109) and
  [`Transfer`](https://github.com/standards-lab/go-web-sdk/blob/v0.18.0/transfer.go#L27) at
  v0.18.0.
- web-app-sdk holds the browser client.
- Bunrei mounts the handler on its API with a store over its blob storage, and its `client` module
  wraps go-web-sdk's client.
- Mikoshi's `items` mounts the same handler with its own store.
- Bunrei's one upload Command is CompleteUpload ([`protocol.md`](protocol.md), "Commands").

go-web-sdk and web-app-sdk each pin the draft revision they implement under rolling currency
(`architecture/principles/rolling-currency.md`). Each library's currency command reads
datatracker's latest revision of the draft and its RFC number, if it has one, and reports the pin
trailing. A new revision becomes the next task's upgrade slice, which moves both libraries
together.

## What the note leaves out

The routes, the store, the handler's implementation, and the version numbers of the releases are
the tasks' that build them: `.bunrei` `upload` and `.mikoshi` `browser-upload`.

A change to the upload reaches:

- `.bunrei`: `upload` and `api`.
- `.mikoshi`: `browser-upload`, `items`, and `ingest`.
- `.foundation`: `events`.
- `.showcase`: `presentation`.
