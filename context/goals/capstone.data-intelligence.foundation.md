# goal · capstone.data-intelligence.foundation

- **State:** building
- **Task:** chunks
- **Branch:** chunks

## Tasks

1. [ ] chunks
2. [ ] protocol
3. [ ] events
4. [ ] stack
5. [ ] athena-mapping
6. [ ] demo-dataset

## Task brief · chunks

**Problem**

Mikoshi's `store`, `contexts`, `ingest`, `hybrid-search`, and `lineage` need one shape for what
the pgvector load stores from docinfer's chunks, and the design leaves it open ("storing chunks by
identity"). docinfer's run-directory lines and Bunrei's result batches carry the same library
shapes, keyed by content, but nothing says how they become rows, how an embedding space is
registered, or how lexical search reads multilingual text. Without the contract, Mikoshi's first
migration decides it alone, and Bunrei and Mikoshi can drift.

**Behaviors**

1. The root's working context holds the `chunks` contract note: four records (embedding space,
   source occurrence, chunk, embedding), what each holds and is keyed by, and who reads it. No
   record carries a context, an item, or an input path.
2. A chunk is keyed by its source text's SHA-256, the chunker identity, and its index in that
   text, and holds its text, its span, and its text's SHA-256. A refused or failed chunk is stored
   with its error and no embedding, and stays searchable by text.
3. An embedding is keyed by its chunk text's SHA-256 and its space. Embeddings share one table
   with an untyped vector column and a partial ANN index per space over a cast to the space's
   dimensions. The note states that a query casts to use the index and that a vector of the wrong
   dimensions is refused, citing sqlate's pgvector tests that prove both.
4. A space's identity is docinfer's embeddings identity (served model, and the settings JSON with
   its request version, input type, and document prefix) plus the dimensions. Metric and query
   prefix are registered attributes. The chunker is not part of the space, and the note says why:
   a re-chunk reuses the vectors of unchanged texts.
5. A source occurrence is keyed by its input content's SHA-256 and its part ID. It holds the part
   (SHA-256, content type, parent, depth, where) and its sources (kind, text SHA-256, stage
   identity), so a blob's SHA-256 leads to its chunks with no context in between.
6. Every chunk carries a stored tsvector generated with the `simple` configuration. The contract
   has no language field, and the note states the cost: Han, Kana, Hangul, and Hebrew text gets
   only whole-run lexical matches, which semantic search covers.
7. Every stored field is mapped from docinfer's `Chunk`, `Source`, and `Batch` and docproc's
   `Part`, linked at their released tags and never restated. The one mapping serves a
   cmd/docinfer schema "2" chunk line and a Bunrei result batch, and vectors decode from base64
   little-endian float32.
8. The note says Mikoshi's `store` owns the schema, the pgvector declaration, and the migration,
   and that the root holds no SQL. It names every task a change to the contract reaches.
9. The context README's capability map lists the chunk contract as built, linking the note;
   Bunrei's protocol and the event protocol stay planned.
10. The coordinator's Mikoshi goal gains a `store` task before `contexts` that waits on this
    contract, and the coordinator's blocking points list it.
11. The root's check passes, the note within lint-context's 1,500-word note budget; the
    coordinator's check passes.

**Test seams**

- The root's check: lint-context (budgets, capability map) and lint-references (links resolve).
- Review against the cited sources: the spec-reviewer checks each record and field in the note
  against docinfer's and docproc's shapes at their tags and against sqlate's pgvector live tests.
  The root has no database tier, so nothing here executes the contract; Mikoshi's `store`
  migration and its integration tests are its executable proof.

**Slices**

1. **The records and keys:** the contract note with the four records, their keys, the space's
   identity, the `simple` tsvector, ownership, and the tasks it reaches, plus the capability map
   entry (behaviors 1–6, 8, 9, 11).
2. **The mapping:** each stored field traced to docinfer's and docproc's shapes at their tags, for
   both a run-directory line and a result batch, with the vector's decoding (behavior 7).
3. **The coordinator's `store` task:** Mikoshi's goal file gains `store` before `contexts`, and
   the coordinator's data-intelligence note gains the blocking line, on the coordinator's own
   branch and pull request, with the coordinator's check passing (behavior 10).

**Out of scope**

- SQL, migrations, and any Mikoshi or Bunrei code; `store` writes them.
- Retrieval queries, reciprocal rank fusion, and how a context filters chunks (`hybrid-search`,
  `contexts`).
- The result-batch event's shape and cap (`events`).
- Per-language text-search configurations and CJK lexical search (the `retrieval` backlog).
- The design page's space tuple, a pending edit for sync.
- Choosing set A's metric; `store` registers it.

**Door**

Two-way. The contract is prose, and the roadmap change is one coordinator pull request; nothing
is released. Once Mikoshi's `store` migrates data, changing a key costs a migration there.

## Progress

slices 0/3 committed · standards — · spec — · editor —
- plan, round 1, question 7: the architect authorized landing Mikoshi's `store` task in this session, through the coordinator's own pull request on `plan-capstone.data-intelligence.mikoshi`.

## Decisions

- capstone: contracts (`chunks`, `protocol`, `events`) are designed here in `.foundation`; Bunrei and Mikoshi build against them, and a task that reads one opens its summary with "Waits on".
- capstone: `events` waits on `.bunrei` `metadata` for the metadata shapes it carries.
- capstone: items join contexts by reference and a context covers its descendants; chunks and embeddings stay keyed by content and carry no context.
- capstone: `.showcase` follows this goal on this root; its `acceptance` waits on `.torii`, `.bunrei`, and `.mikoshi` having synced.
- chunks: the contract is a note in the root with no SQL; Mikoshi's `store` migration is its one schema and executable proof. Rejected: a reference schema the root's check applies, which would be a second copy.
- chunks: the contract maps docinfer's library shapes (`Chunk`, `Source`, `Batch`) and docproc's `Part`, which run-directory lines and Bunrei's result batches both carry; `outdir.Line` is internal to cmd/docinfer.
- chunks: a chunk is keyed by source text SHA-256, chunker identity, and index; an embedding by text SHA-256 and space. Rejected: text SHA-256 alone, which drops span and index.
- chunks: source occurrences (input content SHA-256 and part ID → part, source kind, text SHA-256, stage identity) are in the contract, keyed by content; input paths are not.
- chunks: a space's identity is docinfer's embeddings identity plus dimensions; metric and query prefix are attributes. Rejected: the chunker in the space, which re-embeds on every re-chunk.
- chunks: every chunk's tsvector is `to_tsvector('simple', text)`, with no language field. Rejected: per-language configurations, since no record carries a language; CJK lexical search is `retrieval`'s.
- chunks: Mikoshi's `store`, before `contexts`, creates the database, declares pgvector, and writes the migration.

## Pending edits

- coordinator · docs/data-intelligence.md, "Embedding spaces": drop chunker and revision from the space tuple; replace "vectors partitioned by space" with one table and a partial ANN index per space; link the root's chunks contract. Under "Open items", drop `chunks` (storing chunks by identity).
- coordinator · roadmap/retrieval.toml: add per-language text-search configurations and CJK lexical search (pg_bigm or PGroonga, each a new native-tier extension) to the summary.
