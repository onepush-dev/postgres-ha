#!/bin/bash
# Starts this node's etcd member and Patroni (which manages PostgreSQL).
set -euo pipefail

: "${DATA_ROOT:=/var/lib/postgresql/data}"
: "${PGDATA:=$DATA_ROOT/pgdata}"
: "${PGHA_NODES:?PGHA_NODES must list every node private domain, comma separated}"
: "${RAILWAY_PRIVATE_DOMAIN:?private networking is required}"
: "${PATRONI_SCOPE:=pg-ha}"
: "${PGDATABASE:=railway}"
: "${ETCD_CLUSTER_TOKEN:=pg-ha-etcd}"
: "${PATRONI_TTL:=30}"
: "${PATRONI_LOOP_WAIT:=10}"
: "${PATRONI_RETRY_TIMEOUT:=10}"
: "${PATRONI_MAX_LAG_ON_FAILOVER:=1048576}"
: "${PG_MAX_CONNECTIONS:=200}"
: "${PG_SHARED_BUFFERS:=128MB}"
SELF="$RAILWAY_PRIVATE_DOMAIN"
NAME="${SELF%%.*}"
export PATRONI_NAME="$NAME" PATRONI_SCOPE PGDATABASE
log() { echo "[pg-ha $(date -u +%H:%M:%S)] $*"; }

# Railway private DNS can take a moment after container start.
for i in $(seq 1 60); do getent hosts "$SELF" >/dev/null && break; sleep 1; done

IFS=',' read -ra NODES <<< "$PGHA_NODES"
INITIAL_CLUSTER=""; ETCD_HOSTS=""
for n in "${NODES[@]}"; do
  n="$(echo "$n" | xargs)"; [ -z "$n" ] && continue
  INITIAL_CLUSTER+="${INITIAL_CLUSTER:+,}${n%%.*}=http://$n:2380"
  ETCD_HOSTS+="${ETCD_HOSTS:+,}$n:2379"
done

# Self-signed TLS cert (on the volume) so clients can use sslmode=require through the TCP proxy.
TLS="$DATA_ROOT/tls"
if [ ! -s "$TLS/server.key" ]; then
  openssl req -new -x509 -days "${SSL_CERT_DAYS:-3650}" -nodes -subj "/CN=$SELF" \
    -keyout "$TLS/server.key" -out "$TLS/server.crt" >/dev/null 2>&1
  chmod 600 "$TLS/server.key"
fi

CFG="$PATRONICTL_CONFIG_FILE"
cat > "$CFG" <<YAML
scope: ${PATRONI_SCOPE}
name: ${NAME}
log:
  level: INFO
restapi:
  listen: "*:8008"
  connect_address: "${SELF}:8008"
etcd3:
  hosts: "${ETCD_HOSTS}"
bootstrap:
  dcs:
    ttl: ${PATRONI_TTL}
    loop_wait: ${PATRONI_LOOP_WAIT}
    retry_timeout: ${PATRONI_RETRY_TIMEOUT}
    maximum_lag_on_failover: ${PATRONI_MAX_LAG_ON_FAILOVER}
    failsafe_mode: true
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        max_connections: ${PG_MAX_CONNECTIONS}
        wal_level: replica
        hot_standby: "on"
        max_wal_senders: 10
        max_replication_slots: 10
        wal_keep_size: 512MB
        wal_log_hints: "on"
        password_encryption: scram-sha-256
        shared_preload_libraries: pg_stat_statements,pg_cron
        cron.database_name: ${PGDATABASE}
  initdb:
    - encoding: UTF8
    - locale: C.UTF-8
    - data-checksums
  post_bootstrap: /usr/local/bin/post-bootstrap.sh
postgresql:
  listen: "*:5432"
  connect_address: "${SELF}:5432"
  data_dir: ${PGDATA}
  bin_dir: /usr/lib/postgresql/18/bin
  pgpass: /tmp/pgpass0
  remove_data_directory_on_rewind_failure: true
  remove_data_directory_on_diverged_timelines: true
  parameters:
    unix_socket_directories: /var/run/postgresql
    shared_buffers: ${PG_SHARED_BUFFERS}
    ssl: "on"
    ssl_cert_file: ${TLS}/server.crt
    ssl_key_file: ${TLS}/server.key
  pg_hba:
    - local all all trust
    - host replication ${PATRONI_REPLICATION_USERNAME:-replicator} 0.0.0.0/0 scram-sha-256
    - host replication ${PATRONI_REPLICATION_USERNAME:-replicator} ::/0 scram-sha-256
    - host all all 0.0.0.0/0 scram-sha-256
    - host all all ::/0 scram-sha-256
YAML

# etcd member, restarted if it ever exits.
(
  while true; do
    etcd --name "$NAME" --data-dir "$DATA_ROOT/etcd" \
      --listen-peer-urls "http://[::]:2380" --listen-client-urls "http://[::]:2379" \
      --initial-advertise-peer-urls "http://$SELF:2380" --advertise-client-urls "http://$SELF:2379" \
      --initial-cluster "$INITIAL_CLUSTER" --initial-cluster-state new \
      --initial-cluster-token "$ETCD_CLUSTER_TOKEN" \
      --heartbeat-interval 200 --election-timeout 2000 \
      --auto-compaction-mode periodic --auto-compaction-retention 1h \
      --quota-backend-bytes 1073741824 --log-level warn || true
    echo "[pg-ha] etcd exited, restarting in 3s"; sleep 3
  done
) &
ETCD_LOOP=$!

log "node=$NAME scope=$PATRONI_SCOPE etcd=$INITIAL_CLUSTER"
patroni "$CFG" &
PATRONI_PID=$!

shutdown() {
  log "SIGTERM: stopping Patroni (hands leadership over), then etcd"
  kill -TERM "$PATRONI_PID" 2>/dev/null || true
  wait "$PATRONI_PID" 2>/dev/null || true
  kill -TERM "$ETCD_LOOP" 2>/dev/null || true
  pkill -TERM -x etcd 2>/dev/null || true
  exit 0
}
trap shutdown TERM INT

set +e
wait "$PATRONI_PID"; rc=$?
log "patroni exited with $rc"
pkill -TERM -x etcd 2>/dev/null
exit "$rc"
