#!/usr/bin/env Rscript
# test-load.R: row-group load, and resume after a partial load. NO PHI.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "test-harness.R"))
skip_unless(c("arrow", "duckdb", "DBI", "haven"))
source(file.path(here, "load.R"))

d <- data.frame(id = paste0("K", 1:5), age = c(60, 61, NA, 63, 64),
                dt_surg = as.Date("2020-01-01") + 0:4, stringsAsFactors = FALSE)
attr(d$age, "label") <- "Invented label"
pq <- tempfile(fileext = ".parquet")
arrow::write_parquet(d, pq, chunk_size = 2)   # three row groups: 2, 2, 1

con <- DBI::dbConnect(duckdb::duckdb())
DBI::dbExecute(con, "CREATE TABLE base (id VARCHAR, age DOUBLE, dt_surg DATE)")

check_error("a missing target table is an error",
            load_parquet(con, pq, "nope"), "does not exist")

r <- load_parquet(con, pq, "base")
check("three row groups loaded", r$loaded == 3L && r$row_groups == 3L)
check("five rows in the table",
      DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM base")$n == 5)

r <- load_parquet(con, pq, "base")
check("a second run skips every logged group", r$loaded == 0L && r$skipped == 3L)
check("and adds no rows", DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM base")$n == 5)

# Simulate a crash after the first group: one group logged, its rows present.
DBI::dbExecute(con, "CREATE TABLE base2 (id VARCHAR, age DOUBLE, dt_surg DATE)")
DBI::dbExecute(con, "INSERT INTO base2 SELECT * FROM base WHERE id IN ('K1', 'K2')")
DBI::dbExecute(con, paste("CREATE TABLE base2__load_log",
                          "(row_group INTEGER, n_rows INTEGER, loaded_at VARCHAR)"))
DBI::dbExecute(con, "INSERT INTO base2__load_log VALUES (0, 2, 'earlier')")
r <- load_parquet(con, pq, "base2")
check("resume loads only the missing groups", r$loaded == 2L && r$skipped == 1L)
check("resume ends with every row once",
      DBI::dbGetQuery(con, "SELECT COUNT(DISTINCT id) AS n, COUNT(*) AS m FROM base2")$m == 5)

DBI::dbDisconnect(con, shutdown = TRUE)
finish()
