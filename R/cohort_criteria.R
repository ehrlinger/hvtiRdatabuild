# cohort_criteria.R
#
# Inclusion and exclusion criteria for a cohort_query(). A criterion is a stage (id,
# label, role, undetermined route) around a test (a master row, rows of a view in a
# window, or a combination). Spec: dev/specs/2026-11-16-cohort-criteria-addendum.md.
# The package sets no clinical default: every clinical choice is a required argument.

.reserved_stage_ids <- c("qualifying", "prior_qualifying", "in_master", "index_eligible",
                         "review_undetermined", "build")

.one_string <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
}

.required <- function(fn, arg) {
  .abort("criterion_argument", fn, "(): `", arg, "` is required. The package sets no ",
         "default; the study declares it.")
}

.check_string <- function(fn, arg, x) {
  if (!.one_string(x)) {
    .abort("criterion_argument", fn, "(): `", arg, "` must be one non-empty string.")
  }
  x
}

.check_choice <- function(fn, arg, x, choices) {
  if (!.one_string(x) || !x %in% choices) {
    .abort("criterion_argument", fn, "(): `", arg, "` must be one of ",
           paste0("\"", choices, "\"", collapse = ", "), ".")
  }
  x
}

.check_stage_id <- function(fn, id) {
  if (!.one_string(id) || !grepl("^[A-Za-z][A-Za-z0-9_]*$", id)) {
    .abort("criterion_argument", fn, "(): `id` must start with a letter and use only ",
           "letters, digits and underscores.")
  }
  if (id %in% .reserved_stage_ids) {
    .abort("criterion_argument", fn, "(): `id` \"", id, "\" is a stage the package uses ",
           "itself.")
  }
  id
}

#' Test a condition on the master row
#'
#' A test for [criterion()]: the condition is evaluated on the encounter's own master row.
#' It is met when the condition is true, not met when it is false, and undetermined when
#' it is unknown (a `NULL` in SQL).
#'
#' @param condition Character. A SQL boolean expression over the master's columns,
#'   written by the study programmer. It must never be built from data.
#'
#' @return An object of class `cohort_test`.
#'
#' @seealso [criterion()], [view_rows()], [any_of()]
#'
#' @examples
#' master_row("salvage = 1")
#'
#' @export
master_row <- function(condition) {
  if (missing(condition)) .required("master_row", "condition")
  structure(list(type = "master",
                 condition = .check_string("master_row", "condition", condition)),
            class = "cohort_test")
}

#' Test rows of another view in a window around the encounter
#'
#' A test for [criterion()]: rows of `view` for the same patient whose `date_col` falls
#' within `window` days of the encounter date are judged by `condition`. Which rows are
#' judged is `pick`:
#'
#' * `"any"`: met if any row meets the condition.
#' * `"all"`: met if every row meets it.
#' * `"nearest"`: the row or rows nearest the encounter date must agree, and their
#'   verdict is the test's.
#'
#' The test is **undetermined** when there is no row in the window, when a row's
#' condition is unknown and the verdict depends on it, or when rows tied for nearest
#' disagree. None of `date_col`, `window` or `pick` has a default: they are the study's
#' choices.
#'
#' Windows are whole days on dates. "Within 72 hours before surgery" written as
#' `c(-3, 0)` is wider than 72 hours, and the provenance records the day window used.
#'
#' @param view Character. A view in the same database, optionally schema-qualified.
#' @param date_col Character. The view's date or timestamp column. Timestamps are cast to
#'   dates.
#' @param window Integer vector of length two: first and last day relative to the
#'   encounter date, inclusive. `c(-30, 0)` is the 30 days before, and the day of,
#'   surgery.
#' @param pick `"any"`, `"all"` or `"nearest"`.
#' @param condition Character. A SQL boolean expression over the view's columns, written by
#'   the study programmer. Every column it names must exist in the view.
#' @param mrn_col Character. The view's patient identifier column.
#'
#' @return An object of class `cohort_test`.
#'
#' @seealso [criterion()], [master_row()], [any_of()]
#'
#' @examples
#' view_rows("echo_measure", date_col = "measured_on", window = c(-30, 0),
#'           pick = "nearest", condition = "lvef <= 25")
#'
#' @export
view_rows <- function(view, date_col, window, pick, condition, mrn_col = "mrn") {
  if (missing(view)) .required("view_rows", "view")
  if (missing(date_col)) .required("view_rows", "date_col")
  if (missing(window)) .required("view_rows", "window")
  if (missing(pick)) .required("view_rows", "pick")
  if (missing(condition)) .required("view_rows", "condition")
  if (!is.numeric(window) || length(window) != 2L || any(!is.finite(window))) {
    .abort("criterion_argument", "view_rows(): `window` must be two numbers of days.")
  }
  if (any(window != round(window))) {
    .abort("criterion_argument", "view_rows(): `window` must be whole numbers of days.")
  }
  if (window[[1]] > window[[2]]) {
    .abort("criterion_argument", "view_rows(): `window` must give its start before its ",
           "end.")
  }
  structure(list(
    type = "view",
    view = .check_string("view_rows", "view", view),
    date_col = .check_string("view_rows", "date_col", date_col),
    window = as.integer(window),
    pick = .check_choice("view_rows", "pick", pick, c("any", "all", "nearest")),
    condition = .check_string("view_rows", "condition", condition),
    mrn_col = .check_string("view_rows", "mrn_col", mrn_col)
  ), class = "cohort_test")
}

#' Combine tests
#'
#' `any_of()` is met when any part is met, not met when every part is not met, and
#' undetermined otherwise. `all_of()` is met when every part is met, not met when any part
#' is not met, and undetermined otherwise. Combinations nest.
#'
#' @param ... Two or more tests from [master_row()], [view_rows()], `any_of()` or
#'   `all_of()`.
#'
#' @return An object of class `cohort_test`.
#'
#' @seealso [criterion()]
#'
#' @examples
#' any_of(
#'   view_rows("echo_measure", "measured_on", c(-30, 0), "nearest", "lvef <= 25"),
#'   all_of(
#'     view_rows("echo_measure", "measured_on", c(-30, 0), "nearest", "lvef <= 35"),
#'     master_row("mitral_surgery = 1")
#'   )
#' )
#'
#' @export
any_of <- function(...) .combine_tests("any_of", "any", list(...))

#' @rdname any_of
#' @export
all_of <- function(...) .combine_tests("all_of", "all", list(...))

.combine_tests <- function(fn, type, parts) {
  if (length(parts) < 2L || !all(vapply(parts, inherits, logical(1), "cohort_test"))) {
    .abort("criterion_argument", fn, "(): give two or more tests from master_row(), ",
           "view_rows(), any_of() or all_of().")
  }
  structure(list(type = type, parts = parts), class = "cohort_test")
}

#' Declare an inclusion or exclusion criterion
#'
#' A criterion is one stage of the cohort, evaluated in the warehouse inside the pull's
#' transaction. Its `test` gives met, not met or undetermined for each unit still in the
#' cohort. `role` turns that into a verdict: an `"include"` criterion keeps met units, and
#' an `"exclude"` criterion drops them. `undetermined` says what happens to a unit the
#' test cannot decide: `"exclude"` it, `"keep"` it, or send it to chart `"review"`
#' (see [apply_review()]).
#'
#' No argument has a default. Which source, which window, which row and what to do
#' without one are the study's decisions, and the pull records them.
#'
#' @param id Character. The stage id: a letter, then letters, digits or underscores.
#' @param label Character. The CONSORT label.
#' @param role `"include"` or `"exclude"`.
#' @param test A test from [master_row()], [view_rows()], [any_of()] or [all_of()].
#' @param undetermined `"exclude"`, `"keep"` or `"review"`.
#'
#' @return An object of class `cohort_criterion`.
#'
#' @seealso [cohort_query()], [local_criterion()], [review_criterion()]
#'
#' @examples
#' criterion("inotrope_72h", "Any inotrope within 72 hours before surgery",
#'           role = "exclude",
#'           test = view_rows("med_admin", "given_at", c(-3, 0), "any",
#'                            "drug_class = 'inotrope'"),
#'           undetermined = "keep")
#'
#' @export
criterion <- function(id, label, role, test, undetermined) {
  if (missing(id)) .required("criterion", "id")
  if (missing(label)) .required("criterion", "label")
  if (missing(role)) .required("criterion", "role")
  if (missing(test)) .required("criterion", "test")
  if (missing(undetermined)) .required("criterion", "undetermined")
  if (!inherits(test, "cohort_test")) {
    .abort("criterion_argument", "criterion(): `test` must come from master_row(), ",
           "view_rows(), any_of() or all_of().")
  }
  structure(list(
    id = .check_stage_id("criterion", id),
    label = .check_string("criterion", "label", label),
    role = .check_choice("criterion", "role", role, c("include", "exclude")),
    test = test,
    undetermined = .check_choice("criterion", "undetermined", undetermined,
                                 c("exclude", "keep", "review")),
    kind = "warehouse"
  ), class = "cohort_criterion")
}

#' Declare a criterion evaluated in R on a file the study holds
#'
#' For a source outside the warehouse. It runs after the pull's transaction, against the
#' candidates that survived the warehouse criteria, so the provenance does not claim one
#' snapshot covers it. The file's SHA-256 is taken when the criterion is declared, and
#' again before and after `decide()` reads it. [pull_master()] refuses the pull if the
#' file has changed since it was declared, or changed while it was read.
#'
#' @inheritParams criterion
#' @param path Character. The file the criterion reads.
#' @param decide A function of `(units, path)`. `units` is a data frame with
#'   `cohort_unit`, `mrn` and `encounter_date`, one row per candidate. It must return a
#'   logical vector with one value per row: `TRUE` met, `FALSE` not met, `NA`
#'   undetermined.
#'
#' @return An object of class `cohort_criterion`.
#'
#' @seealso [criterion()], [cohort_query()]
#'
#' @examples
#' f <- tempfile(fileext = ".csv")
#' writeLines("mrn,covid_date", f)
#' local_criterion("covid_14d", "COVID-19 within 14 days", role = "exclude", path = f,
#'                 decide = function(units, path) rep(FALSE, nrow(units)),
#'                 undetermined = "review")
#'
#' @export
local_criterion <- function(id, label, role, path, decide, undetermined) {
  if (missing(id)) .required("local_criterion", "id")
  if (missing(label)) .required("local_criterion", "label")
  if (missing(role)) .required("local_criterion", "role")
  if (missing(path)) .required("local_criterion", "path")
  if (missing(decide)) .required("local_criterion", "decide")
  if (missing(undetermined)) .required("local_criterion", "undetermined")
  if (!.one_string(path) || !file.exists(path)) {
    .abort("criterion_argument", "local_criterion(): `path` must be an existing file.")
  }
  if (!is.function(decide)) {
    .abort("criterion_argument", "local_criterion(): `decide` must be a function.")
  }
  structure(list(
    id = .check_stage_id("local_criterion", id),
    label = .check_string("local_criterion", "label", label),
    role = .check_choice("local_criterion", "role", role, c("include", "exclude")),
    path = path,
    sha256 = digest::digest(path, algo = "sha256", file = TRUE),
    decide = decide,
    undetermined = .check_choice("local_criterion", "undetermined", undetermined,
                                 c("exclude", "keep", "review")),
    kind = "local"
  ), class = "cohort_criterion")
}

#' Declare a criterion decided at chart review
#'
#' For a criterion no data can decide. Every unit still in the cohort after the pull
#' needs a decision for it, recorded with [apply_review()].
#'
#' @inheritParams criterion
#'
#' @return An object of class `cohort_criterion`.
#'
#' @seealso [apply_review()], [review_list()]
#'
#' @examples
#' review_criterion("planned_mcs", "Planned alternative temporary support strategy",
#'                  role = "exclude")
#'
#' @export
review_criterion <- function(id, label, role) {
  if (missing(id)) .required("review_criterion", "id")
  if (missing(label)) .required("review_criterion", "label")
  if (missing(role)) .required("review_criterion", "role")
  structure(list(
    id = .check_stage_id("review_criterion", id),
    label = .check_string("review_criterion", "label", label),
    role = .check_choice("review_criterion", "role", role, c("include", "exclude")),
    kind = "review"
  ), class = "cohort_criterion")
}
