deprecated_calls <- list(
  backfill_corrections = function() backfill_corrections(config = NULL, con = NULL),
  propose_correction = function() {
    propose_correction(
      config = NULL, con = NULL, key_values = list(), variable = "x",
      expected_prior = NA, new_value = 1, evidence_type = "chart_review",
      evidence_ref = "invented", asserted_by = "tester"
    )
  },
  decide_correction = function() {
    decide_correction(
      config = NULL, con = NULL, correction_id = "invented",
      decision = "accept", decided_by = "tester"
    )
  }
)

test_that("each corrections export warns that it is deprecated", {
  withr::local_options(hvtiRdatabuild.warn_deprecated_corrections = TRUE)
  for (fn in names(deprecated_calls)) {
    expect_warning(
      try(deprecated_calls[[fn]](), silent = TRUE),
      regexp = paste0("'", fn, "\\(\\)' is deprecated"),
      class = "deprecatedWarning"
    )
  }
})

test_that("the deprecation warning points at the registry and the issue", {
  withr::local_options(hvtiRdatabuild.warn_deprecated_corrections = TRUE)
  w <- tryCatch(deprecated_calls$propose_correction(), warning = function(w) w)
  expect_s3_class(w, "deprecatedWarning")
  expect_match(conditionMessage(w), "HVTR registry")
  expect_match(conditionMessage(w), "issues/101", fixed = TRUE)
})

test_that("the option silences the deprecation warning", {
  withr::local_options(hvtiRdatabuild.warn_deprecated_corrections = FALSE)
  for (fn in names(deprecated_calls)) {
    w <- tryCatch(
      try(deprecated_calls[[fn]](), silent = TRUE),
      deprecatedWarning = function(w) w
    )
    expect_false(inherits(w, "deprecatedWarning"))
  }
})
