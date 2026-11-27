# Athena onto Bunrei

This note states the capstone's state against Athena, at
[`06ad4e1e6`](https://github.com/s2va/athena/tree/06ad4e1e670db27d61903a1fb00769055f66ade3), as
suggestions. Athena may not adopt them; a design review with the Athena team, outside this
workspace, aligns the two sets of goals. Paths below are under Athena's `server/`.

## Each service owns its data

Athena would be Bunrei's second consumer, beside Mikoshi. It relies only on Bunrei's API: the
Commands and Queries of [`protocol.md`](protocol.md), the events of [`events.md`](events.md), and
GetOutput. It never reads Bunrei's state, and it keeps its own tables. Nothing here changes the
[`chunks`](chunks.md), [`protocol`](protocol.md), or [`events`](events.md) contracts.

## Bunrei's fields onto Athena's chunks

Athena's
[`chunks`](https://github.com/s2va/athena/blob/06ad4e1e670db27d61903a1fb00769055f66ade3/server/internal/postgres/schema_baseline.go#L510)
is keyed by `(vault_id, chunk_id)` and hash-partitioned by vault. A batch's fields are as
[`chunks.md`](chunks.md), "Fields", gives them; the `Job` is [`protocol.md`](protocol.md)'s, and
`started` is `bunrei.job.started`.

| Bunrei field | Athena column | Where Athena differs |
|---|---|---|
| the source's text SHA-256, the chunker from `started`'s `Profile.Chunker`, and the chunk's `index` | `chunk_id` | Athena's key is `<version>-<i>`, positional per document version; the contract's is content |
| the chunk's `index` | `chunk_index` | the contract counts within one source text; Athena within the document |
| none | `total_chunks` | Athena counts the chunks it keeps |
| `Job.Name` | `filename` | none |
| `bunrei.job.queued`'s media type | `file_type` | none |
| `Job.Size` | `file_size` | none |
| `Job.SHA256` | `content_id` | Athena groups same-bytes chunks under a UUID, not the SHA-256 |
| the chunk's `text` | `content` | none: both store bare text; Athena's chunker normalizes whitespace |
| the chunk's `span` | none | Athena has no span column |
| the chunk's `digest` | none | Athena keys nothing by chunk text |
| the chunk's `vector`, in the space `started`'s `Profile` names | `embedding vector(1024)`, or a space's table | Athena drops a chunk whose embedding failed; the contract stores it with its `error` |
| the chunk's `error` | none | as above |
| the part's `where`, for a page | `page_number` | none |
| a source's `kind` and `stage` | `ocr_processed`, `transcription_model` | Athena keeps flags, not source occurrences |
| a document-scope extraction | `summary` | chunk 0 only |
| `started`'s `Profile` and the attempt | `processing_metadata` | chunk 0 only |
| none | `vault_id`, `document_id`, `version_id`, `is_current`, `security_policy`, `blob_key`, `audio_*` | Athena's own |
| none | `search_tsv`, `meta_tsv` | `english`, the filename weighted A over the content's B; the contract's is `simple` over the text |

## Embedding spaces: Arctic to e5

Athena's
[`embedding_spaces`](https://github.com/s2va/athena/blob/06ad4e1e670db27d61903a1fb00769055f66ade3/server/internal/postgres/schema_baseline.go#L140)
holds snowflake-arctic-embed-l-v2.0 as its bootstrap space, in `chunks.embedding`; every other
space is a `chunk_embeddings_s<id>` table with a cosine HNSW index. The move to
multilingual-e5-large is a blue/green between two Athena spaces:

- Athena resubmits every document through Bunrei under the e5 profile, into a new space.
- The Arctic space serves until the e5 space is ready and activated.
- Athena's in-place re-embed command, `cmd/reembed`, and its space worker's embedding role
  ([`internal/embeddings/worker.go`](https://github.com/s2va/athena/blob/06ad4e1e670db27d61903a1fb00769055f66ade3/server/internal/embeddings/worker.go))
  retire.
- Athena's `status` (building, ready, failed) and its `system_settings.active_embedding_space`,
  which activates only a ready space, map onto the space status and the active space of
  [`chunks.md`](chunks.md), "Embedding space".
- Athena's `halfvec` default for a new space
  ([`embedding_spaces.go`](https://github.com/s2va/athena/blob/06ad4e1e670db27d61903a1fb00769055f66ade3/server/internal/postgres/embedding_spaces.go#L31))
  ports directly to a space's type.

## The embedded text

The contract stays keyed by bare chunk text. Athena embeds each chunk headed by its document's
name,
[`ChunkEmbeddingText`](https://github.com/s2va/athena/blob/06ad4e1e670db27d61903a1fb00769055f66ade3/server/pkg/models/embedding_text.go#L21),
which put the right document first for 70% of generated questions against 65% bare. The header is
dropped; its gain is expected back through docinfer's metadata source, which `.bunrei`
`metadata-text` builds.

## Chains

Athena's chains are in
[`chains.go`](https://github.com/s2va/athena/blob/06ad4e1e670db27d61903a1fb00769055f66ade3/server/internal/infrastructure/ai/chains.go#L104).

- **Whisper** maps onto docinfer's transcription.
- **Tesseract** maps onto docinfer's vision. The suggestion is to drop Tesseract pending
  `experiment.ocr` `spike-scanned-documents`, reframed to ask whether an OCR tier is needed at all;
  the spike is not part of the capstone. Athena would lose the confidence gate that discards
  low-confidence or symbol-soup pages
  ([`ocr_quality.go`](https://github.com/s2va/athena/blob/06ad4e1e670db27d61903a1fb00769055f66ade3/server/internal/document/ocr_quality.go#L85)),
  reading on CPU alone, and verbatim text with no invented words.
- **The document summary**, one summary-chain call over the document's text, maps onto
  document-scope extraction.
- **The video summary and key moments**, one prompt over a timeline of transcript and frame
  descriptions
  ([`video_moments.go`](https://github.com/s2va/athena/blob/06ad4e1e670db27d61903a1fb00769055f66ade3/server/internal/document/video_moments.go#L261)),
  map onto video-timeline extraction.

Both extractions are planned in `.bunrei` `document-extraction` ([`protocol.md`](protocol.md),
"Profiles and extraction").

## What stays Athena's

- Regex and pattern entities, including MAC and MGRS (`internal/extraction/`).
- `sparse_rows` places and dates, the `GEOPOINT` and `DATETIME` rows kept since migration 79.
- TEI rerank.
- The `ingest_jobs` queue.
- The video pipeline's own work beyond extraction.
- The vault, ACL, and version columns, and the `english` tsvectors.
- Document metadata (`doc_meta_embeddings`) and document vectors (`document_vectors`), which Athena keeps
  computing itself, through Torii's e5 once its spaces move.

## Assumptions

- Athena is read at `06ad4e1e6`; a later commit may move any line cited here.
- Athena resubmits each document under one Bunrei profile, so one `started`'s `Profile` names its
  space and chunker.
- A page part's `where` carries its page number.
- Athena keeps assigning its own `document_id` and `version_id`, outside Bunrei.
- Torii serves multilingual-e5-large to Athena's own embedding calls.
