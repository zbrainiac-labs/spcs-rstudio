#!/usr/bin/env bash
# Live local test: seed Snowflake, then run R/examples/snowflake_test.R in the
# image as the rstudio user with PAT credentials (no SPCS needed).
# Usage: tests/snowflake_local.sh [image]   (default: spcs-rstudio:local)
# Env:   SNOW_CONNECTION (seeding), SECRETS_FILE (default: .secrets with
#        SNOWFLAKE_HOST / SNOWFLAKE_USER / SNOWFLAKE_TOKEN)
set -euo pipefail

cd "$(dirname "$0")/.."
IMAGE="${1:-spcs-rstudio:local}"
SECRETS_FILE="${SECRETS_FILE:-.secrets}"
[[ -r "$SECRETS_FILE" ]] || { echo "FAIL no ${SECRETS_FILE} (SNOWFLAKE_HOST/USER/TOKEN)"; exit 1; }

tests/seed.sh

OUT=$(docker run --rm --platform "${PLATFORM:-linux/arm64}" --env-file "$SECRETS_FILE" \
  -u rstudio -e HOME=/home/rstudio --entrypoint Rscript "$IMAGE" /home/rstudio/snowflake_test.R 2>&1) \
  || { echo "$OUT" | tail -20; echo "FAIL snowflake_test.R exited non-zero"; exit 1; }

echo "$OUT" | grep -q "Connected to Snowflake via pat" || { echo "$OUT" | tail -20; echo "FAIL not connected via PAT"; exit 1; }
echo "PASS connected via PAT as rstudio user"
echo "$OUT" | grep -q "Results written to R_SPCS_DB.PUBLIC.RST_SAMPLE_DATA_SUMMARY" || { echo "FAIL summary not written"; exit 1; }
echo "$OUT" | grep -q "Done!" || { echo "FAIL snowflake_test.R did not finish"; exit 1; }
echo "PASS snowflake_test.R read RST_SAMPLE_DATA and wrote RST_SAMPLE_DATA_SUMMARY"
