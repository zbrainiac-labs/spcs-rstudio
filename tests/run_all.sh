#!/usr/bin/env bash
# Single test entry point for local runs, act and CI.
# Usage: tests/run_all.sh [--static] [--unit] [--container] [--smoke] [--snowflake] [--integration]
#        (no flags = offline groups only; --snowflake and --integration need credentials)
set -euo pipefail

cd "$(dirname "$0")/.."
IMAGE="${IMAGE:-spcs-rstudio:local}"
TEST_IMAGE="${TEST_IMAGE:-spcs-rstudio:test}"
# Default: native platform of this machine (arm64 on Apple Silicon, no emulation).
# SPCS (GEN_ARM_G1_*) runs linux/arm64; CI also builds linux/amd64.
case "$(uname -m)" in
  arm64|aarch64) NATIVE=linux/arm64 ;;
  *)             NATIVE=linux/amd64 ;;
esac
PLATFORM="${PLATFORM:-$NATIVE}"
export PLATFORM
echo "Platform: ${PLATFORM}"

if [[ $# -eq 0 ]]; then
  set -- --static --unit --container --smoke
fi

build_runtime() {
  if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    docker build --platform "$PLATFORM" -t "$IMAGE" .
  fi
  local arch
  arch=$(docker image inspect -f '{{.Os}}/{{.Architecture}}' "$IMAGE")
  [[ "$arch" == "$PLATFORM" ]] || { echo "FAIL image is ${arch}, expected ${PLATFORM}"; exit 1; }
  echo "PASS image platform ${arch}"
}

for arg in "$@"; do
  case "$arg" in
    --static)
      echo "== static: spec =="
      tests/spec_check.sh
      ;;
    --unit)
      echo "== unit: testthat + coverage =="
      docker build --platform "$PLATFORM" --target test -t "$TEST_IMAGE" .
      mkdir -p coverage
      # No bind mount: under act / self-hosted runners the docker daemon cannot see
      # the job's workspace path, so reports are copied out with docker cp.
      UNIT="spcs-rstudio-unit-$$"
      docker rm -f "$UNIT" > /dev/null 2>&1 || true
      docker run --name "$UNIT" --platform "$PLATFORM" "$TEST_IMAGE" bash -c '
        set -e
        mkdir -p /tmp/out
        Rscript -e "
          res <- testthat::test_dir(\"tests/testthat\", reporter = \"summary\", stop_on_failure = TRUE)
          cov <- covr::file_coverage(\"R/connect.R\", list.files(\"tests/testthat\", full.names = TRUE))
          print(cov)
          covr::to_sonarqube(cov, filename = \"/tmp/out/sonar-coverage.xml\")"
        Rscript tests/lint_r.R /tmp/out/lintr_issues.json' \
        || { docker rm -f "$UNIT" > /dev/null; exit 1; }
      docker cp "$UNIT:/tmp/out/." coverage/
      docker rm -f "$UNIT" > /dev/null
      # Map container paths (/src/R/..., /R/...) to repo-relative paths for Sonar
      sed -E -i.bak 's#path="/?(src/)?#path="#g' coverage/sonar-coverage.xml && rm -f coverage/sonar-coverage.xml.bak
      ;;
    --container)
      echo "== container: structure test =="
      build_runtime
      docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$PWD/tests/container:/tests:ro" \
        gcr.io/gcp-runtimes/container-structure-test:latest \
        test --image "$IMAGE" --config /tests/structure.yaml
      ;;
    --smoke)
      echo "== smoke: runtime =="
      build_runtime
      SKIP_BUILD=1
      tests/smoke.sh "$IMAGE"
      ;;
    --snowflake)
      echo "== snowflake: seed + snowflake_test.R locally (PAT) =="
      build_runtime
      SKIP_BUILD=1
      tests/snowflake_local.sh "$IMAGE"
      ;;
    --integration)
      echo "== integration: SPCS =="
      tests/integration/test_spcs.sh
      ;;
    *)
      echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

echo "All requested test groups passed."
