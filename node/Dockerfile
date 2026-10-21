# Postgres HA node: PostgreSQL 18 + Patroni + a colocated etcd member.
# Every node runs one etcd member, so 3 nodes = a 3-member etcd quorum with no extra services.
FROM quay.io/coreos/etcd:v3.7.2@sha256:e9afa62b1e914f02db62e5c46a7a140d8cdf026f2ed888cab4e5a142ec4d06fd AS etcd

FROM postgres:18.6-trixie@sha256:5486e8fb206952552c7e2eaf2e36e4c7be3cd36b2b396eb41de618aa5664a781

ARG PATRONI_VERSION=4.1.5

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 python3-venv ca-certificates curl openssl \
      postgresql-18-pgvector \
      postgresql-18-postgis-3 postgresql-18-postgis-3-scripts \
      postgresql-18-cron \
 && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/patroni \
 && /opt/patroni/bin/pip install --no-cache-dir "patroni[psycopg3,etcd3]==${PATRONI_VERSION}" \
 && ln -s /opt/patroni/bin/patroni /usr/local/bin/patroni \
 && ln -s /opt/patroni/bin/patronictl /usr/local/bin/patronictl

COPY --from=etcd /usr/local/bin/etcd /usr/local/bin/etcdctl /usr/local/bin/
COPY --chmod=755 entrypoint.sh node.sh post-bootstrap.sh /usr/local/bin/

ENV DATA_ROOT=/var/lib/postgresql/data \
    PGDATA=/var/lib/postgresql/data/pgdata \
    PATRONICTL_CONFIG_FILE=/var/lib/postgresql/patroni.yml

EXPOSE 5432 8008 2379 2380
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
