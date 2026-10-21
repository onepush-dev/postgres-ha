# Postgres HA router: HAProxy that follows the Patroni leader.
# :5432 read-write (current primary only), :5433 read-only (healthy replicas), :8080/health for Railway.
FROM haproxy:3.4.7-alpine@sha256:251da69821897ec8c4819f12b1babbc4b71f562943addc9b9eb14bb6ece40dc6
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
ENV HAPROXY_MAXCONN=4096 \
    HAPROXY_TIMEOUT_CLIENT=30m \
    HAPROXY_TIMEOUT_SERVER=30m \
    HAPROXY_REPLICA_MAX_LAG=16MB
EXPOSE 5432 5433 8080
