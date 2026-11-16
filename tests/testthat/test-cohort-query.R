test_that("a cohort query records its definition", {
  q <- cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")))
  expect_s3_class(q, "cohort_query")
  expect_identical(q$index, "first")
  expect_identical(q$prior, "keep")
  expect_identical(q$epoch, as.Date(c("2000-01-01", "2024-07-31")))
})

test_that("a malformed query or epoch is refused", {
  epoch <- as.Date(c("2000-01-01", "2024-07-31"))
  expect_error(cohort_query("", epoch), "qualifying")
  expect_error(cohort_query(c("a", "b"), epoch), "qualifying")
  expect_error(cohort_query("proc = 'CABG'", rev(epoch)), "start")
  expect_error(cohort_query("proc = 'CABG'", "2000-01-01"), "two Dates")
  expect_error(cohort_query("proc = 'CABG'", epoch, index = "last"), "should be one of")
})

test_that("printing shows the definition", {
  out <- capture.output(print(cohort_query("proc = 'CABG'",
                                           as.Date(c("2000-01-01", "2024-07-31")),
                                           index = "all", prior = "exclude")))
  expect_true(any(grepl("proc = 'CABG'", out, fixed = TRUE)))
  expect_true(any(grepl("2000-01-01 to 2024-07-31", out, fixed = TRUE)))
  expect_true(any(grepl("index all", out, fixed = TRUE)))
})

# No PHI: values are invented.
crit_a <- function(id = "a", kind = "warehouse") {
  switch(kind,
         warehouse = criterion(id, "A", "include", master_row("age >= 18"), "exclude"),
         review = review_criterion(id, "R", "exclude"))
}
ep <- as.Date(c("2019-10-01", "2026-01-31"))

test_that("criteria with index first need index_on stated", {
  expect_error(cohort_query("proc = 'CABG'", ep, criteria = list(crit_a())),
               class = "hvtiRdatabuild_criterion_argument", regexp = "`index_on` is required")
  q <- cohort_query("proc = 'CABG'", ep, criteria = list(crit_a()), index_on = "eligible")
  expect_identical(q$index_on, "eligible")
  expect_error(cohort_query("proc = 'CABG'", ep, index = "all",
                            criteria = list(crit_a()), index_on = "eligible"),
               "only with index = \"first\"")
  expect_error(cohort_query("proc = 'CABG'", ep, index_on = "qualifying"),
               "only with index = \"first\"")
})

test_that("criteria must be criteria, with unique ids, grouped by kind", {
  expect_error(cohort_query("proc = 'CABG'", ep, criteria = list("age >= 18"),
                            index_on = "qualifying"),
               "must be a list of criteria")
  expect_error(cohort_query("proc = 'CABG'", ep, criteria = list(crit_a(), crit_a()),
                            index_on = "qualifying"),
               "ids must be unique")
  expect_error(cohort_query("proc = 'CABG'", ep,
                            criteria = list(crit_a("r", "review"), crit_a()),
                            index_on = "qualifying"),
               "warehouse criteria first, then local, then review")
})

test_that("a query without criteria is unchanged", {
  q <- cohort_query("proc = 'CABG'", ep)
  expect_identical(q$criteria, list())
  expect_null(q$index_on)
  expect_output(print(cohort_query("proc = 'CABG'", ep, criteria = list(crit_a()),
                                   index_on = "qualifying")),
                "a \\[include, warehouse\\]")
})
