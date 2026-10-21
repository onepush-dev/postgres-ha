#!/bin/bash
# Runs as root: Railway volumes mount root-owned, so take ownership, then drop to postgres.
set -euo pipefail
: "${DATA_ROOT:=/var/lib/postgresql/data}"
mkdir -p "$DATA_ROOT/pgdata" "$DATA_ROOT/etcd" "$DATA_ROOT/tls"
chown postgres:postgres "$DATA_ROOT" "$DATA_ROOT/etcd" "$DATA_ROOT/tls"
# Only recurse when ownership is wrong (fast on restarts with a large database).
if [ "$(stat -c %U "$DATA_ROOT/pgdata")" != "postgres" ]; then chown -R postgres:postgres "$DATA_ROOT/pgdata"; fi
if [ -n "$(find "$DATA_ROOT/etcd" ! -user postgres -print -quit)" ]; then chown -R postgres:postgres "$DATA_ROOT/etcd"; fi
chmod 700 "$DATA_ROOT/pgdata" "$DATA_ROOT/etcd"
exec gosu postgres /usr/local/bin/node.sh
