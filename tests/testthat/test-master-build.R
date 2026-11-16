# No PHI: identifiers and values are invented. Fixtures in helper-master-pull.R.

test_that("a master pull becomes a build_result with a build stage", {
  con <- local_master_db()
  pull <- pull_demo(con, unit_cohort(c("SYN101", "SYN999"), c("2010-03-01", "2011-01-01")))

  build <- build_from_master(pull)

  expect_s3_class(build, "build_result")
  expect_identical(names(build), c("data", "cohort", "tables"))
  expect_identical(build$tables, list())
  s <- cohort_summary(build$cohort)$stages
  expect_identical(utils::tail(s$stage_id, 1L), "build")
  expect_identical(utils::tail(s$n_remaining, 1L), 1L)
  expect_setequal(active_units(build$cohort), build$data$cohort_unit)
})

test_that("derive_vars() accepts a master build", {
  con <- local_master_db()
  build <- build_from_master(pull_demo(con, demo_query()))
  config <- structure(list(
    study = "st0000", cohort_table = "unused", warehouse = "unused",
    view_schema = "unused", pull_date = as.Date("2026-11-16"), modules = "base",
    varsets = character(0), derive = stats::setNames(logical(0), character(0))
  ), class = "study_config")

  out <- derive_vars(build, config,
                     function(data, cohort, config) list(data = data, cohort = cohort))

  expect_identical(nrow(out$data), nrow(build$data))
})

test_that("pulled rows that disagree with the cohort are refused", {
  con <- local_master_db()
  pull <- pull_demo(con, demo_query())
  pull$data <- pull$data[-1, , drop = FALSE]
  expect_error(build_from_master(pull), "do not match the active cohort")
})

test_that("only a master_pull is built", {
  expect_error(build_from_master(list()), "master_pull")
})
