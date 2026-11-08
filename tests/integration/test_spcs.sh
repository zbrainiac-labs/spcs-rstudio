#!/usr/bin/env bash
# SPCS integration test, run after a deploy.
# Env:
#   SNOW_CONNECTION  snow CLI connection (default: DEMO_MDAEPPEN)
#   IMAGE_TAG        expected deployed tag (default: sha-<git short sha>)
#
# The caller's-rights path (R as the signed-in user) needs a browser session
# through the endpoint and is checked manually, see README. This test proves
# the parts that can run headless: service READY with the right image, public
# endpoint, internal OAuth without EAI, and that the owner role RSTUDIO_RUNTIME
# (reachable with the plain service token) has no access to the data.
set -euo pipefail

cd "$(dirname "$0")/../.."
SNOW_CONNECTION="${SNOW_CONNECTION:-DEMO_MDAEPPEN}"
IMAGE_TAG="${IMAGE_TAG:-sha-$(git rev-parse --short HEAD)}"
SERVICE="R_SPCS_DB.PUBLIC.RSTUDIO_SERVICE"
JOB="R_SPCS_DB.PUBLIC.RSTUDIO_IT_$(date +%s)"
RUNTIME_ROLE="RSTUDIO_RUNTIME"

sql_json() { snow sql --connection "$SNOW_CONNECTION" --format json -q "$1"; }
fail() { echo "FAIL $*"; exit 1; }

SNOW_CONNECTION="$SNOW_CONNECTION" tests/seed.sh

STATUS_JSON=$(sql_json "SELECT SYSTEM\$GET_SERVICE_STATUS('${SERVICE}') AS S")
echo "$STATUS_JSON" | python3 -c '
import sys, json
s = json.loads(json.load(sys.stdin)[0]["S"])[0]
print("status:", s["status"], "image:", s.get("image", ""))
sys.exit(0 if s["status"] == "READY" else 1)' || fail "service not READY"
echo "PASS service READY"

echo "$STATUS_JSON" | grep -q ":${IMAGE_TAG}" || fail "deployed image is not :${IMAGE_TAG}"
echo "PASS deployed image tag ${IMAGE_TAG}"

OWNER=$(sql_json "SHOW SERVICES LIKE 'RSTUDIO_SERVICE' IN SCHEMA R_SPCS_DB.PUBLIC" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["owner"])')
[[ "$OWNER" == "$RUNTIME_ROLE" ]] || fail "service owner is ${OWNER}, expected ${RUNTIME_ROLE}"
echo "PASS service owner role ${OWNER}"

sql_json "SHOW ENDPOINTS IN SERVICE ${SERVICE}" \
  | python3 -c 'import sys,json; u=[e["ingress_url"] for e in json.load(sys.stdin) if e["name"]=="rstudio"]; print("endpoint:", u[0]); sys.exit(0 if u and "." in u[0] else 1)' \
  || fail "no public rstudio endpoint"
echo "PASS public endpoint provisioned"

# Job service in the deployed image, created by the owner role so it runs as
# RSTUDIO_RUNTIME: owner-mode connect must work (internal OAuth, no EAI) and
# reading the sample table must be denied (least privilege for the plain token).
cleanup() { snow sql --connection "$SNOW_CONNECTION" --role "$RUNTIME_ROLE" -q "DROP SERVICE IF EXISTS ${JOB}" > /dev/null 2>&1 || true; }
trap cleanup EXIT

R_CHECK='source("/home/rstudio/connect.R"); con <- sf_connect();
cat("ROLE=", DBI::dbGetQuery(con, "SELECT CURRENT_ROLE() AS R")$R, "\n", sep = "");
denied <- inherits(try(DBI::dbGetQuery(con, "SELECT COUNT(*) FROM RST_SAMPLE_DATA"), silent = TRUE), "try-error");
cat("DATA_DENIED=", denied, "\n", sep = "")'

# ASYNC + explicit wait: a synchronous EXECUTE JOB SERVICE blocks forever when
# the pool has no free capacity. Small requests so it fits next to RStudio on
# the single 1-vCPU node (tests/spec_check.sh guards the budget).
rsql() { snow sql --connection "$SNOW_CONNECTION" --role "$RUNTIME_ROLE" "$@"; }
JOB_TIMEOUT="${JOB_TIMEOUT:-300}"

rsql -q "
EXECUTE JOB SERVICE IN COMPUTE POOL RSTUDIO_POOL NAME = ${JOB} ASYNC = TRUE
FROM SPECIFICATION \$\$
spec:
  containers:
  - name: rtest
    image: /R_SPCS_DB/PUBLIC/RSTUDIO_REPO/rstudio-spcs:${IMAGE_TAG}
    command: [\"Rscript\", \"-e\", $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$R_CHECK")]
    env:
      SPCS_AUTH_MODE: owner
      SNOWFLAKE_WAREHOUSE: \"${SNOWFLAKE_WAREHOUSE:-MD_TEST_WH}\"
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
\$\$" || fail "could not submit the owner-mode job service"

echo "Waiting up to ${JOB_TIMEOUT}s for job ${JOB}..."
STATE=$(rsql --format json -q "CALL ${JOB}!SPCS_WAIT_FOR('DONE', ${JOB_TIMEOUT})" \
  | python3 -c 'import sys,json; r=json.load(sys.stdin)[0]; print(next(iter(r.values())))' || echo "UNKNOWN")
LOGS=$(rsql -q "SELECT SYSTEM\$GET_SERVICE_LOGS('${JOB}', 0, 'rtest')" 2>&1 || true)
# SPCS_WAIT_FOR returns a sentence, e.g. "<job> reached target status DONE."
if [[ "$STATE" != *"reached target status DONE"* ]]; then
  rsql -q "SELECT SYSTEM\$GET_SERVICE_STATUS('${JOB}')" || true
  echo "$LOGS" | tail -20
  fail "owner-mode job ended as '${STATE}' within ${JOB_TIMEOUT}s"
fi
echo "PASS owner-mode job finished (${STATE})"
echo "$LOGS" | grep -q "ROLE=${RUNTIME_ROLE}" || { echo "$LOGS" | tail -20; fail "job did not connect as ${RUNTIME_ROLE}"; }
echo "PASS internal OAuth connect without EAI as ${RUNTIME_ROLE}"
echo "$LOGS" | grep -q "DATA_DENIED=TRUE" || fail "owner role can read RST_SAMPLE_DATA (should be denied)"
echo "PASS owner role cannot read data (plain service token is harmless)"
