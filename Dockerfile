ARG ALPINE_TAG="3.22.2"
ARG WAIT_FOR_IT_RELEASE="https://github.com/roerohan/wait-for-it/releases/download/v0.2.14/wait-for-it"

FROM alpine:${ALPINE_TAG} AS grafana-init

ARG ALPINE_TAG
ARG WAIT_FOR_IT_RELEASE

ENV GRAFANA_URL="http://grafana:3000" \
    GRAFANA_USER="admin" \
    GRAFANA_PASS="admin" \
    DASHBOARD_DIR="/dashboards" \
    WAIT_FOR_IT_TIMEOUT="15"

# hadolint ignore=DL3020
ADD "${WAIT_FOR_IT_RELEASE}" /usr/local/bin/wait-for-it

# hadolint ignore=DL3018
RUN --mount=type=cache,id=apk_cache_${ALPINE_TAG},target=/var/cache/apk,sharing=locked \
    apk add ca-certificates \
            curl \
 \
 && chmod -v +x /usr/local/bin/wait-for-it \
 && mkdir -pv /dashboards

COPY ./dashboards/* /dashboards/
COPY ./grafana-dashboard-import.sh /usr/local/bin/grafana-dashboard-import

CMD [ "grafana-dashboard-import" ]

LABEL org.opencontainers.image.title="grafana-dashboard-import" \
      org.opencontainers.image.source="https://github.com/insan3d/grafana-dashboard-import" \
      org.opencontainers.image.licenses="MIT"
