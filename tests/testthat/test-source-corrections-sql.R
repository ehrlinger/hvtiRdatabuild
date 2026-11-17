# No PHI: identifiers and values are invented.

test_that("table_types() keeps a decimal's precision and scale", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbExecute(con, "CREATE TABLE t_dec (a DECIMAL(10,2), b INTEGER)")
  expect_identical(unname(table_types(con, "t_dec")), c("DECIMAL(10,2)", "INTEGER"))
})

test_that("parse_value() reads logical text", {
  expect_identical(parse_value("1", "logical"), TRUE)
  expect_identical(parse_value("FALSE", "logical"), FALSE)
  expect_identical(parse_value("maybe", "logical"), NA)
  expect_identical(value_text(TRUE), "TRUE")
})

test_that("each source gets its own typed corrections and decisions tables", {
  con <- local_sources_db()
  types <- table_types(con, "stg_echo")
  ddl <- source_corrections_ddl("stg_echo", types[c("mrn", "encounter_date")], "duckdb")
  expect_named(ddl, c("corrections", "decisions"))
  for (s in ddl) DBI::dbExecute(con, s)
  got <- table_types(con, "stg_echo_corrections")
  expect_identical(unname(got[c("mrn", "encounter_date")]), unname(types[c("mrn",
                                                                           "encounter_date")]))
  expect_true(all(c("source", "variable", "expected_prior_missing") %in% names(got)))
  expect_true(DBI::dbExistsTable(con, "stg_echo_correction_decisions"))
})

test_that("the R reference applies each rule of the case matrix", {
  con <- local_sources_db()
  base <- DBI::dbGetQuery(con, "SELECT * FROM stg_echo ORDER BY mrn")
  ref <- resolve_source_corrections(base, case_corrections(), case_decisions(),
                                    c("mrn", "encounter_date"))
  expect_identical(ref$data$lvef, c(35, 45, 40, 50, 55))
  expect_identical(ref$data$mr_grade, c("3", "3", "1", NA, "4"))
  expect_identical(sort(ref$applied$correction_id),
                   c("c01", "c02", "c05", "c06", "c14", "c15"))
  stale <- stats::setNames(ref$stale$reason, ref$stale$correction_id)
  expect_identical(stale[sort(names(stale))],
                   c(c07 = "filled_upstream_agrees", c09 = "prior_mismatch",
                     c10 = "no_variable", c11 = "no_record", c12 = "prior_unknown",
                     c13 = "does_not_cast"))
  conf <- stats::setNames(ref$conflicts$reason, ref$conflicts$correction_id)
  expect_identical(conf[sort(names(conf))],
                   c(c03 = "accepted_disagree", c04 = "accepted_disagree",
                     c08 = "filled_upstream_disagrees"))
  expect_false(any(c("c16", "c17") %in% c(ref$applied$correction_id,
                                          ref$stale$correction_id,
                                          ref$conflicts$correction_id)))
})
