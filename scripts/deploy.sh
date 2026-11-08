#!/usr/bin/env bash
# Build, push and deploy RStudio to SPCS from a workstation.
# CI uses the same steps via .github/workflows/ci.yml.
#
# Env:
#   SNOW_CONNECTION  snow CLI connection name (default: DEMO_MDAEPPEN); its role must
#                    inherit RSTUDIO_RUNTIME (CICD, SYSADMIN), see sql/admin/00_setup_roles.sql
#   IMAGE_TAG        image tag to build/deploy (default: sha-<git short sha>)
#   RSTUDIO_ALLOWED_USER  the one Snowflake user admitted to RStudio (default: MDAEPPEN)
#   PLATFORM         image platform; must match the compute pool CPU architecture
#                    (default: linux/arm64 for RSTUDIO_POOL on GEN_ARM_G1_2)
#   SKIP_BUILD=1     push/deploy an already built image
#   SOURCE_IMAGE     existing local image to retag and push instead of building
#                    (CI: the tested image pulled from GHCR by digest)
set -euo pipefail

cd "$(dirname "$0")/.."

SNOW_CONNECTION="${SNOW_CONNECTION:-DEMO_MDAEPPEN}"
IMAGE_TAG="${IMAGE_TAG:-sha-$(git rev-parse --short HEAD)}"
RSTUDIO_ALLOWED_USER="${RSTUDIO_ALLOWED_USER:-MDAEPPEN}"
PLATFORM="${PLATFORM:-linux/arm64}"
SERVICE="R_SPCS_DB.PUBLIC.RSTUDIO_SERVICE"
IMAGE_NAME="rstudio-spcs"
# The service owner can't be changed later: always create / alter it as this role
RUNTIME_ROLE="RSTUDIO_RUNTIME"
rsql() { snow sql --connection "$SNOW_CONNECTION" --role "$RUNTIME_ROLE" "$@"; }

REPO_URL=$(snow spcs image-repository url RSTUDIO_REPO \
  --database R_SPCS_DB --schema PUBLIC --connection "$SNOW_CONNECTION")
IMAGE="${REPO_URL}/${IMAGE_NAME}:${IMAGE_TAG}"

if [[ -n "${SOURCE_IMAGE:-}" ]]; then
  echo "Using tested image ${SOURCE_IMAGE}..."
  docker tag "$SOURCE_IMAGE" "$IMAGE"
elif [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "Building ${IMAGE} (${PLATFORM})..."
  docker build --platform "$PLATFORM" -t "$IMAGE" .
fi

echo "Logging into Snowflake registry..."
snow spcs image-registry login --connection "$SNOW_CONNECTION"

echo "Pushing image..."
docker push "$IMAGE"

echo "Deploying service ${SERVICE} with ${IMAGE_TAG}..."
# Previous image, for a manual rollback: IMAGE_TAG=<previous> SKIP_BUILD=1 scripts/deploy.sh
snow sql --connection "$SNOW_CONNECTION" -q "SHOW SERVICE CONTAINERS IN SERVICE ${SERVICE}" 2>/dev/null \
  | grep -oE 'rstudio-spcs:[A-Za-z0-9._-]+' | head -1 | sed 's/^/Previous image: /' || true
SPEC=$(IMAGE_TAG="$IMAGE_TAG" RSTUDIO_ALLOWED_USER="$RSTUDIO_ALLOWED_USER" scripts/render-spec.sh)
# First deploy creates the service; later deploys update the spec in place
rsql -q "CREATE SERVICE IF NOT EXISTS ${SERVICE}
  IN COMPUTE POOL RSTUDIO_POOL
  MIN_INSTANCES = 1 MAX_INSTANCES = 1
  QUERY_WAREHOUSE = MD_TEST_WH
  FROM SPECIFICATION \$\$
${SPEC}
\$\$"
rsql -q "ALTER SERVICE ${SERVICE} FROM SPECIFICATION \$\$
${SPEC}
\$\$"
# Endpoint access for the RStudio user (nginx additionally admits only RSTUDIO_ALLOWED_USER)
rsql -q "GRANT SERVICE ROLE ${SERVICE}!ALL_ENDPOINTS_USAGE TO ROLE RSTUDIO_USER"

scripts/wait-ready.sh "$SNOW_CONNECTION" "$SERVICE"
echo "Done. Endpoint: SHOW ENDPOINTS IN SERVICE ${SERVICE};"
