# No PHI: identifiers and values are invented.

test_that("a patient with two encounters is two units", {
  units <- cohort_unit_id(c("SYN101", "SYN101"),
                          as.Date(c("2010-03-01", "2015-06-30")))
  expect_identical(units, c("SYN101|2010-03-01", "SYN101|2015-06-30"))
  expect_false(anyDuplicated(units) > 0L)
})

test_that("units split back into MRN and encounter date", {
  key <- split_cohort_unit(cohort_unit_id("SYN101", as.Date("2010-03-01")))
  expect_identical(key$mrn, "SYN101")
  expect_identical(key$encounter_date, as.Date("2010-03-01"))
})

test_that("an incomplete key is refused without echoing it", {
  expect_error(cohort_unit_id("SYN101", as.Date(NA)), "no missing values")
  expect_error(cohort_unit_id(NA_character_, as.Date("2010-03-01")), "no missing")
  expect_error(cohort_unit_id("SYN|101", as.Date("2010-03-01")), "must not contain")
  expect_error(cohort_unit_id("SYN101", "2010-03-01"), "Date vector")
  expect_error(cohort_unit_id(c("SYN101", "SYN102"), as.Date("2010-03-01")), "same length")
  err <- tryCatch(cohort_unit_id("SYN|101", as.Date("2010-03-01")),
                  error = conditionMessage)
  expect_false(grepl("SYN", err, fixed = TRUE))
})

test_that("a malformed unit is refused", {
  expect_error(split_cohort_unit("SYN101"), "cohort_unit_id")
  expect_error(split_cohort_unit("SYN101|not-a-date"), "cohort_unit_id")
  expect_error(split_cohort_unit(1), "cohort_unit_id")
})

test_that("a unit cohort_unit_id() cannot produce is refused", {
  expect_error(split_cohort_unit("|2010-03-01"), "cohort_unit_id")
  expect_error(split_cohort_unit("SYN101|2010-03-01|"), "cohort_unit_id")
})
