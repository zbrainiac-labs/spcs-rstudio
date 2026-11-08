# Snowflake connection helper for RStudio on SPCS and local Docker.
#
# Inside SPCS the platform mounts a short-lived OAuth token at
# /snowflake/session/token and injects SNOWFLAKE_HOST / SNOWFLAKE_ACCOUNT.
# The service runs with restricted caller's rights (spec: executeAsCaller):
# nginx in the container keeps the latest Sf-Context-Current-User-Token from
# the browser requests in /run/sf-caller/token.log, and R connects as the
# signed-in user with "<service token>.<caller token>". Both tokens rotate, so
# they are re-read on every connect.
#
# SPCS_AUTH_MODE=owner connects as the service owner role instead (job
# services without browser requests, e.g. the integration test). Without it a
# missing caller token is an error, never a silent fall back to the owner role.
# Outside SPCS a programmatic access token (PAT) from the environment is used.

SPCS_TOKEN_PATH <- "/snowflake/session/token"
SPCS_CALLER_TOKEN_PATH <- "/run/sf-caller/token.log"

sf_env <- function(name, default = "") {
  value <- Sys.getenv(name, unset = "")
  if (nzchar(value)) value else default
}

sf_auth_mode <- function(token_path = SPCS_TOKEN_PATH) {
  if (!file.exists(token_path)) {
    return("pat")
  }
  if (tolower(sf_env("SPCS_AUTH_MODE")) == "owner") "spcs_owner" else "spcs_caller"
}

sf_read_token <- function(path, what) {
  lines <- trimws(readLines(path, warn = FALSE))
  lines <- lines[nzchar(lines)]
  if (length(lines) == 0) stop(what, " is empty: ", path, call. = FALSE)
  lines[length(lines)]
}

sf_connection_args <- function(token_path = SPCS_TOKEN_PATH,
                               caller_token_path = SPCS_CALLER_TOKEN_PATH) {
  common <- list(
    # Driver name registered by Snowflake ODBC 4.x in /etc/odbcinst.ini
    Driver    = sf_env("SNOWFLAKE_ODBC_DRIVER", "Snowflake ODBC"),
    Database  = sf_env("SNOWFLAKE_DATABASE", "R_SPCS_DB"),
    Schema    = sf_env("SNOWFLAKE_SCHEMA", "PUBLIC"),
    Warehouse = sf_env("SNOWFLAKE_WAREHOUSE", "MD_TEST_WH")
  )
  role <- sf_env("SNOWFLAKE_ROLE")
  if (nzchar(role)) common$Role <- role

  mode <- sf_auth_mode(token_path)
  if (mode != "pat") {
    host <- sf_env("SNOWFLAKE_HOST")
    if (!nzchar(host)) stop("SNOWFLAKE_HOST is not set; expected inside SPCS", call. = FALSE)
    token <- sf_read_token(token_path, "SPCS token file")
    if (mode == "spcs_caller") {
      if (!file.exists(caller_token_path)) {
        stop("No SPCS caller token at ", caller_token_path,
             ". Open RStudio through the SPCS endpoint (caller's rights).", call. = FALSE)
      }
      caller <- sf_read_token(caller_token_path,
                              "SPCS caller token (reload RStudio in the browser)")
      token <- paste0(token, ".", caller)
    }
    return(c(common, list(
      Server        = host,
      Account       = sf_env("SNOWFLAKE_ACCOUNT"),
      Authenticator = "oauth",
      Token         = token
    )))
  }

  missing <- Filter(function(v) !nzchar(sf_env(v)),
                    c("SNOWFLAKE_HOST", "SNOWFLAKE_USER", "SNOWFLAKE_TOKEN"))
  if (length(missing) > 0) {
    stop("Not running in SPCS and missing env vars: ", paste(missing, collapse = ", "),
         ". Start the container with local/start.sh (reads .secrets) or",
         " docker run --env-file .secrets, or set them in ~/.Renviron and restart R.",
         call. = FALSE)
  }
  c(common, list(
    Server        = sf_env("SNOWFLAKE_HOST"),
    UID           = sf_env("SNOWFLAKE_USER"),
    Authenticator = "programmatic_access_token",
    Token         = sf_env("SNOWFLAKE_TOKEN")
  ))
}

sf_connect <- function(token_path = SPCS_TOKEN_PATH,
                       caller_token_path = SPCS_CALLER_TOKEN_PATH) {
  args <- sf_connection_args(token_path, caller_token_path)
  do.call(DBI::dbConnect, c(list(odbc::odbc()), args))
}
