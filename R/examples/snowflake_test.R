library(DBI)
library(odbc)
library(dplyr)

source(file.path(Sys.getenv("CONNECT_R_DIR", "/home/rstudio"), "connect.R"))

# -- 1. Connect to Snowflake ------------------------------------------------
# SPCS: OAuth session token; local: PAT from SNOWFLAKE_* env vars
con <- tryCatch(sf_connect(), error = function(e) {
  # stop here instead of cascading errors when run line by line in RStudio
  stop("Snowflake connection failed: ", conditionMessage(e), call. = FALSE)
})
stopifnot(DBI::dbIsValid(con))

cat("Connected to Snowflake via", sf_auth_mode(), "\n")

# -- 2. Read RST_SAMPLE_DATA -----------------------------------------------
raw <- dbReadTable(con, "RST_SAMPLE_DATA")
cat("\nRaw data:\n")
print(raw)

# -- 3. Calculate summary stats per category --------------------------------
summary_data <- raw |>
  group_by(CATEGORY) |>
  summarise(
    N          = n(),
    MEAN_AMOUNT = mean(AMOUNT),
    MAX_AMOUNT  = max(AMOUNT),
    MIN_AMOUNT  = min(AMOUNT),
    SUM_AMOUNT  = sum(AMOUNT)
  ) |>
  mutate(
    PCT_OF_TOTAL = round(SUM_AMOUNT / sum(SUM_AMOUNT) * 100, 2),
    CALC_DATE    = Sys.time()
  )

cat("\nCalculated summary:\n")
print(summary_data)

# -- 4. Write results back to Snowflake -------------------------------------
dbWriteTable(
  con,
  name      = "RST_SAMPLE_DATA_SUMMARY",
  value     = as.data.frame(summary_data),
  overwrite = TRUE
)

cat("\nResults written to R_SPCS_DB.PUBLIC.RST_SAMPLE_DATA_SUMMARY\n")

# -- 5. Verify by reading back -----------------------------------------------
verify <- dbReadTable(con, "RST_SAMPLE_DATA_SUMMARY")
cat("\nVerification - data in Snowflake:\n")
print(verify)

dbDisconnect(con)
cat("\nDone!\n")
