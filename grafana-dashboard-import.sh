#!/usr/bin/env ash
# shellcheck shell=dash

# MIT License
#
# Copyright (c) 2025 Alexander Pozlevich
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -e

log() { echo "$(date +"%Y-%m-%d %H:%M:%S") [grafana-init]: $*"; }
fail() { log "Error: $*" >&2 && exit 1; }

# Check provided URL is Grafana API, not web interface (in case of misconfigured
# subpath) and what Grafana is healthy.
check_grafana() {
    URL="$GRAFANA_URL/api/health"
    START_TS=$(date +%s)
    log "Waiting for Grafana API at $GRAFANA_URL for $GRAFANA_WAIT_TIMEOUT seconds"

    while true; do
        RESPONSE=$(
            curl --fail --silent --show-error --insecure \
                --write-out "HTTPSTATUS:%{http_code}" "$URL"
        )

        # Parse status code. Expected only 200.
        RC=$?
        HTTP_BODY=$(printf "%s" "$RESPONSE" | sed -e 's/HTTPSTATUS:.*//')
        HTTP_CODE=$(printf "%s" "$RESPONSE" | sed -ne 's/.*HTTPSTATUS://p')

        if [ "$RC" -ne 0 ]; then
            fail "curl transport failure: $RC"
        else
            # May be HTML instead of JSON.
            if [ "$HTTP_CODE" = "200" ]; then
                if printf "%s" "$HTTP_BODY" | grep -qi '<html>'; then
                    fail "misconfigured subpath: got HTML instead of API JSON"
                fi

                # Healthcheck passed.
                if printf "%s" "$HTTP_BODY" | grep -q '"database"[[:space:]]*:[[:space:]]*"ok"'; then
                    log "Grafana API is healthy"
                    return 0
                fi
            fi
        fi

        # Not yet ready - check timeout.
        elapsed=$(( $(date +%s)-START_TS ))
        if [ "$elapsed" -ge "$GRAFANA_WAIT_TIMEOUT" ]; then
            fail "Grafana API not ready after $GRAFANA_WAIT_TIMEOUT seconds"
        fi

        sleep 1
    done
}

# Theoretically, this should normalize all exports and grafana.com downloads
# since ancient versions. Guess who never tested.
normalize_json() {
    IN=$1
    OUT=$(mktemp /tmp/grafana_normalized_XXXXXX)

    jq '
        # Get dashboard from wrapper if it exists
        (.dashboard // .)
        # Delete some conflicting API fields
        | del(.meta, .gnetId, .revision)
        # ID should be null to support creation, not only updating
        | (.id = null)
        # Final modern payload
        | { dashboard: ., overwrite: true, folderId: (env.GRAFANA_FOLDER_ID // 0 | tonumber) }
    ' "$IN" > "$OUT"

    mv -f "$OUT" "$IN"
}

# Uploads JSON from disk.
upload_json() {
    JSONFILE="$1"
    URL="$GRAFANA_URL/api/dashboards/db"

    log "Uploading $JSONFILE"
    normalize_json "$JSONFILE"

    # Writes to STDOUT received text and status code.
    RESPONSE=$(
        curl --fail --silent --show-error --insecure \
            --write-out "HTTPSTATUS:%{http_code}" \
            --user "$GRAFANA_USER:$GRAFANA_PASS" \
            --header "Content-Type: application/json" \
            --request POST "$URL" \
            --data @"$JSONFILE"
    )

    # Save exit code, received text and status code.
    RC=$?
    HTTP_BODY=$(printf "%s" "$RESPONSE" | sed -e 's/HTTPSTATUS:.*//')
    HTTP_CODE=$(printf "%s" "$RESPONSE" | sed -ne 's/.*HTTPSTATUS://p')

    # Handle errors. At least one error terminates process.
    if [ "$RC" -ne 0 ]; then
        fail "curl transport failure: $RC"
    else
        case "$HTTP_CODE" in
            200|201)
                log "Successfully uploaded $JSONFILE"
                ;;
            401)
                fail "unauthorized (wrong GRAFANA_USER/GRAFANA_PASS)"
                ;;
            404)
                log "either endpoint ($GRAFANA_URL/api/dashboards/db) not found or badly formatted JSON"
                fail "do NOT download JSON from grafana.com, they are not valid dashboard import format"
                ;;
            *)
                log "Received content: $HTTP_BODY"
                fail "unexpected HTTP status code $HTTP_CODE"
                ;;
        esac
    fi
}

# Downloads JSON from network and uploads to Grafana.
download_and_upload_json() {
    URL="$1"
    DOWNLOAD=$(mktemp /tmp/grafana_dashboard_XXXXXX)

    RESPONSE=$(
        curl --fail --silent --show-error --insecure --location \
        --write-out "HTTPSTATUS:%{http_code}" \
        --output "$DOWNLOAD" "$URL"
    )

    # Parse status code. Expected only 200.
    RC=$?
    HTTP_CODE=$(printf "%s" "$RESPONSE" | sed -ne 's/.*HTTPSTATUS://p')

    if [ "$RC" -ne 0 ]; then
        fail "curl transport failure: $RC"
    else
        case "$HTTP_CODE" in
            200)
                log "Successfully downloaded to $DOWNLOAD"
                ;;
            *)
                fail "unexpected HTTP status code $HTTP_CODE"
                ;;
        esac
    fi

    upload_json "$DOWNLOAD"
    rm -f "$DOWNLOAD"
}

# Process all JSON files in directory.
process_json_files() {
    find "$DASHBOARD_DIR" -mindepth 1 -maxdepth 1 -type f -iname '*.json' | \
    while IFS= read -r DASHBOARD_FILE; do
        upload_json "$DASHBOARD_FILE"
    done
}

# Process all text files in directory.
process_text_files() {
    find "$DASHBOARD_DIR" -mindepth 1 -maxdepth 1 -type f -iname '*.txt' | \
    while IFS= read -r LINKS_FILE; do
        log "Processing file $LINKS_FILE"

        while IFS= read -r URL ; do
            # Trim leading whitespace
            URL=$(printf '%s' "$URL" | sed 's/^[[:space:]]*//')
            
            # Skip empty or commented lines
            case "$URL" in
                ''|\#*)
                    continue
                    ;;
            esac

            log "Processing $(printf '%s' "$URL")"
            download_and_upload_json "$URL"
        done < "$LINKS_FILE"
    done
}

# Download by URLs from envvars, if some.
process_from_env() {
    PREFIX="GRAFANA_DASHBOARD_"
    log "Scanning environment for $PREFIX* variables"

    printenv | while IFS= read -r LINE; do
        [ -z "$LINE" ] && continue

        VAR=${LINE%%=*}
        VALUE=${LINE#*=}

        case "$VAR" in
            ${PREFIX}*)

            case "$VALUE" in
                http://*|https://*)
                    [ -z "$LINE" ] && continue

                    log "Processing $VAR: $VALUE"
                    download_and_upload_json "$VALUE"
                    ;;
                *)
                    fail "Variable $VAR does not contain a valid URL: $(printf '%s' "$VALUE")"
                    ;;
            esac
        esac
    done
}

# Remove trailing slash to avoid redirections.
GRAFANA_URL="${GRAFANA_URL%/}"

# Read secret if provided.
if [ -n "$GRAFANA_PASS_FILE" ] ; then
    log "Reading password from $GRAFANA_PASS_FILE"

    if [ ! -f "$GRAFANA_PASS_FILE" ] ; then
        fail "no such file: $GRAFANA_PASS_FILE"
    fi

    GRAFANA_PASS=$(head -n1 "$GRAFANA_PASS_FILE")
fi

check_grafana
process_from_env
process_text_files
process_json_files
