#' Create an ordered cohort history
#'
#' A cohort record stores each patient's outcome at every stage they entered.
#' Patients excluded at a stage do not appear in later stages. Summaries are
#' derived from these outcomes, so stage counts cannot drift from membership.
#'
#' @param members A data frame with `patient_id`, `stage_id`, `included`, and
#'   `reason` columns. Identifiers are runtime data and are never printed.
#' @param stages A data frame with `stage_id`, `order`, `label`, `source`, and
#'   `provenance` columns, ordered by `order`.
#' @param patient_id_col Name of the patient identifier column in associated
#'   patient-level data.
#'
#' @return An object of class `cohort_record` with `members`, `stages`, and
#'   `patient_id_col` elements.
#' @export
new_cohort_record <- function(members, stages, patient_id_col) {
  .validate_cohort_tables(members, stages)
  if (nrow(stages) == 0L) {
    stop("A cohort history must contain at least one stage.", call. = FALSE)
  }

  if (!is.character(patient_id_col) || length(patient_id_col) != 1L ||
        is.na(patient_id_col) || !nzchar(patient_id_col)) {
    stop("'patient_id_col' must be one non-empty column name.", call. = FALSE)
  }

  stage_ids <- stages$stage_id
  if (nrow(members) && any(!members$stage_id %in% stage_ids)) {
    stop("'members' contains an unknown stage reference.", call. = FALSE)
  }

  if (anyDuplicated(members[c("stage_id", "patient_id")])) {
    stop("Duplicate patient-stage rows are not allowed.", call. = FALSE)
  }

  .validate_cohort_outcomes(members)
  .validate_cohort_sequence(members, stages)

  member_data <- members[c("patient_id", "stage_id", "included", "reason")]
  stage_data <- stages[c("stage_id", "order", "label", "source", "provenance")]
  row.names(member_data) <- NULL
  row.names(stage_data) <- NULL
  structure(
    list(members = member_data, stages = stage_data,
         patient_id_col = patient_id_col),
    class = "cohort_record"
  )
}

#' Append an outcome stage to a cohort history
#'
#' @param cohort A `cohort_record` created by [new_cohort_record()].
#' @param stage A one-row data frame with the `stages` schema.
#' @param outcomes A data frame with one `patient_id`, `included`, and `reason`
#'   outcome for every patient active at the preceding stage.
#'
#' @return An updated object of class `cohort_record`.
#' @export
append_cohort_stage <- function(cohort, stage, outcomes) {
  if (!inherits(cohort, "cohort_record")) {
    stop("'cohort' must be a cohort_record.", call. = FALSE)
  }
  .validate_cohort_tables(outcomes, stage, outcomes_only = TRUE)
  if (nrow(stage) != 1L) {
    stop("'stage' must contain exactly one row.", call. = FALSE)
  }
  if (stage$order <= max(cohort$stages$order)) {
    stop("The appended stage order must follow all existing stages.",
         call. = FALSE)
  }

  active <- cohort$members$patient_id[
    cohort$members$stage_id == utils::tail(cohort$stages$stage_id, 1L) &
      cohort$members$included
  ]
  .validate_cohort_outcomes(outcomes)
  if (anyDuplicated(outcomes$patient_id) ||
        !setequal(outcomes$patient_id, active)) {
    stop("Stage outcomes must contain exactly one row for every active patient.",
         call. = FALSE)
  }

  members <- rbind(
    cohort$members,
    data.frame(
      patient_id = outcomes$patient_id,
      stage_id = rep(stage$stage_id, nrow(outcomes)),
      included = outcomes$included,
      reason = outcomes$reason,
      stringsAsFactors = FALSE
    )
  )
  stages <- rbind(cohort$stages, stage)
  new_cohort_record(members, stages, cohort$patient_id_col)
}

#' Summarize cohort attrition without patient identifiers
#'
#' @param cohort A `cohort_record`.
#'
#' @return A list with `stages` (stage counts) and `reasons` (exclusion counts)
#'   data frames. Neither table contains patient identifiers.
#' @export
cohort_summary <- function(cohort) {
  if (!inherits(cohort, "cohort_record")) {
    stop("'cohort' must be a cohort_record.", call. = FALSE)
  }

  keys <- cohort$stages$stage_id
  counts <- lapply(keys, function(key) {
    rows <- cohort$members[cohort$members$stage_id == key, , drop = FALSE]
    c(n_in = nrow(rows), n_excluded = sum(!rows$included),
      n_remaining = sum(rows$included))
  })
  stage_summary <- data.frame(
    stage_id = keys,
    label = cohort$stages$label,
    do.call(rbind, counts),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
  stage_summary[c("n_in", "n_excluded", "n_remaining")] <- lapply(
    stage_summary[c("n_in", "n_excluded", "n_remaining")], as.integer
  )

  excluded <- cohort$members[!cohort$members$included, , drop = FALSE]
  if (nrow(excluded)) {
    reason_keys <- unique(excluded[c("stage_id", "reason")])
    row.names(reason_keys) <- NULL
    reason_keys$n_excluded <- vapply(seq_len(nrow(reason_keys)), function(i) {
      sum(excluded$stage_id == reason_keys$stage_id[i] &
            excluded$reason == reason_keys$reason[i])
    }, integer(1))
    reason_summary <- reason_keys
  } else {
    reason_summary <- data.frame(
      stage_id = character(), reason = character(), n_excluded = integer(),
      stringsAsFactors = FALSE
    )
  }

  list(stages = stage_summary, reasons = reason_summary)
}

#' @export
print.cohort_record <- function(x, ...) {
  summary <- cohort_summary(x)
  cat("Cohort record:", nrow(x$stages), "stage(s),",
      nrow(x$members), "patient-stage outcome(s)\n")
  print(summary$stages[c("label", "n_in", "n_excluded", "n_remaining")],
        row.names = FALSE)
  invisible(x)
}

#' Safely inspect a cohort record
#'
#' @param object A `cohort_record`.
#' @param ... Ignored.
#'
#' @return `NULL`, invisibly.
#' @export
str.cohort_record <- function(object, ...) {
  cat("Structure of cohort_record\n")
  print.cohort_record(object, ...)
  invisible(NULL)
}

.validate_cohort_tables <- function(members, stages, outcomes_only = FALSE) {
  if (!is.data.frame(members) || !is.data.frame(stages)) {
    stop("'members' and 'stages' must be data frames.", call. = FALSE)
  }
  member_fields <- if (outcomes_only) {
    c("patient_id", "included", "reason")
  } else {
    c("patient_id", "stage_id", "included", "reason")
  }
  stage_fields <- c("stage_id", "order", "label", "source", "provenance")
  if (!setequal(names(members), member_fields)) {
    stop("'members' must have the documented cohort outcome columns.",
         call. = FALSE)
  }
  if (!setequal(names(stages), stage_fields)) {
    stop("'stages' must have the documented stage metadata columns.",
         call. = FALSE)
  }
  if (!is.character(stages$stage_id) || anyNA(stages$stage_id) ||
        any(!nzchar(stages$stage_id)) || anyDuplicated(stages$stage_id)) {
    stop("Stage identifiers must be unique, non-empty strings.", call. = FALSE)
  }
  if (!is.numeric(stages$order) || anyNA(stages$order) ||
        any(!is.finite(stages$order)) || any(stages$order <= 0) ||
        anyDuplicated(stages$order) || is.unsorted(stages$order, strictly = TRUE)) {
    stop("Stage order must be positive, unique, and strictly increasing.",
         call. = FALSE)
  }
  for (field in c("label", "source", "provenance")) {
    value <- stages[[field]]
    if (!is.character(value) || anyNA(value) || any(!nzchar(value))) {
      stop("Stage labels, sources, and provenance must be non-empty strings.",
           call. = FALSE)
    }
  }
  if (any(!stages$source %in% c("upstream", "build", "derive"))) {
    stop("Stage source must be upstream, build, or derive.", call. = FALSE)
  }

  if (!is.character(members$patient_id) || anyNA(members$patient_id) ||
        any(!nzchar(members$patient_id))) {
    stop("Patient identifiers must be non-empty character values.", call. = FALSE)
  }
  if (!outcomes_only &&
        (!is.character(members$stage_id) || anyNA(members$stage_id) ||
           any(!nzchar(members$stage_id)))) {
    stop("Member stage identifiers must be non-empty character values.",
         call. = FALSE)
  }
}

.validate_cohort_outcomes <- function(members) {
  if (!is.logical(members$included) || anyNA(members$included)) {
    stop("'included' outcomes must be non-missing logical values.",
         call. = FALSE)
  }
  if (!is.character(members$reason)) {
    stop("'reason' outcomes must be character values.", call. = FALSE)
  }
  if (any(members$included & !is.na(members$reason)) ||
        any(!members$included & (is.na(members$reason) | !nzchar(members$reason)))) {
    stop("Included outcomes require a missing reason; excluded outcomes need one.",
         call. = FALSE)
  }
}

.validate_cohort_sequence <- function(members, stages) {
  if (nrow(stages) < 2L) {
    return(invisible(NULL))
  }
  for (i in 2:nrow(stages)) {
    prior <- members$patient_id[
      members$stage_id == stages$stage_id[i - 1L] & members$included
    ]
    current <- members$patient_id[members$stage_id == stages$stage_id[i]]
    if (any(!current %in% prior)) {
      stop("An inactive patient cannot reappear at a later stage.",
           call. = FALSE)
    }
    if (any(!prior %in% current)) {
      stop("Each stage must contain exactly one outcome for every active patient.",
           call. = FALSE)
    }
  }
  invisible(NULL)
}
