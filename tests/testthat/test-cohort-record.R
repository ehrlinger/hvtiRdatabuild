# Cohort IDs and values below are invented. No PHI.

.cohort_fixture <- function() {
  stages <- data.frame(
    stage_id = c("selected", "assembled", "eligible"),
    order = 1:3,
    label = c("Selected", "Assembled", "Eligible"),
    source = c("upstream", "build", "derive"),
    provenance = c("synthetic selection", "synthetic build", "synthetic rules"),
    stringsAsFactors = FALSE
  )
  members <- data.frame(
    patient_id = c("SYN001", "SYN002", "SYN001", "SYN002", "SYN001"),
    stage_id = c("selected", "selected", "assembled", "assembled", "eligible"),
    included = c(TRUE, TRUE, TRUE, FALSE, TRUE),
    reason = c(NA, NA, NA, "synthetic exclusion", NA),
    stringsAsFactors = FALSE
  )
  new_cohort_record(members, stages, "patient_id")
}

test_that("a valid ordered cohort record summarizes attrition", {
  record <- .cohort_fixture()
  summary <- cohort_summary(record)

  expect_s3_class(record, "cohort_record")
  expect_identical(summary$stages$n_in, c(2L, 2L, 1L))
  expect_identical(summary$stages$n_excluded, c(0L, 1L, 0L))
  expect_identical(summary$stages$n_remaining, c(2L, 1L, 1L))
  expect_identical(summary$reasons$n_excluded, 1L)
})

test_that("duplicate patient rows fail without echoing identifiers", {
  record <- .cohort_fixture()
  members <- rbind(record$members, record$members[1, ])

  err <- tryCatch(
    new_cohort_record(members, record$stages, "patient_id"),
    error = identity
  )
  expect_s3_class(err, "error")
  expect_match(conditionMessage(err), "Duplicate patient")
  expect_false(grepl("SYN001", conditionMessage(err), fixed = TRUE))
})

test_that("unknown stages and invalid inclusion outcomes fail", {
  record <- .cohort_fixture()
  unknown <- record$members
  unknown$stage_id[1] <- "missing-stage"
  expect_error(new_cohort_record(unknown, record$stages, "patient_id"),
               "unknown stage")

  missing_outcome <- record$members
  missing_outcome$included[1] <- NA
  expect_error(new_cohort_record(missing_outcome, record$stages, "patient_id"),
               "included.*missing")
})

test_that("rejected patients cannot reappear at later stages", {
  record <- .cohort_fixture()
  members <- record$members
  members <- rbind(members, data.frame(
    patient_id = "SYN002", stage_id = "eligible", included = TRUE,
    reason = NA_character_, stringsAsFactors = FALSE
  ))

  expect_error(new_cohort_record(members, record$stages, "patient_id"),
               "inactive patient")
})

test_that("stage append requires one outcome for each active patient", {
  record <- .cohort_fixture()
  stage <- data.frame(
    stage_id = "final", order = 4L, label = "Final", source = "derive",
    provenance = "synthetic final rule", stringsAsFactors = FALSE
  )
  outcomes <- data.frame(
    patient_id = character(), included = logical(), reason = character(),
    stringsAsFactors = FALSE
  )

  expect_error(append_cohort_stage(record, stage, outcomes), "every active patient")
})

test_that("record printing omits patient identifiers", {
  printed <- paste(capture.output(print(.cohort_fixture())), collapse = "\n")

  expect_match(printed, "Cohort record")
  expect_match(printed, "Selected")
  expect_false(grepl("SYN00", printed, fixed = TRUE))
})

test_that("stage metadata must have strictly increasing order", {
  record <- .cohort_fixture()
  stages <- record$stages
  stages$order[3] <- stages$order[2]

  expect_error(new_cohort_record(record$members, stages, "patient_id"),
               "strictly increasing")
})

test_that("included and excluded outcomes have consistent reasons", {
  record <- .cohort_fixture()
  members <- record$members
  members$reason[1] <- "unexpected reason"
  expect_error(new_cohort_record(members, record$stages, "patient_id"),
               "Included outcomes require")

  members <- record$members
  members$reason[4] <- NA_character_
  expect_error(new_cohort_record(members, record$stages, "patient_id"),
               "excluded outcomes need one")
})

test_that("stage append records a complete active-patient outcome", {
  record <- .cohort_fixture()
  stage <- data.frame(
    stage_id = "final", order = 4L, label = "Final", source = "derive",
    provenance = "synthetic final rule", stringsAsFactors = FALSE
  )
  outcomes <- data.frame(
    patient_id = "SYN001", included = FALSE, reason = "synthetic final exclusion",
    stringsAsFactors = FALSE
  )
  updated <- append_cohort_stage(record, stage, outcomes)

  expect_identical(tail(updated$stages$stage_id, 1L), "final")
  expect_identical(tail(updated$members$patient_id, 1L), "SYN001")
  expect_identical(tail(updated$members$included, 1L), FALSE)
})

test_that("a cohort history must contain an initial stage", {
  members <- data.frame(
    patient_id = character(), stage_id = character(), included = logical(),
    reason = character(), stringsAsFactors = FALSE
  )
  stages <- data.frame(
    stage_id = character(), order = numeric(), label = character(),
    source = character(), provenance = character(), stringsAsFactors = FALSE
  )

  expect_error(new_cohort_record(members, stages, "patient_id"),
               "at least one stage")
})
