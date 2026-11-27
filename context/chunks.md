# The chunks contract

The chunks contract defines what Mikoshi stores from docinfer's chunks, which Bunrei's result
batches deliver, and how Mikoshi reads them. docinfer's run-directory lines and Bunrei's result batches carry the same library
shapes, those of [docinfer v0.3.0](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go),
which embed parts from [docproc
v0.9.0](https://github.com/standards-lab/docproc/blob/v0.9.0/dispatch/stage.go). The contract maps
them onto four records, each keyed by content. None carries a context, an item, or an input path:
items join contexts by reference in Mikoshi, and a blob's SHA-256 leads to its chunks with no
context in between.

## Records

### Embedding space

A space is keyed by its identity: docinfer's embeddings
[`Identity`](https://github.com/standards-lab/docinfer/blob/v0.3.0/capability.go#L212) (the served
model and the settings of its document convention) plus the dimensions and the pgvector type:
`vector`, `halfvec`, `bit`, or `sparsevec`. It holds three attributes that are not identity: the
metric; the query prefix, from the query convention docinfer's `Profile` reports as
`embedding_query`; and a status, building, ready, or failed.

One space is active, and searches read it. A model change or a type change adds a space, which
fills while the active space serves and becomes active only once it is ready. Filling it means
resubmitting the items to Bunrei under a profile that names the new space; docinfer's and
docproc's content-keyed caches then recompute only the embeddings. A `halfvec` or `bit` space can
instead be filled from a `vector` space without calling the model; a `sparsevec` space needs a
sparse model. The SQL that fills and activates a space is Mikoshi's.

The chunker is not part of a space. docinfer keys an embedding by the embeddings identity and the
chunk text's SHA-256
([`embed.go:89`](https://github.com/standards-lab/docinfer/blob/v0.3.0/embed.go#L89)), and a
chunking by the chunker identity and the source text's SHA-256
([`embed.go:39`](https://github.com/standards-lab/docinfer/blob/v0.3.0/embed.go#L39)), so a
re-chunk reuses the vectors of every chunk text that didn't change. A space that named its chunker
would re-embed them all.

Mikoshi's `store` registers set A's space (multilingual-e5-large, 1,024 dimensions, `vector`);
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
is stored whether or not its embedding succeeded, and stays searchable by text.

Every chunk carries a stored generated tsvector, `to_tsvector('simple', text)`. The contract has
no language field, since no docproc or docinfer record carries one. The cost is CJK and Hebrew
text: PostgreSQL 19 has no text-search configuration for Chinese, Japanese, Korean, or Hebrew, and
`simple` keeps an unspaced run of Han or Kana as one lexeme and splits Hangul only at spaces, so
that text gets only whole-run lexical matches. Semantic search covers it. Per-language
configurations and CJK lexical search are the `retrieval` backlog goal's.

Mikoshi's `ingest` writes chunks; `hybrid-search` reads their text, tsvector, and span.

### Embedding

An embedding is keyed by its chunk text's SHA-256 and its space, so chunks with the same text share
one vector per space, of its space's pgvector type. An embedding the endpoint refused, or that
failed, is stored with its error and no vector: docinfer's error comes from one embeddings
endpoint, so it belongs to one space. Embeddings share one table with an untyped `vector` column,
and each space has a partial HNSW index over a cast to its dimensions, `embedding::vector(n)`,
restricted to that space's rows. That shape serves `vector` spaces. Whether the other types take
typed columns or expression indexes over the one `vector` column is for `.mikoshi`
`pgvector-types` to prove.

A query casts to use the index: a nearest-neighbour query that orders by the cast scans its space's
index, and one without the cast misses every index. A vector of the wrong dimensions is refused in
an indexed space, since the index's cast rejects it. sqlate's pgvector live tests prove all three
for every metric
([`space_live_test.go`](https://github.com/standards-lab/sqlate/blob/postgres/pgvector/v0.1.0/postgres/pgvector/space_live_test.go#L123):
`TestLive_QueryRepeatingTheCastScansItsSpaceIndex`,
`TestLive_QueryWithoutTheCastMissesEveryIndex`, and
`TestLive_InsertOfTheWrongDimensionIntoAnIndexedSpaceFails`).

Mikoshi's `ingest` writes embeddings; `hybrid-search` reads them.

## Mapping

One mapping serves both inputs, since both carry the same shapes. A cmd/docinfer schema "2" chunk
line,
[`Line`](https://github.com/standards-lab/docinfer/blob/cmd/docinfer/v0.2.0/cmd/docinfer/internal/outdir/manifest.go#L116),
inlines the part and source a batch indexes, plus a run-local input path that is not stored; the
manifest's
[`inputs`](https://github.com/standards-lab/docinfer/blob/cmd/docinfer/v0.2.0/cmd/docinfer/internal/outdir/manifest.go#L63)
map that path to the input content's SHA-256. `Line` is internal to cmd/docinfer, so no other
module imports it; the contract relies on its JSON. A Bunrei result batch is a
[`Batch`](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go#L117):
a chunk's `source` indexes its `sources`, and a source's `part` indexes its `parts`.

### Space and chunker

From a pipeline's
[`Profile`](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go#L53),
a space's identity and dimensions are `embeddings` and `dimensions`, and the query prefix is
`embedding_query`'s `prefix`. From a run directory, the manifest's
[`capabilities`](https://github.com/standards-lab/docinfer/blob/cmd/docinfer/v0.2.0/cmd/docinfer/internal/outdir/manifest.go#L74)
entry whose `capability` is `embeddings` gives the identity, and
[`embedding_space`](https://github.com/standards-lab/docinfer/blob/cmd/docinfer/v0.2.0/cmd/docinfer/internal/outdir/manifest.go#L100)
gives `dimensions`, absent until the run ends. A run directory records no query convention, so it
cannot supply the query prefix; that comes from a `Profile` or from `store`'s registration. Neither
input carries the metric, which `store` registers.

docinfer builds the chunker identity from the `chunk` capability, the splitter's `Model`, and its
[`Settings()`](https://github.com/standards-lab/docinfer/blob/v0.3.0/chunk/chunk.go#L59)
([`run.go:222`](https://github.com/standards-lab/docinfer/blob/v0.3.0/run.go#L222)).
`Profile.Chunker` and `embedding_space.chunker` carry those settings alone, but the settings'
`model` member is that same `Model`. So either input supplies the full identity: capability
`chunk`, the model from the settings' `model`, and the settings as given. A batch carries neither
the space nor the chunker; they come from the `Profile` of the pipeline that made it.

### Fields

- Source occurrence: the input content's SHA-256 is a line's `input` through the manifest's
  `inputs`. A batch carries no input, since a
  [`Source`](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go#L134)'s
  `Origin` never marshals and the batch holds only the parts its chunks come from, so a batch alone
  cannot supply it. The part ID and the part are
  [`Part`](https://github.com/standards-lab/docproc/blob/v0.9.0/dispatch/stage.go#L251)'s
  `id`, `sha256`, `content_type`, `parent`, `depth`, and `where`. Each source is a `Source`'s
  `kind`, `stage`, and text SHA-256: its `sha256`, or for an output, its `output`'s `sha256`.
- Chunk: the source text's SHA-256 is its source's text SHA-256, as above, and the chunker
  identity is as "Space and chunker" gives it. The index is
  [`Chunk`](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go#L148)'s
  `index`, the text and span are
  [`chunk.Chunk`](https://github.com/standards-lab/docinfer/blob/v0.3.0/chunk/chunk.go#L24)'s
  `text` and `span`, and the text's SHA-256 is `digest`.
- Embedding: the chunk text's SHA-256 is `digest`, and the space is as above. The vector is
  `vector`, decoded by
  [`DecodeVector`](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go#L161),
  and absent on a refused or failed chunk; the error is `error`.

## Ownership

Mikoshi's `store` task (`capstone.data-intelligence.mikoshi`) owns the schema, the migration,
and the pgvector declaration, a native-tier extension declared in capstone-mikoshi only. This
repository holds no SQL; the contract is this note, and `store`'s migration and its integration
tests are its executable proof.

A change to the contract reaches:

- `.mikoshi`: `store`, `contexts`, `ingest`, `hybrid-search`, `lineage`, `pgvector-types`, and
  `space-switch`.
- `.foundation` [`events`](events.md) and `.bunrei` `api`, because Bunrei's result batches carry
  docinfer's [`Batch`](https://github.com/standards-lab/docinfer/blob/v0.3.0/shapes.go#L117) (its
  parts, sources, and chunks).
- `.foundation` [`protocol`](protocol.md), because it and [`events`](events.md) between them carry
  what a batch alone lacks: the input content's SHA-256, and the processing profile that names the
  space and the chunker.
