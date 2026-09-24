# Tests for lift_master(), on duckdb with invented data. No PHI.

lift_fixture <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  d <- data.frame(id = paste0("K", 1:6), dt_surg = as.Date("2020-01-01") + 0:5,
                  age = c(60.25, 61, NA, 63, 64, 65),
                  surgeon = c("A", "a", "A ", NA, "B", "B"), stringsAsFactors = FALSE)
  pq <- file.path(dir, "built_2026.parquet")
  arrow::write_parquet(d, pq)
  cols <- list(list(variable = "id", r_class = "character"),
               list(variable = "dt_surg", r_class = "Date"),
               list(variable = "age", r_class = "numeric"),
               list(variable = "surgeon", r_class = "character"))
  meta <- list(parquet_sha256 = "invented", columns = cols)
  jsonlite::write_json(meta, file.path(dir, "built_2026.meta.json"), auto_unbox = TRUE)
  cfg <- structure(list(name = "master_t", key = c("id", "dt_surg"), alt_keys = list(),
                        parent = NULL, parent_release = NULL, snapshots = dir,
                        current = "built_2026.sas7bdat", history = NULL,
                        build_program = file.path(dir, "bd.sas"),
                        file = file.path(dir, "master.yml")), class = "master_config")
  list(dir = dir, pq = pq, cfg = cfg, data = d)
}

test_that("the dry run writes the DDL and touches nothing", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  f <- lift_fixture()
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  res <- lift_master(f$cfg, con, f$pq, dialect = "duckdb")
  expect_true(res$dry_run)
  expect_true(file.exists(res$ddl_path))
  expect_equal(res$base_table, "master_t_base_built_2026")
  expect_equal(length(DBI::dbListTables(con)), 0L)
})

test_that("an executed lift loads, passes parity, records it, and creates the view", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("dplyr")
  skip_if_not_installed("withr")
  skip_if_not_installed("tidyselect")
  f <- lift_fixture()
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  res <- lift_master(f$cfg, con, f$pq, dry_run = FALSE, dialect = "duckdb")
  expect_equal(res$verdict, "pass")
  v <- DBI::dbGetQuery(con, "SELECT * FROM master_t ORDER BY id")
  expect_equal(nrow(v), 6L)
  expect_equal(.current_base(con, f$cfg, "duckdb"), "master_t_base_built_2026")
  expect_true(DBI::dbExistsTable(con, "master_t_meta"))
})

test_that("a key that is not unique stops before any table is created", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  f <- lift_fixture()
  f$cfg$key <- "surgeon"
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  expect_error(lift_master(f$cfg, con, f$pq, dry_run = FALSE, dialect = "duckdb"),
               "not unique")
  expect_equal(length(DBI::dbListTables(con)), 0L)
})

test_that(".current_base stops when no parity has passed", {
  skip_if_not_installed("duckdb")
  f <- list(cfg = structure(list(name = "master_none"), class = "master_config"))
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  expect_error(.current_base(con, f$cfg, "duckdb"), "no passing parity")
})
