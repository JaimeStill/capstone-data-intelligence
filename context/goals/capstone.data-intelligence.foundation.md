# goal · capstone.data-intelligence.foundation

- **State:** idle
- **Task:** none
- **Branch:** none

## Tasks

1. [x] chunks
2. [ ] protocol
3. [ ] events
4. [ ] stack
5. [ ] athena-mapping
6. [ ] demo-dataset

## Decisions

- capstone: contracts (`chunks`, `protocol`, `events`) are designed here in `.foundation`; Bunrei and Mikoshi build against them, and a task that reads one opens its summary with "Waits on".
- capstone: `events` waits on `.bunrei` `metadata` for the metadata shapes it carries.
- capstone: items join contexts by reference and a context covers its descendants; chunks and embeddings stay keyed by content and carry no context.
- capstone: `.showcase` follows this goal on this root; its `acceptance` waits on `.torii`, `.bunrei`, and `.mikoshi` having synced.
- chunks: a Bunrei result batch alone lacks the input content's SHA-256 (`Source.Origin` is unserialized; the `/` part is often absent) and the producing `Profile` (space and chunker); `protocol` or `events` must carry both for Mikoshi to key source occurrences, chunks, and embeddings.
- chunks: Mikoshi's `store`, before `contexts`, creates the database, declares pgvector, and writes the migration.

## Pending edits

- coordinator · docs/data-intelligence.md, "Embedding spaces": drop chunker and revision from the space tuple; replace "vectors partitioned by space" with one table and a partial ANN index per space; link the root's chunks contract. Under "Open items", drop `chunks` (storing chunks by identity).
- coordinator · roadmap/retrieval.toml: add per-language text-search configurations and CJK lexical search (pg_bigm or PGroonga, each a new native-tier extension) to the summary.
