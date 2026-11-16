#' @section Quiet mode:
#' Informational messages, such as the progress lines of [snapshot_master()] and
#' [lift_master()], follow the hvtiR family option `hvti.quiet`:
#' `options(hvti.quiet = TRUE)` silences them. Warnings and errors are never
#' silenced by it. A call that finishes with work left undone warns, so quiet
#' mode cannot hide it: [snapshot_master()] when a historical snapshot fails,
#' and [backfill_corrections()] when a legacy fact is unresolved or a statement
#' unparsed.
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
## usethis namespace: end
NULL
