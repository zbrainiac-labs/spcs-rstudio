#!/usr/bin/env bash
# Wait until an SPCS service reports READY.
# Usage: wait-ready.sh <snow-connection> <service-fqn> [timeout-seconds]
set -euo pipefail

CONNECTION="$1"
SERVICE="$2"
TIMEOUT="${3:-600}"
DEADLINE=$((SECONDS + TIMEOUT))

while (( SECONDS < DEADLINE )); do
  STATUS=$(snow sql --connection "$CONNECTION" --format json \
    -q "SELECT PARSE_JSON(SYSTEM\$GET_SERVICE_STATUS('${SERVICE}'))[0]:status::string AS S" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["S"])')
  echo "Service status: ${STATUS}"
  if [[ "$STATUS" == "READY" ]]; then
    exit 0
  fi
  if [[ "$STATUS" == "FAILED" ]]; then
    exit 1
  fi
  sleep 15
done

echo "Timed out after ${TIMEOUT}s waiting for ${SERVICE}" >&2
exit 1
