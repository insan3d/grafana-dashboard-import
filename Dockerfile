ARG ALPINE_TAG="3.22.2"

FROM alpine:${ALPINE_TAG} AS grafana-init

ARG ALPINE_TAG

ENV DASHBOARD_DIR="/dashboards" \
    GRAFANA_FOLDER_ID="0" \
    GRAFANA_PASS="admin" \
    GRAFANA_URL="http://grafana:3000" \
    GRAFANA_USER="admin" \
    GRAFANA_WAIT_TIMEOUT="15"

# hadolint ignore=DL3018
RUN --mount=type=cache,id=apk_cache_${ALPINE_TAG},target=/var/cache/apk,sharing=locked \
    apk add ca-certificates \
            curl \
            jq \
 \
 && mkdir -pv /dashboards

COPY ./grafana-dashboard-import.sh /usr/local/bin/grafana-dashboard-import

VOLUME [ "/dashboards" ]

CMD [ "grafana-dashboard-import" ]

LABEL org.opencontainers.image.title="grafana-dashboard-import" \
      org.opencontainers.image.source="https://github.com/insan3d/grafana-dashboard-import" \
      org.opencontainers.image.licenses="MIT"
