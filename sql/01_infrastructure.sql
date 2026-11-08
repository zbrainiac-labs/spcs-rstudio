/*
 * 01_infrastructure.sql -- Image repository and compute pool for RStudio (run as CICD).
 * Prerequisite: sql/admin/00_setup_roles.sql (ACCOUNTADMIN, once).
 * Context comes from the CLI, not from USE statements:
 *   snow sql -c <conn> --role CICD --database R_SPCS_DB --schema PUBLIC -f sql/01_infrastructure.sql
 * The service is created by scripts/deploy.sh (as RSTUDIO_RUNTIME) once an image is pushed.
 */

CREATE IMAGE REPOSITORY IF NOT EXISTS RSTUDIO_REPO
COMMENT = 'Container images for RStudio on SPCS (rstudio-spcs:sha-<short>)';

-- ARM pool: the image is built for linux/arm64 (scripts/deploy.sh PLATFORM)
CREATE COMPUTE POOL IF NOT EXISTS RSTUDIO_POOL
MIN_NODES = 1
MAX_NODES = 1
INSTANCE_FAMILY = GEN_ARM_G1_2
AUTO_SUSPEND_SECS = 600
AUTO_RESUME = TRUE
COMMENT = 'RStudio on SPCS (ARM)';

-- Service owner role: pull images and run on the pool, nothing more
GRANT READ ON IMAGE REPOSITORY RSTUDIO_REPO TO ROLE RSTUDIO_RUNTIME;
GRANT USAGE, MONITOR ON COMPUTE POOL RSTUDIO_POOL TO ROLE RSTUDIO_RUNTIME;

SHOW IMAGE REPOSITORIES LIKE 'RSTUDIO_REPO';
