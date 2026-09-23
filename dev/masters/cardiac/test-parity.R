#!/usr/bin/env Rscript
# test-parity.R: parity between a parquet snapshot and its loaded table. NO PHI.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "test-harness.R"))
skip_unless(c("arrow", "duckdb", "DBI", "dplyr", "withr", "tidyselect", "hvtiRdatabuild"))
source(file.path(here, "sql-common.R"))
source(file.path(here, "parity.R"))

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

DBI::dbDisconnect(con, shutdown = TRUE)
finish()
