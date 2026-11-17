# No PHI: identifiers and values are invented.

test_that("the generated SQL creates every object, with GO between statements", {
  con <- local_sources_db()
  cfg <- corrections_config()
  dir <- withr::local_tempdir()
  paths <- generate_corrections_sql(cfg, con, dir, dialect = "duckdb")
  expect_setequal(basename(paths), c("stg_echo.tables.sql", "stg_echo.views.sql",
                                     "stg_patient.tables.sql", "stg_patient.views.sql"))
  for (p in paths[grepl("tables", paths)]) {
    for (s in strsplit(paste(readLines(p), collapse = "\n"), "\nGO\n?")[[1]]) {
      DBI::dbExecute(con, s)
    }
  }
  for (p in paths[grepl("views", paths)]) {
    for (s in strsplit(paste(readLines(p), collapse = "\n"), "\nGO\n?")[[1]]) {
      DBI::dbExecute(con, s)
    }
  }
  expect_true(DBI::dbExistsTable(con, "stg_patient_corrected"))
  expect_identical(nrow(DBI::dbGetQuery(con, "SELECT * FROM stg_echo_corrections_stale")), 0L)
})

test_that("an undeclared or keyless source stops generation", {
  con <- local_sources_db()
  cfg <- corrections_config()
  cfg$sources$stg_missing <- list(key = "mrn")
  expect_error(generate_corrections_sql(cfg, con, withr::local_tempdir(), "duckdb"),
               class = "hvtiRdatabuild_unknown_source")
  cfg <- corrections_config()
  cfg$sources$stg_echo$key <- c("mrn", "no_such_column")
  expect_error(generate_corrections_sql(cfg, con, withr::local_tempdir(), "duckdb"),
               class = "hvtiRdatabuild_unknown_key_column")
})

test_that("the template has one column per declared key, and is never overwritten", {
  cfg <- corrections_config()
  path <- withr::local_tempfile(fileext = ".csv")
  write_corrections_template(cfg, path)
  expect_identical(names(utils::read.csv(path, check.names = FALSE)),
                   c("source", "mrn", "encounter_date", "variable", "expected_prior",
                     "expected_prior_missing", "new_value", "new_value_missing",
                     "evidence_type", "evidence_ref", "asserted_by"))
  expect_error(write_corrections_template(cfg, path), class = "hvtiRdatabuild_file_exists")
})
