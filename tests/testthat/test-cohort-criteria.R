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

test_that("compiling numbers the leaves across stages", {
  a <- criterion("a", "A", "include", any_of(master_row("x = 1"), master_row("y = 1")),
                 "exclude")
  b <- criterion("b", "B", "exclude", master_row("z = 1"), "keep")
  r <- review_criterion("r", "R", "exclude")
  comp <- .compile_criteria(list(a, b, r))
  expect_identical(comp$n_flags, 3L)
  expect_length(comp$stages, 2L)
  expect_identical(vapply(.node_leaves(comp$stages[[1]]$node), `[[`, "", "col"),
                   c("crit_1", "crit_2"))
  expect_identical(comp$stages[[2]]$node$col, "crit_3")
})

test_that("any_of and all_of follow three-valued logic", {
  flags <- data.frame(crit_1 = c(1L, 0L, 0L, NA, NA, 1L),
                      crit_2 = c(NA, 0L, NA, 0L, NA, 1L))
  leaf <- function(k) list(type = "leaf", col = paste0("crit_", k))
  any_node <- list(type = "any", parts = list(leaf(1), leaf(2)))
  all_node <- list(type = "all", parts = list(leaf(1), leaf(2)))
  expect_identical(.eval_node(any_node, flags), c(1L, 0L, NA, NA, NA, 1L))
  expect_identical(.eval_node(all_node, flags), c(NA, 0L, 0L, 0L, NA, 1L))
})

test_that("a stage outcome applies role and the undetermined route", {
  s <- c(1L, 0L, NA)
  inc <- .stage_outcome("include", "review", s, "LVEF")
  expect_identical(inc$included, c(TRUE, FALSE, TRUE))
  expect_identical(inc$reason, c(NA, "did not meet: LVEF", NA))
  expect_identical(inc$review, c(FALSE, FALSE, TRUE))
  exc <- .stage_outcome("exclude", "exclude", s, "Inotrope")
  expect_identical(exc$included, c(FALSE, TRUE, FALSE))
  expect_identical(exc$reason, c("excluded: Inotrope", NA, "undetermined: Inotrope"))
})

test_that("a stage with nobody active gives typed, empty outcomes", {
  out <- .stage_outcome("include", "exclude", integer(), "LVEF")
  expect_identical(out$included, logical())
  expect_identical(out$reason, character())
  expect_identical(out$review, logical())
})
