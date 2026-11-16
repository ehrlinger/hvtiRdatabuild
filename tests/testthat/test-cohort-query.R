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
