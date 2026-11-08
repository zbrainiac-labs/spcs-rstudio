#!/usr/bin/env bash
# Render spec/rstudio-service.yaml to stdout.
# Env: IMAGE_TAG (immutable, e.g. sha-abc1234), RSTUDIO_ALLOWED_USER (Snowflake user name)
set -euo pipefail

: "${IMAGE_TAG:?IMAGE_TAG must be set (e.g. sha-abc1234)}"
: "${RSTUDIO_ALLOWED_USER:?RSTUDIO_ALLOWED_USER must be set (the one Snowflake user admitted)}"
if [[ ! "$IMAGE_TAG" =~ ^[A-Za-z0-9._-]+$ ]] || [[ "$IMAGE_TAG" == "latest" ]]; then
  echo "Invalid IMAGE_TAG '${IMAGE_TAG}' (immutable tag required, not 'latest')" >&2
  exit 1
fi
if [[ ! "$RSTUDIO_ALLOWED_USER" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
  echo "Invalid RSTUDIO_ALLOWED_USER '${RSTUDIO_ALLOWED_USER}'" >&2
  exit 1
fi

cd "$(dirname "$0")/.."
sed -e "s/\${IMAGE_TAG}/${IMAGE_TAG}/g" \
    -e "s/\${RSTUDIO_ALLOWED_USER}/${RSTUDIO_ALLOWED_USER}/g" \
    spec/rstudio-service.yaml
