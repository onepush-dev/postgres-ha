# Postgres HA — 3-node Patroni cluster with HAProxy on Railway. Deploy on Railway with one click.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/PLACEHOLDER)

A production-style **PostgreSQL 18** high-availability cluster on Railway: three Patroni nodes (each with a colocated etcd member) and an HAProxy router that always points clients at the current primary. Automatic failover, streaming replication, TLS on every node, and connection URLs ready for your app.

## Features

- **3-node Patroni + etcd** — quorum without extra etcd services; any node can become primary
- **HAProxy router** — `:5432` read/write (primary only), `:5433` read-only (replicas, falls back to primary), `:8080/health` for Railway
- **PostgreSQL 18.6** with **pgvector**, **PostGIS**, and **pg_cron** preinstalled
- **Self-signed TLS** on every node (`sslmode=require`); rotate by clearing the volume's `tls/` dir
- **One shared secret set** — passwords are defined on `pg-1` and referenced by `pg-2`, `pg-3`, and the router
- **Private networking** — nodes talk over `*.railway.internal`; public access is the router's TCP proxy

## Services

| Service | Image | Role | Volume |
| --- | --- | --- | --- |
| **pg-1** / **pg-2** / **pg-3** | `ghcr.io/onepush-dev/postgres-ha-node:18.6` | Patroni + etcd + PostgreSQL | `/var/lib/postgresql/data` |
| **Postgres** (router) | `ghcr.io/onepush-dev/postgres-ha-router:18.6` | HAProxy + TCP proxy + connection URLs | none |

## How to connect

After deploy, open the **Postgres** (router) service → Variables:

| Variable | Use |
| --- | --- |
| `DATABASE_PUBLIC_URL` | Apps outside Railway (uses the TCP proxy host/port) |
| `DATABASE_URL` | Apps inside the same Railway project (private, port 5432, primary) |
| `DATABASE_URL_READONLY` | Read replicas inside the project (private, port 5433) |
| `PGHOST` / `PGPORT` / `PGUSER` / `PGPASSWORD` / `PGDATABASE` | Split form of the private URL |

Example with `psql` (self-signed cert — see SSL note below):

```bash
psql "$DATABASE_PUBLIC_URL?sslmode=require"
```

Write traffic always goes to the current primary. After a failover, reopen connections (most pools do this on error); HAProxy health-checks Patroni every second.

## SSL note

Each node generates a **self-signed** certificate on first boot and stores it on its volume. Use `sslmode=require` (encrypt, do not verify the CA). Full certificate verification (`verify-full`) will fail unless you replace the certs with ones you trust.

## Health

The router exposes `GET /health` on port **8080** (Railway healthcheck) and `GET /status` for primary/replica counts. Patroni REST API on each node listens on **8008** (private).

## Persistence and failover

- Each node has its own volume. Do not shrink or delete a volume while the cluster is running.
- Losing one node is fine (2/3 quorum). Losing two nodes loses quorum until enough members return.
- Changing `PATRONI_*_PASSWORD` after the first boot requires updating roles inside PostgreSQL; prefer leaving the generated secrets alone.

## Repo layout

- `node/` — Dockerfile for the Patroni/etcd/Postgres image
- `router/` — Dockerfile + `haproxy.cfg` for the router image
- Images are built by GitHub Actions and published to GHCR; the Railway template pins digests.
