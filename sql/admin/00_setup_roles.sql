/*
 * admin/00_setup_roles.sql -- One-time setup by ACCOUNTADMIN (account-level grants).
 *   snow sql -c <admin-conn> --role ACCOUNTADMIN -f sql/admin/00_setup_roles.sql
 *
 * Roles:
 *   CICD             deploy role (existing): owns R_SPCS_DB, the image repository and
 *                    the compute pool; pushes images and upgrades the service.
 *   RSTUDIO_RUNTIME  owner of RSTUDIO_SERVICE. Anyone in RStudio can read the plain
 *                    SPCS service token, so this role gets no data access: only what
 *                    the service itself needs plus the caller grants below.
 *   RSTUDIO_USER     the one RStudio user's data + endpoint access (granted to them).
 *
 * R runs with restricted caller's rights: as the signed-in user, limited to the
 * caller grants on RSTUDIO_RUNTIME (R_SPCS_DB.PUBLIC and MD_TEST_WH only).
 * Edit the user name below before running.
 */

SET RSTUDIO_USER_NAME = 'MDAEPPEN';

-- Roles and hierarchy (CICD may act as RSTUDIO_RUNTIME to create and upgrade the service)
CREATE ROLE IF NOT EXISTS RSTUDIO_RUNTIME
COMMENT = 'Owner of RSTUDIO_SERVICE; no data access (caller grants only)';
CREATE ROLE IF NOT EXISTS RSTUDIO_USER
COMMENT = 'RStudio on SPCS user: data in R_SPCS_DB.PUBLIC and endpoint access';
GRANT ROLE RSTUDIO_RUNTIME TO ROLE CICD;
GRANT ROLE RSTUDIO_RUNTIME TO ROLE SYSADMIN;
GRANT ROLE RSTUDIO_USER TO ROLE SYSADMIN;
GRANT ROLE RSTUDIO_USER TO USER IDENTIFIER($RSTUDIO_USER_NAME);

-- Account-level privileges CICD and the service owner are missing
GRANT CREATE COMPUTE POOL ON ACCOUNT TO ROLE CICD;
GRANT BIND SERVICE ENDPOINT ON ACCOUNT TO ROLE RSTUDIO_RUNTIME;

-- Database owned by CICD (created here if the deploy has not run yet)
CREATE DATABASE IF NOT EXISTS R_SPCS_DB
COMMENT = 'RStudio on Snowpark Container Services: image repository, compute pool, service and sample data';
GRANT OWNERSHIP ON DATABASE R_SPCS_DB TO ROLE CICD COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA R_SPCS_DB.PUBLIC TO ROLE CICD COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ALL TABLES IN SCHEMA R_SPCS_DB.PUBLIC TO ROLE CICD COPY CURRENT GRANTS;

-- RSTUDIO_RUNTIME: create the service, nothing else (repo READ + pool USAGE: 01_infrastructure.sql)
GRANT USAGE ON DATABASE R_SPCS_DB TO ROLE RSTUDIO_RUNTIME;
GRANT USAGE, CREATE SERVICE ON SCHEMA R_SPCS_DB.PUBLIC TO ROLE RSTUDIO_RUNTIME;

-- RSTUDIO_USER: what the signed-in user may do in R
GRANT USAGE ON DATABASE R_SPCS_DB TO ROLE RSTUDIO_USER;
GRANT USAGE, CREATE TABLE ON SCHEMA R_SPCS_DB.PUBLIC TO ROLE RSTUDIO_USER;
GRANT SELECT ON ALL TABLES IN SCHEMA R_SPCS_DB.PUBLIC TO ROLE RSTUDIO_USER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA R_SPCS_DB.PUBLIC TO ROLE RSTUDIO_USER;
GRANT USAGE ON WAREHOUSE MD_TEST_WH TO ROLE RSTUDIO_USER;

-- Caller grants: which of the caller's privileges the service may use (restricted caller's rights)
GRANT CALLER USAGE ON DATABASE R_SPCS_DB TO ROLE RSTUDIO_RUNTIME;
GRANT CALLER USAGE, CREATE TABLE ON SCHEMA R_SPCS_DB.PUBLIC TO ROLE RSTUDIO_RUNTIME;
GRANT CALLER USAGE ON WAREHOUSE MD_TEST_WH TO ROLE RSTUDIO_RUNTIME;
GRANT ALL INHERITED CALLER PRIVILEGES ON ALL TABLES IN SCHEMA R_SPCS_DB.PUBLIC TO ROLE RSTUDIO_RUNTIME;
-- not part of ALL ... PRIVILEGES; needed for DROP / CREATE OR REPLACE (dbWriteTable overwrite)
-- on tables the caller owns
GRANT INHERITED CALLER OWNERSHIP ON ALL TABLES IN SCHEMA R_SPCS_DB.PUBLIC TO ROLE RSTUDIO_RUNTIME;

-- Caller token validity for services in this schema: 8 hours (default 2 minutes)
ALTER SCHEMA R_SPCS_DB.PUBLIC SET SERVICE_CALLER_TOKEN_VALIDITY_SECS = 28800;

SHOW CALLER GRANTS TO ROLE RSTUDIO_RUNTIME;
