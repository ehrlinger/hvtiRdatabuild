# All identifiers and values below are invented. No PHI.

test_that("build and study derivation preserve an auditable cohort history", {
  path <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(list(
    study = "synthetic",
    cohort_table = "synthetic.cohort",
    warehouse = "synthetic_warehouse",
    view_schema = "dbo",
    pull_date = "2026-10-01",
    modules = list("base", "vitalstatus"),
    derive = list(scale_value = TRUE)
  ), path)
  config <- read_study_config(path)

  ids <- c("SYN201", "SYN202", "SYN203")
  cohort <- new_cohort_record(
    members = data.frame(
      patient_id = ids, stage_id = "selected", included = TRUE,
      reason = NA_character_, stringsAsFactors = FALSE
    ),
    stages = data.frame(
      stage_id = "selected", order = 1L, label = "Selected",
      source = "upstream", provenance = "synthetic selection",
      stringsAsFactors = FALSE
    ),
    patient_id_col = "masterid"
  )
  base <- data.frame(
    masterid = ids, base_value = c(3, 5, 8), keep = c(TRUE, FALSE, TRUE),
    stringsAsFactors = FALSE
  )
  status <- data.frame(
    masterid = ids, status_value = c("alive", "alive", "deceased"),
    stringsAsFactors = FALSE
  )
  raw <- structure(list(
    tables = list(bdbase = base, bdstat = status),
    manifest = data.frame(
      module = c("base", "vitalstatus"),
      output = c("bdbase", "bdstat"),
      n_rows = c(3L, 3L), n_cols = c(3L, 2L),
      pulled_at = as.POSIXct(rep("2026-10-01", 2L), tz = "UTC")
    )
  ), class = "pull_result")

  built <- build_dataset(raw, config, cohort)
  study_derive <- function(data, cohort, config) {
    keep <- data$keep
    if (isTRUE(config$derive[["scale_value"]])) {
      data$analysis_value <- data$base_value * 2
    }
    reason <- rep(NA_character_, length(keep))
    reason[!keep] <- "synthetic study exclusion"
    stage <- data.frame(
      stage_id = "study_eligibility",
      order = max(cohort$stages$order) + 1L,
      label = "Study eligibility",
      source = "derive",
      provenance = "synthetic study rule",
      stringsAsFactors = FALSE
    )
    outcomes <- data.frame(
      patient_id = data$masterid, included = keep, reason = reason,
      stringsAsFactors = FALSE
    )
    updated <- append_cohort_stage(cohort, stage, outcomes)
    list(data = data[keep, , drop = FALSE], cohort = updated)
  }
  result <- derive_vars(built, config, study_derive)
  summary <- cohort_summary(result$cohort)$stages

  expect_equal(nrow(result$data), 2L)
  expect_equal(ncol(result$data), 5L)
  expect_identical(result$data$analysis_value, c(6, 16))
  expect_identical(summary$n_in, c(3L, 3L, 3L))
  expect_identical(summary$n_excluded, c(0L, 0L, 1L))
  expect_identical(summary$n_remaining, c(3L, 3L, 2L))
})
