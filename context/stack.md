# The compose stack

The compose stack is the development infrastructure Bunrei and Mikoshi run against: NATS with
JetStream, a PostgreSQL server with pgvector for each service, and a SeaweedFS S3 gateway. It
gives each service a server to reach and nothing more; each service creates what it keeps there.
[`compose.yml`](../compose.yml) includes one `compose/<service>.yml` per service, and each
service's `compose/<service>/Dockerfile` holds its pins and settings.

## Services

Each service publishes one port on 127.0.0.1, and an environment variable overrides the host port.

| Service | Host port | Override | Reached from the host at |
|---|---|---|---|
| `nats` | 4226 | `NATS_PORT` | `nats://127.0.0.1:4226` |
| `postgres-bunrei` | 5439 | `POSTGRES_BUNREI_PORT` | `postgres://app:app@127.0.0.1:5439/app` |
| `postgres-mikoshi` | 5442 | `POSTGRES_MIKOSHI_PORT` | `postgres://app:app@127.0.0.1:5442/app` |
| `seaweedfs` | 8335 | `SEAWEEDFS_S3_PORT` | `http://127.0.0.1:8335` |

NATS takes no credentials. Both PostgreSQL servers take user `app`, password `app`, database
`app`, and the S3 gateway takes access key `admin`, secret `secret`. These credentials are
published development values, committed in the clear as
`architecture/principles/development-secrets.md`, "What is not a secret", allows.

Each service keeps its data in a named volume: JetStream's file storage, each server's data
directory, and SeaweedFS's store.

## Tasks

- `mise run stack:up` builds and starts the stack and waits until every service is healthy.
- `mise run stack:down` stops it and keeps the volumes.
- `mise run stack:reset` stops it and drops the volumes, so the next `stack:up` starts empty.
- `mise run stack:smoke` proves each service of the running stack does its job, then deletes
  what it created; [`smoke.sh`](../scripts/smoke.sh) says how.

`mise run currency` reports every root pin that trails its latest release: the stack's Dockerfile
`FROM` tags, pgvector's source version, and the root's mise tools. `mise run upgrade` moves those
pins to their latest release.

## What the stack creates and exposes

The stack creates nothing a service keeps, and exposes only the ports in the table above.

- The stack creates no JetStream stream, S3 bucket, database schema, or extension: each service
  creates its own. The S3 gateway's bucket auto-creation is off, so a write never creates a
  bucket.
- NATS keeps its default 1 MB `max_payload`, which [`events.md`](events.md), "Result batches", and
  [`protocol.md`](protocol.md), "Profiles and extraction", size against.
- NATS serves its monitoring endpoint on the container's loopback only (`127.0.0.1:8222`), for
  the health check; neither the host nor the other containers reach it.
- NATS opens no WebSocket listener; the browser reads Mikoshi's SSE relay
  ([`events.md`](events.md), "The browser's transport").
- Both PostgreSQL servers have pgvector built in, and the stack creates the `vector` extension in
  neither: each service creates it in its own database.

## Torii

Torii, the model gateway, is not part of the stack. It runs on gb10-2 as agentgateway, with one
base URL per alias, `http://gb10-2:3000/<alias>/v1`, for `agent`, `vision`, `audio`, and
`embedding`, behind a Bearer key. Bunrei holds a key of the bulk class and Mikoshi one of the
interactive class; ai-hosting's
[gateway document](https://github.com/standards-lab/ai-hosting/blob/6f7c1b327ef73f8dc8e78a5663b8c79fb24b76ea/docs/gateway.md#keys)
defines the classes and their limits. `.bunrei` `jobs` and `.mikoshi` `hybrid-search` each issue
their service's key with ai-hosting's `hosting key issue`, into that repository's own `fnox.toml`.

## Where the services run

Bunrei and Mikoshi run on the host against these loopback ports until `.showcase` `services`
brings them into the stack.

Mikoshi runs from its checkout against `postgres-mikoshi`:

- Under `MIKOSHI_ENV=local`, Mikoshi's local overlay already names the stack's host, database,
  and user, but port 5440. Set `MIKOSHI_DATABASE_PORT=5442`, and set the password `app` through
  `MIKOSHI_DATABASE_PASSWORD=app` or a `secrets.json`.
- The server embeds the web client, so `client:build` runs first; Mikoshi's `mise run serve`
  runs both.
- Mikoshi runs its migrations, the `vector` extension's included, at startup.
- It serves on 127.0.0.1:8080, which the dataset suite's default `MIKOSHI_URL` reaches.

`mise run dataset:live` exercises it ([`dataset.md`](dataset.md), "Commands").
