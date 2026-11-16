# No PHI: identifiers and values are invented. Fixtures in helper-master-pull.R and
# helper-criteria.R.

lvef_25 <- criterion("lvef", "LVEF 25% or less within 30 days", "include",
                     view_rows("echo_demo", "measured_on", c(-30, 0), "nearest",
                               "lvef <= 25"),
                     undetermined = "exclude")
inotrope <- criterion("inotrope", "Inotrope within 72 hours", "exclude",
                      view_rows("med_demo", "given_at", c(-3, 0), "any",
                                "drug_class = 'inotrope'"),
                      undetermined = "keep")
criteria_db <- function(env = parent.frame()) {
  con <- local_master_db(env)
  seed_criteria_views(con)
}

test_that("each criterion is a counted stage, in declared order", {
  con <- criteria_db()
  res <- pull_demo(con, demo_query(criteria = list(lvef_25), index_on = "qualifying"))
  s <- cohort_summary(res$cohort)$stages
  expect_identical(s$stage_id, c("qualifying", "prior_qualifying", "lvef", "in_master"))
  expect_identical(res$data$cohort_unit, "SYN101|2010-03-01")
  expect_identical(res$meta$status, "complete")
  expect_identical(res$cohort$stages$source[3], "upstream")
  expect_match(res$cohort$stages$provenance[3], "met 1, not met 0, undetermined 2")
})

test_that("an exclusion keeps undetermined units when told to", {
  con <- criteria_db()
  res <- pull_demo(con, demo_query(criteria = list(inotrope), index_on = "qualifying"))
  # SYN101 and SYN103 had an inotrope in the window; SYN104 had none in it.
  expect_identical(res$data$cohort_unit, "SYN104|2020-01-10")
  excluded <- res$cohort$members[res$cohort$members$stage_id == "inotrope" &
                                   !res$cohort$members$included, ]
  expect_setequal(excluded$reason, "excluded: Inotrope within 72 hours")
})

test_that("index_on decides whether a later encounter can be the index", {
  con <- criteria_db()
  DBI::dbExecute(con, second_cabg)
  on_qualifying <- pull_demo(con, demo_query(criteria = list(inotrope),
                                             index_on = "qualifying"))
  on_eligible <- pull_demo(con, demo_query(criteria = list(inotrope),
                                           index_on = "eligible"))
  expect_false(any(grepl("^SYN103", on_qualifying$data$cohort_unit)))
  expect_true("SYN103|2018-02-02" %in% on_eligible$data$cohort_unit)
  expect_identical(cohort_summary(on_eligible$cohort)$stages$stage_id,
                   c("qualifying", "prior_qualifying", "inotrope", "in_master",
                     "index_eligible"))
  expect_false(anyDuplicated(sub("\\|.*", "", on_eligible$data$cohort_unit)) > 0)
})

test_that("a criterion that excludes everyone still records the stages after it", {
  con <- criteria_db()
  nobody <- criterion("nobody", "Nobody", "include", master_row("age > 200"), "exclude")
  res <- pull_demo(con, demo_query(criteria = list(nobody, inotrope),
                                   index_on = "eligible"))
  s <- cohort_summary(res$cohort)$stages
  expect_identical(s$stage_id, c("qualifying", "prior_qualifying", "nobody", "inotrope",
                                 "in_master", "index_eligible"))
  expect_identical(nrow(res$data), 0L)
  expect_identical(res$meta$status, "complete")
  expect_identical(res$meta$n_cohort, 0L)
})

test_that("undetermined units routed to review leave the pull awaiting review", {
  con <- criteria_db()
  routed <- criterion("lvef", "LVEF 25% or less", "include",
                      view_rows("echo_demo", "measured_on", c(-30, 0), "nearest",
                                "lvef <= 25"),
                      undetermined = "review")
  res <- pull_demo(con, demo_query(criteria = list(routed), index_on = "qualifying"))
  expect_identical(res$meta$status, "awaiting review")
  expect_setequal(res$review$queue$cohort_unit,
                  c("SYN103|2015-06-30", "SYN104|2020-01-10"))
  expect_identical(nrow(res$data), 3L)
})

test_that("only keys and flags leave the database during selection", {
  con <- criteria_db()
  seen <- character()
  real <- DBI::dbGetQuery
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      seen <<- c(seen, statement)
      real(conn, statement, ...)
    },
    .package = "DBI"
  )
  pull_demo(con, demo_query(criteria = list(lvef_25, inotrope), index_on = "qualifying"))
  expect_false(any(grepl("echo_demo|med_demo", seen)))
})

test_that("a pull without criteria is unchanged", {
  con <- criteria_db()
  res <- pull_demo(con, demo_query())
  expect_identical(cohort_summary(res$cohort)$stages$stage_id,
                   c("qualifying", "prior_qualifying", "in_master"))
  expect_identical(res$meta$status, "complete")
})
