# No PHI: identifiers and values are invented. Fixtures in helper-master-pull.R.

test_that("a supplied cohort pulls only its encounters and the study's columns", {
  con <- local_master_db()
  res <- pull_demo(con, unit_cohort(c("SYN101", "SYN102", "SYN999"),
                                    c("2010-03-01", "2012-07-15", "2011-01-01")))

  expect_s3_class(res, "master_pull")
  expect_setequal(names(res$data), c("mrn", "encounter_date", "age", "cohort_unit"))
  expect_identical(nrow(res$data), 2L)
  expect_identical(res$provenance$n_cohort, 3L)
  expect_identical(res$provenance$n_matched, 2L)
  expect_identical(res$provenance$n_unmatched, 1L)
})

test_that("a unit with no master row is excluded at the in_master stage", {
  con <- local_master_db()
  res <- pull_demo(con, unit_cohort(c("SYN101", "SYN999"), c("2010-03-01", "2011-01-01")))

  s <- cohort_summary(res$cohort)$stages
  expect_identical(utils::tail(s$stage_id, 1L), "in_master")
  expect_identical(utils::tail(s$n_excluded, 1L), 1L)
  expect_setequal(active_units(res$cohort), res$data$cohort_unit)
  expect_true(all(res$cohort$stages$source %in% c("upstream", "build", "derive")))
})

test_that("index first takes each patient's earliest qualifying encounter in the epoch", {
  con <- local_master_db()
  DBI::dbExecute(con, second_cabg)
  res <- pull_demo(con, demo_query())

  expect_setequal(res$data$cohort_unit,
                  c("SYN101|2010-03-01", "SYN103|2015-06-30", "SYN104|2020-01-10"))
  expect_identical(cohort_summary(res$cohort)$stages$stage_id,
                   c("qualifying", "prior_qualifying", "in_master"))
})

test_that("index all keeps every qualifying encounter in the epoch", {
  con <- local_master_db()
  DBI::dbExecute(con, second_cabg)
  expect_identical(nrow(pull_demo(con, demo_query(index = "all"))$data), 4L)
})

test_that("an earlier qualifying encounter is counted and kept by default", {
  con <- local_master_db()
  res <- pull_demo(con, demo_query())
  s <- cohort_summary(res$cohort)$stages
  prior <- res$cohort$stages$provenance[res$cohort$stages$stage_id == "prior_qualifying"]

  expect_identical(s$n_remaining[s$stage_id == "prior_qualifying"], 3L)
  expect_match(prior, "1 unit(s)", fixed = TRUE)
  expect_match(prior, "kept", fixed = TRUE)
})

test_that("prior = 'exclude' drops those units and does not pull their data", {
  con <- local_master_db()
  res <- pull_demo(con, demo_query(prior = "exclude"))
  s <- cohort_summary(res$cohort)$stages

  expect_identical(s$n_excluded[s$stage_id == "prior_qualifying"], 1L)
  expect_false("SYN101|2010-03-01" %in% res$data$cohort_unit)
  expect_identical(nrow(res$data), 2L)
})

test_that("keys outside the cohort never leave the database", {
  con <- local_master_db()
  DBI::dbExecute(con,
                 "INSERT INTO master_demo VALUES ('SYN105', DATE '2025-03-03', 'CABG', 60)")
  seen <- list()
  real_get <- DBI::dbGetQuery
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      out <- real_get(conn, statement, ...)
      seen[[length(seen) + 1L]] <<- out
      out
    },
    .package = "DBI"
  )

  pull_demo(con, demo_query())

  returned <- unlist(lapply(seen, function(d) unlist(lapply(d, as.character))))
  expect_false("SYN105" %in% returned)       # qualifying, but after the epoch
  expect_false("SYN102" %in% returned)       # in the epoch, but not qualifying
  expect_false("1998-05-01" %in% returned)   # the earlier encounter's date
})

test_that("a change committed during the pull is invisible to it", {
  skip_if_not_installed("duckdb")
  path <- withr::local_tempfile(fileext = ".duckdb")
  drv <- duckdb::duckdb(path)
  con <- DBI::dbConnect(drv)
  other <- DBI::dbConnect(drv)
  withr::defer({
    DBI::dbDisconnect(other)
    DBI::dbDisconnect(con, shutdown = TRUE)
  })
  seed_master(con)
  real_read <- .read_deployment
  testthat::local_mocked_bindings(.read_deployment = function(...) {
    DBI::dbExecute(other, second_cabg)
    DBI::dbExecute(other, "UPDATE master_demo_deployment SET sql_commit = 'new9999'")
    real_read(...)
  })

  res <- pull_master(con, "master_demo", demo_query(index = "all"), columns = "age",
                     dialect = "duckdb")

  expect_identical(res$provenance$sql_commit, "abc1234")
  expect_false("SYN103|2018-02-02" %in% res$data$cohort_unit)
  expect_false("SYN103|2018-02-02" %in% res$cohort$members$patient_id)
})

test_that("the pull records the deployment and only its own cohort's corrections", {
  con <- local_master_db()
  res <- pull_demo(con, unit_cohort(c("SYN101", "SYN102"), c("2010-03-01", "2012-07-15")))

  expect_identical(res$provenance$sql_commit, "abc1234")
  expect_identical(res$provenance$applied_correction_ids, "C1")
  expect_match(res$provenance$read_at,
               "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{6}Z$")
})

test_that("a unit matching two master rows stops the pull and rolls back", {
  con <- local_master_db()
  DBI::dbExecute(con,
                 "INSERT INTO master_demo VALUES ('SYN102', DATE '2012-07-15', 'AVR', 71)")
  cohort <- unit_cohort("SYN102", "2012-07-15")

  expect_error(pull_demo(con, cohort), "more than one master row")

  DBI::dbExecute(con, "DELETE FROM master_demo WHERE age = 71")
  expect_identical(nrow(pull_demo(con, cohort)$data), 1L)
})

test_that("two pulls on one connection both succeed", {
  con <- local_master_db()
  expect_identical(nrow(pull_demo(con, demo_query())$data), 3L)
  expect_identical(nrow(pull_demo(con, demo_query())$data), 3L)
})

test_that("an epoch with no qualifying encounters is an error", {
  con <- local_master_db()
  q <- cohort_query("proc = 'CABG'", as.Date(c("2021-01-01", "2021-12-31")))
  expect_error(pull_demo(con, q), "No qualifying encounters")
})

test_that("a deployment view without exactly one commit stops the pull", {
  con <- local_master_db()
  DBI::dbExecute(con, "INSERT INTO master_demo_deployment VALUES ('def5678')")
  expect_error(pull_demo(con, demo_query()), "exactly one")
})

test_that("a cohort not built on encounter units, or not a cohort, is refused", {
  con <- local_master_db()
  by_patient <- new_cohort_record(
    members = data.frame(patient_id = "SYN101", stage_id = "s", included = TRUE,
                         reason = NA_character_, stringsAsFactors = FALSE),
    stages = data.frame(stage_id = "s", order = 1L, label = "S", source = "upstream",
                        provenance = "fixture", stringsAsFactors = FALSE),
    patient_id_col = "masterid"
  )
  expect_error(pull_demo(con, by_patient), "cohort_unit")
  expect_error(pull_demo(con, list()), "cohort_query")
})

test_that("bad column requests are refused before any query", {
  con <- local_master_db()
  expect_error(pull_demo(con, demo_query(), columns = character(0)), "at least one")
  expect_error(pull_demo(con, demo_query(), columns = c("age", "age")), "duplicate")
})

test_that("a database error is withheld", {
  con <- local_master_db()
  err <- tryCatch(
    pull_master(con, "no_such_master", demo_query(), columns = "age", dialect = "duckdb"),
    error = conditionMessage
  )
  expect_match(err, "withheld")
})

test_that("print() and str() show counts, never identifiers or values", {
  con <- local_master_db()
  res <- pull_demo(con, demo_query())
  for (out in list(capture.output(print(res)), capture.output(str(res)))) {
    expect_true(any(grepl("matched", out)))
    expect_false(any(grepl("SYN", out, fixed = TRUE)))
    expect_false(any(grepl("2010-03-01", out, fixed = TRUE)))
  }
})

test_that("corrections in effect cover rows outside the cohort", {
  con <- local_master_db()
  DBI::dbExecute(con, paste("INSERT INTO master_demo_corrections_applied",
                            "VALUES ('C9', 'SYN102', DATE '2012-07-15')"))
  res <- pull_demo(con, demo_query())

  expect_false("C9" %in% res$provenance$applied_correction_ids)
  expect_setequal(res$provenance$corrections_in_effect, c("C1", "C2", "C9"))
})

test_that("an excluded prior encounter's corrections are not attributed to the pull", {
  con <- local_master_db()
  res <- pull_demo(con, demo_query(prior = "exclude"))

  expect_identical(res$provenance$applied_correction_ids, "C2")
  expect_setequal(res$provenance$corrections_in_effect, c("C1", "C2"))
})
