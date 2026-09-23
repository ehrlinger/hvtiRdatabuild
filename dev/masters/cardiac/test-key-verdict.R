#!/usr/bin/env Rscript
# test-key-verdict.R: key_verdict() on invented keys. NO PHI.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "test-harness.R"))
skip_unless(c("arrow", "tidyselect"))
source(file.path(here, "key-verdict.R"))

pq <- tempfile(fileext = ".parquet")
arrow::write_parquet(data.frame(
  id      = c("K1", "K1", "K2", "K3", NA),
  dt_surg = as.Date(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-01-01",
                      "2020-01-01")),
  alt     = c("E1", "E2", NA, "E2", "E3"),
  stringsAsFactors = FALSE
), pq)

v <- key_verdict(pq, c("id", "dt_surg"))
check("id + date: one null key part makes it not unique", v$verdict == "not unique")
check("id + date: no duplicates among the rows", v$n_duplicates == 0L)
check("id + date: one row has a null key part", v$n_null_key == 1L)

v <- key_verdict(pq, "id")
check("id alone: duplicates found", v$n_duplicates == 1L)

v <- key_verdict(pq, "alt", nonnull_only = TRUE)
check("alt, non-null only: counts only the non-null rows", v$n_rows == 4L)
check("alt, non-null only: E2 twice is a duplicate", v$verdict == "not unique")

v <- key_verdict(pq, c("id", "missing_col"))
check("a missing column gives verdict 'absent'", v$verdict == "absent")

line <- format_key_verdict(key_verdict(pq, "id"))
check("the formatted line carries no key value", !grepl("K1|K2|K3", line))

finish()
