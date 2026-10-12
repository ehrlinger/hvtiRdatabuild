#' Assemble the patient-level dataset
#'
#' Joins the patient-level base and vital-status modules while retaining
#' repeated-event modules as supporting tables. The supplied cohort history is
#' carried forward and receives a build stage after membership is verified.
#'
#' @param raw A `pull_result` from [dw_pull()].
#' @param config A `study_config` from [read_study_config()].
#' @param cohort A `cohort_record` whose latest stage identifies the selected
#'   build membership.
#'
#' @return An object of class `build_result` with `data`, `cohort`, and `tables`
#'   elements. `tables` contains unjoined repeated-event module data.
#' @examples
#' # Synthetic identifiers and values; no PHI, no warehouse connection.
#' ids <- c("SYN201", "SYN202", "SYN203")
#' cohort <- new_cohort_record(
#'   members = data.frame(
#'     patient_id = ids, stage_id = "selected", included = TRUE,
#'     reason = NA_character_
#'   ),
#'   stages = data.frame(
#'     stage_id = "selected", order = 1L, label = "Selected",
#'     source = "upstream", provenance = "synthetic selection"
#'   ),
#'   patient_id_col = "masterid"
#' )
#' path <- tempfile(fileext = ".yaml")
#' yaml::write_yaml(list(
#'   study = "synthetic", cohort_table = "synthetic.cohort",
#'   warehouse = "synthetic_warehouse", view_schema = "dbo",
#'   pull_date = "2026-10-01", modules = list("base", "vitalstatus"),
#'   derive = list(scale_value = TRUE)
#' ), path)
#' config <- read_study_config(path)
#' unlink(path)
#' raw <- structure(list(
#'   tables = list(
#'     bdbase = data.frame(masterid = ids, base_value = c(3, 5, 8),
#'                         keep = c(TRUE, FALSE, TRUE)),
#'     bdstat = data.frame(masterid = ids,
#'                         status_value = c("alive", "alive", "deceased"))
#'   ),
#'   manifest = data.frame(
#'     module = c("base", "vitalstatus"), output = c("bdbase", "bdstat"),
#'     n_rows = c(3L, 3L), n_cols = c(3L, 2L),
#'     pulled_at = as.POSIXct(rep("2026-10-01", 2L), tz = "UTC")
#'   )
#' ), class = "pull_result")
#' built <- build_dataset(raw, config, cohort)
#' built
#' @export
build_dataset <- function(raw, config, cohort) {
  if (!inherits(raw, "pull_result") || !is.list(raw$tables) ||
        !is.data.frame(raw$manifest)) {
    stop("'raw' must be a pull_result with tables and a manifest.", call. = FALSE)
  }
  if (!inherits(config, "study_config")) {
    stop("'config' must be a study_config from read_study_config().",
         call. = FALSE)
  }
  if (!inherits(cohort, "cohort_record")) {
    stop("'cohort' must be a cohort_record.", call. = FALSE)
  }

  specs <- .read_module_specs()
  unknown <- setdiff(config$modules, names(specs))
  if (length(unknown)) {
    stop("Study configuration names an unknown module.", call. = FALSE)
  }
  if (!"base" %in% config$modules) {
    stop("Study configuration must include the required 'base' module.",
         call. = FALSE)
  }
  outputs <- vapply(config$modules, function(module) {
    specs[[module]]$output
  }, character(1))
  if (anyDuplicated(outputs) ||
        !identical(names(raw$tables), unname(outputs))) {
    stop("Pulled module tables must match the configured module outputs.",
         call. = FALSE)
  }

  base_spec <- specs$base
  data <- .normalize_module_table(
    raw$tables[[base_spec$output]], base_spec$module,
    c(base_spec$join_key, cohort$patient_id_col)
  )
  base_keys <- .validate_module_key(data, base_spec$module, base_spec$join_key)
  patient_id_col <- cohort$patient_id_col
  if (!patient_id_col %in% names(data)) {
    stop("The base module is missing the cohort patient identifier column.",
         call. = FALSE)
  }
  patient_ids <- as.character(data[[patient_id_col]])
  if (anyNA(patient_ids) || any(!nzchar(patient_ids)) ||
        anyDuplicated(patient_ids)) {
    stop("The base module must contain unique, non-missing patient identifiers.",
         call. = FALSE)
  }

  active_ids <- cohort$members$patient_id[
    cohort$members$stage_id == utils::tail(cohort$stages$stage_id, 1L) &
      cohort$members$included
  ]
  if (!setequal(patient_ids, active_ids)) {
    stop("Base module rows do not match the active cohort membership.",
         call. = FALSE)
  }

  support_modules <- setdiff(config$modules, c("base", "vitalstatus"))
  tables <- raw$tables[setdiff(outputs, base_spec$output)]
  for (module in support_modules) {
    spec <- specs[[module]]
    .validate_module_key(raw$tables[[spec$output]], spec$module, spec$join_key,
                         unique = FALSE)
  }
  if ("vitalstatus" %in% config$modules) {
    status_spec <- specs$vitalstatus
    status <- .normalize_module_table(
      raw$tables[[status_spec$output]], status_spec$module,
      c(status_spec$join_key, patient_id_col)
    )
    status_keys <- .validate_module_key(
      status, status_spec$module, status_spec$join_key
    )
    if (!setequal(base_keys, status_keys)) {
      stop("The vitalstatus module does not cover the base patient keys.",
           call. = FALSE)
    }
    data <- dplyr::left_join(
      data,
      status,
      by = status_spec$join_key,
      suffix = c("", ".bdstat")
    )
    data <- as.data.frame(data)
    tables[[status_spec$output]] <- NULL
  }

  stage <- data.frame(
    stage_id = "build",
    order = max(cohort$stages$order) + 1,
    label = "Patient-level build",
    source = "build",
    provenance = "hvtiRdatabuild::build_dataset",
    stringsAsFactors = FALSE
  )
  outcomes <- data.frame(
    patient_id = active_ids,
    included = rep(TRUE, length(active_ids)),
    reason = rep(NA_character_, length(active_ids)),
    stringsAsFactors = FALSE
  )
  cohort <- append_cohort_stage(cohort, stage, outcomes)

  structure(
    list(data = data, cohort = cohort, tables = tables),
    class = "build_result"
  )
}

#' Print a built dataset result without patient values
#'
#' @param x A `build_result` from [build_dataset()].
#' @param ... Ignored.
#'
#' @return `x`, invisibly.
#' @export
print.build_result <- function(x, ...) {
  cat("Built dataset:", nrow(x$data), "row(s),", ncol(x$data), "column(s)\n")
  cat("Supporting module tables:", length(x$tables), "\n")
  print(cohort_summary(x$cohort)$stages,
        row.names = FALSE)
  invisible(x)
}

#' Safely inspect a built dataset result
#'
#' @param object A `build_result`.
#' @param ... Ignored.
#'
#' @return `NULL`, invisibly.
#' @export
str.build_result <- function(object, ...) {
  cat("Structure of build_result\n")
  print.build_result(object, ...)
  invisible(NULL)
}

.validate_module_key <- function(data, module, key, unique = TRUE) {
  if (!is.data.frame(data)) {
    stop("Module '", module, "' did not return a data frame.", call. = FALSE)
  }
  if (!key %in% names(data)) {
    stop("Module '", module, "' is missing its declared join key.",
         call. = FALSE)
  }
  .check_duplicate_ids(data, module, key)
  values <- data[[key]]
  if (!is.atomic(values) || anyNA(values)) {
    stop("Module '", module, "' has missing or invalid join-key values.",
         call. = FALSE)
  }
  values <- as.character(values)
  if (any(!nzchar(values))) {
    stop("Module '", module, "' has missing or invalid join-key values.",
         call. = FALSE)
  }
  if (unique && anyDuplicated(values)) {
    stop("Module '", module, "' must have unique values for its patient join key.",
         call. = FALSE)
  }
  values
}

.normalize_module_table <- function(data, module, identifier_columns) {
  if (!is.data.frame(data)) {
    stop("Module '", module, "' did not return a data frame.", call. = FALSE)
  }
  .check_duplicate_ids(data, module, identifier_columns)
  names(data) <- make.unique(names(data), sep = ".dup")
  data
}

.check_duplicate_ids <- function(data, module, columns) {
  for (column in unique(columns)) {
    positions <- which(names(data) == column)
    if (length(positions) > 1L) {
      first <- data[[positions[1L]]]
      matches <- vapply(positions[-1L], function(i) {
        isTRUE(all.equal(first, data[[i]], check.attributes = FALSE))
      }, logical(1))
      if (!all(matches)) {
        stop("Module '", module,
             "' contains conflicting copies of an identifier column.",
             call. = FALSE)
      }
    }
  }
  invisible(NULL)
}
