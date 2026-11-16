test_that("identical frames yield all identical", {
  d <- .fixture_frame()
  res <- compare_built(d, d, id_col = "ccfidu")
  expect_true(all(res$verdict == "identical"))
  expect_equal(nrow(res), 4L)  # age, bmi, dt_surg, surgeon
})

test_that("a sub-tolerance perturbation is within_tolerance with a real diff", {
  d <- .fixture_frame()
  p <- d
  p$age[1] <- p$age[1] + 1e-10

  res <- compare_built(d, p, id_col = "ccfidu", tolerance = 1e-8)
  age <- res[res$variable == "age", ]
  expect_equal(age$verdict, "within_tolerance")
  expect_equal(age$n_differ, 1L)
  expect_true(age$max_abs_diff > 0 && age$max_abs_diff <= 1e-8)
})

test_that("a supra-tolerance perturbation differs and reports the magnitude", {
  d <- .fixture_frame()
  p <- d
  p$age[1] <- p$age[1] + 0.5

  res <- compare_built(d, p, id_col = "ccfidu", tolerance = 1e-8)
  age <- res[res$variable == "age", ]
  expect_equal(age$verdict, "differs")
  expect_equal(age$n_differ, 1L)
  expect_equal(age$max_abs_diff, 0.5)
})

test_that("a renamed variable is never reported as matching", {
  d <- .fixture_frame()
  p <- d
  names(p)[names(p) == "age"] <- "age_at_surgery"

  res <- compare_built(d, p, id_col = "ccfidu")
  expect_equal(res$verdict[res$variable == "age"], "absent_in_r")
  expect_equal(res$verdict[res$variable == "age_at_surgery"], "absent_in_sas")
  expect_false(any(res$verdict == "identical" &
                     res$variable %in% c("age", "age_at_surgery")))
})

test_that("the SAS missing-sorts-low divergence is visible, not hidden", {
  # SAS: `if bmi < 18.5 then underweight = 1` marks missing BMI as underweight.
  # R excludes it. compare_built must surface this rather than smooth it over.
  d <- .fixture_frame()
  sas <- data.frame(
    ccfidu      = d$ccfidu,
    underweight = as.numeric(!is.na(d$bmi) & d$bmi < 18.5 | is.na(d$bmi)),
    stringsAsFactors = FALSE
  )
  r <- data.frame(
    ccfidu      = d$ccfidu,
    underweight = as.numeric(d$bmi < 18.5),
    stringsAsFactors = FALSE
  )

  res <- compare_built(sas, r, id_col = "ccfidu")
  expect_equal(res$verdict[res$variable == "underweight"], "differs")
  expect_true(res$n_differ[res$variable == "underweight"] >= 1L)
})

test_that("numeric ids match by value whatever their storage type", {
  o <- data.frame(ccfidu = c(100000, 200000, 1e15), age = c(60, 61, 62))
  r <- data.frame(ccfidu = c(100000L, 200000L), age = c(60, 61))
  res <- compare_built(o[1:2, ], r, id_col = "ccfidu")
  rows <- attr(res, "rows")
  expect_equal(rows$n_common, 2L)
  expect_length(rows$only_oracle, 0L)
  expect_length(rows$only_r, 0L)
  expect_equal(res$verdict[res$variable == "age"], "identical")
  big <- compare_built(o[3, ], data.frame(ccfidu = 1e15, age = 62), id_col = "ccfidu")
  expect_equal(attr(big, "rows")$n_common, 1L)
})

test_that("distinct numeric ids that print alike are never matched as one", {
  ids <- c(0.12345678901234561, 0.12345678901234568)
  o <- data.frame(ccfidu = ids, v = c(1, 2))
  r <- data.frame(ccfidu = ids, v = c(1, 999))
  res <- compare_built(o, r, id_col = "ccfidu")
  expect_equal(attr(res, "rows")$n_common, 2L)
  expect_equal(res$verdict[res$variable == "v"], "differs")
  expect_equal(res$n_differ[res$variable == "v"], 1L)
})

test_that("integer and double ids match by value, and large doubles stay distinct", {
  big <- 2^52 + c(0, 1)
  o <- data.frame(ccfidu = big, v = c(1, 2))
  res <- compare_built(o, o, id_col = "ccfidu")
  expect_equal(attr(res, "rows")$n_common, 2L)
  mixed <- compare_built(data.frame(ccfidu = c(1e15, 7), v = 1:2),
                         data.frame(ccfidu = c(7L, 8L), v = 2:3), id_col = "ccfidu")
  expect_equal(attr(mixed, "rows")$n_common, 1L)
})

test_that("numeric ids beyond exact double precision are refused", {
  o <- data.frame(ccfidu = c(2^53 + 2, 1), v = 1:2)
  expect_error(compare_built(o, o, id_col = "ccfidu"), "compare_built\\(\\): .*exactly")
})
