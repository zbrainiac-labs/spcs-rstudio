# Run lintr on all R sources and write a SonarQube generic external-issues report.
# Usage (test image): Rscript tests/lint_r.R <output.json>
out <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(out)) out <- "lintr_issues.json"

files <- c(list.files("R", pattern = "\\.R$", recursive = TRUE, full.names = TRUE),
           list.files("tests", pattern = "\\.R$", recursive = TRUE, full.names = TRUE))
lints <- unlist(lapply(files, lintr::lint), recursive = FALSE)

severity <- function(type) switch(type, error = "MAJOR", warning = "MINOR", "INFO")
esc <- function(x) gsub("([\"\\\\])", "\\\\\\1", x)

issues <- vapply(lints, function(l) {
  sprintf(paste0(
    '{"engineId":"lintr","ruleId":"%s","severity":"%s","type":"CODE_SMELL",',
    '"primaryLocation":{"message":"%s","filePath":"%s","textRange":{"startLine":%d}}}'
  ), esc(l$linter), severity(l$type), esc(l$message), esc(sub("^/src/", "", l$filename)),
  as.integer(l$line_number))
}, character(1))

writeLines(sprintf('{"issues":[%s]}', paste(issues, collapse = ",")), out)
cat("lintr findings:", length(lints), "\n")
for (l in lints) cat(sprintf("  %s:%d [%s] %s\n", l$filename, l$line_number, l$linter, l$message))
