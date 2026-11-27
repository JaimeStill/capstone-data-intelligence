# The chunks contract

What Mikoshi stores from docinfer's chunks, and how both services read it. docinfer's run-directory
lines and Bunrei's result batches carry the same library shapes, [docinfer
v0.3.0](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go) over [docproc
v0.9.0](https://github.com/standards-lab/docproc/blob/v0.9.0/dispatch/stage.go); this contract
turns them into four records. Every record is keyed by content. None carries a context, an item,
or an input path: items join contexts by reference in Mikoshi, and a blob's SHA-256 leads to its
chunks with no context in between.

## Records

### Embedding space

A space is keyed by its identity: docinfer's embeddings
[`Identity`](https://github.com/standards-lab/docinfer/blob/v0.3.0/capability.go#L212) (the served
model, and the settings JSON with its request version, input type `document`, and document
prefix) plus the dimensions. It holds two registered attributes that are not identity: the metric,
and the query prefix, from the query convention docinfer's `Profile` reports as
`embedding_query`. A model change adds a space and re-embeds the stored chunks into it.

The chunker is not part of a space. docinfer keys an embedding by the embeddings identity and the
chunk text's SHA-256 ([`embed.go:89`](https://github.com/standards-lab/docinfer/blob/v0.3.0/embed.go#L89)),
and a chunking by the chunker identity and the source text's SHA-256
([`embed.go:39`](https://github.com/standards-lab/docinfer/blob/v0.3.0/embed.go#L39)), so a
re-chunk reuses the vectors of every chunk text that didn't change. A space that named its chunker
would re-embed them all.

Mikoshi's `store` registers set A's space (multilingual-e5-large, 1,024 dimensions);
`hybrid-search` reads a space's dimensions, metric, and query prefix to embed a query and reach
its index.

### Source occurrence

A source occurrence is keyed by its input content's SHA-256 and its docproc part ID. A part ID
names where the part occurs within its input, `/` for the input itself, and is stable across runs
([`Part`](https://github.com/standards-lab/docproc/blob/v0.9.0/dispatch/stage.go#L241)). The
occurrence holds the part (its SHA-256, content type, parent, depth, and where it was found) and
its sources, each with its kind (output, metadata, vision, or transcript), its text's SHA-256,
and the identity of the stage that made it. The run-local input path is not stored.

The occurrence is how a blob reaches its chunks: the blob's SHA-256 names an input or a part, and
each source's text SHA-256 names the chunks cut from that text. Mikoshi's `contexts` and `lineage`
read it.

### Chunk

A chunk is keyed by its source text's SHA-256, the chunker identity, and its index in that text.
It holds its text, its span (byte offsets into the source text), and its text's SHA-256. A chunk
the embeddings endpoint refused, or that failed, is stored with its error and no embedding, and
stays searchable by text.

Every chunk carries a stored generated tsvector, `to_tsvector('simple', text)`. The contract has
no language field, since no docproc or docinfer record carries one. The cost is CJK and Hebrew
text: PostgreSQL 19 has no text-search configuration for Chinese, Japanese, Korean, or Hebrew, and
`simple` keeps an unspaced run of Han or Kana as one lexeme and splits Hangul only at spaces, so
that text gets only whole-run lexical matches. Semantic search covers it. Per-language
configurations and CJK lexical search are the `retrieval` backlog goal's.

Mikoshi's `ingest` writes chunks; `hybrid-search` reads their text, tsvector, and span.

### Embedding

An embedding is keyed by its chunk text's SHA-256 and its space, so chunks with the same text share
one vector per space. Embeddings share one table with an untyped `vector` column, and each space
has a partial HNSW index over a cast to its dimensions, `embedding::vector(n)`, restricted to that
space's rows.

A query casts to use the index: a nearest-neighbour query that orders by the cast scans its space's
index, and one without the cast misses every index. A vector of the wrong dimensions is refused in
an indexed space, since the index's cast rejects it. sqlate's pgvector live tests prove all three,
for every metric
([`space_live_test.go`](https://github.com/standards-lab/sqlate/blob/postgres/pgvector/v0.1.0/postgres/pgvector/space_live_test.go#L123):
`TestLive_QueryRepeatingTheCastScansItsSpaceIndex`, `TestLive_QueryWithoutTheCastMissesEveryIndex`,
`TestLive_InsertOfTheWrongDimensionIntoAnIndexedSpaceFails`).

Mikoshi's `ingest` writes embeddings; `hybrid-search` reads them.

## Ownership

Mikoshi's `store` task (`capstone.data-intelligence.mikoshi`) owns the schema, the pgvector
declaration, a native-tier extension in capstone-mikoshi only, and the migration. This repository
holds no SQL; the contract is this note, and `store`'s migration and its integration tests are its
executable proof.

A change to the contract reaches:

- `.mikoshi`: `store`, `contexts`, `ingest`, `hybrid-search`, and `lineage`.
- `.foundation` `events` and `.bunrei` `api`, insofar as Bunrei's result batches carry docinfer's
  [`Batch`](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go#L117) (its parts,
  sources, and chunks).
