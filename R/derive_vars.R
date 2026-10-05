#' Apply study-specific variable derivations
#'
#' Runs committed study-specific R code after dataset assembly. The callback
#' may add analysis variables and append local exclusion stages to the cohort
#' record; it may not rewrite earlier membership decisions.
#'
#' @param build A `build_result` from [build_dataset()].
#' @param config A `study_config` from [read_study_config()].
#' @param study_derive A function with arguments `data`, `cohort`, and `config`.
#'   It returns a named list with updated `data` and `cohort` elements.
#'
#' @return An object of class `derive_result` with `data`, `cohort`, and
#'   unchanged supporting `tables` elements.
#' @export
derive_vars <- function(build, config, study_derive) {
  if (!inherits(build, "build_result") || !is.data.frame(build$data) ||
        !inherits(build$cohort, "cohort_record") || !is.list(build$tables)) {
    stop("'build' must be a build_result with data, cohort, and tables.",
         call. = FALSE)
  }
  if (!inherits(config, "study_config")) {
    stop("'config' must be a study_config from read_study_config().",
         call. = FALSE)
  }
  if (!is.function(study_derive)) {
    stop("'study_derive' must be a function.", call. = FALSE)
  }

  diagnostics <- new.env(parent = emptyenv())
  diagnostics$warning <- FALSE
  diagnostics$message <- FALSE
  callback_result <- tryCatch(
    withCallingHandlers(
      study_derive(build$data, build$cohort, config),
      warning = function(condition) {
        diagnostics$warning <- TRUE
        invokeRestart("muffleWarning")
      },
      message = function(condition) {
        diagnostics$message <- TRUE
        invokeRestart("muffleMessage")
      }
    ),
    error = function(error) {
      .report_derive_diagnostics(diagnostics)
      stop("Study derivation callback failed; error details were suppressed.",
           call. = FALSE)
    }
  )
  .report_derive_diagnostics(diagnostics)
  if (!is.list(callback_result) || is.null(names(callback_result)) ||
        anyDuplicated(names(callback_result)) ||
        !all(c("data", "cohort") %in% names(callback_result))) {
    stop("Study derivation must return a named data and cohort list.",
         call. = FALSE)
  }

  data <- callback_result$data
  if (!is.data.frame(data)) {
    stop("Study derivation data must be a data frame.", call. = FALSE)
  }
  candidate <- callback_result$cohort
  if (!inherits(candidate, "cohort_record")) {
    stop("Study derivation cohort must be a cohort_record.", call. = FALSE)
  }
  cohort <- tryCatch(
    new_cohort_record(candidate$members, candidate$stages,
                      candidate$patient_id_col),
    error = function(error) {
      stop("Study derivation returned an invalid cohort record; details were suppressed.",
           call. = FALSE)
    }
  )
  .validate_derived_cohort(build$cohort, cohort)

  id_col <- cohort$patient_id_col
  if (!id_col %in% names(data)) {
    stop("Study derivation data is missing its patient identifier column.",
         call. = FALSE)
  }
  ids <- as.character(data[[id_col]])
  if (anyNA(ids) || any(!nzchar(ids)) || anyDuplicated(ids)) {
    stop("Study derivation data must have unique, non-missing patient identifiers.",
         call. = FALSE)
  }
  last_stage <- utils::tail(cohort$stages$stage_id, 1L)
  active_ids <- cohort$members$patient_id[
    cohort$members$stage_id == last_stage & cohort$members$included
  ]
  if (!setequal(ids, active_ids)) {
    stop("Study derivation data identifiers must match the final cohort membership.",
         call. = FALSE)
  }

  structure(
    list(data = data, cohort = cohort, tables = build$tables),
    class = "derive_result"
  )
}

#' Print a derived dataset result without patient values
#'
#' @param x A `derive_result` from [derive_vars()].
#' @param ... Ignored.
#'
#' @return `x`, invisibly.
#' @export
print.derive_result <- function(x, ...) {
  cat("Derived dataset:", nrow(x$data), "row(s),", ncol(x$data), "column(s)\n")
  cat("Supporting module tables:", length(x$tables), "\n")
  print(cohort_summary(x$cohort)$stages,
        row.names = FALSE)
  invisible(x)
}

#' Safely inspect a derived dataset result
#'
#' @param object A `derive_result`.
#' @param ... Ignored.
#'
#' @return `NULL`, invisibly.
#' @export
str.derive_result <- function(object, ...) {
  cat("Structure of derive_result\n")
  print.derive_result(object, ...)
  invisible(NULL)
}

.report_derive_diagnostics <- function(diagnostics) {
  if (diagnostics$warning) {
    warning("Study derivation callback warning(s) occurred; details suppressed.",
            call. = FALSE)
  }
  if (diagnostics$message) {
    message("Study derivation callback message(s) occurred; details suppressed.")
  }
}

.validate_derived_cohort <- function(original, updated) {
  if (!identical(original$patient_id_col, updated$patient_id_col)) {
    stop("Study derivation may not change the patient identifier column.",
         call. = FALSE)
  }
  n_stages <- nrow(original$stages)
  n_members <- nrow(original$members)
  if (nrow(updated$stages) < n_stages || nrow(updated$members) < n_members ||
        !identical(updated$stages[seq_len(n_stages), , drop = FALSE],
                   original$stages) ||
        !identical(updated$members[seq_len(n_members), , drop = FALSE],
                   original$members)) {
    stop("Study derivation may append history but may not rewrite prior stages.",
         call. = FALSE)
  }
  if (nrow(updated$stages) > n_stages) {
    added <- updated$stages$source[seq.int(n_stages + 1L, nrow(updated$stages))]
    if (any(added != "derive")) {
      stop("Study derivation may append only derive stages.", call. = FALSE)
    }
  }
}
