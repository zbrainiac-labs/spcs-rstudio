# Changelog

## Unreleased

- Repository moved to `zbrainiac-labs/spcs-rstudio`; files reorganized into `sql/`, `R/`, `spec/`, `scripts/`, `docker/`.
- **Security:** R now runs with restricted caller's rights as the signed-in user. The PAT is no longer passed into the service spec. New roles `RSTUDIO_RUNTIME` (service owner, no data access) and `RSTUDIO_USER`; one-time `sql/admin/00_setup_roles.sql`.
- nginx in front of RStudio: single allowed user, caller token for R, `/healthz` readiness probe.
- Image: arm64 (SPCS `GEN_ARM_G1_2`), pinned `rocker/rstudio:4.6.2`, Snowflake ODBC 4.3.0 with checksums, `apt-get upgrade` for the apt CVE.
- No external access integration needed (internal OAuth); egress setup moved to `sql/optional/`.
- Sample table renamed to `RST_SAMPLE_DATA` (column `VALUE` → `AMOUNT`).
- Tests (`tests/run_all.sh`), local CI (`local-ci/act.sh`), SonarQube self-scan and the GitHub workflow `ci.yml`.
