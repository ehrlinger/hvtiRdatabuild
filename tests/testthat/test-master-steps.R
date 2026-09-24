test_that("key_verdict reports uniqueness, nulls and absence without values", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("tidyselect")
  pq <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(data.frame(
    id      = c("K1", "K1", "K2", "K3", NA),
    dt_surg = as.Date(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-01-01",
                        "2020-01-01")),
    alt     = c("E1", "E2", NA, "E2", "E3"),
    stringsAsFactors = FALSE
  ), pq)

  v <- key_verdict(pq, c("id", "dt_surg"))
  expect_true(v$verdict == "not unique",
              label = "id + date: one null key part makes it not unique")
  expect_true(v$n_duplicates == 0L, label = "id + date: no duplicates among the rows")
  expect_true(v$n_null_key == 1L, label = "id + date: one row has a null key part")

  v <- key_verdict(pq, "id")
  expect_true(v$n_duplicates == 1L, label = "id alone: duplicates found")

  v <- key_verdict(pq, "alt", nonnull_only = TRUE)
  expect_true(v$n_rows == 4L, label = "alt, non-null only: counts only the non-null rows")
  expect_true(v$verdict == "not unique",
              label = "alt, non-null only: E2 twice is a duplicate")

  v <- key_verdict(pq, c("id", "missing_col"))
  expect_true(v$verdict == "absent", label = "a missing column gives verdict 'absent'")

  line <- format_key_verdict(key_verdict(pq, "id"))
  expect_true(!grepl("K1|K2|K3", line), label = "the formatted line carries no key value")
})

test_that("master_ddl measures character widths and preflights row size and column count", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("tidyselect")
  pq <- withr::local_tempfile(fileext = ".parquet")
  sex <- c("M", "Foo")
  attr(sex, "format.sas") <- "$20."
  site <- c("Cleveland Clinic Main Campus", "X")
  attr(site, "format.sas") <- "$10."
  arrow::write_parquet(data.frame(
    id      = c("K1", "K22"),
    age     = c(60.5, NA),
    n       = c(1L, 2L),
    flag    = c(TRUE, FALSE),
    dt_surg = as.Date(c("2020-01-01", "2021-02-03")),
    note    = c(NA_character_, NA_character_),
    sex     = sex,
    site    = site,
    stringsAsFactors = FALSE
  ), pq)

  d <- master_ddl(pq, "master_cardiac_base_test")
  expect_true(grepl("CREATE TABLE [dbo].[master_cardiac_base_test]", d$sql, fixed = TRUE),
              label = "table is schema-qualified and quoted")
  expect_true(d$types[["id"]] == "nvarchar(3)", label = "character width is measured")
  expect_true(d$types[["note"]] == "nvarchar(255)",
              label = "an all-missing character column gets width 255")
  expect_true(d$types[["sex"]] == "nvarchar(20)",
              label = "a SAS-declared width wider than the data wins")
  expect_true(d$types[["site"]] == sprintf("nvarchar(%d)", nchar("Cleveland Clinic Main Campus")),
              label = "observed data wider than the SAS-declared width wins")
  expect_true(d$types[["age"]] == "float", label = "double maps to float")
  expect_true(d$types[["n"]] == "int", label = "integer maps to int")
  expect_true(d$types[["flag"]] == "bit", label = "logical maps to bit")
  expect_true(d$types[["dt_surg"]] == "date", label = "date maps to date")
  expect_true(lengths(regmatches(d$sql, gregexpr(" NULL", d$sql))) == 8L,
              label = "every column is nullable")

  expect_error(mssql_type("list<item: int32>"), "No SQL")
  expect_true(mssql_type("string", 5000L)$sql == "nvarchar(max)",
              label = "a very long string becomes nvarchar(max)")

  wide <- rep(list(mssql_type("double")), 1000L)
  p <- ddl_preflight(wide)
  expect_true(!p$ok && p$row_bytes > 8060,
              label = "1,000 float columns exceed the 8,060-byte row")
  expect_true(grepl("8060", p$message), label = "the message names the limit")

  many <- rep(list(mssql_type("bool")), 1100L)
  p <- ddl_preflight(many)
  expect_true(!p$ok && grepl("1024", p$message),
              label = "1,100 columns exceed the column limit")
})

test_that("master_ddl(schema_name = NULL) leaves the table unqualified", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("tidyselect")
  pq <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(data.frame(id = c("K1", "K2"), x = c(1, 2)), pq)

  d <- master_ddl(pq, "master_x_base_test", schema_name = NULL)
  expect_false(grepl("[dbo].", d$sql, fixed = TRUE),
               label = "the executed-path DDL has no schema prefix")
  expect_true(grepl("CREATE TABLE [master_x_base_test]", d$sql, fixed = TRUE),
              label = "the table name alone is quoted")

  expect_true(ddl_preflight(rep(list(mssql_type("double")), 10L))$ok,
              label = "a narrow table passes")
})

test_that("load_parquet loads row groups and resumes after a partial load", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  skip_if_not_installed("haven")
  d <- data.frame(id = paste0("K", 1:5), age = c(60, 61, NA, 63, 64),
                  dt_surg = as.Date("2020-01-01") + 0:4, stringsAsFactors = FALSE)
  attr(d$age, "label") <- "Invented label"
  pq <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(d, pq, chunk_size = 2)   # three row groups: 2, 2, 1

  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbExecute(con, "CREATE TABLE base (id VARCHAR, age DOUBLE, dt_surg DATE)")

  expect_error(load_parquet(con, pq, "nope"), "does not exist")

  r <- load_parquet(con, pq, "base")
  expect_true(r$loaded == 3L && r$row_groups == 3L, label = "three row groups loaded")
  expect_true(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM base")$n == 5,
              label = "five rows in the table")

  r <- load_parquet(con, pq, "base")
  expect_true(r$loaded == 0L && r$skipped == 3L,
              label = "a second run skips every logged group")
  expect_true(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM base")$n == 5,
              label = "and adds no rows")

  # Simulate a crash after the first group: one group logged, its rows present.
  DBI::dbExecute(con, "CREATE TABLE base2 (id VARCHAR, age DOUBLE, dt_surg DATE)")
  DBI::dbExecute(con, "INSERT INTO base2 SELECT * FROM base WHERE id IN ('K1', 'K2')")
  DBI::dbExecute(con, paste("CREATE TABLE base2__load_log",
                            "(row_group INTEGER, n_rows INTEGER, loaded_at VARCHAR)"))
  DBI::dbExecute(con, "INSERT INTO base2__load_log VALUES (0, 2, 'earlier')")
  r <- load_parquet(con, pq, "base2")
  expect_true(r$loaded == 2L && r$skipped == 1L, label = "resume loads only the missing groups")
  expect_true(DBI::dbGetQuery(con, "SELECT COUNT(DISTINCT id) AS n, COUNT(*) AS m FROM base2")$m
              == 5, label = "resume ends with every row once")
})

test_that("parity_check catches a changed value and a missing row, aggregates only", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  skip_if_not_installed("dplyr")
  skip_if_not_installed("withr")
  skip_if_not_installed("tidyselect")

  d <- data.frame(id = paste0("K", 1:6), dt_surg = as.Date("2020-01-01") + 0:5,
                  age = c(60.25, 61, NA, 63, 64, 65), surgeon = c("A", "a", "A ", NA, "B", "B"),
                  stringsAsFactors = FALSE)
  pq <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(d, pq)

  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbWriteTable(con, "base", d)

  res <- parity_check(con, "base", pq, c("id", "dt_surg"), sample_n = 4L, dialect = "duckdb")
  expect_true(res$verdict == "pass", label = "an exact load passes")
  expect_true(all(res$columns$verdict == "match"), label = "every column matches")
  expect_true(all(res$sample$verdict == "match"), label = "the sample matches")

  DBI::dbExecute(con, "UPDATE base SET age = 99 WHERE id = 'K2'")
  res <- parity_check(con, "base", pq, c("id", "dt_surg"), sample_n = 6L, dialect = "duckdb")
  expect_true(res$verdict == "fail", label = "a changed value fails")
  expect_true(res$columns$verdict[res$columns$variable == "age"] == "mismatch",
              label = "the age column is the mismatch")
  expect_true(!grepl("K2|99|60.25", parity_summary(res)),
              label = "the summary carries no key or value")

  DBI::dbExecute(con, "DELETE FROM base WHERE id = 'K6'")
  res <- parity_check(con, "base", pq, c("id", "dt_surg"), sample_n = 2L, dialect = "duckdb")
  expect_true(res$row_count == "mismatch", label = "a missing row fails the row count")
})

test_that("parity_full catches a compensating swap that parity_check's aggregates miss", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  skip_if_not_installed("dplyr")
  skip_if_not_installed("withr")
  skip_if_not_installed("tidyselect")

  # C4: parity_full compares every row, not just the sample. A swap of two cells
  # leaves the sum and the distinct count unchanged, so parity_check's aggregates
  # cannot see it; with this seed and sample_n = 1 the sample also misses it.
  d2 <- data.frame(id = paste0("K", 1:6), dt_surg = as.Date("2020-01-01") + 0:5,
                   age = c(60, 61, 62, 63, 64, 65), stringsAsFactors = FALSE)
  pq2 <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(d2, pq2)
  con2 <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con2, shutdown = TRUE))
  DBI::dbWriteTable(con2, "base2", d2)

  res_full <- parity_full(con2, "base2", pq2, c("id", "dt_surg"), dialect = "duckdb")
  expect_true(all(res_full$verdict == "match"), label = "full parity passes on an exact load")

  DBI::dbExecute(con2, "UPDATE base2 SET age = 65 WHERE id = 'K5'")
  DBI::dbExecute(con2, "UPDATE base2 SET age = 64 WHERE id = 'K6'")
  idx <- withr::with_seed(1L, sample.int(6, 1))
  expect_true(!idx %in% c(5, 6), label = "the sample for this seed avoids the swapped rows")
  res_check <- parity_check(con2, "base2", pq2, c("id", "dt_surg"), sample_n = 1L, seed = 1L,
                            dialect = "duckdb")
  expect_true(res_check$verdict == "pass",
              label = "parity_check passes despite the swap (aggregates and sample both miss it)")
  res_full2 <- parity_full(con2, "base2", pq2, c("id", "dt_surg"), dialect = "duckdb")
  expect_true(res_full2$verdict[res_full2$variable == "age"] == "mismatch",
              label = "parity_full catches the swap that parity_check missed")
  expect_true(!grepl("K5|K6|64|65", full_summary(res_full2)),
              label = "the full summary carries no key or value")
})
