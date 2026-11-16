#' Identify a cohort unit by MRN and encounter date
#'
#' A cohort row is one encounter, not one patient: a patient with two operations is
#' two units. `cohort_unit_id()` joins the medical record number and the encounter date
#' into the single identifier a [new_cohort_record()] carries as `patient_id`, so the
#' cohort history works unchanged while its unit becomes the encounter. A cohort built
#' this way uses `patient_id_col = "cohort_unit"`, the column [pull_master()] adds to
#' the data it returns.
#'
#' Values are never echoed in an error.
#'
#' @param mrn Character. Medical record numbers, none missing or empty, none
#'   containing `|`.
#' @param encounter_date A `Date` vector the same length as `mrn`, none missing.
#'
#' @return A character vector of unit identifiers, `"<mrn>|<YYYY-MM-DD>"`.
#'
#' @seealso [split_cohort_unit()], [pull_master()], [cohort_query()]
#'
#' @examples
#' # Synthetic identifiers; no PHI.
#' cohort_unit_id(c("SYN101", "SYN101"), as.Date(c("2010-03-01", "2015-06-30")))
#'
#' @export
cohort_unit_id <- function(mrn, encounter_date) {
  if (!is.character(mrn) || anyNA(mrn) || any(!nzchar(mrn))) {
    stop("'mrn' must be a character vector with no missing or empty values.",
         call. = FALSE)
  }
  if (any(grepl("|", mrn, fixed = TRUE))) {
    stop("'mrn' must not contain '|', which separates the unit key.", call. = FALSE)
  }
  if (!inherits(encounter_date, "Date")) {
    stop("'encounter_date' must be a Date vector.", call. = FALSE)
  }
  if (anyNA(encounter_date)) {
    stop("'encounter_date' must have no missing values.", call. = FALSE)
  }
  if (length(mrn) != length(encounter_date)) {
    stop("'mrn' and 'encounter_date' must be the same length.", call. = FALSE)
  }
  paste(mrn, format(encounter_date, "%Y-%m-%d"), sep = "|")
}

#' Split cohort unit identifiers into MRN and encounter date
#'
#' The inverse of [cohort_unit_id()].
#'
#' @param unit Character. Identifiers made by [cohort_unit_id()].
#'
#' @return A data frame with columns `mrn` (character) and `encounter_date` (`Date`),
#'   one row per element of `unit`.
#'
#' @seealso [cohort_unit_id()]
#'
#' @examples
#' # Synthetic identifiers; no PHI.
#' split_cohort_unit(cohort_unit_id("SYN101", as.Date("2010-03-01")))
#'
#' @export
split_cohort_unit <- function(unit) {
  malformed <- "'unit' must hold identifiers made by cohort_unit_id()."
  if (!is.character(unit) || anyNA(unit)) {
    stop(malformed, call. = FALSE)
  }
  parts <- strsplit(unit, "|", fixed = TRUE)
  if (any(lengths(parts) != 2L)) {
    stop(malformed, call. = FALSE)
  }
  mrn <- vapply(parts, `[[`, character(1), 1L)
  date_text <- vapply(parts, `[[`, character(1), 2L)
  dates <- as.Date(date_text, format = "%Y-%m-%d")
  if (any(!nzchar(mrn)) || anyNA(dates) ||
        !identical(paste(mrn, format(dates, "%Y-%m-%d"), sep = "|"), unit)) {
    stop(malformed, call. = FALSE)
  }
  data.frame(mrn = mrn, encounter_date = dates, stringsAsFactors = FALSE)
}
