# No PHI: identifiers and values are invented.

lvef_test <- function(...) {
  view_rows("echo_demo", date_col = "measured_on", window = c(-30, 0),
            pick = "nearest", condition = "lvef <= 25", ...)
}

test_that("a criterion needs every clinical choice stated", {
  expect_error(criterion("lvef", "LVEF", test = lvef_test(), undetermined = "exclude"),
               class = "hvtiRdatabuild_criterion_argument", regexp = "`role` is required")
  expect_error(criterion("lvef", "LVEF", role = "include", test = lvef_test()),
               "`undetermined` is required")
  expect_error(view_rows("echo_demo", "measured_on", pick = "any", condition = "lvef < 1"),
               "`window` is required")
  expect_error(view_rows("echo_demo", "measured_on", c(-30, 0), condition = "lvef < 1"),
               "`pick` is required")
  expect_error(view_rows("echo_demo", window = c(-30, 0), pick = "any",
                         condition = "lvef < 1"),
               "`date_col` is required")
})

test_that("choices and windows are checked", {
  expect_error(criterion("lvef", "LVEF", "maybe", lvef_test(), "exclude"),
               "`role` must be one of")
  expect_error(criterion("lvef", "LVEF", "include", lvef_test(), "guess"),
               "`undetermined` must be one of")
  expect_error(view_rows("v", "d", c(0, -30), "any", "x = 1"), "start before its end")
  expect_error(view_rows("v", "d", c(-1.5, 0), "any", "x = 1"), "whole numbers of days")
  expect_error(view_rows("v", "d", c(-1, 0), "first", "x = 1"), "`pick` must be one of")
  expect_identical(view_rows("v", "d", c(-3, 0), "any", "x = 1")$window, c(-3L, 0L))
})

test_that("stage ids are identifiers and not the package's own stages", {
  expect_error(criterion("in_master", "X", "include", lvef_test(), "exclude"),
               "a stage the package uses itself")
  expect_error(criterion("2lvef", "X", "include", lvef_test(), "exclude"),
               "must start with a letter")
})

test_that("combinations take two or more tests and nest", {
  mitral <- master_row("mitral_surgery = 1")
  combo <- any_of(lvef_test(), all_of(mitral, master_row("mr_grade >= 3")))
  expect_s3_class(combo, "cohort_test")
  expect_identical(combo$type, "any")
  expect_identical(combo$parts[[2]]$type, "all")
  expect_error(any_of(mitral), "two or more tests")
  expect_error(all_of(mitral, "x = 1"), "two or more tests")
})

test_that("local and review criteria record what they need", {
  f <- withr::local_tempfile(fileext = ".csv")
  writeLines("mrn,flag", f)
  loc <- local_criterion("covid", "COVID-19 within 14 days", "exclude", f,
                         decide = function(units, path) rep(FALSE, nrow(units)),
                         undetermined = "review")
  expect_identical(loc$kind, "local")
  expect_identical(loc$sha256, digest::digest(f, algo = "sha256", file = TRUE))
  expect_error(local_criterion("covid", "C", "exclude", f, decide = "no",
                               undetermined = "review"),
               "`decide` must be a function")
  rev <- review_criterion("strategy", "Planned alternative support strategy", "exclude")
  expect_identical(rev$kind, "review")
  expect_error(review_criterion("strategy", "S"), "`role` is required")
})
