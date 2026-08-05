test_that(".cmp_class collapses storage variants to comparison classes", {
  expect_equal(.cmp_class(1.5), "numeric")
  expect_equal(.cmp_class(1L), "numeric")
  expect_equal(.cmp_class(haven::labelled(c(1, 2), c(a = 1))), "numeric")
  expect_equal(.cmp_class("a"), "character")
  expect_equal(.cmp_class(as.Date("2020-01-01")), "date")
  expect_equal(.cmp_class(factor("a")), "factor")
  expect_equal(.cmp_class(TRUE), "logical")
})

test_that(".compare_vector treats matched NA as equal", {
  r <- .compare_vector(c(1, NA), c(1, NA), tolerance = 1e-8)
  expect_equal(r$verdict, "identical")
  expect_equal(r$n_differ, 0L)
})

test_that(".compare_vector treats unmatched NA as a difference", {
  r <- .compare_vector(c(1, NA), c(1, 2), tolerance = 1e-8)
  expect_equal(r$verdict, "differs")
  expect_equal(r$n_differ, 1L)
})

test_that(".compare_vector honours tolerance", {
  within <- .compare_vector(c(1, 2), c(1, 2 + 1e-10), tolerance = 1e-8)
  expect_equal(within$verdict, "within_tolerance")
  expect_true(within$max_abs_diff > 0)

  beyond <- .compare_vector(c(1, 2), c(1, 2.5), tolerance = 1e-8)
  expect_equal(beyond$verdict, "differs")
  expect_equal(beyond$max_abs_diff, 0.5)
})

test_that(".compare_vector ignores trailing blanks, as SAS does", {
  r <- .compare_vector(c("Smith", "Jones "), c("Smith", "Jones"),
                       tolerance = 1e-8)
  expect_equal(r$verdict, "identical")
})

test_that('.compare_vector treats SAS empty-string as character NA', {
  # SAS has no character missing value distinct from "". A missing character
  # in the oracle reads back as ""; the R pipeline produces NA. Reporting that
  # as a difference would be a false positive on every character column that
  # has any missing value.
  sas <- c("Smith", "")
  r   <- c("Smith", NA_character_)
  expect_equal(.compare_vector(sas, r, tolerance = 1e-8)$verdict, "identical")

  # Whitespace-only is also missing, once trimmed.
  expect_equal(
    .compare_vector(c("Smith", "   "), r, tolerance = 1e-8)$verdict,
    "identical"
  )

  # A genuine value difference is still caught.
  differs <- .compare_vector(c("Smith", "Jones"), r, tolerance = 1e-8)
  expect_equal(differs$verdict, "differs")
  expect_equal(differs$n_differ, 1L)
})

test_that(".compare_vector compares dates by value, not representation", {
  a <- as.Date(c("2020-01-15", NA))
  b <- as.Date(c("2020-01-15", NA))
  expect_equal(.compare_vector(a, b, tolerance = 1e-8)$verdict, "identical")
})

test_that(".compare_vector does not truncate datetimes to dates", {
  # haven returns POSIXct for SAS DATETIME variables (dtn_disc, dtn_inst...).
  # Folding those to Date would silently pass any within-day difference.
  a <- as.POSIXct("2020-01-15 08:00:00", tz = "UTC")
  b <- as.POSIXct("2020-01-15 23:59:00", tz = "UTC")

  expect_equal(.cmp_class(a), "datetime")

  r <- .compare_vector(a, b, tolerance = 1e-8)
  expect_equal(r$verdict, "differs")
  expect_equal(r$n_differ, 1L)
  expect_true(r$max_abs_diff > 0)

  # Equal datetimes still agree.
  expect_equal(.compare_vector(a, a, tolerance = 1e-8)$verdict, "identical")

  # A Date and a POSIXct are different types, not silently equal.
  expect_equal(.cmp_class(as.Date("2020-01-15")), "date")
})

test_that(".compare_vector handles infinities without warning", {
  # Inf - Inf is NaN; equal values must still differ by zero.
  expect_silent(r <- .compare_vector(c(Inf, 1), c(Inf, 1), tolerance = 1e-8))
  expect_equal(r$verdict, "identical")
  expect_equal(r$max_abs_diff, 0)
  expect_equal(r$max_rel_diff, 0)

  expect_silent(neg <- .compare_vector(-Inf, -Inf, tolerance = 1e-8))
  expect_equal(neg$verdict, "identical")
  expect_equal(neg$max_abs_diff, 0)

  # Opposite infinities are a real difference.
  expect_equal(.compare_vector(Inf, -Inf, tolerance = 1e-8)$verdict, "differs")

  # An infinity against a finite value is a real difference.
  differs <- .compare_vector(Inf, 5, tolerance = 1e-8)
  expect_equal(differs$verdict, "differs")
  expect_equal(differs$n_differ, 1L)
})

test_that(".compare_vector folds NaN into missing, as SAS does", {
  # SAS has one missing value and no NaN: 0/0 and log(-1) both land there.
  expect_equal(.compare_vector(NaN, NA_real_, tolerance = 1e-8)$verdict,
               "identical")
  expect_equal(.compare_vector(NaN, NaN, tolerance = 1e-8)$verdict,
               "identical")
  # But NaN against a real value still differs.
  expect_equal(.compare_vector(NaN, 5, tolerance = 1e-8)$verdict, "differs")
})
