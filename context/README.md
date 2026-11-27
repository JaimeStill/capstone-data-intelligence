# capstone-data-intelligence context

This repository is the integration root of capstone.data-intelligence: the contracts Bunrei and
Mikoshi build against side by side, the compose stack, the demo dataset arranged as a context tree,
the acceptance run over docs-corpus v0.2.0 measured against its baseline, and the live presentation
that walks the signal flow layer by layer and argues for an elemental architecture.

`standards-lab/context/data-intelligence.md` holds the capstone's architecture, scope, and
blocking points, and `standards-lab/docs/data-intelligence.md` its design detail. This repository
takes their working detail in as its tasks settle it. Its goals live in the coordinator's roadmap:
`capstone.data-intelligence.foundation` now, whose record is
[`goals/capstone.data-intelligence.foundation.md`](goals/capstone.data-intelligence.foundation.md),
then `capstone.data-intelligence.showcase`.

## Capability map

- **Chunk contract** (built): the records Mikoshi stores from docinfer's chunks and their embedding spaces, [`chunks.md`](chunks.md).
- **Bunrei's protocol** (built): the Queries and Commands Bunrei's callers send it, and the types they exchange, [`protocol.md`](protocol.md).
- **Resumable upload** (built): the chunked HTTP upload, resumable after a dropped connection, that Bunrei and Mikoshi serve and their clients send, [`upload.md`](upload.md).
- **Event protocol** (built): the events Bunrei and Mikoshi publish, their envelope and lineage, and the manifest that proves a job's results arrived whole, [`events.md`](events.md).
- **Compose stack** (built): NATS, PostgreSQL with pgvector for Bunrei and Mikoshi, and a SeaweedFS S3 gateway, their host ports and credentials, and the tasks that run them, [`stack.md`](stack.md).
- **Demo dataset** (planned): `capstone.data-intelligence.foundation`, `demo-dataset`.
- **Acceptance run** (planned): `capstone.data-intelligence.showcase`, `acceptance`.
- **Presentation** (planned): `capstone.data-intelligence.showcase`, `presentation`.
