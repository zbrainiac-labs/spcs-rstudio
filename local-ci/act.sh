#!/bin/bash
# -----------------------------------------------------------------------------
# Run .github/workflows/ci.yml locally with nektos/act -- same jobs as GitHub:
# lint, test, sonar, image (arm64), deploy-spcs, verify-spcs. GHCR pushes and
# attestations are skipped. Uses the working copy, so uncommitted changes are tested.
#
#   deploy-spcs runs with PAT auth (no OIDC locally): DRY_RUN by default (render
#   and validate the spec, no Snowflake changes); --full pushes the locally built
#   arm64 image to RSTUDIO_REPO and updates RSTUDIO_SERVICE, then verify-spcs
#   runs the SPCS integration test.
#
# Usage: bash local-ci/act.sh [--job=<id>] [--full] [-- <extra act args>]
#   --job=<id>   run a single job (lint | test | sonar | image | deploy-spcs | verify-spcs)
#   --full       real SPCS deploy + integration test instead of a dry run
# Env:   BACKBONE (default ../DataOpsBackbone), SNOW_CONFIG_B64 (else built from
#        the DataOpsBackbone .env via local-ci/snow-config.sh), GITHUB_TOKEN
#        (else from `gh auth token`)
# Requires: act, docker, the running DataOpsBackbone stack (SonarQube, sonarnet)
# -----------------------------------------------------------------------------
set -Eeuo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKBONE="$(cd "${BACKBONE:-$REPO/../DataOpsBackbone}" && pwd)"
JOB=""
FULL=false
ACT_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --job=*) JOB="${1#*=}" ;;
    --full) FULL=true ;;
    --) shift; ACT_ARGS=("$@"); break ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
  shift
done

for cmd in act docker; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd not found"; exit 1; }
done
NETWORK=$(docker network ls --format '{{.Name}}' | grep -m1 'sonarnet$' || true)
VOLUME=$(docker volume ls --format '{{.Name}}' | grep -m1 'sonar_env$' || true)
[[ -n "$NETWORK" && -n "$VOLUME" ]] || { echo "ERROR: DataOpsBackbone stack not running -- run its ./start.sh first"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
chmod 700 "$TMP"

# github.event.act marks local runs in ci.yml; full=true switches deploy-spcs to a real deploy
cat > "$TMP/event.json" <<JSON
{"act": true, "full": $FULL,
 "repository": {"name": "spcs-rstudio", "full_name": "zbrainiac-labs/spcs-rstudio",
                "owner": {"login": "zbrainiac-labs"}}}
JSON

# --- secrets (never echoed; files are removed on exit) -----------------------
SNOW_CONFIG_B64="${SNOW_CONFIG_B64:-}"
if [[ -z "$SNOW_CONFIG_B64" && ( -z "$JOB" || "$JOB" == deploy-spcs || "$JOB" == verify-spcs ) ]]; then
  SNOW_CONFIG_B64=$(cd "$BACKBONE" && bash local-ci/snow-config.sh) \
    || { echo "ERROR: no Snowflake credentials (SNOW_CONFIG_B64 or SNOW_* in $BACKBONE/.env)"; exit 1; }
fi
{
  echo "SNOW_CONFIG_B64=$SNOW_CONFIG_B64"
  echo "GITHUB_TOKEN=${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"
} > "$TMP/secrets"

RUN_SEQ=$(date +%s)   # act always reports run 1
{
  echo "GITHUB_RUN_NUMBER=$RUN_SEQ"
  echo "GITHUB_RUN_ID=$RUN_SEQ"
} > "$TMP/env"

# --- run ----------------------------------------------------------------------
LOG_DIR="$REPO/local-ci/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$(date +%Y%m%dT%H%M%S)-ci.log"
echo "act: ci.yml ${JOB:+job=$JOB }(deploy-spcs: $([[ $FULL == true ]] && echo 'real deploy' || echo 'dry run')) -- log: $LOG"

# self-hosted = the DataOpsBackbone runner image; ubuntu-* = act image with buildx
# (arm64 runs natively on Apple Silicon)
# --bind: all jobs share this working copy, so coverage/ (test -> sonar) needs no
# artifact server (unreachable from containers on sonarnet)
set +e
act workflow_dispatch \
  -C "$REPO" \
  -W "$REPO/.github/workflows/ci.yml" \
  -e "$TMP/event.json" \
  ${JOB:+-j "$JOB"} \
  -P self-hosted=brainiac/local-github-runner \
  -P ubuntu-latest=catthehacker/ubuntu:act-24.04 \
  -P ubuntu-24.04-arm=catthehacker/ubuntu:act-24.04 \
  --pull=false \
  --local-repository "zbrainiac-labs/DataOpsBackbone@main=$BACKBONE" \
  --network "$NETWORK" \
  --container-options "-v $VOLUME:/sonar:ro" \
  --bind \
  --secret-file "$TMP/secrets" \
  --env-file "$TMP/env" \
  ${ACT_ARGS[@]+"${ACT_ARGS[@]}"} 2>&1 | tee "$LOG"
RC=${PIPESTATUS[0]}
set -e

if grep -qE 'squ_[A-Za-z0-9]{20,}|gh[ops]_[A-Za-z0-9]{20,}' "$LOG"; then
  echo "ERROR: secret-looking value found in log $LOG"
  RC=1
fi
echo "act exit code: $RC"
exit "$RC"
