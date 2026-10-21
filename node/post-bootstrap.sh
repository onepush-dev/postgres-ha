#!/bin/bash
# Runs once on the node that initialises the cluster.
set -euo pipefail
DB="${PGDATABASE:-railway}"
PSQL=(psql -v ON_ERROR_STOP=1 -h /var/run/postgresql -U "${PATRONI_SUPERUSER_USERNAME:-postgres}" -d postgres -qAt)
if [ "$("${PSQL[@]}" -c "SELECT 1 FROM pg_database WHERE datname='${DB}'")" != "1" ]; then
  "${PSQL[@]}" -c "CREATE DATABASE \"${DB}\""
fi
psql -v ON_ERROR_STOP=1 -h /var/run/postgresql -U "${PATRONI_SUPERUSER_USERNAME:-postgres}" -d "$DB" -q \
  -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements" \
  -c "CREATE EXTENSION IF NOT EXISTS pg_cron"
echo "[pg-ha] post-bootstrap: database ${DB} ready"
