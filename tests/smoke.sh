#!/usr/bin/env bash
# Runtime smoke test: start the image and check RStudio + ODBC.
# Usage: tests/smoke.sh [image]   (default: spcs-rstudio:local)
set -euo pipefail

IMAGE="${1:-spcs-rstudio:local}"
NAME="spcs-rstudio-smoke-$$"

cleanup() { docker rm -f "$NAME" > /dev/null 2>&1 || true; }
trap cleanup EXIT

# No published port: checks run inside the container via docker exec, so they
# work the same on the host, under act (job in a container) and on GitHub.
docker run -d --name "$NAME" --platform "${PLATFORM:-linux/arm64}" \
  -e DISABLE_AUTH=true -e RSTUDIO_ALLOWED_USER=SMOKE_USER "$IMAGE" > /dev/null

rstudio_up() { docker exec "$NAME" curl -fs -o /dev/null http://localhost:8787/; }

echo "Waiting for RStudio on :8787..."
for _ in $(seq 1 60); do
  if rstudio_up; then
    echo "PASS RStudio responds with HTTP 200"
    break
  fi
  sleep 2
done
rstudio_up || { echo "FAIL RStudio not reachable"; docker logs "$NAME"; exit 1; }

# SPCS readiness probe path must answer exactly 200 (RStudio's "/" is a 302)
HEALTH=$(docker exec "$NAME" curl -s -o /dev/null -w '%{http_code}' http://localhost:8787/healthz)
[[ "$HEALTH" == "200" ]] || { echo "FAIL /healthz returned ${HEALTH}, SPCS readiness needs 200"; exit 1; }
echo "PASS /healthz returns 200 (SPCS readiness probe)"

# nginx in front of RStudio (caller's rights, single user)
http_code() { docker exec "$NAME" curl -s -o /dev/null -w '%{http_code}' "$@" http://localhost:8787/; }
[[ "$(http_code -H 'Sf-Context-Current-User: OTHER_USER')" == "403" ]] \
  || { echo "FAIL other SPCS user not rejected"; exit 1; }
echo "PASS other SPCS user gets 403"
[[ "$(http_code -H 'Sf-Context-Current-User: smoke_user' -H 'Sf-Context-Current-User-Token: smoke-token-1')" =~ ^(200|302)$ ]] \
  || { echo "FAIL allowed SPCS user not admitted"; exit 1; }
echo "PASS allowed SPCS user admitted (case-insensitive)"
sleep 1
[[ "$(docker exec "$NAME" tail -n 1 /run/sf-caller/token.log)" == "smoke-token-1" ]] \
  || { echo "FAIL caller token not captured"; exit 1; }
echo "PASS caller token captured for R"
[[ "$(docker exec "$NAME" stat -c '%a %U:%G' /run/sf-caller/token.log)" == "640 root:rstudio" ]] \
  || { echo "FAIL token file permissions: $(docker exec "$NAME" stat -c '%a %U:%G' /run/sf-caller/token.log)"; exit 1; }
docker exec -u rstudio "$NAME" test -r /run/sf-caller/token.log || { echo "FAIL rstudio cannot read token"; exit 1; }
echo "PASS token file 0640 root:rstudio, readable by rstudio only"
docker exec "$NAME" curl -fs -o /dev/null http://localhost:8788/ \
  || { echo "FAIL RStudio not on 127.0.0.1:8788 behind nginx"; exit 1; }
docker exec "$NAME" sh -c 'tr "\0" " " < /proc/$(pgrep -o rserver)/cmdline' | grep -q -- '--www-address=127.0.0.1' \
  || { echo "FAIL RStudio not bound to localhost"; exit 1; }
echo "PASS RStudio bound to 127.0.0.1:8788, only reachable through nginx"

if docker exec "$NAME" Rscript -e "quit(status = !any(grepl('Snowflake', odbc::odbcListDrivers()\$name)))"; then
  echo "PASS Snowflake ODBC driver visible to R"
else
  echo "FAIL Snowflake ODBC driver not visible"; exit 1
fi

if docker exec "$NAME" Rscript /home/rstudio/helloworld.R > /dev/null; then
  echo "PASS helloworld.R runs"
else
  echo "FAIL helloworld.R"; exit 1
fi

# .trivyignore DS-0002: only s6 /init runs as root; RStudio's rserver drops to a
# non-root service user (rsession, spawned per browser session, runs as rstudio).
SERVER_USER=$(docker exec "$NAME" ps -o user:32= -C rserver 2>/dev/null | head -1 | tr -d ' ' || true)
if [[ -n "$SERVER_USER" && "$SERVER_USER" != "root" ]]; then
  echo "PASS rserver runs as non-root user ${SERVER_USER}"
else
  echo "FAIL rserver user is '${SERVER_USER:-none}' (expected non-root)"; exit 1
fi

# rocker init tries chpasswd even with DISABLE_AUTH=true; that failure is expected
if docker logs "$NAME" 2>&1 \
    | grep -Ev 'chpasswd: \(user rstudio\) pam_chauthtok\(\) failed|^Authentication token manipulation error$' \
    | grep -Ei '\b(error|fatal)\b'; then
  echo "FAIL errors in container log"; exit 1
fi
echo "PASS no errors in container log"
