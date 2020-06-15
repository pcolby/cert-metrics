#! /bin/bash
#
# A simple script for fetching some TLS certificate metrics, and exporting them in
# Graphite format. Useful for monitoring upcoming certificate expirations, for example.
#

set -Ceuo pipefail

: "${GRAFANA_URL:=https://graphite-us-central1.grafana.net/metrics}"
[ -n "${GRAFANA_USER_ID:-}" ] || { echo "GRAFANA_USER_ID not set" >&2; }
[ -n "${GRAFANA_API_KEY:-}" ] || { echo "GRAFANA_API_KEY not set" >&2; }
: "${METRIC_NAME_PREFIX:=certificate.}"

function require {
  local C;
  for c in "$@"; do
    if [ -v "${c^^}" ]; then continue; fi
    C=$(command -v "$c") || { echo "Required command not found: $c" >&2; exit 1; }
    declare -gr "${c^^}"="$C"
  done
}

require curl date openssl

[ $# -lt 1 ] || unset HOSTS

readonly NOW="$(date +%s)"
readonly METRIC_FORMAT="$(cat <<-"-"
{
  "name": "%s",
  "interval": 10,
  "time": %d,
  "value": %d,
  "mtype": "gauge"
},
-
)"
readonly METRICS=$(
  for host in "$@" ${HOSTS:-}; do
    metricName="$METRIC_NAME_PREFIX${host//[^a-zA-Z0-9]/_}"
    [[ "$host" == *:* ]] || host="$host:443"
    cert=$("$OPENSSL" s_client -connect "$host" -servername "${host%:*}" -strict -verify_quiet < /dev/null)
    notBefore="$("$OPENSSL" x509 -startdate -noout <<< "$cert")"
    notBefore="$("$DATE" -d "${notBefore#*=}" '+%s')"
    notAfter="$("$OPENSSL" x509 -enddate -noout <<< "$cert")"
    notAfter="$("$DATE" -d "${notAfter#*=}" '+%s')"
    echo "$host $notBefore $notAfter" >&2
    printf "$METRIC_FORMAT" "$metricName.notBefore.abs" "$NOW" "$notBefore"
    printf "$METRIC_FORMAT" "$metricName.notBefore.age" "$NOW" "$((NOW-notBefore))"
    printf "$METRIC_FORMAT" "$metricName.notAfter.abs"  "$NOW" "$notAfter"
    printf "$METRIC_FORMAT" "$metricName.notAfter.ttl"  "$NOW" "$((notAfter-NOW))"
  done
)

[ -z "${GRAFANA_API_KEY:-}" ] && echo "[${METRICS%?}]" ||
  "$CURL" -u "$GRAFANA_USER_ID:$GRAFANA_API_KEY" -H "Content-Type: application/json" "$GRAFANA_URL" -sS -d "[${METRICS%?}]"
