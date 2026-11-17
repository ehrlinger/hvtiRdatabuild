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

test_that("a clean file is appendable on a dry run, and nothing is written", {
  s <- propose_setup()
  patient <- good_row(source = "stg_patient", encounter_date = "", variable = "sex",
                      expected_prior = "F", new_value = "M")
  f <- write_submission(s$cfg, list(good_row(), patient))
  out <- propose_corrections(s$cfg, s$con, f, dialect = "duckdb")
  expect_identical(out$verdicts$verdict, c("appendable", "appendable"))
  expect_identical(out$appended, 0L)
  expect_identical(DBI::dbGetQuery(s$con, "SELECT COUNT(*) AS n FROM stg_echo_corrections")$n,
                   0)
  expect_match(out$file_sha256, "^[0-9a-f]{64}$")
})

test_that("every verdict is reached, and a bad row refuses the whole file", {
  s <- propose_setup()
  rows <- list(
    good_row(),                                                      # 1 appendable
    good_row(mrn = "SYN2*"),                                         # 2 rule_not_fact
    good_row(source = "stg_nowhere"),                                # 3 unknown_source
    good_row(evidence_type = "hunch"),                               # 4 invalid_field
    good_row(expected_prior_missing = "1"),                          # 5 invalid_field
    good_row(variable = "nosuch"),                                   # 6 no_variable
    # 7 derived_variable
    good_row(variable = "mr_severe", expected_prior = "0", new_value = "1"),
    good_row(mrn = "SYN299"),                                        # 8 unknown_key
    good_row(source = "stg_patient", variable = "sex", expected_prior = "F",
             new_value = "M"),                                       # 9 unknown_key
    good_row(variable = "seen_on", expected_prior = "2019-12-01",
             new_value = "not a date"),                              # 10 does_not_cast
    good_row(expected_prior = "31"),                                 # 11 prior_mismatch
    # 12 no_variable (key)
    good_row(variable = "mrn", expected_prior = "SYN201", new_value = "SYN209"),
    good_row(mrn = "SYN204", encounter_date = "2020-04-01", variable = "mr_grade",
             expected_prior = "", expected_prior_missing = "1", new_value = "",
             new_value_missing = "1")                                # 13 appendable: NA to NA
  )
  f <- write_submission(s$cfg, rows)
  out <- propose_corrections(s$cfg, s$con, f, dialect = "duckdb")
  expected <- c("appendable", "rule_not_fact", "unknown_source", "invalid_field",
                "invalid_field", "no_variable", "derived_variable", "unknown_key",
                "unknown_key", "does_not_cast", "prior_mismatch", "no_variable",
                "appendable")
  expect_identical(out$verdicts$verdict, expected)
  expect_error(propose_corrections(s$cfg, s$con, f, dry_run = FALSE, dialect = "duckdb"),
               class = "hvtiRdatabuild_corrections_refused")
  expect_identical(DBI::dbGetQuery(s$con, "SELECT COUNT(*) AS n FROM stg_echo_corrections")$n,
                   0)
})

test_that("an appended file is canonical text and live once accepted", {
  s <- propose_setup()
  f <- write_submission(s$cfg, list(good_row(expected_prior = "30.0", new_value = "35.00")))
  out <- propose_corrections(s$cfg, s$con, f, dry_run = FALSE, dialect = "duckdb")
  expect_identical(out$appended, 1L)
  row <- DBI::dbGetQuery(s$con, "SELECT * FROM stg_echo_corrections")
  expect_identical(c(row$expected_prior, row$new_value), c("30", "35"))
  expect_identical(row$asserted_by, "reviewer_a")
  DBI::dbAppendTable(s$con, "stg_echo_correction_decisions",
                     dec_row("d1", out$correction_ids[[1]]))
  got <- DBI::dbGetQuery(s$con, "SELECT lvef FROM stg_echo_corrected WHERE mrn = 'SYN201'")
  expect_identical(got$lvef, 35)
})

test_that("no value or key reaches a message", {
  s <- propose_setup()
  f <- write_submission(s$cfg, list(good_row(expected_prior = "31")))
  msgs <- testthat::capture_messages(
    try(propose_corrections(s$cfg, s$con, f, dry_run = FALSE, dialect = "duckdb"),
        silent = TRUE)
  )
  err <- tryCatch(propose_corrections(s$cfg, s$con, f, dry_run = FALSE, dialect = "duckdb"),
                  error = conditionMessage)
  for (text in c(msgs, err)) {
    expect_false(grepl("SYN201|2020-01-01|31|35", text))
  }
})

test_that("a value the column would round or overflow does not cast; booleans do", {
  s <- propose_setup()
  DBI::dbExecute(s$con, paste("CREATE TABLE stg_lab (mrn VARCHAR, encounter_date DATE,",
                              "potassium DECIMAL(4,1), on_pump BOOLEAN, n_grafts SMALLINT)"))
  DBI::dbExecute(s$con, "INSERT INTO stg_lab VALUES ('SYN201', DATE '2020-01-01', 4.1, TRUE, 3)")
  s$cfg$sources$stg_lab <- list(key = c("mrn", "encounter_date"))
  lab <- function(...) good_row(source = "stg_lab", ...)
  f <- write_submission(s$cfg, list(
    lab(variable = "potassium", expected_prior = "4.1", new_value = "4.25"),  # rounds
    lab(variable = "potassium", expected_prior = "4.1", new_value = "4.2"),
    lab(variable = "on_pump", expected_prior = "TRUE", new_value = "0"),
    lab(variable = "n_grafts", expected_prior = "3", new_value = "70000")    # overflows
  ))
  out <- propose_corrections(s$cfg, s$con, f, dialect = "duckdb")
  expect_identical(out$verdicts$verdict,
                   c("does_not_cast", "appendable", "appendable", "does_not_cast"))
})

test_that("keys and values are kept verbatim; only structural fields are trimmed", {
  s <- propose_setup()
  DBI::dbExecute(s$con, "UPDATE stg_echo SET mr_grade = ' 2' WHERE mrn = 'SYN201'")
  padded <- good_row(variable = " mr_grade ", expected_prior = " 2", new_value = "3")
  plain <- good_row(variable = "mr_grade", expected_prior = "2", new_value = "3")
  f <- write_submission(s$cfg, list(padded, plain))
  out <- propose_corrections(s$cfg, s$con, f, dialect = "duckdb")
  expect_identical(out$verdicts$verdict, c("appendable", "prior_mismatch"))
})

test_that("an empty string and significant spaces survive intake into the view", {
  s <- propose_setup()
  empty <- good_row(variable = "mr_grade", expected_prior = "2", new_value = "")
  spaced <- good_row(mrn = "SYN203", encounter_date = "2020-03-01", variable = "mr_grade",
                     expected_prior = "1", new_value = "  3 ")
  f <- write_submission(s$cfg, list(empty, spaced))
  out <- propose_corrections(s$cfg, s$con, f, dry_run = FALSE, dialect = "duckdb")
  expect_identical(out$appended, 2L)
  stored <- DBI::dbGetQuery(s$con, paste("SELECT new_value, new_value_missing FROM",
                                         "stg_echo_corrections ORDER BY mrn"))
  expect_identical(stored$new_value, c("", "  3 "))
  expect_identical(stored$new_value_missing, c(0L, 0L))
  DBI::dbAppendTable(s$con, "stg_echo_correction_decisions",
                     rbind(dec_row("d1", out$correction_ids[[1]]),
                           dec_row("d2", out$correction_ids[[2]])))
  got <- DBI::dbGetQuery(s$con, paste("SELECT mr_grade FROM stg_echo_corrected",
                                      "WHERE mrn IN ('SYN201', 'SYN203') ORDER BY mrn"))
  expect_identical(got$mr_grade, c("", "  3 "))
})

test_that("a template with the wrong columns is refused before any row is read", {
  s <- propose_setup()
  f <- withr::local_tempfile(fileext = ".csv")
  writeLines("source,mrn,variable", f)
  expect_error(propose_corrections(s$cfg, s$con, f, dialect = "duckdb"),
               class = "hvtiRdatabuild_template_columns")
})

test_that("the intake join is exact on mssql for character keys only", {
  types <- c(mrn = "nvarchar(128)", encounter_date = "date", lvef = "float")
  sql <- .intake_lookup_sql("#correction_intake", "stg_echo", c("mrn", "encounter_date"),
                            types, "lvef", "mssql")
  expect_match(sql, "b.[mrn] COLLATE Latin1_General_BIN2", fixed = TRUE)
  expect_match(sql, "DATALENGTH(b.[mrn]) = DATALENGTH(t.[mrn])", fixed = TRUE)
  expect_match(sql, "b.[encounter_date] = t.[encounter_date]", fixed = TRUE)
  expect_equal(lengths(regmatches(sql, gregexpr("COLLATE", sql))), 2L)
  expect_match(sql, "t.row_id AS intake_row_", fixed = TRUE)
  duck <- .intake_lookup_sql("correction_intake", "stg_echo", c("mrn", "encounter_date"),
                             types, "lvef", "duckdb")
  expect_false(grepl("COLLATE|DATALENGTH", duck))
})

test_that("a key matching more than one source row is ambiguous", {
  s <- propose_setup()
  DBI::dbExecute(s$con, paste("INSERT INTO stg_echo VALUES ('SYN201', DATE '2020-01-01',",
                              "31, '2', DATE '2019-12-01')"))
  f <- write_submission(s$cfg, list(good_row()))
  out <- propose_corrections(s$cfg, s$con, f, dialect = "duckdb")
  expect_identical(out$verdicts$verdict, "ambiguous_key")
})

test_that("a key the column would round names no row, and cannot correct another", {
  s <- propose_setup()
  DBI::dbExecute(s$con, "CREATE TABLE stg_num (id INTEGER, lvef DOUBLE)")
  DBI::dbExecute(s$con, "INSERT INTO stg_num VALUES (1, 30)")
  s$cfg$sources$stg_num <- list(key = "id")
  num <- function(id) good_row(source = "stg_num", mrn = "", encounter_date = "", id = id)
  f <- write_submission(s$cfg, list(num("1.2"), num("1")))
  out <- propose_corrections(s$cfg, s$con, f, dialect = "duckdb")
  expect_identical(out$verdicts$verdict, c("unknown_key", "appendable"))
  expect_error(propose_corrections(s$cfg, s$con, write_submission(s$cfg, list(num("1.2"))),
                                   dry_run = FALSE, dialect = "duckdb"),
               class = "hvtiRdatabuild_corrections_refused")
})

test_that("a key or value with a malformed suffix is refused, not cut to a prefix", {
  s <- propose_setup()
  f <- write_submission(s$cfg, list(
    good_row(encounter_date = "2020-01-01junk"),                         # would name row 1
    good_row(variable = "seen_on", expected_prior = "2019-12-01",
             new_value = "2019-12-05x"),
    good_row(new_value = "0x23"),                                        # hex for 35
    good_row(encounter_date = "2020-01-01")
  ))
  out <- propose_corrections(s$cfg, s$con, f, dialect = "duckdb")
  expect_identical(out$verdicts$verdict,
                   c("unknown_key", "does_not_cast", "does_not_cast", "appendable"))
})

test_that("submitted text must be the whole of a supported form", {
  ok <- function(x, cls) !is.na(.parse_submitted(x, cls))
  expect_true(ok("2020-01-01", "Date"))
  expect_false(ok("2020-01-01junk", "Date"))
  expect_false(ok("2020-1-1", "Date"))
  expect_true(ok("2020-01-01 10:30", "POSIXct"))
  expect_true(ok("2020-01-01 10:30:05.123456", "POSIXct"))
  expect_false(ok("2020-01-01 10:30junk", "POSIXct"))
  expect_true(ok("-1.5e3", "numeric"))
  expect_true(ok("30.0", "numeric"))
  expect_false(ok("0x23", "integer"))
  expect_false(ok("30 ", "numeric"))
  expect_identical(.parse_submitted(" 2", "character"), " 2")
})
