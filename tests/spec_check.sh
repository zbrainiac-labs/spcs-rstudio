#!/usr/bin/env bash
# Static checks for the SPCS spec: required keys, placeholders, caller's rights, no secrets.
set -euo pipefail

cd "$(dirname "$0")/.."
SPEC=spec/rstudio-service.yaml
RENDERED=$(IMAGE_TAG=sha-test123 RSTUDIO_ALLOWED_USER=TEST_USER scripts/render-spec.sh)

python3 - "$RENDERED" <<'PY'
import sys, yaml
doc = yaml.safe_load(sys.argv[1])
spec = doc["spec"]
c = spec["containers"][0]
assert c["image"].endswith(":sha-test123"), "image tag not rendered"
assert c["env"]["RSTUDIO_ALLOWED_USER"] == "TEST_USER", "allowed user not rendered"
assert c["readinessProbe"]["port"] == 8787, "readinessProbe port"
# SPCS needs HTTP 200 from the probe; RStudio's "/" is a 302
assert c["readinessProbe"]["path"] == "/healthz", "readinessProbe must use /healthz (\"/\" returns 302)"
# RSTUDIO_POOL = 1 node GEN_ARM_G1_2 (1 vCPU, 6 GiB): service + integration job (100m, 256Mi) must fit
def millicpu(v): return int(v[:-1]) if str(v).endswith("m") else int(float(v) * 1000)
def mib(v): return int(v[:-2]) * (1024 if v.endswith("Gi") else 1)
req = c["resources"]["requests"]
assert millicpu(req["cpu"]) + 100 <= 1000, f"cpu request {req['cpu']} leaves no room for the test job on 1 vCPU"
assert mib(req["memory"]) + 256 <= 6 * 1024, f"memory request {req['memory']} leaves no room for the test job"
assert any(e["port"] == 8787 and e["public"] for e in spec["endpoints"]), "public endpoint 8787"
assert doc["capabilities"]["securityContext"]["executeAsCaller"] is True, "executeAsCaller not enabled"
for k in c.get("env", {}):
    assert not any(s in k.upper() for s in ("TOKEN", "PASSWORD", "SECRET")), f"secret-like env var in spec: {k}"
print("PASS spec structure (caller's rights, allowed user, endpoint)")
PY

if IMAGE_TAG=latest RSTUDIO_ALLOWED_USER=U scripts/render-spec.sh > /dev/null 2>&1; then
  echo "FAIL render-spec accepted :latest"; exit 1
fi
echo "PASS render-spec rejects :latest"

if IMAGE_TAG=sha-x RSTUDIO_ALLOWED_USER='u"; return 200; #' scripts/render-spec.sh > /dev/null 2>&1; then
  echo "FAIL render-spec accepted an unsafe user name"; exit 1
fi
echo "PASS render-spec rejects unsafe user names"

grep -q '\${IMAGE_TAG}' "$SPEC" || { echo "FAIL spec has no IMAGE_TAG placeholder"; exit 1; }
echo "PASS spec uses IMAGE_TAG placeholder"
