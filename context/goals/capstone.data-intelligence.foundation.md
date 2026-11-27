# goal · capstone.data-intelligence.foundation

- **State:** idle
- **Task:** none
- **Branch:** none

## Tasks

1. [ ] chunks
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

## Pending edits

- none
