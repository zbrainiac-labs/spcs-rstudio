/*
 * 00_database.sql -- Database for RStudio on SPCS.
 * Run first, without database context:
 *   snow sql -c <conn> -f sql/00_database.sql
 */

CREATE DATABASE IF NOT EXISTS R_SPCS_DB
COMMENT = 'RStudio on Snowpark Container Services: image repository, compute pool, service and sample data';
