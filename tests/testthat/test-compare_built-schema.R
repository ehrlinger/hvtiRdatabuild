test_that("compare_built reports variables present on only one side", {
  o <- data.frame(ccfidu = "A1", age = 65, dropped = 1)
  r <- data.frame(ccfidu = "A1", age = 65, added   = 1)

  res <- compare_built(o, r, id = "ccfidu")

  expect_s3_class(res, "built_comparison")
  expect_equal(res$verdict[res$variable == "dropped"], "absent_in_r")
  expect_equal(res$verdict[res$variable == "added"],   "absent_in_sas")
})

test_that("compare_built flags type mismatches without comparing values", {
  o <- data.frame(ccfidu = "A1", x = 1)
  r <- data.frame(ccfidu = "A1", x = "1", stringsAsFactors = FALSE)

  res <- compare_built(o, r, id = "ccfidu")
  expect_equal(res$verdict[res$variable == "x"], "type_mismatch")
})

test_that("compare_built reports row-set differences separately", {
  o <- data.frame(ccfidu = c("A1", "A2"), age = c(1, 2))
  r <- data.frame(ccfidu = c("A2", "A3"), age = c(2, 3))

  res <- compare_built(o, r, id = "ccfidu")
  rows <- attr(res, "rows")

  expect_equal(rows$n_oracle, 2L)
  expect_equal(rows$n_r, 2L)
  expect_equal(rows$n_common, 1L)
  expect_equal(rows$only_oracle, "A1")
  expect_equal(rows$only_r, "A3")

  # The shared row matches, so age is identical despite the cohort difference.
  expect_equal(res$verdict[res$variable == "age"], "identical")
})

test_that("compare_built errors when the id column is missing", {
  o <- data.frame(ccfidu = "A1", age = 1)
  r <- data.frame(other  = "A1", age = 1)
  expect_error(compare_built(o, r, id = "ccfidu"), "not present")
})

test_that("compare_built errors on duplicate ids", {
  o <- data.frame(ccfidu = c("A1", "A1"), age = c(1, 2))
  r <- data.frame(ccfidu = c("A1", "A1"), age = c(1, 2))
  expect_error(compare_built(o, r, id = "ccfidu"), "duplicated")
})

test_that("compare_built errors when no identifiers are shared", {
  o <- data.frame(ccfidu = c("A1", "A2"), age = c(65, 70))
  r <- data.frame(ccfidu = c("B1", "B2"), age = c(99, 99))
  # Must not report "identical" about rows it never compared.
  expect_error(compare_built(o, r, id = "ccfidu"), "No shared values")
})

test_that("compare_built rejects missing identifiers on either side", {
  ok  <- data.frame(ccfidu = c("A1", "A2"), age = c(65, 70))
  bad <- data.frame(ccfidu = c("A1", NA), age = c(65, 70))
  expect_error(compare_built(bad, ok, id = "ccfidu"), "missing value")
  expect_error(compare_built(ok, bad, id = "ccfidu"), "missing value")
})

test_that("compare_built aligns rows by identifier, not by position", {
  # Same data, different row order. A positional join would report
  # spurious differences on every variable.
  o <- data.frame(ccfidu = c("A1", "A2", "A3"),
                  age = c(65, 70, 58), bmi = c(30, 25, 22))
  r <- data.frame(ccfidu = c("A3", "A1", "A2"),
                  age = c(58, 65, 70), bmi = c(22, 30, 25))

  res <- compare_built(o, r, id = "ccfidu")
  expect_true(all(res$verdict == "identical"))

  # And a single real difference is isolated to the right variable.
  r2 <- r
  r2$age[r2$ccfidu == "A2"] <- 71
  res2 <- compare_built(o, r2, id = "ccfidu")
  expect_equal(res2$verdict[res2$variable == "age"], "differs")
  expect_equal(res2$n_differ[res2$variable == "age"], 1L)
  expect_equal(res2$verdict[res2$variable == "bmi"], "identical")
})

test_that("compare_built reports within_tolerance end to end", {
  o <- data.frame(ccfidu = c("A1", "A2"), age = c(65, 70))
  r <- data.frame(ccfidu = c("A1", "A2"), age = c(65, 70 + 1e-10))

  res <- compare_built(o, r, id = "ccfidu", tolerance = 1e-8)
  age <- res[res$variable == "age", ]
  expect_equal(age$verdict, "within_tolerance")
  expect_equal(age$n_differ, 1L)
  expect_true(age$max_abs_diff > 0 && age$max_abs_diff <= 1e-8)
})
