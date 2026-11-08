#!/bin/bash
# -----------------------------------------------------------------------------
# Scan this repo with the DataOpsBackbone SonarQube and fail on scanner errors,
# a failed quality gate, or any HIGH/BLOCKER/CRITICAL issue. Used locally and in CI.
#
# Steps: Trivy fs (vuln/misconfig/secret), gitleaks (history), hadolint,
#        ShellCheck, SQLFluff (external issues), lintr + R coverage (from
#        coverage/, produced by tests/run_all.sh --unit or the CI test job),
#        sonar-scanner with qualitygate.wait.
#
# Local: tools run as pinned containers; Sonar runs in a throwaway runner
#        container on the stack's network.
# CI:    on a DataOpsBackbone self-hosted runner (/sonar mounted, on sonarnet)
#        tools are pinned release binaries and Sonar runs inline.
#
# Usage: bash local-ci/sonar-self-scan.sh
# Env:   SONAR_HOST (default http://sonarqube:9000)
#        SONAR_PROJECT_KEY (default spcs-rstudio-local; ci.yml sets it per stream)
#        RUNNER_IMAGE (default brainiac/local-github-runner)
#        SKIP_TRIVY=1, SKIP_GITLEAKS=1 to skip those steps
# Out:   .sonar-issues.tsv (severity, rule, file, line, message) in the repo root
# -----------------------------------------------------------------------------
set -Eeuo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

TRIVY_VERSION="${TRIVY_VERSION:-0.76.2}"
GITLEAKS_VERSION="${GITLEAKS_VERSION:-8.30.1}"
HADOLINT_VERSION="${HADOLINT_VERSION:-2.14.0}"
SHELLCHECK_VERSION="${SHELLCHECK_VERSION:-0.11.0}"

INLINE=false
[[ -r /sonar/.sonar_env ]] && command -v sonar-scanner >/dev/null && INLINE=true

BIN=$(mktemp -d)
trap 'rm -rf "$BIN"' EXIT

# Run a pinned tool: release binary when inline, container otherwise.
fetch_bins() {
  # release asset names per architecture (the DataOpsBackbone runner is aarch64)
  local t g h s
  case "$(uname -m)" in
    aarch64|arm64) t=ARM64; g=arm64; h=arm64;  s=aarch64 ;;
    *)             t=64bit; g=x64;   h=x86_64; s=x86_64 ;;
  esac
  curl -sfL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${t}.tar.gz" \
    | tar -xz -C "$BIN" trivy
  curl -sfL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${g}.tar.gz" \
    | tar -xz -C "$BIN" gitleaks
  curl -sfL -o "$BIN/hadolint" "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-linux-${h}"
  chmod +x "$BIN/hadolint"
  # .tar.xz without needing xz on the runner (python3 has lzma)
  curl -sfL -o "$BIN/shellcheck.tar.xz" \
    "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.${s}.tar.xz"
  python3 - "$BIN" "$SHELLCHECK_VERSION" <<'PY'
import sys, tarfile, os
bindir, ver = sys.argv[1], sys.argv[2]
with tarfile.open(os.path.join(bindir, "shellcheck.tar.xz"), "r:xz") as t:
    member = t.getmember(f"shellcheck-v{ver}/shellcheck")
    member.name = "shellcheck"
    t.extract(member, bindir, filter="data")
PY
  chmod +x "$BIN/shellcheck"
  rm -f "$BIN/shellcheck.tar.xz"
}

trivy() {
  if $INLINE; then "$BIN/trivy" "$@"
  else docker run --rm -v "$REPO:/src" -w /src -v trivy-cache:/root/.cache/trivy "aquasec/trivy:$TRIVY_VERSION" "$@"; fi
}
gitleaks() {
  if $INLINE; then "$BIN/gitleaks" "$@"
  else docker run --rm -v "$REPO:/src" -w /src "zricethezav/gitleaks:v$GITLEAKS_VERSION" "$@"; fi
}
hadolint() {
  if $INLINE; then "$BIN/hadolint" "$@"
  else docker run --rm -i -v "$REPO:/src" -w /src "hadolint/hadolint:v$HADOLINT_VERSION" hadolint "$@"; fi
}
shellcheck() {
  if $INLINE; then "$BIN/shellcheck" "$@"
  else docker run --rm -v "$REPO:/src" -w /src "koalaman/shellcheck:v$SHELLCHECK_VERSION" "$@"; fi
}

$INLINE && fetch_bins

if [[ "${SKIP_TRIVY:-0}" != 1 ]]; then
  echo "=== Trivy $TRIVY_VERSION"
  trivy fs --scanners vuln,misconfig,secret --severity HIGH,CRITICAL --exit-code 1 \
    --ignorefile .trivyignore --skip-files .secrets \
    --skip-dirs coverage --skip-dirs local-ci/logs --skip-dirs .snowflake --no-progress .
fi

if [[ "${SKIP_GITLEAKS:-0}" != 1 ]]; then
  echo "=== gitleaks $GITLEAKS_VERSION (git history)"
  git config --global --add safe.directory "$REPO" 2>/dev/null || true
  gitleaks git --no-banner --redact .
fi

echo "=== hadolint $HADOLINT_VERSION"
hadolint --failure-threshold warning Dockerfile

echo "=== shellcheck $SHELLCHECK_VERSION"
SH_FILES=()
while IFS= read -r f; do SH_FILES+=("$f"); done < <(git ls-files '*.sh' 'docker/services.d/*/run')  # bash 3.2 (macOS): no mapfile
shellcheck --severity=warning "${SH_FILES[@]}"

[[ -f coverage/sonar-coverage.xml ]] \
  || echo "WARN: coverage/sonar-coverage.xml missing -- run tests/run_all.sh --unit first"

# shellcheck disable=SC2016  # expanded by the inner shell
SCAN='
  set -Eeuo pipefail
  source /sonar/.sonar_env
  git config --global --add safe.directory "$SRC"
  cd "$SRC"
  WORK=$(mktemp -d)
  trap "rm -rf $WORK" EXIT
  bash /usr/local/bin/sqlfluff-to-sonar.sh sql "$WORK/sqlfluff_issues.json" 0 >/dev/null
  echo "SQLFluff findings: $(jq ".issues | length" "$WORK/sqlfluff_issues.json")"
  EXT="$WORK/sqlfluff_issues.json"
  [[ -f coverage/lintr_issues.json ]] && EXT="$EXT,coverage/lintr_issues.json"
  COV=()
  [[ -f coverage/sonar-coverage.xml ]] && COV=(-Dsonar.coverageReportPaths=coverage/sonar-coverage.xml)
  RC=0
  sonar-scanner -Dsonar.host.url="$H" -Dsonar.token="$SONAR_TOKEN" -Dsonar.projectKey="$KEY" \
    -Dsonar.projectName="$NAME" "${COV[@]}" \
    -Dsonar.externalIssuesReportPaths="$EXT" \
    -Dsonar.working.directory="$WORK/.scannerwork" -Dsonar.qualitygate.wait=true \
    >"$WORK/scanner.log" 2>&1 || RC=$?
  grep -E "ERROR|WARN.*(coverage|external)|ANALYSIS SUCCESSFUL|QUALITY GATE|EXECUTION" "$WORK/scanner.log" || true
  q() { curl -sf -u "$SONAR_TOKEN:" "$H/api/issues/search?componentKeys=$KEY&issueStatuses=OPEN,CONFIRMED&ps=500&$1"; }
  ALL=$(q "")
  echo "Open issues (all severities): $(jq .total <<<"$ALL")"
  jq -r ".issues[] | [(.impacts|map(.severity)|join(\"/\")) + \"|\" + .severity, .rule,
    (.component|sub(\"^[^:]*:\";\"\")), (.line//0|tostring), .message] | @tsv" <<<"$ALL" \
    | sort -k3,3 -k4,4n | tee .sonar-issues.tsv
  ISSUES=$(jq -s "[.[].issues[]] | unique_by(.key)" \
    <(q "impactSeverities=BLOCKER,HIGH") <(q "severities=BLOCKER,CRITICAL"))
  COUNT=$(jq length <<<"$ISSUES")
  echo "HIGH/BLOCKER/CRITICAL issues: $COUNT"
  # informational: the shared sonar-init token may lack hotspot browse permission (403)
  HOT=$(curl -sf -u "$SONAR_TOKEN:" "$H/api/hotspots/search?project=$KEY&status=TO_REVIEW&ps=500" \
    | jq .paging.total 2>/dev/null || echo "n/a (token cannot read hotspots)")
  echo "Security hotspots to review: $HOT"
  [[ "$RC" -eq 0 ]] || { echo "sonar-scanner or quality gate failed (exit $RC)"; tail -n 20 "$WORK/scanner.log"; exit "$RC"; }
  [[ "$COUNT" -eq 0 ]]
'

export H="${SONAR_HOST:-http://sonarqube:9000}"
export KEY="${SONAR_PROJECT_KEY:-spcs-rstudio-local}"
case "$KEY" in
  spcs-rstudio) NAME="spcs-rstudio (main)" ;;
  *-local-pr) NAME="spcs-rstudio (pull requests)" ;;
  *) NAME="spcs-rstudio (self-scan)" ;;
esac
export NAME

echo "=== SonarQube ($KEY)"
if $INLINE; then
  SRC="$REPO" bash -c "$SCAN"
  exit
fi

NETWORK=$(docker network ls --format '{{.Name}}' | grep -m1 'sonarnet$' || true)
VOLUME=$(docker volume ls --format '{{.Name}}' | grep -m1 'sonar_env$' || true)
[[ -n "$NETWORK" && -n "$VOLUME" ]] || { echo "ERROR: DataOpsBackbone stack not running -- run its ./start.sh first"; exit 1; }

docker run --rm --network "$NETWORK" \
  -v "$VOLUME:/sonar:ro" -v "$REPO:/src" -w /src \
  -e H -e KEY -e NAME -e SRC=/src \
  --user root --entrypoint bash "${RUNNER_IMAGE:-brainiac/local-github-runner}" -c "$SCAN"
