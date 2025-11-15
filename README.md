# `grafana-dashboard-import`

Small, standalone Alpine-based helper container for automatic provisioning of Grafana dashboards via API, without bind-mounts and without modifying Grafana image — just drop it into any Docker Compose or Swarm stack.

## Features

- As uploaded via API, dashboards are editable and deletable.
- Supports local dashboard JSON files (`*.json`).
- Supports "link files" (`*.txt`) containing one URL per line.
- Idempotent: dashboards are overwritten only if needed.
- Requires only Grafana username/password (basic auth).
- Tiny footprint: one BusyBox shell script and curl

## Environment variables

| Variable | Default value | Description |
|-|-|-|
| `GRAFANA_URL` | `http://grafana:3000` | Base URL of Grafana instance |
| `GRAFANA_USER` | `admin` | Username for Grafana API |
| `GRAFANA_PASS` | `admin` | Password for Grafana API |
| `GRAFANA_PASS_FILE` | | File to read password from, overwrites `GRAFANA_PASS` |
| `DASHBOARD_DIR` | `/dashboards` | Directory to scan for `*.json` / `*.txt` |
| `WAIT_FOR_IT_TIMEOUT` | `15` | Seconds to wait until `$GRAFANA_URL` will be available |
| `GRAFANA_DASHBOARD_*` | | URL of dashboard(s) |

### Dashboard URLs via envvars

Any environment variable starting with `GRAFANA_DASHBOARD_` is treated as a URL to a dashboard JSON. Example:

```bash
GRAFANA_DASHBOARD_NODE_EXPORTER=https://grafana.com/api/dashboards/1860/revisions/42/download
GRAFANA_DASHBOARD_CUSTOM=https://example.org/mydashboard.json
```

These are downloaded and uploaded automatically.

## Usage

### File formats

#### Local JSON files (`*.json`):

Must contain a valid Grafana dashboard object.

**NOTE:** Old Grafana.com dashboard (Grafana 5/6 era) JSONs are **NOT valid Grafana import format**.

#### Link lists (`*.txt`):

Each line should contain a single URL:

```plain
https://example.org/foo.json
https://grafana.com/api/dashboards/xxx/revisions/yyy/download
https://raw.githubusercontent.com/.../dashboard.json
```

Empty lines and `# comments` are ignored.

### Logs example

```plain
2025-11-15 17:35:23 [grafana-init]: Waiting 15 seconds for host.docker.internal:8080
2025-11-15 17:35:23 [grafana-init]: host.docker.internal:8080 is available after 0s
2025-11-15 17:35:23 [grafana-init]: Checking Grafana API
2025-11-15 17:35:23 [grafana-init]: Scanning environment for GRAFANA_DASHBOARD_* variables
2025-11-15 17:35:23 [grafana-init]: Processing GRAFANA_DASHBOARD_NODE_EXPORTER: https://grafana.com/api/dashboards/1860/revisions/42/download
2025-11-15 17:35:24 [grafana-init]: Successfully downloaded to /tmp/grafana_dashboard_EFfiGI
2025-11-15 17:35:24 [grafana-init]: Uploading /tmp/grafana_dashboard_EFfiGI
2025-11-15 17:35:24 [grafana-init]: Successfully uploaded /tmp/grafana_dashboard_EFfiGI
2025-11-15 17:35:24 [grafana-init]: Processing file /dashboards/external.txt
2025-11-15 17:35:24 [grafana-init]: Processing https://grafana.com/api/dashboards/1860/revisions/42/download
2025-11-15 17:35:24 [grafana-init]: Successfully downloaded to /tmp/grafana_dashboard_KoKoKo
2025-11-15 17:35:24 [grafana-init]: Uploading /tmp/grafana_dashboard_KoKoKo
2025-11-15 17:35:24 [grafana-init]: Successfully uploaded /tmp/grafana_dashboard_KoKoKo
2025-11-15 17:35:24 [grafana-init]: Uploading /dashboards/1860_rev42.json
2025-11-15 17:35:25 [grafana-init]: Successfully uploaded /dashboards/1860_rev42.json
```

### Exit behavior

`grafana-init` terminates the container with `exit 0` only when Grafana API is reachable and healthy and all dashboards are imported successfully. Otherwise it logs the error and exits non-zero. This is appropriate for init containers in Compose or Kubernetes.

### Common pitfalls the script protects against

- Wrong Grafana URL.
- Wrong credentials.
- Bad subpath (`/grafana` without proper Grafana config e.g. `GF_SERVER_ROOT_URL`).
- Traefik/nginx serving HTML instead of Grafana API.
- Network failures or HTTPS issues.

### Docker Compose example

```yaml
services:
  grafana:
    image: grafana/grafana:latest
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
      GF_SERVER_ROOT_URL: http://grafana:3000/grafana
      GF_SERVER_SERVE_FROM_SUB_PATH: "true"

    labels:
      # Traefik example
      traefik.http.routers.grafana.rule: PathPrefix(`/grafana`)

    ports:
      - "3000:3000"

  grafana-init:
    image: apozlevich/grafana-dashboard-import:latest
    depends_on:
      - grafana

    environment:
      GRAFANA_URL: http://grafana:3000/grafana
      GRAFANA_USER: admin
      GRAFANA_PASS: admin

      # Auto-import these dashboards
      GRAFANA_DASHBOARD_NODE_EXPORTER: https://grafana.com/api/dashboards/1860/revisions/42/download
      GRAFANA_DASHBOARD_VM: https://example.org/vm.json

    # Optional: provide local dashboards
    volumes:
      - ./dashboards:/dashboards:ro
```

## Limitations

- Remote URLs must serve raw JSON without authentication.
- Dashboards must contain valid `uid` fields if overwrite behavior is desired.

# License

MIT.
