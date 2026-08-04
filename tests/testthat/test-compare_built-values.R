test_that("identical frames yield all identical", {
  d <- .fixture_frame()
  res <- compare_built(d, d, id = "ccfidu")
  expect_true(all(res$verdict == "identical"))
  expect_equal(nrow(res), 4L)  # age, bmi, dt_surg, surgeon
})

test_that("a sub-tolerance perturbation is within_tolerance with a real diff", {
  d <- .fixture_frame()
  p <- d
  p$age[1] <- p$age[1] + 1e-10

  res <- compare_built(d, p, id = "ccfidu", tolerance = 1e-8)
  age <- res[res$variable == "age", ]
  expect_equal(age$verdict, "within_tolerance")
  expect_equal(age$n_differ, 1L)
  expect_true(age$max_abs_diff > 0 && age$max_abs_diff <= 1e-8)
})

test_that("a supra-tolerance perturbation differs and reports the magnitude", {
  d <- .fixture_frame()
  p <- d
  p$age[1] <- p$age[1] + 0.5

  res <- compare_built(d, p, id = "ccfidu", tolerance = 1e-8)
  age <- res[res$variable == "age", ]
  expect_equal(age$verdict, "differs")
  expect_equal(age$n_differ, 1L)
  expect_equal(age$max_abs_diff, 0.5)
})

test_that("a renamed variable is never reported as matching", {
  d <- .fixture_frame()
  p <- d
  names(p)[names(p) == "age"] <- "age_at_surgery"

  res <- compare_built(d, p, id = "ccfidu")
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

  res <- compare_built(sas, r, id = "ccfidu")
  expect_equal(res$verdict[res$variable == "underweight"], "differs")
  expect_true(res$n_differ[res$variable == "underweight"] >= 1L)
})
