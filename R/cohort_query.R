#' Define a cohort by a query on a master view
#'
#' A definition only: nothing is read until [pull_master()] runs it, inside the same
#' transaction as the pull, so the cohort and its data describe one state of the
#' warehouse.
#'
#' The cohort is every encounter in the master that meets `qualifying` and falls inside
#' `epoch`. `index` sets the study's unit: `"first"` keeps each patient's earliest
#' qualifying encounter in the epoch (one row per patient; later encounters remain
#' follow-up events), and `"all"` keeps every qualifying encounter in the epoch.
#'
#' A patient whose qualifying encounter in the epoch was preceded by one **before** the
#' epoch is a redo, not a first. Those units are always recorded as a cohort stage,
#' `prior_qualifying`: `prior = "keep"` keeps them, `prior = "exclude"` drops them with a
#' reason. Nothing is dropped silently. The earlier encounter is detected in the database;
#' its date never leaves it.
#'
#' `qualifying` is SQL written by the study programmer and run as a `WHERE` condition on
#' the master. It must never be built from data.
#'
#' @param qualifying Character. A SQL boolean expression over the master's columns, for
#'   example `"proc = 'CABG'"`.
#' @param epoch A `Date` vector of length two: first and last encounter date, inclusive.
#' @param index `"first"` or `"all"`.
#' @param prior `"keep"` or `"exclude"`, for units with a qualifying encounter before
#'   the epoch.
#'
#' @return An object of class `cohort_query`.
#'
#' @seealso [pull_master()]
#'
#' @examples
#' cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")))
#'
#' @export
cohort_query <- function(qualifying, epoch, index = c("first", "all"),
                         prior = c("keep", "exclude")) {
  index <- match.arg(index)
  prior <- match.arg(prior)
  if (!is.character(qualifying) || length(qualifying) != 1L || is.na(qualifying) ||
        !nzchar(trimws(qualifying))) {
    stop("'qualifying' must be one non-empty SQL condition.", call. = FALSE)
  }
  if (!inherits(epoch, "Date") || length(epoch) != 2L || anyNA(epoch)) {
    stop("'epoch' must be two Dates: the first and last encounter date.", call. = FALSE)
  }
  if (epoch[[1]] > epoch[[2]]) {
    stop("'epoch' must give its start before its end.", call. = FALSE)
  }
  structure(list(qualifying = qualifying, epoch = epoch, index = index, prior = prior),
            class = "cohort_query")
}

#' Print a cohort query
#'
#' @param x A `cohort_query` from [cohort_query()].
#' @param ... Ignored.
#'
#' @return `x`, invisibly.
#'
#' @export
print.cohort_query <- function(x, ...) {
  cat("Cohort query: ", x$qualifying, "\n", sep = "")
  cat("  epoch ", format(x$epoch[[1]]), " to ", format(x$epoch[[2]]), "; index ",
      x$index, "; earlier qualifying encounter: ", x$prior, "\n", sep = "")
  invisible(x)
}
