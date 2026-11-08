# Local CI

Requires Docker, [act](https://nektosact.com) and the running DataOpsBackbone
stack (`../DataOpsBackbone/start.sh`: SonarQube, `sonarnet`, `sonar_env` volume,
runner image).

## `act.sh` — the GitHub workflow, locally

```bash
bash local-ci/act.sh                 # all jobs; deploy-spcs as a dry run
bash local-ci/act.sh --job=sonar     # one job
bash local-ci/act.sh --full          # real SPCS deploy + integration test
```

- Uses the working copy, so uncommitted changes are tested.
- No OIDC locally: Snowflake auth uses `SNOW_CONFIG_B64` (built from the DataOpsBackbone `.env`).
- Jobs share the working copy (`--bind`); GHCR pushes and attestations are skipped.
- Logs go to `local-ci/logs/` (gitignored); the run fails if a token-like string appears in the log.

## `sonar-self-scan.sh` — quality gate

```bash
tests/run_all.sh --unit              # produces coverage/ and the lintr report
bash local-ci/sonar-self-scan.sh
```

Runs Trivy (fs), gitleaks (git history), hadolint, ShellCheck, SQLFluff and
lintr, then sonar-scanner with the quality gate. Fails on a failed gate or any
HIGH/BLOCKER/CRITICAL issue and writes `.sonar-issues.tsv`.

- Locally the tools run as pinned containers; on the self-hosted runner as pinned binaries.
- Reviewed suppressions live in `sonar-project.properties` and `.trivyignore`, each with its reason.
- SonarQube has no R analyzer, so R coverage shows in the test output, not in SonarQube.
