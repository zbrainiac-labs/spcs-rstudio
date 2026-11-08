# Tests

Single entry point: `tests/run_all.sh [groups]`. Without flags it runs the offline groups.

| Group | Script | Needs | Checks |
|---|---|---|---|
| `--static` | `spec_check.sh` | python3 + PyYAML | spec renders; `executeAsCaller`; `/healthz` probe; CPU/memory budget for the 1-vCPU pool; rejects `:latest` and unsafe user names; no secrets in env |
| `--unit` | `testthat/`, `lint_r.R` | Docker | `connect.R` modes (caller, owner, PAT), token rotation, no owner fallback; covr coverage and lintr report in `coverage/` |
| `--container` | `container/structure.yaml` | Docker | ODBC driver registered, R packages load, files present, no test tooling in the runtime image |
| `--smoke` | `smoke.sh` | Docker | `/healthz` = 200; nginx admits only the allowed user (others 403); caller token captured with `0640 root:rstudio`; RStudio only on localhost; `rserver` not root; clean logs |
| `--snowflake` | `seed.sh`, `snowflake_local.sh` | `.secrets` (PAT), snow CLI | seeds `RST_SAMPLE_DATA` as `CICD`; runs `snowflake_test.R` in the image |
| `--integration` | `integration/test_spcs.sh` | a deployed service | READY, image tag, owner `RSTUDIO_RUNTIME`, endpoint; job service connects without EAI as `RSTUDIO_RUNTIME` and **cannot** read data |

The caller's-rights path (R as the signed-in user) needs a browser session, so
it is a manual check: open the endpoint and Source `snowflake_test.R`.

Env: `PLATFORM` (default: this machine's), `IMAGE`, `SKIP_BUILD=1`, `SNOW_CONNECTION`, `IMAGE_TAG`.
