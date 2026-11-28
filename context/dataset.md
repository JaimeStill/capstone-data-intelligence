# The demo dataset

The demo dataset is the set of files, records, and contexts the presentation and `.showcase` load
into Mikoshi, the same way every time. [`dataset/dataset.json`](../dataset/dataset.json) defines
it, and the header of [`lib/tree.jq`](../lib/tree.jq) defines that file's format. The files
themselves are never committed: the suite fetches them into a cache and verifies each against its
pinned sha256.

## The three top-level contexts

The definition declares three top-level explicit contexts, side by side:

- `tour` holds 10 docs-corpus v0.2.0 files that show the platform's capabilities: EUR-Lex in four
  languages, one in a non-Latin script; a signed 3D portfolio over 4 MiB; a scanned document; a
  Japanese `.msg` mail; and a HEIC image, a OneNote file, and a zip inside a zip.
- `share` is an organization's file share: 27 files in five branches (psyops, operations
  planning, intelligence, information operations, admin). Most come from public government
  sources. Four are authored office files of a fictional unit's exercise, which
  [`lib/generate.py`](../lib/generate.py) writes byte for byte the same on every run. Eight
  authored JSON records in [`dataset/records/`](../dataset/records/) annotate share files. Four
  files sit in more than one branch, the collection plan among them.
- `views` holds query contexts that filter on `route` and `duration`. A filter selects from every
  item in Mikoshi, not only from those under its parent, so the views sit beside `tour` and
  `share` rather than inside a branch.

## Provenance and credit

Each file has exactly one provenance: a URL, a manual download with how-to steps, a docs-corpus
path, or the generator's output name. Every provenance pins the file's sha256; a docs-corpus file
takes its pin from that file's entry in docs-corpus's v0.2.0 MANIFEST.

The dataset admits files under a looser rule than docs-corpus's, because the files are never
committed. A URL or manual file needs only its pinned sha256 and size and a `credit` that records
its source and rights as found, caveats included.

## Live entries and live steps

The presenter makes some changes in Mikoshi's web client during the presentation, and the
definition declares them so the check can validate them:

- A file flagged `live` is added in the client. There are two: Ghost Tape No. 10, and OPORD v2,
  a new entry that supersedes OPORD v1.
- `live_steps` lists the context changes made in the client, in order: a create, a rename, and a
  move. The check validates each step against the tree the steps before it leave, and the load
  never creates a context that a step creates.

## Commands

`bin/dataset <group> <verb>`, or `mise run dataset -- <group> <verb>`, runs each dataset
command; with no arguments it lists them. Each `bin/dataset-<group>-<verb>` header documents its
command. `mise run check` runs `dataset tree check`.

| Variable | Read by | Default |
|---|---|---|
| `MIKOSHI_URL` | `tree load`, `tree reset`, `dataset:live` | `http://localhost:8080` |
| `DOCS_CORPUS` | `source fetch` | `~/architecture/docs-corpus`, read at tag v0.2.0 |
| `DATASET_CACHE` | `source fetch` | `dataset/.cache/` |

`dataset source fetch` fills the cache. It stores each file as `<cache>/<sha256>` once the file
matches its pinned sha256 and size, skips a file already cached, and refuses a file that doesn't
match. The default cache is gitignored.

`dataset tree load` builds the context tree through Mikoshi's contexts API, and `dataset tree
reset` deletes the three top-level contexts with their subtrees. `mise run dataset:live` runs
load, load, reset, and load against a running Mikoshi; [`stack.md`](stack.md), "Where the services
run", says how to run Mikoshi for it. `mise run check` never runs it.

## What `.showcase` `demo-load` adds

The suite builds only the context tree. `.showcase` `demo-load`, which waits on `.mikoshi`
`items` and `ingest`, is planned to load the files as items, the authored records, and the
references into that tree, and to review the share, tour, and authored lists again. A record
loads without its `annotates` link, since a Mikoshi record keeps no link to the files it
annotates.

## Assumptions

- Mikoshi checks a filter's field names against the items read's field contract, which takes
  `route`, `kind`, and `duration` and refuses any other field. The check accepts the same three.
