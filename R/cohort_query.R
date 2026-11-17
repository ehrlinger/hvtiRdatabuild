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
#' Criteria are evaluated in the warehouse, in the pull's transaction; see [criterion()].
#'
#' @param qualifying Character. A SQL boolean expression over the master's columns, for
#'   example `"proc = 'CABG'"`.
#' @param epoch A `Date` vector of length two: first and last encounter date, inclusive.
#' @param index `"first"` or `"all"`.
#' @param prior `"keep"` or `"exclude"`, for units with a qualifying encounter before
#'   the epoch.
#' @param criteria A list of criteria from [criterion()], [local_criterion()] and
#'   [review_criterion()], in the order they run: warehouse criteria, then local, then
#'   review. Each becomes a counted cohort stage; see [criterion()].
#' @param index_on With `index = "first"` and criteria, which encounter is the index:
#'   `"qualifying"` takes each patient's first qualifying encounter and then applies the
#'   criteria, so a patient excluded there is out; `"eligible"` applies the criteria to
#'   every qualifying encounter and takes each patient's first that survives. The two give
#'   different cohorts, so there is no default. Leave `NULL` otherwise.
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
                         prior = c("keep", "exclude"), criteria = list(),
                         index_on = NULL) {
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
  if (!is.list(criteria) || inherits(criteria, "cohort_criterion") ||
        !all(vapply(criteria, inherits, logical(1), "cohort_criterion"))) {
    .abort("criterion_argument", "cohort_query(): `criteria` must be a list of criteria ",
           "from criterion(), local_criterion() or review_criterion().")
  }
  ids <- vapply(criteria, `[[`, character(1), "id")
  if (anyDuplicated(ids)) {
    .abort("criterion_argument", "cohort_query(): criterion ids must be unique.")
  }
  rank <- match(vapply(criteria, `[[`, character(1), "kind"),
                c("warehouse", "local", "review"))
  if (is.unsorted(rank)) {
    .abort("criterion_argument", "cohort_query(): declare warehouse criteria first, then ",
           "local, then review; that is the order they run in.")
  }
  if (length(criteria) && identical(index, "first")) {
    if (is.null(index_on)) .required("cohort_query", "index_on")
    index_on <- .check_choice("cohort_query", "index_on", index_on,
                              c("qualifying", "eligible"))
  } else if (!is.null(index_on)) {
    .abort("criterion_argument", "cohort_query(): `index_on` applies only with ",
           "index = \"first\" and criteria.")
  }
  structure(list(qualifying = qualifying, epoch = epoch, index = index, prior = prior,
                 criteria = criteria, index_on = index_on),
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
  if (length(x$criteria)) {
    if (!is.null(x$index_on)) cat("  index on: ", x$index_on, "\n", sep = "")
    for (cr in x$criteria) cat("  ", .describe_criterion(cr), "\n", sep = "")
  }
  invisible(x)
}
