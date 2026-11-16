#' Build a study dataset from a master pull
#'
#' The master-view counterpart of [build_dataset()]. A master is already one wide row per
#' encounter, so there are no modules to join: the pulled rows are the built dataset.
#' `build_from_master()` checks they match the cohort's active units exactly and records
#' the build as a cohort stage, returning the same `build_result` shape that
#' [derive_vars()] consumes.
#'
#' @param pull A `master_pull` from [pull_master()].
#'
#' @return A `build_result`: a list with `data`, `cohort` (ending with a `build` stage)
#'   and `tables` (empty).
#'
#' @seealso [pull_master()], [derive_vars()], [build_dataset()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   # Synthetic data; no PHI.
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   DBI::dbWriteTable(con, "master_demo", data.frame(
#'     mrn = "SYN101", encounter_date = as.Date("2010-03-01"), proc = "CABG", age = 62
#'   ))
#'   DBI::dbWriteTable(con, "master_demo_corrections_applied", data.frame(
#'     correction_id = character(), mrn = character(), encounter_date = as.Date(character())
#'   ))
#'   DBI::dbWriteTable(con, "master_demo_deployment", data.frame(sql_commit = "abc1234"))
#'   DBI::dbWriteTable(con, "master_demo_parity", data.frame(
#'     sql_commit = "abc1234", verdict = "pass", verified_at = Sys.time()
#'   ))
#'   config <- tempfile(fileext = ".yaml")
#'   writeLines("study: st0000", config)
#'   q <- cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")))
#'   pull <- pull_master(con, "master_demo", q, columns = "age", study_config = config,
#'                       dialect = "duckdb")
#'   build_from_master(pull)
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#' }
#' }
#'
#' @export
build_from_master <- function(pull) {
  if (!inherits(pull, "master_pull")) {
    stop("'pull' must be a master_pull from pull_master().", call. = FALSE)
  }
  cohort <- pull$cohort
  last <- utils::tail(cohort$stages$stage_id[order(cohort$stages$order)], 1L)
  active <- cohort$members$patient_id[cohort$members$stage_id == last &
                                        cohort$members$included]
  units <- pull$data$cohort_unit
  if (is.null(units) || anyNA(units) || anyDuplicated(units) ||
        !setequal(units, active)) {
    stop("The pulled rows do not match the active cohort membership.", call. = FALSE)
  }
  cohort <- append_cohort_stage(
    cohort,
    data.frame(stage_id = "build", order = max(cohort$stages$order) + 1L,
               label = "Encounter-level build", source = "build",
               provenance = "hvtiRdatabuild::build_from_master", stringsAsFactors = FALSE),
    data.frame(patient_id = active, included = TRUE, reason = NA_character_,
               stringsAsFactors = FALSE)
  )
  structure(list(data = pull$data, cohort = cohort, tables = list()),
            class = "build_result")
}
