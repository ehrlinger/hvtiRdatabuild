# Gated: runs only against a scratch warehouse schema, with invented data. No PHI.
# Set HVTI_MASTER_TEST_DSN (an ODBC DSN whose login already defaults to a scratch schema)
# and HVTI_MASTER_TEST_SCHEMA (that schema's name). The test never changes the login: it
# skips unless the login's default schema is the scratch one.

test_that("lift and corrections behave on SQL Server as on duckdb", {
  dsn <- Sys.getenv("HVTI_MASTER_TEST_DSN")
  schema <- Sys.getenv("HVTI_MASTER_TEST_SCHEMA")
  skip_if(!nzchar(dsn) || !nzchar(schema), "no scratch warehouse configured")
  for (p in c("arrow", "odbc", "jsonlite", "dplyr", "withr", "tidyselect", "digest")) {
    skip_if_not_installed(p)
  }
  con <- DBI::dbConnect(odbc::odbc(), dsn = dsn)
  withr::defer(DBI::dbDisconnect(con))
  current <- DBI::dbGetQuery(con, "SELECT SCHEMA_NAME() AS s")$s
  skip_if(!identical(current, schema), "the DSN's default schema is not the scratch schema")
  dir <- withr::local_tempdir()
  d <- data.frame(
    ccfid = c("K1", "K2"), dt_surg = as.Date("2020-01-01") + 0:1,
    age = c(65.5, 1 / 3), surgeon = c("s1", "S1 "), stringsAsFactors = FALSE
  )
  pq <- file.path(dir, "built_it.parquet")
  arrow::write_parquet(d, pq)
  jsonlite::write_json(
    list(parquet_sha256 = "invented", columns = list(
      list(variable = "ccfid", r_class = "character"),
      list(variable = "dt_surg", r_class = "Date"),
      list(variable = "age", r_class = "numeric"),
      list(variable = "surgeon", r_class = "character")
    )),
    file.path(dir, "built_it.meta.json"),
    auto_unbox = TRUE
  )
  writeLines("data m; run;", file.path(dir, "bd.sas"))
  cfg <- structure(list(
    name = paste0("master_it_", format(Sys.time(), "%H%M%S")),
    key = c("ccfid", "dt_surg"), alt_keys = list(), parent = NULL,
    parent_release = NULL, snapshots = dir, current = "built_it.sas7bdat",
    history = NULL, build_program = file.path(dir, "bd.sas"),
    file = file.path(dir, "master.yml")
  ), class = "master_config")
  res <- suppressMessages(lift_master(cfg, con, pq, dry_run = FALSE))
  expect_equal(res$verdict, "pass")
  suppressMessages(backfill_corrections(cfg, con, dry_run = FALSE))
  r <- suppressMessages(propose_correction(
    cfg, con,
    key_values = list(ccfid = "K2", dt_surg = as.Date("2020-01-02")),
    variable = "age", expected_prior = 1 / 3, new_value = 2 / 3,
    evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester"
  ))
  suppressMessages(decide_correction(cfg, con, r$correction_id, "accept", "tester"))
  suppressMessages(backfill_corrections(cfg, con, dry_run = FALSE))
  v <- DBI::dbGetQuery(con, paste0("SELECT age FROM [", cfg$name, "] WHERE ccfid = 'K2'"))
  expect_equal(v$age, 2 / 3)
})
