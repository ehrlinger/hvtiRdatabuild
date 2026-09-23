#!/usr/bin/env Rscript
# test-parity.R: parity between a parquet snapshot and its loaded table. NO PHI.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "test-harness.R"))
skip_unless(c("arrow", "duckdb", "DBI", "dplyr", "withr", "tidyselect", "hvtiRdatabuild"))
source(file.path(here, "sql-common.R"))
source(file.path(here, "parity.R"))

msg <- check_error("run_step withholds the driver's message",
                   run_step("x", stop("secret K9")), "Step 'x'")
check("run_step's message does not leak the driver's text", !grepl("K9", msg))

check("mssql quoting doubles a closing bracket", quoter("mssql")("a]b") == "[a]]b]")
check("duckdb quoting doubles a quote", quoter("duckdb")("a\"b") == "\"a\"\"b\"")
check("string literals double a single quote", sql_string("O'Neil") == "'O''Neil'")
check("mssql distinct on text uses a hash",
      grepl("HASHBYTES", parity_sql("t", "s", FALSE, TRUE, "mssql")))
check("numeric columns get a sum", grepl("SUM", parity_sql("t", "x", TRUE, FALSE, "duckdb")))

d <- data.frame(id = paste0("K", 1:6), dt_surg = as.Date("2020-01-01") + 0:5,
                age = c(60.25, 61, NA, 63, 64, 65), surgeon = c("A", "a", "A ", NA, "B", "B"),
                stringsAsFactors = FALSE)
pq <- tempfile(fileext = ".parquet")
arrow::write_parquet(d, pq)

con <- DBI::dbConnect(duckdb::duckdb())
DBI::dbWriteTable(con, "base", d)

res <- parity_check(con, "base", pq, c("id", "dt_surg"), sample_n = 4L, dialect = "duckdb")
check("an exact load passes", res$verdict == "pass")
check("every column matches", all(res$columns$verdict == "match"))
check("the sample matches", all(res$sample$verdict == "match"))

DBI::dbExecute(con, "UPDATE base SET age = 99 WHERE id = 'K2'")
res <- parity_check(con, "base", pq, c("id", "dt_surg"), sample_n = 6L, dialect = "duckdb")
check("a changed value fails", res$verdict == "fail")
check("the age column is the mismatch",
      res$columns$verdict[res$columns$variable == "age"] == "mismatch")
check("the summary carries no key or value",
      !grepl("K2|99|60.25", parity_summary(res)))

DBI::dbExecute(con, "DELETE FROM base WHERE id = 'K6'")
res <- parity_check(con, "base", pq, c("id", "dt_surg"), sample_n = 2L, dialect = "duckdb")
check("a missing row fails the row count", res$row_count == "mismatch")

# C4: parity_full compares every row, not just the sample. A swap of two cells
# leaves the sum and the distinct count unchanged, so parity_check's aggregates
# cannot see it; with this seed and sample_n = 1 the sample also misses it.
d2 <- data.frame(id = paste0("K", 1:6), dt_surg = as.Date("2020-01-01") + 0:5,
                 age = c(60, 61, 62, 63, 64, 65), stringsAsFactors = FALSE)
pq2 <- tempfile(fileext = ".parquet")
arrow::write_parquet(d2, pq2)
con2 <- DBI::dbConnect(duckdb::duckdb())
DBI::dbWriteTable(con2, "base2", d2)

res_full <- parity_full(con2, "base2", pq2, c("id", "dt_surg"), dialect = "duckdb")
check("full parity passes on an exact load", all(res_full$verdict == "match"))

DBI::dbExecute(con2, "UPDATE base2 SET age = 65 WHERE id = 'K5'")
DBI::dbExecute(con2, "UPDATE base2 SET age = 64 WHERE id = 'K6'")
idx <- withr::with_seed(1L, sample.int(6, 1))
check("the sample for this seed avoids the swapped rows", !idx %in% c(5, 6))
res_check <- parity_check(con2, "base2", pq2, c("id", "dt_surg"), sample_n = 1L, seed = 1L,
                          dialect = "duckdb")
check("parity_check passes despite the swap (aggregates and sample both miss it)",
      res_check$verdict == "pass")
res_full2 <- parity_full(con2, "base2", pq2, c("id", "dt_surg"), dialect = "duckdb")
check("parity_full catches the swap that parity_check missed",
      res_full2$verdict[res_full2$variable == "age"] == "mismatch")
check("the full summary carries no key or value", !grepl("K5|K6|64|65", full_summary(res_full2)))

DBI::dbDisconnect(con2, shutdown = TRUE)
DBI::dbDisconnect(con, shutdown = TRUE)
finish()
