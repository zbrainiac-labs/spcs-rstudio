#!/usr/bin/env bash
# Seed the sample data in Snowflake (idempotent). Used by the live test groups.
# Env: SNOW_CONNECTION (default: DEMO_MDAEPPEN), SEED_ROLE (default: CICD, the
#      owner of R_SPCS_DB; see sql/admin/00_setup_roles.sql)
set -euo pipefail

cd "$(dirname "$0")/.."
SNOW_CONNECTION="${SNOW_CONNECTION:-DEMO_MDAEPPEN}"
SEED_ROLE="${SEED_ROLE:-CICD}"
ssql() { snow sql --connection "$SNOW_CONNECTION" --role "$SEED_ROLE" "$@"; }

echo "Seeding R_SPCS_DB / RST_SAMPLE_DATA via ${SNOW_CONNECTION} as ${SEED_ROLE}..."
ssql -f sql/00_database.sql > /dev/null
ssql --database R_SPCS_DB --schema PUBLIC -f sql/02_sample_data.sql > /dev/null

ROWS=$(ssql --format json \
  -q "SELECT COUNT(*) AS N FROM R_SPCS_DB.PUBLIC.RST_SAMPLE_DATA" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["N"])')
[[ "$ROWS" == "8" ]] || { echo "FAIL seed: expected 8 rows, got ${ROWS}"; exit 1; }
echo "PASS seed: RST_SAMPLE_DATA has 8 rows"
