/*
 * optional/egress_fallback.sql -- NOT part of the default setup.
 * Only needed if R inside SPCS cannot reach Snowflake through the internal
 * SPCS OAuth path (the default, see R/connect.R). Opens public egress to the
 * account host and attaches it to the service.
 *   snow sql -c <conn> --database R_SPCS_DB --schema PUBLIC -f sql/optional/egress_fallback.sql
 * Replace <ORG>-<ACCOUNT> with your account identifier first.
 */

CREATE OR REPLACE NETWORK RULE RSTUDIO_SNOWFLAKE_EGRESS_RULE
MODE = EGRESS
TYPE = HOST_PORT
VALUE_LIST = ('<ORG>-<ACCOUNT>.snowflakecomputing.com:443')
COMMENT = 'Egress from RStudio on SPCS to the Snowflake account host';

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION R_SPCS_SNOWFLAKE_ACCESS
ALLOWED_NETWORK_RULES = (RSTUDIO_SNOWFLAKE_EGRESS_RULE)
ENABLED = TRUE
COMMENT = 'Fallback egress for RStudio on SPCS';

ALTER SERVICE RSTUDIO_SERVICE SET EXTERNAL_ACCESS_INTEGRATIONS = (R_SPCS_SNOWFLAKE_ACCESS);
