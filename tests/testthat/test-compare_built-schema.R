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
