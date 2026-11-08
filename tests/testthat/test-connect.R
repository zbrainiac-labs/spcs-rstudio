# covr pre-loads instrumented functions; only source when running plain testthat
if (!exists("sf_connection_args", mode = "function")) {
  source(file.path(Sys.getenv("CONNECT_R_DIR", "../../R"), "connect.R"))
}

sf_vars <- c("SNOWFLAKE_HOST", "SNOWFLAKE_USER", "SNOWFLAKE_TOKEN", "SNOWFLAKE_ACCOUNT",
             "SNOWFLAKE_ROLE", "SNOWFLAKE_DATABASE", "SNOWFLAKE_SCHEMA", "SNOWFLAKE_WAREHOUSE",
             "SNOWFLAKE_ODBC_DRIVER", "SPCS_AUTH_MODE")

clear_sf_env <- function() {
  old <- Sys.getenv(sf_vars, unset = NA, names = TRUE)
  Sys.unsetenv(sf_vars)
  old
}

restore_sf_env <- function(old) {
  Sys.unsetenv(sf_vars)
  set <- old[!is.na(old)]
  if (length(set) > 0) do.call(Sys.setenv, as.list(set))
}

# Clear SNOWFLAKE_* for the calling test and restore them when it ends
local_clean_sf_env <- function(envir = parent.frame()) {
  old <- clear_sf_env()
  withr::defer(restore_sf_env(old), envir = envir)
}

with_token_file <- function(content, code) {
  path <- tempfile("token")
  writeLines(content, path)
  on.exit(unlink(path), add = TRUE)
  code(path)
}

test_that("auth mode is pat when no SPCS token file exists", {
  expect_equal(sf_auth_mode(tempfile("missing")), "pat")
})

test_that("auth mode in SPCS is caller's rights unless owner mode is explicit", {
  local_clean_sf_env()
  with_token_file("abc", function(p) {
    expect_equal(sf_auth_mode(p), "spcs_caller")
    Sys.setenv(SPCS_AUTH_MODE = "owner")
    expect_equal(sf_auth_mode(p), "spcs_owner")
  })
})

test_that("caller mode combines service token and latest caller token", {
  local_clean_sf_env()
  Sys.setenv(SNOWFLAKE_HOST = "acct.snowflakecomputing.com", SNOWFLAKE_ACCOUNT = "ACCT")
  with_token_file("svc-1\n", function(p) {
    with_token_file(c("old-user", "", "new-user"), function(c) {
      args <- sf_connection_args(p, c)
      expect_equal(args$Authenticator, "oauth")
      expect_equal(args$Token, "svc-1.new-user")
      expect_equal(args$Server, "acct.snowflakecomputing.com")
      expect_equal(args$Account, "ACCT")
      expect_null(args$UID)
    })
  })
})

test_that("caller mode never falls back to the owner role", {
  local_clean_sf_env()
  Sys.setenv(SNOWFLAKE_HOST = "h")
  with_token_file("svc", function(p) {
    expect_error(sf_connection_args(p, tempfile("missing")), "caller's rights")
    with_token_file("", function(c) expect_error(sf_connection_args(p, c), "caller token"))
  })
})

test_that("owner mode uses the service token only", {
  local_clean_sf_env()
  Sys.setenv(SNOWFLAKE_HOST = "h", SPCS_AUTH_MODE = "owner")
  with_token_file("svc-only", function(p) {
    expect_equal(sf_connection_args(p, tempfile("missing"))$Token, "svc-only")
  })
})

test_that("both tokens are re-read on every call (token rotation)", {
  local_clean_sf_env()
  Sys.setenv(SNOWFLAKE_HOST = "h")
  with_token_file("svc-a", function(p) {
    with_token_file("user-a", function(c) {
      expect_equal(sf_connection_args(p, c)$Token, "svc-a.user-a")
      writeLines("svc-b", p)
      writeLines("user-b", c)
      expect_equal(sf_connection_args(p, c)$Token, "svc-b.user-b")
    })
  })
})

test_that("SPCS mode fails clearly on empty token or missing host", {
  local_clean_sf_env()
  Sys.setenv(SPCS_AUTH_MODE = "owner")
  with_token_file("x", function(p) expect_error(sf_connection_args(p), "SNOWFLAKE_HOST"))
  Sys.setenv(SNOWFLAKE_HOST = "h")
  with_token_file("", function(p) expect_error(sf_connection_args(p), "empty"))
})

test_that("PAT mode uses env credentials", {
  local_clean_sf_env()
  Sys.setenv(SNOWFLAKE_HOST = "h", SNOWFLAKE_USER = "u", SNOWFLAKE_TOKEN = "pat")
  args <- sf_connection_args(tempfile("missing"))
  expect_equal(args$Authenticator, "programmatic_access_token")
  expect_equal(args$UID, "u")
  expect_equal(args$Token, "pat")
})

test_that("PAT mode lists all missing env vars", {
  local_clean_sf_env()
  expect_error(sf_connection_args(tempfile("missing")),
               "SNOWFLAKE_HOST, SNOWFLAKE_USER, SNOWFLAKE_TOKEN")
})

test_that("defaults and optional role", {
  local_clean_sf_env()
  Sys.setenv(SNOWFLAKE_HOST = "h", SNOWFLAKE_USER = "u", SNOWFLAKE_TOKEN = "t")
  args <- sf_connection_args(tempfile("missing"))
  expect_equal(args$Driver, "Snowflake ODBC")
  expect_equal(args$Database, "R_SPCS_DB")
  expect_equal(args$Schema, "PUBLIC")
  expect_null(args$Role)
  Sys.setenv(SNOWFLAKE_ROLE = "ANALYST", SNOWFLAKE_WAREHOUSE = "WH")
  args <- sf_connection_args(tempfile("missing"))
  expect_equal(args$Role, "ANALYST")
  expect_equal(args$Warehouse, "WH")
})
