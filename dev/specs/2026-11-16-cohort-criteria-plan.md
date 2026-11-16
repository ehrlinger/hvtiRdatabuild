# Cohort criteria evaluated in the warehouse: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a study declare windowed inclusion and exclusion criteria on its
`cohort_query()`. Each criterion is evaluated in the warehouse inside the pull's
transaction, recorded as its own counted stage, and has no clinical defaults.

**Architecture:** A criterion is a **stage** (`criterion()`, with an id, label, role and
undetermined route) wrapping a **test** (`master_row()`, `view_rows()`, or `any_of()` /
`all_of()` over tests). `pull_master()` compiles the tests' leaves into flag columns on the
session cohort table, sets each flag by a correlated `UPDATE` (1 met, 0 not met, NULL
undetermined), and deactivates units stage by stage in SQL. Only keys and flags are read
back. R rebuilds the stages from the flags with the same three-valued logic and **refuses
the pull if R and SQL disagree** on the active set. Local criteria run in R after the
transaction. Review criteria and review-routed units leave the pull `"awaiting review"`
until `apply_review()` records a decisions file.

**Tech Stack:** R (>= 4.4.0), DBI, duckdb 2.0.0 (tests), digest, testthat 3.

**Spec:** `dev/specs/2026-11-16-cohort-criteria-addendum.md` (#108), on top of
`2026-11-16-master-views-design.md` §5–6 and the pull shipped in #106.

### Refinements to the addendum, decided here

1. **A criterion is split into a stage and its test.** The addendum's `criterion()` carried
   the view arguments directly, so the parts of an `any_of()` would each have needed a role
   and an undetermined route that mean nothing inside a combination. Here the parts are
   *tests* (`master_row()`, `view_rows()`), and only the stage (`criterion()`) has a role
   and a route.
2. **The declared order must already be grouped:** warehouse criteria, then local, then
   review. The addendum let the package regroup them. Refusing an ungrouped list is
   simpler, and the printed order then matches the CONSORT order.
3. **A row whose condition is unknown (SQL NULL) makes its test undetermined**, not "not
   met". An echo with no LVEF recorded is not evidence that LVEF is above 25.
4. **`freeze_study_pull()` also refuses a pull awaiting review.** The addendum named only
   `build_from_master()`. A release with undecided members would be wrong for the same
   reason.
5. **With `index_on = "eligible"`, every qualifying encounter's key leaves the database**,
   not only each patient's first. That is the candidate set, and it carries keys and flags,
   never view values.
6. **`nearest` avoids an aggregate over an outer reference.** SQL Server refuses
   `MIN(ABS(DATEDIFF(day, outer.date, inner.date)))` (error 8124). The nearest row is found
   from the latest row on or before the encounter and the earliest row on or after it,
   each an aggregate over inner columns only.

## Global constraints

- Lines are **100 characters** (`.lintr`). Roxygen markdown is enabled.
- testthat **edition 3**. Test files are `test-*.R`, with a hyphen.
- **No PHI.** Every fixture is invented and says so ("No PHI: identifiers and values are
  invented."). **No identifier or data value appears in any error, warning, message or print
  output.** Counts, stage ids and labels only.
- **Errors a caller may catch use `.abort(condition, ...)`** (`R/rubric.R`), with the
  message prefixed `fn(): `. Wrap every DBI call in `run_step(name, expr)`
  (`R/sql_dialect.R`), which withholds the driver's message.
- **Cohort stage `source` is one of `"upstream"`, `"build"`, `"derive"`, and from Task 1
  also `"review"`.** Warehouse criteria are `upstream`, local criteria `build`, and review
  stages `review`.
- **No clinical default anywhere.** `role`, `undetermined`, `window`, `pick`, `date_col` and
  `index_on` (when it applies) are required arguments. A missing one is refused with a
  message naming the argument.
- **SQL that a study writes (`condition`, `qualifying`) is never built from data.** Window
  bounds are validated integers and are inlined. Nothing else is.
- **SQL stays in the shared subset**, so one statement runs on both dialects: correlated
  scalar subqueries, `CASE`, `COUNT`/`MIN`/`MAX`, `EXISTS`, `CAST(... AS DATE)`. The two
  dialect-specific pieces go through helpers: day shift (`DATEADD` versus `date + n`) and
  day difference (`DATEDIFF` versus `date_diff`).
- `duckdb` is in **Suggests**. Tests call `skip_if_not_installed("duckdb")` through
  `local_master_db()`.
- **No version bump.** One news fragment, `news/feat-cohort-criteria.md`, written in
  Task 9. Bullets only, no heading.
- Done means: `devtools::document()` run and committed; `devtools::test()` passing with no
  new skips; `devtools::check()` at 0 errors, 0 warnings, 0 notes;
  `lintr::lint_package()` clean; `pkgdown::check_pkgdown()` clean.

## File structure

| File | Responsibility |
|---|---|
| `R/cohort_record.R` (modify) | accept the `review` stage source |
| `R/cohort_criteria.R` (new) | `master_row()`, `view_rows()`, `any_of()`, `all_of()`, `criterion()`, `local_criterion()`, `review_criterion()`; compile, three-valued evaluation, stage outcomes, descriptions |
| `R/criteria_sql.R` (new) | dialect date helpers, leaf `UPDATE`, combination expression, deactivation, first-eligible |
| `R/cohort_query.R` (modify) | `criteria` and `index_on` arguments, validation, print |
| `R/master_pull.R` (modify) | flag columns, evaluation in the transaction, stages, agreement check, local stages, review status |
| `R/master_review.R` (new) | `review_list()`, `apply_review()` |
| `R/master_build.R`, `R/master_freeze.R` (modify) | refuse a pull awaiting review |
| `tests/testthat/helper-criteria.R` (new) | invented echo and medication views, a flag-table harness |
| `tests/testthat/test-cohort-criteria.R`, `test-criteria-sql.R`, `test-master-criteria.R`, `test-master-review.R` (new) | tests |
| `tests/testthat/test-cohort-record.R` (modify) | `review` source |
| `_pkgdown.yml` (modify) | new reference group |

---

### Task 1: `review` stage source

**Files:**
- Modify: `R/cohort_record.R:270-272` (the source check), and the `@param stages` roxygen
  near line 9
- Test: `tests/testthat/test-cohort-record.R`

**Interfaces:**
- Produces: `new_cohort_record()` and `append_cohort_stage()` accept `source = "review"`.

- [ ] **Step 1: Write the failing test** (append to `test-cohort-record.R`)

```r
test_that("a review stage is a valid stage source", {
  # No PHI: identifiers are invented.
  rec <- new_cohort_record(
    members = data.frame(patient_id = c("SYN1", "SYN2"), stage_id = "s1",
                         included = TRUE, reason = NA_character_),
    stages = data.frame(stage_id = "s1", order = 1L, label = "Selected",
                        source = "upstream", provenance = "fixture"),
    patient_id_col = "id"
  )
  rec <- append_cohort_stage(
    rec,
    data.frame(stage_id = "r1", order = 2L, label = "Chart review", source = "review",
               provenance = "decisions file sha256 0"),
    data.frame(patient_id = c("SYN1", "SYN2"), included = c(TRUE, FALSE),
               reason = c(NA, "excluded at review: R1"))
  )
  expect_identical(rec$stages$source, c("upstream", "review"))
  expect_error(
    append_cohort_stage(
      rec,
      data.frame(stage_id = "x", order = 3L, label = "X", source = "chart",
                 provenance = "p"),
      data.frame(patient_id = "SYN1", included = TRUE, reason = NA_character_)
    ),
    "upstream, build, derive, or review"
  )
})
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `Rscript -e 'devtools::test(filter = "cohort-record")'`
Expected: FAIL with "Stage source must be upstream, build, or derive."

- [ ] **Step 3: Implement**

In `R/cohort_record.R`, replace

```r
  if (any(!stages$source %in% c("upstream", "build", "derive"))) {
    stop("Stage source must be upstream, build, or derive.", call. = FALSE)
  }
```

with

```r
  if (any(!stages$source %in% c("upstream", "build", "derive", "review"))) {
    stop("Stage source must be upstream, build, derive, or review.", call. = FALSE)
  }
```

In the roxygen for `stages` (line 9 area), add `"review"` to the list of sources and one
sentence: "`review` is a decision made at chart review, recorded by [apply_review()]."

- [ ] **Step 4: Fix the one existing assertion that pins the old vocabulary**

`tests/testthat/test-master-pull.R` checks
`all(res$cohort$stages$source %in% c("upstream", "build", "derive"))`. It stays true for that
test (a pull without review), so leave it. Run
`grep -rn '"upstream", "build", "derive"' R tests` and update only a check that tests
the vocabulary itself rather than one pull's stages.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::test(filter = "cohort-record|master-pull")'`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add R/cohort_record.R tests/testthat/test-cohort-record.R
git commit -m "feat: review is a cohort stage source"
```

---

### Task 2: Criteria and tests: constructors with no defaults

**Files:**
- Create: `R/cohort_criteria.R`
- Test: `tests/testthat/test-cohort-criteria.R`

**Interfaces:**
- Produces:
  - `master_row(condition)` → class `cohort_test`, `type = "master"`
  - `view_rows(view, date_col, window, pick, condition, mrn_col = "mrn")` → `cohort_test`,
    `type = "view"`, with `window` as an integer vector of length 2
  - `any_of(...)`, `all_of(...)` → `cohort_test`, `type` `"any"` or `"all"`, with `parts`
  - `criterion(id, label, role, test, undetermined)` → class `cohort_criterion`,
    `kind = "warehouse"`
  - `local_criterion(id, label, role, path, decide, undetermined)` → `cohort_criterion`,
    `kind = "local"`, plus `sha256`
  - `review_criterion(id, label, role)` → `cohort_criterion`, `kind = "review"`
  - internal `.reserved_stage_ids`, `.one_string(x)`

- [ ] **Step 1: Write the failing tests**

```r
# No PHI: identifiers and values are invented.

lvef_test <- function(...) {
  view_rows("echo_demo", date_col = "measured_on", window = c(-30, 0),
            pick = "nearest", condition = "lvef <= 25", ...)
}

test_that("a criterion needs every clinical choice stated", {
  expect_error(criterion("lvef", "LVEF", test = lvef_test(), undetermined = "exclude"),
               class = "hvtiRdatabuild_criterion_argument", regexp = "`role` is required")
  expect_error(criterion("lvef", "LVEF", role = "include", test = lvef_test()),
               "`undetermined` is required")
  expect_error(view_rows("echo_demo", "measured_on", pick = "any", condition = "lvef < 1"),
               "`window` is required")
  expect_error(view_rows("echo_demo", "measured_on", c(-30, 0), condition = "lvef < 1"),
               "`pick` is required")
  expect_error(view_rows("echo_demo", window = c(-30, 0), pick = "any",
                         condition = "lvef < 1"),
               "`date_col` is required")
})

test_that("choices and windows are checked", {
  expect_error(criterion("lvef", "LVEF", "maybe", lvef_test(), "exclude"),
               "`role` must be one of")
  expect_error(criterion("lvef", "LVEF", "include", lvef_test(), "guess"),
               "`undetermined` must be one of")
  expect_error(view_rows("v", "d", c(0, -30), "any", "x = 1"), "start before its end")
  expect_error(view_rows("v", "d", c(-1.5, 0), "any", "x = 1"), "whole numbers of days")
  expect_error(view_rows("v", "d", c(-1, 0), "first", "x = 1"), "`pick` must be one of")
  expect_identical(view_rows("v", "d", c(-3, 0), "any", "x = 1")$window, c(-3L, 0L))
})

test_that("stage ids are identifiers and not the package's own stages", {
  expect_error(criterion("in_master", "X", "include", lvef_test(), "exclude"),
               "a stage the package uses itself")
  expect_error(criterion("2lvef", "X", "include", lvef_test(), "exclude"),
               "must start with a letter")
})

test_that("combinations take two or more tests and nest", {
  mitral <- master_row("mitral_surgery = 1")
  combo <- any_of(lvef_test(), all_of(mitral, master_row("mr_grade >= 3")))
  expect_s3_class(combo, "cohort_test")
  expect_identical(combo$type, "any")
  expect_identical(combo$parts[[2]]$type, "all")
  expect_error(any_of(mitral), "two or more tests")
  expect_error(all_of(mitral, "x = 1"), "two or more tests")
})

test_that("local and review criteria record what they need", {
  f <- withr::local_tempfile(fileext = ".csv")
  writeLines("mrn,flag", f)
  loc <- local_criterion("covid", "COVID-19 within 14 days", "exclude", f,
                         decide = function(units, path) rep(FALSE, nrow(units)),
                         undetermined = "review")
  expect_identical(loc$kind, "local")
  expect_identical(loc$sha256, digest::digest(f, algo = "sha256", file = TRUE))
  expect_error(local_criterion("covid", "C", "exclude", f, decide = "no",
                               undetermined = "review"),
               "`decide` must be a function")
  rev <- review_criterion("strategy", "Planned alternative support strategy", "exclude")
  expect_identical(rev$kind, "review")
  expect_error(review_criterion("strategy", "S"), "`role` is required")
})
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "cohort-criteria")'`
Expected: FAIL with `could not find function "view_rows"`.

- [ ] **Step 3: Implement `R/cohort_criteria.R`**

```r
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
#' snapshot covers it. The file's SHA-256 is recorded when the criterion is declared.
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
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "cohort-criteria")'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add R/cohort_criteria.R tests/testthat/test-cohort-criteria.R NAMESPACE man/
git commit -m "feat: criterion constructors with no clinical defaults"
```

---

### Task 3: Compile, evaluate three-valued, and the matching SQL expressions

**Files:**
- Modify: `R/cohort_criteria.R` (append)
- Create: `R/criteria_sql.R`
- Test: `tests/testthat/test-cohort-criteria.R`, `tests/testthat/test-criteria-sql.R`

**Interfaces:**
- Consumes: Task 2's `cohort_test`, `cohort_criterion`.
- Produces:
  - `.compile_criteria(criteria)` → `list(stages, n_flags)`. Each element of `stages` is a
    warehouse criterion with `node` added. A node is `list(type = "leaf", col = "crit_<k>",
    test)` or `list(type = "any"|"all", parts)`.
  - `.node_leaves(node)` → a list of leaf nodes.
  - `.eval_node(node, flags)` → an integer vector (1, 0, `NA`), one per row of `flags`.
  - `.stage_outcome(role, undetermined, s, label)` → `list(included, reason, review)`.
  - `.active_units(record)` → the units active at the record's last stage.
  - `.describe_test(test)`, `.describe_criterion(cr)` → character.
  - `.node_sql(node)` → a SQL expression over the flag columns.
  - `.deactivate_sql(tmp, stage)` → an `UPDATE` statement.

- [ ] **Step 1: Write the failing tests**

Append to `test-cohort-criteria.R`:

```r
test_that("compiling numbers the leaves across stages", {
  a <- criterion("a", "A", "include", any_of(master_row("x = 1"), master_row("y = 1")),
                 "exclude")
  b <- criterion("b", "B", "exclude", master_row("z = 1"), "keep")
  r <- review_criterion("r", "R", "exclude")
  comp <- .compile_criteria(list(a, b, r))
  expect_identical(comp$n_flags, 3L)
  expect_length(comp$stages, 2L)
  expect_identical(vapply(.node_leaves(comp$stages[[1]]$node), `[[`, "", "col"),
                   c("crit_1", "crit_2"))
  expect_identical(comp$stages[[2]]$node$col, "crit_3")
})

test_that("any_of and all_of follow three-valued logic", {
  flags <- data.frame(crit_1 = c(1L, 0L, 0L, NA, NA, 1L),
                      crit_2 = c(NA, 0L, NA, 0L, NA, 1L))
  leaf <- function(k) list(type = "leaf", col = paste0("crit_", k))
  any_node <- list(type = "any", parts = list(leaf(1), leaf(2)))
  all_node <- list(type = "all", parts = list(leaf(1), leaf(2)))
  expect_identical(.eval_node(any_node, flags), c(1L, 0L, NA, NA, NA, 1L))
  expect_identical(.eval_node(all_node, flags), c(NA, 0L, 0L, 0L, NA, 1L))
})

test_that("a stage outcome applies role and the undetermined route", {
  s <- c(1L, 0L, NA)
  inc <- .stage_outcome("include", "review", s, "LVEF")
  expect_identical(inc$included, c(TRUE, FALSE, TRUE))
  expect_identical(inc$reason, c(NA, "did not meet: LVEF", NA))
  expect_identical(inc$review, c(FALSE, FALSE, TRUE))
  exc <- .stage_outcome("exclude", "exclude", s, "Inotrope")
  expect_identical(exc$included, c(FALSE, TRUE, FALSE))
  expect_identical(exc$reason, c("excluded: Inotrope", NA, "undetermined: Inotrope"))
})
```

Create `test-criteria-sql.R`:

```r
# No PHI: identifiers and values are invented.

test_that("the SQL combination agrees with R on every flag pattern", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  vals <- c(1L, 0L, NA)
  grid <- expand.grid(crit_1 = vals, crit_2 = vals, crit_3 = vals)
  DBI::dbWriteTable(con, "flags", grid)
  leaf <- function(k) list(type = "leaf", col = paste0("crit_", k))
  nodes <- list(
    list(type = "any", parts = list(leaf(1), leaf(2), leaf(3))),
    list(type = "all", parts = list(leaf(1), leaf(2), leaf(3))),
    list(type = "any", parts = list(leaf(1),
                                    list(type = "all", parts = list(leaf(2), leaf(3)))))
  )
  for (node in nodes) {
    got <- DBI::dbGetQuery(con, paste("SELECT", .node_sql(node), "AS s FROM flags"))$s
    expect_identical(as.integer(got), .eval_node(node, grid))
  }
})

test_that("deactivation keeps exactly the units R keeps", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  for (role in c("include", "exclude")) {
    for (und in c("exclude", "keep", "review")) {
      DBI::dbWriteTable(con, "t", data.frame(active = 1L, crit_1 = c(1L, 0L, NA)),
                        overwrite = TRUE)
      stage <- list(role = role, undetermined = und,
                    node = list(type = "leaf", col = "crit_1"))
      DBI::dbExecute(con, .deactivate_sql("t", stage))
      got <- DBI::dbGetQuery(con, "SELECT active FROM t")$active == 1L
      expect_identical(got, .stage_outcome(role, und, c(1L, 0L, NA), "L")$included,
                       info = paste(role, und))
    }
  }
})
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "cohort-criteria|criteria-sql")'`
Expected: FAIL with `could not find function ".compile_criteria"`.

- [ ] **Step 3: Append to `R/cohort_criteria.R`**

```r
# Compile the warehouse criteria: number every leaf test as a flag column, crit_<k>, in
# declared order.
.compile_test <- function(test, counter) {
  if (test$type %in% c("master", "view")) {
    counter$n <- counter$n + 1L
    return(list(type = "leaf", col = paste0("crit_", counter$n), test = test))
  }
  list(type = test$type, parts = lapply(test$parts, .compile_test, counter = counter))
}

.compile_criteria <- function(criteria) {
  counter <- new.env(parent = emptyenv())
  counter$n <- 0L
  warehouse <- Filter(function(cr) identical(cr$kind, "warehouse"), criteria)
  stages <- lapply(warehouse, function(cr) {
    cr$node <- .compile_test(cr$test, counter)
    cr
  })
  list(stages = stages, n_flags = counter$n)
}

.node_leaves <- function(node) {
  if (identical(node$type, "leaf")) return(list(node))
  do.call(c, lapply(node$parts, .node_leaves))
}

# Three-valued evaluation of a node over flag columns: 1 met, 0 not met, NA undetermined.
.eval_node <- function(node, flags) {
  if (identical(node$type, "leaf")) return(as.integer(flags[[node$col]]))
  n <- nrow(flags)
  if (!n) return(integer())
  m <- matrix(unlist(lapply(node$parts, .eval_node, flags = flags)), nrow = n)
  ones <- rowSums(m == 1L, na.rm = TRUE)
  zeros <- rowSums(m == 0L, na.rm = TRUE)
  out <- if (identical(node$type, "any")) {
    ifelse(ones > 0, 1L, ifelse(zeros == ncol(m), 0L, NA_integer_))
  } else {
    ifelse(zeros > 0, 0L, ifelse(ones == ncol(m), 1L, NA_integer_))
  }
  as.integer(out)
}

# A stage's verdict for each unit. An include criterion passes met units, an exclude
# criterion passes units that are not met. An undetermined unit follows the route, and
# `review` marks it for chart review while keeping it in.
.stage_outcome <- function(role, undetermined, s, label) {
  target <- if (identical(role, "include")) 1L else 0L
  und <- is.na(s)
  passes <- !und & s == target
  included <- passes | (und & !identical(undetermined, "exclude"))
  failed <- if (identical(role, "include")) "did not meet: " else "excluded: "
  reason <- ifelse(included, NA_character_,
                   ifelse(und, paste0("undetermined: ", label), paste0(failed, label)))
  list(included = included, reason = reason,
       review = und & identical(undetermined, "review"))
}

.active_units <- function(record) {
  last <- utils::tail(record$stages$stage_id[order(record$stages$order)], 1L)
  record$members$patient_id[record$members$stage_id == last & record$members$included]
}

.describe_test <- function(test) {
  switch(test$type,
         master = paste("master row:", test$condition),
         view = sprintf("%s rows by %s, days %d to %d, %s: %s", test$view, test$date_col,
                        test$window[[1]], test$window[[2]], test$pick, test$condition),
         any = paste0("any of [", paste(vapply(test$parts, .describe_test, ""),
                                        collapse = "; "), "]"),
         all = paste0("all of [", paste(vapply(test$parts, .describe_test, ""),
                                        collapse = "; "), "]"))
}

.describe_criterion <- function(cr) {
  switch(cr$kind,
         warehouse = sprintf("%s [%s, warehouse]: %s; undetermined: %s", cr$id, cr$role,
                             .describe_test(cr$test), cr$undetermined),
         local = sprintf("%s [%s, local]: file sha256 %s; undetermined: %s", cr$id,
                         cr$role, cr$sha256, cr$undetermined),
         review = sprintf("%s [%s, review]", cr$id, cr$role))
}
```

- [ ] **Step 4: Create `R/criteria_sql.R`**

```r
# criteria_sql.R
#
# SQL for cohort criteria, run inside pull_master()'s transaction against the session
# cohort table. Flags are 1 met, 0 not met, NULL undetermined. Spec:
# dev/specs/2026-11-16-cohort-criteria-addendum.md §4.

# A node as a SQL expression over the flag columns, with the same three-valued logic
# as .eval_node().
.node_sql <- function(node) {
  if (identical(node$type, "leaf")) return(node$col)
  parts <- vapply(node$parts, .node_sql, character(1))
  win <- if (identical(node$type, "any")) 1L else 0L
  lose <- 1L - win
  sprintf("CASE WHEN %s THEN %d WHEN %s THEN %d END",
          paste0("(", parts, ") = ", win, collapse = " OR "), win,
          paste0("(", parts, ") = ", lose, collapse = " AND "), lose)
}

# Deactivate the active units a stage does not keep (see .stage_outcome()).
.deactivate_sql <- function(tmp, stage) {
  s <- .node_sql(stage$node)
  target <- if (identical(stage$role, "include")) 1L else 0L
  und_keeps <- if (identical(stage$undetermined, "exclude")) 0L else 1L
  sprintf(paste("UPDATE %s SET active = 0 WHERE active = 1 AND",
                "(CASE WHEN (%s) = %d THEN 1 WHEN (%s) IS NULL THEN %d ELSE 0 END) = 0"),
          tmp, s, target, s, und_keeps)
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::test(filter = "cohort-criteria|criteria-sql")'`
Expected: PASS. The agreement test covers all 27 patterns of three flags.

- [ ] **Step 6: Commit**

```bash
git add R/cohort_criteria.R R/criteria_sql.R tests/testthat/test-cohort-criteria.R \
  tests/testthat/test-criteria-sql.R
git commit -m "feat: compile criteria; three-valued logic in R and SQL agree"
```

---

### Task 4: Leaf SQL: one flag per test

**Files:**
- Modify: `R/criteria_sql.R` (append)
- Create: `tests/testthat/helper-criteria.R`
- Test: `tests/testthat/test-criteria-sql.R`

**Interfaces:**
- Consumes: Task 3's leaf nodes.
- Produces:
  - `.date_shift_sql(dialect, x, days)`, `.day_diff_sql(dialect, from, to)`
  - `.leaf_value_sql(test, tmp, master_q, mrn_q, date_q, dialect)` → a scalar subquery
  - `.leaf_update_sql(leaf, tmp, master_q, mrn_q, date_q, dialect)` →
    `UPDATE <tmp> SET <col> = <value> WHERE active = 1`
  - Test helper `flag_table(con, units)`: creates the duckdb temp table `study_cohort`
    with `active` and `crit_1`, holding the given units.
  - Test helper `seed_criteria_views(con)`: creates `echo_demo` and `med_demo`.

- [ ] **Step 1: Write the helper** `tests/testthat/helper-criteria.R`

```r
# No PHI: identifiers and values are invented.

# Echo and medication views for the master_demo encounters in helper-master-pull.R:
# SYN101 2010-03-01, SYN103 2015-06-30 (and 2018-02-02 with second_cabg),
# SYN104 2020-01-10.
seed_criteria_views <- function(con) {
  DBI::dbWriteTable(con, "echo_demo", data.frame(
    mrn = c("SYN101", "SYN101", "SYN103", "SYN103", "SYN103"),
    measured_on = as.Date(c("2010-02-20", "2010-01-01", "2015-06-25", "2015-06-25",
                            "2018-01-30")),
    lvef = c(22, 50, 30, 20, 24),
    stringsAsFactors = FALSE
  ))
  DBI::dbWriteTable(con, "med_demo", data.frame(
    mrn = c("SYN101", "SYN103", "SYN104"),
    given_at = as.POSIXct(c("2010-02-27 08:00", "2015-06-29 10:00", "2020-01-14 09:00"),
                          tz = "UTC"),
    drug_class = c("inotrope", "inotrope", "inotrope"),
    stringsAsFactors = FALSE
  ))
  invisible(con)
}

# A bare cohort table, as pull_master() builds it, for testing one leaf at a time.
flag_table <- function(con, mrn, dates) {
  DBI::dbExecute(con, paste("CREATE OR REPLACE TEMP TABLE study_cohort (mrn VARCHAR NOT",
                            "NULL, encounter_date DATE NOT NULL, active TINYINT NOT NULL",
                            "DEFAULT 1, crit_1 TINYINT)"))
  DBI::dbExecute(con, "INSERT INTO study_cohort (mrn, encounter_date) VALUES (?, ?)",
                 params = list(mrn, as.Date(dates)))
}

leaf_flags <- function(con, test) {
  leaf <- list(type = "leaf", col = "crit_1", test = test)
  DBI::dbExecute(con, .leaf_update_sql(leaf, "study_cohort", "master_demo", "\"mrn\"",
                                       "\"encounter_date\"", "duckdb"))
  out <- DBI::dbGetQuery(con, "SELECT mrn, crit_1 FROM study_cohort ORDER BY mrn")
  stats::setNames(as.integer(out$crit_1), out$mrn)
}
```

- [ ] **Step 2: Write the failing tests** (append to `test-criteria-sql.R`)

```r
lvef <- function(pick, window = c(-30, 0), condition = "lvef <= 25") {
  view_rows("echo_demo", "measured_on", window, pick, condition)
}

test_that("pick any, all and nearest judge the rows in the window", {
  con <- local_master_db()
  seed_criteria_views(con)
  flag_table(con, c("SYN101", "SYN103", "SYN104"),
             c("2010-03-01", "2015-06-30", "2020-01-10"))
  # SYN101: 22 in window, 50 outside. SYN103: 30 and 20 tied nearest. SYN104: none.
  expect_identical(leaf_flags(con, lvef("any")),
                   c(SYN101 = 1L, SYN103 = 1L, SYN104 = NA))
  expect_identical(leaf_flags(con, lvef("all")),
                   c(SYN101 = 1L, SYN103 = 0L, SYN104 = NA))
  expect_identical(leaf_flags(con, lvef("nearest")),
                   c(SYN101 = 1L, SYN103 = NA, SYN104 = NA))
})

test_that("window edges are inclusive and outside rows are ignored", {
  con <- local_master_db()
  seed_criteria_views(con)
  flag_table(con, "SYN101", "2010-03-01")
  # The 22 is 9 days before.
  expect_identical(leaf_flags(con, lvef("any", c(-9, 0))), c(SYN101 = 1L))
  expect_identical(leaf_flags(con, lvef("any", c(-8, 0))), c(SYN101 = NA))
  # The 50 is 59 days before.
  expect_identical(leaf_flags(con, lvef("any", c(-59, -59))), c(SYN101 = 0L))
})

test_that("an unknown condition makes the test undetermined, not unmet", {
  con <- local_master_db()
  seed_criteria_views(con)
  DBI::dbExecute(con, "INSERT INTO echo_demo VALUES ('SYN104', DATE '2020-01-09', NULL)")
  flag_table(con, "SYN104", "2020-01-10")
  expect_identical(leaf_flags(con, lvef("nearest")), c(SYN104 = NA))
  expect_identical(leaf_flags(con, lvef("any")), c(SYN104 = NA))
})

test_that("nearest takes the closer side and a timestamp is cast to its date", {
  con <- local_master_db()
  seed_criteria_views(con)
  DBI::dbExecute(con, "INSERT INTO echo_demo VALUES ('SYN104', DATE '2020-01-12', 60)")
  DBI::dbExecute(con, "INSERT INTO echo_demo VALUES ('SYN104', DATE '2020-01-05', 20)")
  flag_table(con, "SYN104", "2020-01-10")
  expect_identical(leaf_flags(con, lvef("nearest", c(-30, 30))), c(SYN104 = 0L))
  inotrope <- view_rows("med_demo", "given_at", c(-3, 0), "any",
                        "drug_class = 'inotrope'")
  flag_table(con, c("SYN101", "SYN104"), c("2010-03-01", "2020-01-10"))
  expect_identical(leaf_flags(con, inotrope), c(SYN101 = 1L, SYN104 = NA))
})

test_that("a master_row test reads the encounter's own row", {
  con <- local_master_db()
  flag_table(con, c("SYN101", "SYN104"), c("2010-03-01", "2020-01-10"))
  expect_identical(leaf_flags(con, master_row("age >= 65")),
                   c(SYN101 = 0L, SYN104 = 1L))
})

test_that("inactive units are not evaluated", {
  con <- local_master_db()
  flag_table(con, c("SYN101", "SYN104"), c("2010-03-01", "2020-01-10"))
  DBI::dbExecute(con, "UPDATE study_cohort SET active = 0 WHERE mrn = 'SYN104'")
  expect_identical(leaf_flags(con, master_row("age >= 65")),
                   c(SYN101 = 0L, SYN104 = NA))
})
```

- [ ] **Step 3: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "criteria-sql")'`
Expected: FAIL with `could not find function ".leaf_update_sql"`.

- [ ] **Step 4: Append to `R/criteria_sql.R`**

```r
.date_shift_sql <- function(dialect, x, days) {
  switch(dialect,
         mssql = sprintf("DATEADD(day, %d, %s)", as.integer(days), x),
         duckdb = sprintf("CAST(%s + %d AS DATE)", x, as.integer(days)))
}

.day_diff_sql <- function(dialect, from, to) {
  switch(dialect,
         mssql = sprintf("DATEDIFF(day, %s, %s)", from, to),
         duckdb = sprintf("date_diff('day', %s, %s)", from, to))
}

# 1 when the condition is true, 0 when false, NULL when unknown.
.met_sql <- function(condition) {
  sprintf("CASE WHEN (%s) THEN 1 WHEN NOT (%s) THEN 0 END", condition, condition)
}

# Over the judged rows: their common verdict, or NULL when there are none, any is
# unknown, or they disagree.
.agree_sql <- function(met) {
  sprintf(paste("CASE WHEN COUNT(*) > 0 AND COUNT(%1$s) = COUNT(*) AND",
                "MIN(%1$s) = MAX(%1$s) THEN MIN(%1$s) END"), met)
}

# One leaf's value for the cohort row `tmp`, as a correlated scalar subquery. Aggregates
# take inner columns only: SQL Server refuses an aggregate over an outer reference.
.leaf_value_sql <- function(test, tmp, master_q, mrn_q, date_q, dialect) {
  met <- .met_sql(test$condition)
  enc <- paste0(tmp, ".encounter_date")
  if (identical(test$type, "master")) {
    return(sprintf("(SELECT %s FROM %s m WHERE m.%s = %s.mrn AND m.%s = %s)",
                   .agree_sql(met), master_q, mrn_q, tmp, date_q, enc))
  }
  q <- quoter(dialect)
  view_q <- .qualified_name(test$view, dialect)
  day <- function(alias) sprintf("CAST(%s.%s AS DATE)", alias, q(test$date_col))
  in_window <- function(alias) {
    sprintf("%s.%s = %s.mrn AND %s BETWEEN %s AND %s", alias, q(test$mrn_col), tmp,
            day(alias), .date_shift_sql(dialect, enc, test$window[[1]]),
            .date_shift_sql(dialect, enc, test$window[[2]]))
  }
  where <- in_window("v")
  if (identical(test$pick, "nearest")) {
    before <- sprintf("(SELECT MAX(%s) FROM %s v2 WHERE %s AND %s <= %s)", day("v2"),
                      view_q, in_window("v2"), day("v2"), enc)
    after <- sprintf("(SELECT MIN(%s) FROM %s v3 WHERE %s AND %s >= %s)", day("v3"),
                     view_q, in_window("v3"), day("v3"), enc)
    gap <- function(x) sprintf("ABS(%s)", .day_diff_sql(dialect, enc, x))
    nearest_gap <- sprintf(paste("CASE WHEN %1$s IS NULL THEN %4$s WHEN %2$s IS NULL",
                                 "THEN %3$s WHEN %3$s <= %4$s THEN %3$s ELSE %4$s END"),
                           before, after, gap(before), gap(after))
    where <- sprintf("%s AND %s = %s", where, gap(day("v")), nearest_gap)
  }
  agg <- switch(
    test$pick,
    any = sprintf(paste("CASE WHEN MAX(%1$s) = 1 THEN 1 WHEN COUNT(*) > 0 AND",
                        "COUNT(%1$s) = COUNT(*) THEN 0 END"), met),
    all = sprintf(paste("CASE WHEN MIN(%1$s) = 0 THEN 0 WHEN COUNT(*) > 0 AND",
                        "COUNT(%1$s) = COUNT(*) THEN 1 END"), met),
    nearest = .agree_sql(met)
  )
  sprintf("(SELECT %s FROM %s v WHERE %s)", agg, view_q, where)
}

.leaf_update_sql <- function(leaf, tmp, master_q, mrn_q, date_q, dialect) {
  sprintf("UPDATE %s SET %s = %s WHERE active = 1", tmp, leaf$col,
          .leaf_value_sql(leaf$test, tmp, master_q, mrn_q, date_q, dialect))
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::test(filter = "criteria-sql")'`
Expected: PASS.

If duckdb rejects `date + integer` or the correlated `UPDATE`, **stop and report**. Both
were checked on duckdb 2.0.0 when this plan was written. Do not rewrite the SQL into a
form SQL Server cannot run: the shapes here were chosen to run on both.

- [ ] **Step 6: Commit**

```bash
git add R/criteria_sql.R tests/testthat/helper-criteria.R tests/testthat/test-criteria-sql.R
git commit -m "feat: leaf SQL sets one criterion flag per test"
```

---

### Task 5: `cohort_query()` takes criteria and `index_on`

**Files:**
- Modify: `R/cohort_query.R`
- Test: `tests/testthat/test-cohort-query.R`

**Interfaces:**
- Consumes: Task 2's `cohort_criterion`.
- Produces: `cohort_query(qualifying, epoch, index, prior, criteria = list(),
  index_on = NULL)`, whose object has `criteria` (a list) and `index_on` (`NULL`,
  `"qualifying"` or `"eligible"`). Without criteria the object is as before, plus
  `criteria = list()` and `index_on = NULL`.

- [ ] **Step 1: Write the failing tests** (append to `test-cohort-query.R`)

```r
# No PHI: values are invented.
crit_a <- function(id = "a", kind = "warehouse") {
  switch(kind,
         warehouse = criterion(id, "A", "include", master_row("age >= 18"), "exclude"),
         review = review_criterion(id, "R", "exclude"))
}
ep <- as.Date(c("2019-10-01", "2026-01-31"))

test_that("criteria with index first need index_on stated", {
  expect_error(cohort_query("proc = 'CABG'", ep, criteria = list(crit_a())),
               class = "hvtiRdatabuild_criterion_argument", regexp = "`index_on` is required")
  q <- cohort_query("proc = 'CABG'", ep, criteria = list(crit_a()), index_on = "eligible")
  expect_identical(q$index_on, "eligible")
  expect_error(cohort_query("proc = 'CABG'", ep, index = "all",
                            criteria = list(crit_a()), index_on = "eligible"),
               "only with index = \"first\"")
  expect_error(cohort_query("proc = 'CABG'", ep, index_on = "qualifying"),
               "only with index = \"first\"")
})

test_that("criteria must be criteria, with unique ids, grouped by kind", {
  expect_error(cohort_query("proc = 'CABG'", ep, criteria = list("age >= 18"),
                            index_on = "qualifying"),
               "must be a list of criteria")
  expect_error(cohort_query("proc = 'CABG'", ep, criteria = list(crit_a(), crit_a()),
                            index_on = "qualifying"),
               "ids must be unique")
  expect_error(cohort_query("proc = 'CABG'", ep,
                            criteria = list(crit_a("r", "review"), crit_a()),
                            index_on = "qualifying"),
               "warehouse criteria first, then local, then review")
})

test_that("a query without criteria is unchanged", {
  q <- cohort_query("proc = 'CABG'", ep)
  expect_identical(q$criteria, list())
  expect_null(q$index_on)
  expect_output(print(cohort_query("proc = 'CABG'", ep, criteria = list(crit_a()),
                                   index_on = "qualifying")),
                "a \\[include, warehouse\\]")
})
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "cohort-query")'`
Expected: FAIL with `unused argument (criteria = ...)`.

- [ ] **Step 3: Implement**

Change the signature and add validation before `structure(...)` in `R/cohort_query.R`:

```r
cohort_query <- function(qualifying, epoch, index = c("first", "all"),
                         prior = c("keep", "exclude"), criteria = list(),
                         index_on = NULL) {
```

```r
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
```

and add `criteria = criteria, index_on = index_on` to the `structure(list(...))`.

Roxygen to add:

```r
#' @param criteria A list of criteria from [criterion()], [local_criterion()] and
#'   [review_criterion()], in the order they run: warehouse criteria, then local, then
#'   review. Each becomes a counted cohort stage; see [criterion()].
#' @param index_on With `index = "first"` and criteria, which encounter is the index:
#'   `"qualifying"` takes each patient's first qualifying encounter and then applies the
#'   criteria, so a patient excluded there is out; `"eligible"` applies the criteria to
#'   every qualifying encounter and takes each patient's first that survives. The two give
#'   different cohorts, so there is no default. Leave `NULL` otherwise.
```

In the `@details` paragraph, add: "Criteria are evaluated in the warehouse, in the pull's
transaction; see [criterion()]."

Extend `print.cohort_query`, after the existing lines:

```r
  if (length(x$criteria)) {
    if (!is.null(x$index_on)) cat("  index on: ", x$index_on, "\n", sep = "")
    for (cr in x$criteria) cat("  ", .describe_criterion(cr), "\n", sep = "")
  }
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "cohort-query|master-pull")'`
Expected: PASS, including every existing `master-pull` test.

- [ ] **Step 5: Commit**

```bash
git add R/cohort_query.R tests/testthat/test-cohort-query.R man/
git commit -m "feat: cohort_query() takes criteria and a declared index_on"
```

---

### Task 6: `pull_master()` evaluates warehouse criteria in the transaction

**Files:**
- Modify: `R/master_pull.R`
- Modify: `R/criteria_sql.R` (append `.first_eligible_sql()`)
- Modify: `R/cohort_criteria.R` (append `.criteria_stages()`)
- Test: `tests/testthat/test-master-criteria.R`

**Interfaces:**
- Consumes: Tasks 3–5.
- Produces:
  - `.cohort_temp(dialect, n_flags = 0L)`: as before, plus `active` (default 1) and
    `crit_1..crit_n`.
  - `.criteria_stages(record, compiled, selected, query)` → `list(cohort, queue)`, where
    `queue` is a data frame of `cohort_unit` and `criterion_id`.
  - `pull_master()` returns, in addition: `meta$status` (`"complete"` or
    `"awaiting review"`), `meta$review_decisions_sha256` (`NA`), `meta$cohort_definition`
    with `criteria` and `index_on`, and `pull$review` (`queue`, `criteria`: a data frame
    of `criterion_id`, `label`, `role`, `kind`).

- [ ] **Step 1: Write the failing tests** `tests/testthat/test-master-criteria.R`

```r
# No PHI: identifiers and values are invented. Fixtures in helper-master-pull.R and
# helper-criteria.R.

lvef_25 <- criterion("lvef", "LVEF 25% or less within 30 days", "include",
                     view_rows("echo_demo", "measured_on", c(-30, 0), "nearest",
                               "lvef <= 25"),
                     undetermined = "exclude")
inotrope <- criterion("inotrope", "Inotrope within 72 hours", "exclude",
                      view_rows("med_demo", "given_at", c(-3, 0), "any",
                                "drug_class = 'inotrope'"),
                      undetermined = "keep")
criteria_db <- function(env = parent.frame()) {
  con <- local_master_db(env)
  seed_criteria_views(con)
}

test_that("each criterion is a counted stage, in declared order", {
  con <- criteria_db()
  res <- pull_demo(con, demo_query(criteria = list(lvef_25), index_on = "qualifying"))
  s <- cohort_summary(res$cohort)$stages
  expect_identical(s$stage_id, c("qualifying", "prior_qualifying", "lvef", "in_master"))
  expect_identical(res$data$cohort_unit, "SYN101|2010-03-01")
  expect_identical(res$meta$status, "complete")
  expect_identical(res$cohort$stages$source[3], "upstream")
  expect_match(res$cohort$stages$provenance[3], "met 1, not met 0, undetermined 2")
})

test_that("an exclusion keeps undetermined units when told to", {
  con <- criteria_db()
  res <- pull_demo(con, demo_query(criteria = list(inotrope), index_on = "qualifying"))
  # SYN101 and SYN103 had an inotrope in the window; SYN104 had none in it.
  expect_identical(res$data$cohort_unit, "SYN104|2020-01-10")
  excluded <- res$cohort$members[res$cohort$members$stage_id == "inotrope" &
                                   !res$cohort$members$included, ]
  expect_setequal(excluded$reason, "excluded: Inotrope within 72 hours")
})

test_that("index_on decides whether a later encounter can be the index", {
  con <- criteria_db()
  DBI::dbExecute(con, second_cabg)
  on_qualifying <- pull_demo(con, demo_query(criteria = list(inotrope),
                                             index_on = "qualifying"))
  on_eligible <- pull_demo(con, demo_query(criteria = list(inotrope),
                                           index_on = "eligible"))
  expect_false(any(grepl("^SYN103", on_qualifying$data$cohort_unit)))
  expect_true("SYN103|2018-02-02" %in% on_eligible$data$cohort_unit)
  expect_identical(cohort_summary(on_eligible$cohort)$stages$stage_id,
                   c("qualifying", "prior_qualifying", "inotrope", "index_eligible",
                     "in_master"))
})

test_that("undetermined units routed to review leave the pull awaiting review", {
  con <- criteria_db()
  routed <- criterion("lvef", "LVEF 25% or less", "include",
                      view_rows("echo_demo", "measured_on", c(-30, 0), "nearest",
                                "lvef <= 25"),
                      undetermined = "review")
  res <- pull_demo(con, demo_query(criteria = list(routed), index_on = "qualifying"))
  expect_identical(res$meta$status, "awaiting review")
  expect_setequal(res$review$queue$cohort_unit,
                  c("SYN103|2015-06-30", "SYN104|2020-01-10"))
  expect_identical(nrow(res$data), 3L)
})

test_that("only keys and flags leave the database during selection", {
  con <- criteria_db()
  seen <- character()
  real <- DBI::dbGetQuery
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      seen <<- c(seen, statement)
      real(conn, statement, ...)
    },
    .package = "DBI"
  )
  pull_demo(con, demo_query(criteria = list(lvef_25, inotrope), index_on = "qualifying"))
  expect_false(any(grepl("echo_demo|med_demo", seen)))
})

test_that("a pull without criteria is unchanged", {
  con <- criteria_db()
  res <- pull_demo(con, demo_query())
  expect_identical(cohort_summary(res$cohort)$stages$stage_id,
                   c("qualifying", "prior_qualifying", "in_master"))
  expect_identical(res$meta$status, "complete")
})
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "master-criteria")'`
Expected: FAIL. With no criteria evaluation the `lvef` stage is missing.

- [ ] **Step 3: `.first_eligible_sql()`** (append to `R/criteria_sql.R`)

```r
# Keep each patient's earliest still-active encounter.
.first_eligible_sql <- function(tmp) {
  sprintf(paste("UPDATE %1$s SET active = 0 WHERE active = 1 AND EXISTS (SELECT 1 FROM",
                "%1$s e WHERE e.mrn = %1$s.mrn AND e.active = 1 AND",
                "e.encounter_date < %1$s.encounter_date)"), tmp)
}
```

- [ ] **Step 4: `.criteria_stages()`** (append to `R/cohort_criteria.R`)

```r
# Rebuild the warehouse criteria stages from the flags read back, then the
# index_eligible stage. Returns the record and the units routed to review.
.criteria_stages <- function(record, compiled, selected, query) {
  units <- cohort_unit_id(as.character(selected$mrn), as.Date(selected$encounter_date))
  queue <- data.frame(cohort_unit = character(), criterion_id = character(),
                      stringsAsFactors = FALSE)
  add_stage <- function(record, id, label, provenance, active, out) {
    append_cohort_stage(
      record,
      data.frame(stage_id = id, order = max(record$stages$order) + 1L, label = label,
                 source = "upstream", provenance = provenance, stringsAsFactors = FALSE),
      data.frame(patient_id = active, included = out$included, reason = out$reason,
                 stringsAsFactors = FALSE)
    )
  }
  for (st in compiled$stages) {
    active <- .active_units(record)
    s <- .eval_node(st$node, selected[match(active, units), , drop = FALSE])
    out <- .stage_outcome(st$role, st$undetermined, s, st$label)
    prov <- sprintf("%s; met %d, not met %d, undetermined %d", .describe_criterion(st),
                    sum(s %in% 1L), sum(s %in% 0L), sum(is.na(s)))
    record <- add_stage(record, st$id, st$label, prov, active, out)
    if (any(out$review)) {
      queue <- rbind(queue, data.frame(cohort_unit = active[out$review],
                                       criterion_id = st$id, stringsAsFactors = FALSE))
    }
  }
  if (identical(query$index_on, "eligible")) {
    active <- .active_units(record)
    parts <- split_cohort_unit(active)
    ord <- order(parts$mrn, parts$encounter_date)
    first <- logical(length(active))
    first[ord] <- !duplicated(parts$mrn[ord])
    out <- list(included = first,
                reason = ifelse(first, NA_character_,
                                "a later eligible encounter; the first is the index"))
    record <- add_stage(record, "index_eligible", "First eligible encounter per patient",
                        sprintf("%d later eligible encounter(s) set aside", sum(!first)),
                        active, out)
  }
  list(cohort = record, queue = queue)
}
```

- [ ] **Step 5: Change `R/master_pull.R`**

5a. Replace `.cohort_temp()`:

```r
.cohort_temp <- function(dialect, n_flags = 0L) {
  flag_cols <- function(type) {
    if (!n_flags) return("")
    paste0(", crit_", seq_len(n_flags), " ", type, collapse = "")
  }
  switch(dialect,
         mssql = list(
           name = "#study_cohort",
           create = paste0("CREATE TABLE #study_cohort (mrn nvarchar(128) NOT NULL, ",
                           "encounter_date date NOT NULL, prior_qualifying tinyint NOT ",
                           "NULL, active tinyint NOT NULL DEFAULT 1",
                           flag_cols("tinyint NULL"), ")")
         ),
         duckdb = list(
           name = "study_cohort",
           create = paste0("CREATE TEMP TABLE study_cohort (mrn VARCHAR NOT NULL, ",
                           "encounter_date DATE NOT NULL, prior_qualifying TINYINT NOT ",
                           "NULL, active TINYINT NOT NULL DEFAULT 1",
                           flag_cols("TINYINT"), ")")
         ))
}
```

5b. In `.select_units_sql()`, replace the last line

```r
    if (identical(query$index, "first")) "WHERE q.rn = 1" else ""
```

with

```r
    if (identical(query$index, "first") && !identical(query$index_on, "eligible")) {
      "WHERE q.rn = 1"
    } else {
      ""
    }
```

5c. In `pull_master()`, after `supplied <- ...`, compile:

```r
  compiled <- .compile_criteria(if (is_query) cohort$criteria else list())
```

Replace `tmp <- .cohort_temp(dialect)` with `tmp <- .cohort_temp(dialect, compiled$n_flags)`.

Replace the two prior-only join conditions with one rule, since `active` now carries
every exclusion:

```r
  join_sql <- sprintf("m.%s = c.mrn AND m.%s = c.encounter_date AND c.active = 1",
                      q(mrn_col), q(date_col))
```

(delete the `if (is_query && identical(cohort$prior, "exclude"))` block after it), and

```r
    applied_join <- "a.mrn = c.mrn AND a.encounter_date = c.encounter_date AND c.active = 1"
```

(delete its `if` block too).

5d. Inside the transaction, in the `if (is_query)` branch, replace the "read cohort keys"
query and keep the empty-epoch check:

```r
      if (identical(cohort$prior, "exclude")) {
        run_step("set aside earlier-qualifying units", DBI::dbExecute(
          con, paste("UPDATE", tmp$name, "SET active = 0 WHERE prior_qualifying = 1")
        ))
      }
      for (st in compiled$stages) {
        for (leaf in .node_leaves(st$node)) {
          run_step(paste("evaluate criterion", st$id), DBI::dbExecute(
            con, .leaf_update_sql(leaf, tmp$name, master_q, q(mrn_col), q(date_col),
                                  dialect)
          ))
        }
        run_step(paste("apply criterion", st$id),
                 DBI::dbExecute(con, .deactivate_sql(tmp$name, st)))
      }
      if (identical(cohort$index_on, "eligible")) {
        run_step("keep first eligible encounter",
                 DBI::dbExecute(con, .first_eligible_sql(tmp$name)))
      }
      flag_sql <- if (compiled$n_flags) {
        paste0(", crit_", seq_len(compiled$n_flags), collapse = "")
      } else {
        ""
      }
      selected <- run_step("read cohort keys and flags", DBI::dbGetQuery(
        con, paste0("SELECT mrn, encounter_date, prior_qualifying, active", flag_sql,
                    " FROM ", tmp$name)
      ))
```

5e. After the transaction, replace

```r
  base <- if (is_query) .query_cohort(cohort, read$selected, master, read$commit) else cohort
```

with

```r
  queue <- data.frame(cohort_unit = character(), criterion_id = character(),
                      stringsAsFactors = FALSE)
  if (is_query) {
    staged <- .criteria_stages(.query_cohort(cohort, read$selected, master, read$commit),
                               compiled, read$selected, cohort)
    base <- staged$cohort
    queue <- staged$queue
    sql_active <- cohort_unit_id(as.character(read$selected$mrn),
                                 as.Date(read$selected$encounter_date))[
                                   read$selected$active == 1L]
    if (!setequal(sql_active, .active_units(base))) {
      .abort("criteria_disagree",
             "pull_master(): the warehouse and R disagree on the active cohort (",
             length(setdiff(sql_active, .active_units(base))), " and ",
             length(setdiff(.active_units(base), sql_active)), " unit(s)). This is a ",
             "package defect; nothing was pulled.")
    }
  } else {
    base <- cohort
  }
```

`.query_cohort()` excludes prior-qualifying units already, so with no criteria the check
compares the same set it always did.

5f. After `data <- read$data[...]` and before `fields <- list(`, add:

```r
  final_active <- .active_units(final)
  queue <- queue[queue$cohort_unit %in% final_active, , drop = FALSE]
  criteria <- if (is_query) cohort$criteria else list()
  has_review <- any(vapply(criteria, function(cr) identical(cr$kind, "review"),
                           logical(1)))
  status <- if (nrow(queue) || (has_review && length(final_active))) {
    "awaiting review"
  } else {
    "complete"
  }
```

5g. In `fields`, change the query branch of `cohort_definition` to

```r
      list(qualifying = cohort$qualifying, epoch = format(cohort$epoch),
           index = cohort$index, prior = cohort$prior, index_on = cohort$index_on,
           criteria = vapply(cohort$criteria, .describe_criterion, character(1)))
```

and append after `n_unmatched = sum(!found)`:

```r
    status = status,
    review_decisions_sha256 = NA_character_
```

5h. Return `review` in the object:

```r
  structure(list(
    data = data,
    cohort = final,
    meta = c(.provenance_record("pull_master"), fields),
    provenance = fields,
    review = list(
      queue = queue,
      criteria = data.frame(
        criterion_id = vapply(criteria, `[[`, character(1), "id"),
        label = vapply(criteria, `[[`, character(1), "label"),
        role = vapply(criteria, `[[`, character(1), "role"),
        kind = vapply(criteria, `[[`, character(1), "kind"),
        stringsAsFactors = FALSE
      )
    )
  ), class = "master_pull")
```

5i. Roxygen for `pull_master()`: under `@return`, add `status`, `review_decisions_sha256`,
and the `review` element. Add a paragraph: "A query's criteria are evaluated in the
warehouse, inside the same transaction: each sets a flag on the session cohort table, and
only the keys and flags are read back. The pull refuses itself if the stages R rebuilds
from the flags disagree with the warehouse."

`print.master_pull()` gains one line:

```r
  if (identical(p$status, "awaiting review")) {
    cat("  awaiting review: ", nrow(x$review$queue), " routed unit(s)\n", sep = "")
  }
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "master-")'`
Expected: PASS, including every plan-1 test in `test-master-pull.R`,
`test-master-build.R` and `test-master-freeze.R`.

If a plan-1 test fails because of the `c.active = 1` join, **stop and report**. The join
must give the same rows as before when there are no criteria.

- [ ] **Step 7: Commit**

```bash
git add R/master_pull.R R/criteria_sql.R R/cohort_criteria.R \
  tests/testthat/test-master-criteria.R man/
git commit -m "feat: pull_master() evaluates criteria in the transaction"
```

---

### Task 7: Local criteria after the pull

**Files:**
- Modify: `R/cohort_criteria.R` (append `.local_stages()`)
- Modify: `R/master_pull.R`
- Test: `tests/testthat/test-master-criteria.R`

**Interfaces:**
- Consumes: Task 2's `local_criterion()`, Task 6's queue.
- Produces: `.local_stages(record, locals)` → `list(cohort, queue)`. In `pull_master()`,
  local stages follow `in_master`, with source `build`.

- [ ] **Step 1: Write the failing tests** (append)

```r
test_that("a local criterion runs on the surviving candidates and records the file", {
  con <- criteria_db()
  f <- withr::local_tempfile(fileext = ".csv")
  writeLines(c("mrn", "SYN104"), f)
  seen_n <- NULL
  covid <- local_criterion(
    "covid", "COVID-19 within 14 days", "exclude", f,
    decide = function(units, path) {
      seen_n <<- nrow(units)
      units$mrn %in% utils::read.csv(path)$mrn
    },
    undetermined = "keep"
  )
  res <- pull_demo(con, demo_query(criteria = list(inotrope, covid),
                                   index_on = "qualifying"))
  expect_identical(seen_n, 1L)
  expect_identical(nrow(res$data), 0L)
  s <- res$cohort$stages
  expect_identical(utils::tail(s$stage_id, 1L), "covid")
  expect_identical(utils::tail(s$source, 1L), "build")
  expect_match(utils::tail(s$provenance, 1L), covid$sha256, fixed = TRUE)
})

test_that("a local criterion must return one decision per unit", {
  con <- criteria_db()
  f <- withr::local_tempfile(fileext = ".csv")
  writeLines("mrn", f)
  bad <- local_criterion("bad", "Bad", "exclude", f,
                         decide = function(units, path) TRUE, undetermined = "keep")
  expect_error(pull_demo(con, demo_query(criteria = list(bad), index_on = "qualifying")),
               class = "hvtiRdatabuild_local_criterion",
               regexp = "returned 1 value\\(s\\) for 3 unit\\(s\\)")
})
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "master-criteria")'`
Expected: FAIL. The `covid` stage is missing.

- [ ] **Step 3: `.local_stages()`** (append to `R/cohort_criteria.R`)

```r
.local_stages <- function(record, locals) {
  queue <- data.frame(cohort_unit = character(), criterion_id = character(),
                      stringsAsFactors = FALSE)
  for (cr in locals) {
    active <- .active_units(record)
    keys <- split_cohort_unit(active)
    units <- data.frame(cohort_unit = active, mrn = keys$mrn,
                        encounter_date = keys$encounter_date, stringsAsFactors = FALSE)
    met <- cr$decide(units, cr$path)
    if (!is.logical(met) || length(met) != length(active)) {
      .abort("local_criterion", "pull_master(): local criterion \"", cr$id,
             "\" returned ", length(met), " value(s) for ", length(active),
             " unit(s); it must return one logical per unit.")
    }
    s <- ifelse(is.na(met), NA_integer_, as.integer(met))
    out <- .stage_outcome(cr$role, cr$undetermined, s, cr$label)
    prov <- sprintf("%s; met %d, not met %d, undetermined %d; after the snapshot",
                    .describe_criterion(cr), sum(s %in% 1L), sum(s %in% 0L),
                    sum(is.na(s)))
    record <- append_cohort_stage(
      record,
      data.frame(stage_id = cr$id, order = max(record$stages$order) + 1L,
                 label = cr$label, source = "build", provenance = prov,
                 stringsAsFactors = FALSE),
      data.frame(patient_id = active, included = out$included, reason = out$reason,
                 stringsAsFactors = FALSE)
    )
    if (any(out$review)) {
      queue <- rbind(queue, data.frame(cohort_unit = active[out$review],
                                       criterion_id = cr$id, stringsAsFactors = FALSE))
    }
  }
  list(cohort = record, queue = queue)
}
```

- [ ] **Step 4: Wire it into `pull_master()`**

Immediately after `final <- append_cohort_stage(base, ...)` (the `in_master` stage), and
before `data <- read$data[...]`:

```r
  locals <- Filter(function(cr) identical(cr$kind, "local"),
                   if (is_query) cohort$criteria else list())
  if (length(locals)) {
    local_out <- .local_stages(final, locals)
    final <- local_out$cohort
    queue <- rbind(queue, local_out$queue)
  }
```

Then change the data filter from `active[found]` to the final active set:

```r
  data <- read$data[read$data$cohort_unit %in% .active_units(final), , drop = FALSE]
```

`n_matched` and `n_unmatched` keep their in-master meaning. They are computed from
`found` before this point, so leave them.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::test(filter = "master-")'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add R/cohort_criteria.R R/master_pull.R tests/testthat/test-master-criteria.R
git commit -m "feat: local criteria run in R after the snapshot, with the file checksum"
```

---

### Task 8: Chart review: `review_list()`, `apply_review()`, and the guards

**Files:**
- Create: `R/master_review.R`
- Modify: `R/master_build.R`, `R/master_freeze.R`
- Test: `tests/testthat/test-master-review.R`

**Interfaces:**
- Consumes: Task 6's `pull$review` and `meta$status`.
- Produces:
  - `review_list(pull)` → a data frame of `cohort_unit` and `criterion_id`: every routed
    unit, plus every final active unit for each review criterion.
  - `apply_review(pull, path, reason_codes)` → the `master_pull` with `review`-source
    stages appended, `data` filtered, `meta$status = "complete"` and
    `meta$review_decisions_sha256` set.
  - `build_from_master()` and `freeze_study_pull()` refuse with class
    `hvtiRdatabuild_awaiting_review`.

- [ ] **Step 1: Write the failing tests** `tests/testthat/test-master-review.R`

```r
# No PHI: identifiers, values and decisions are invented.

review_pull <- function(env = parent.frame()) {
  con <- local_master_db(env)
  seed_criteria_views(con)
  routed <- criterion("lvef", "LVEF 25% or less", "include",
                      view_rows("echo_demo", "measured_on", c(-30, 0), "nearest",
                                "lvef <= 25"),
                      undetermined = "review")
  strategy <- review_criterion("strategy", "Planned alternative support", "exclude")
  pull_demo(con, demo_query(criteria = list(routed, strategy), index_on = "qualifying"))
}

write_decisions <- function(rows) {
  f <- withr::local_tempfile(fileext = ".csv", .local_envir = parent.frame())
  utils::write.csv(rows, f, row.names = FALSE, na = "")
  f
}

test_that("the review list holds routed units and every unit for review criteria", {
  pull <- review_pull()
  rl <- review_list(pull)
  expect_identical(nrow(rl), 5L)
  expect_identical(sum(rl$criterion_id == "lvef"), 2L)
  expect_identical(sum(rl$criterion_id == "strategy"), 3L)
})

test_that("a pull awaiting review cannot be built or frozen", {
  pull <- review_pull()
  expect_error(build_from_master(pull), class = "hvtiRdatabuild_awaiting_review")
  expect_error(freeze_study_pull(pull, demo_config, tempdir(), "x", Sys.Date()),
               class = "hvtiRdatabuild_awaiting_review")
})

test_that("decisions are applied as review stages, with the file checksum", {
  pull <- review_pull()
  rl <- review_list(pull)
  rl$outcome <- "not_met"
  rl$reason_code <- NA_character_
  # SYN103's tied echoes: the reviewer finds LVEF 20 is the valid study.
  rl$outcome[rl$criterion_id == "lvef" & grepl("^SYN103", rl$cohort_unit)] <- "met"
  rl$reason_code[rl$criterion_id == "lvef" & grepl("^SYN104", rl$cohort_unit)] <- "NO_ECHO"
  f <- write_decisions(rl)
  out <- apply_review(pull, f, reason_codes = c("NO_ECHO", "PLANNED"))
  expect_identical(out$meta$status, "complete")
  expect_identical(out$meta$review_decisions_sha256,
                   digest::digest(f, algo = "sha256", file = TRUE))
  s <- out$cohort$stages
  expect_identical(utils::tail(s$stage_id, 2L), c("review_undetermined", "strategy"))
  expect_true(all(utils::tail(s$source, 2L) == "review"))
  expect_setequal(out$data$cohort_unit, c("SYN101|2010-03-01", "SYN103|2015-06-30"))
  expect_s3_class(build_from_master(out), "build_result")
})

test_that("decisions must answer exactly the review list, with declared reasons", {
  pull <- review_pull()
  rl <- review_list(pull)
  rl$outcome <- "not_met"
  rl$reason_code <- NA_character_
  expect_error(apply_review(pull, write_decisions(rl[-1, ]), "X"),
               class = "hvtiRdatabuild_review", regexp = "1 decision\\(s\\) missing")
  rl$reason_code[rl$criterion_id == "lvef"] <- "MADE_UP"
  expect_error(apply_review(pull, write_decisions(rl), "NO_ECHO"),
               "reason code not in `reason_codes`")
  rl$reason_code <- NA_character_
  expect_error(apply_review(pull, write_decisions(rl), "NO_ECHO"),
               "an exclusion needs a reason code")
})
```

The last case works as follows: the two `lvef` rows are `not_met` on an include
criterion, so they are exclusions and need a code.

- [ ] **Step 2: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "master-review")'`
Expected: FAIL with `could not find function "review_list"`.

- [ ] **Step 3: Create `R/master_review.R`**

```r
# master_review.R
#
# Chart review of a master pull: the units and criteria that need a person, and the
# decisions file that settles them. Spec: dev/specs/2026-11-16-cohort-criteria-addendum.md
# §3.5.

#' List what a pull needs decided at chart review
#'
#' Every unit a criterion routed to review (`undetermined = "review"`), and every unit
#' still in the cohort for each [review_criterion()]. The list holds unit identifiers. Keep
#' it with the study's other restricted files, and never print it to a shared log.
#'
#' @param pull A `master_pull` from [pull_master()].
#'
#' @return A data frame with `cohort_unit` and `criterion_id`.
#'
#' @seealso [apply_review()]
#'
#' @export
review_list <- function(pull) {
  if (!inherits(pull, "master_pull")) {
    .abort("review", "review_list(): `pull` must be a master_pull from pull_master().")
  }
  rv <- pull$review
  if (is.null(rv)) {
    return(data.frame(cohort_unit = character(), criterion_id = character(),
                      stringsAsFactors = FALSE))
  }
  review_ids <- rv$criteria$criterion_id[rv$criteria$kind == "review"]
  active <- .active_units(pull$cohort)
  rbind(
    rv$queue,
    data.frame(cohort_unit = rep(active, times = length(review_ids)),
               criterion_id = rep(review_ids, each = length(active)),
               stringsAsFactors = FALSE)
  )
}

#' Record chart-review decisions on a pull
#'
#' Reads a decisions file with one row per entry of [review_list()]: `cohort_unit`,
#' `criterion_id`, `outcome` (`"met"` or `"not_met"`) and `reason_code`. An outcome that
#' excludes the unit (not met on an include criterion, or met on an exclude criterion)
#' needs a code from `reason_codes`. Codes, never free text: chart notes are PHI.
#'
#' Routed units are decided in one `review_undetermined` stage, then each review criterion
#' is its own stage, all with source `review`. The file's SHA-256 is recorded in the
#' pull's metadata, and the pull is then complete.
#'
#' @param pull A `master_pull` awaiting review.
#' @param path Character. The decisions file, as CSV.
#' @param reason_codes Character. The study's declared reason codes.
#'
#' @return The `master_pull`, with the review stages appended and `data` filtered.
#'
#' @seealso [review_list()], [review_criterion()]
#'
#' @export
apply_review <- function(pull, path, reason_codes) {
  if (!inherits(pull, "master_pull")) {
    .abort("review", "apply_review(): `pull` must be a master_pull from pull_master().")
  }
  if (!identical(.pull_meta(pull)$status, "awaiting review")) {
    .abort("review", "apply_review(): this pull is not awaiting review.")
  }
  if (!.one_string(path) || !file.exists(path)) {
    .abort("review", "apply_review(): `path` must be an existing decisions file.")
  }
  if (!is.character(reason_codes) || !length(reason_codes) || anyNA(reason_codes)) {
    .abort("review", "apply_review(): `reason_codes` must name the study's codes.")
  }
  dec <- utils::read.csv(path, colClasses = "character", na.strings = "")
  if (!all(c("cohort_unit", "criterion_id", "outcome", "reason_code") %in% names(dec))) {
    .abort("review", "apply_review(): the decisions file needs cohort_unit, ",
           "criterion_id, outcome and reason_code.")
  }
  wanted <- review_list(pull)
  key <- paste(dec$cohort_unit, dec$criterion_id, sep = "\r")
  want_key <- paste(wanted$cohort_unit, wanted$criterion_id, sep = "\r")
  if (anyDuplicated(key)) {
    .abort("review", "apply_review(): ", sum(duplicated(key)), " duplicate decision(s).")
  }
  if (!setequal(key, want_key)) {
    .abort("review", "apply_review(): ", length(setdiff(want_key, key)),
           " decision(s) missing and ", length(setdiff(key, want_key)),
           " not asked for.")
  }
  if (any(!dec$outcome %in% c("met", "not_met"))) {
    .abort("review", "apply_review(): every outcome must be \"met\" or \"not_met\".")
  }
  crit <- pull$review$criteria
  role <- crit$role[match(dec$criterion_id, crit$criterion_id)]
  excludes <- (role == "include" & dec$outcome == "not_met") |
    (role == "exclude" & dec$outcome == "met")
  if (any(excludes & is.na(dec$reason_code))) {
    .abort("review", "apply_review(): ", sum(excludes & is.na(dec$reason_code)),
           " decision(s) exclude a unit without a code; an exclusion needs a reason code.")
  }
  if (any(!is.na(dec$reason_code) & !dec$reason_code %in% reason_codes)) {
    .abort("review", "apply_review(): ",
           sum(!is.na(dec$reason_code) & !dec$reason_code %in% reason_codes),
           " decision(s) use a reason code not in `reason_codes`.")
  }
  sha <- digest::digest(path, algo = "sha256", file = TRUE)
  label <- crit$label[match(dec$criterion_id, crit$criterion_id)]
  dec$reason <- ifelse(excludes, paste0(label, " at review: ", dec$reason_code),
                       NA_character_)
  review_stage <- function(record, id, stage_label, rows) {
    active <- .active_units(record)
    hit <- rows[rows$cohort_unit %in% active & !is.na(rows$reason), , drop = FALSE]
    hit <- hit[!duplicated(hit$cohort_unit), , drop = FALSE]
    out <- !active %in% hit$cohort_unit
    append_cohort_stage(
      record,
      data.frame(stage_id = id, order = max(record$stages$order) + 1L,
                 label = stage_label, source = "review",
                 provenance = sprintf("decisions file sha256 %s; %d decided", sha,
                                      nrow(rows)),
                 stringsAsFactors = FALSE),
      data.frame(patient_id = active, included = out,
                 reason = ifelse(out, NA_character_,
                                 hit$reason[match(active, hit$cohort_unit)]),
                 stringsAsFactors = FALSE)
    )
  }
  record <- pull$cohort
  routed <- dec[dec$criterion_id %in% pull$review$queue$criterion_id &
                  key %in% paste(pull$review$queue$cohort_unit,
                                 pull$review$queue$criterion_id, sep = "\r"), ]
  if (nrow(routed)) {
    record <- review_stage(record, "review_undetermined",
                           "Undetermined at a criterion, decided at chart review", routed)
  }
  for (i in which(crit$kind == "review")) {
    rows <- dec[dec$criterion_id == crit$criterion_id[[i]], , drop = FALSE]
    record <- review_stage(record, crit$criterion_id[[i]], crit$label[[i]], rows)
  }
  pull$cohort <- record
  pull$data <- pull$data[pull$data$cohort_unit %in% .active_units(record), , drop = FALSE]
  row.names(pull$data) <- NULL
  for (el in c("meta", "provenance")) {
    if (!is.null(pull[[el]])) {
      pull[[el]]$status <- "complete"
      pull[[el]]$review_decisions_sha256 <- sha
    }
  }
  pull
}
```

- [ ] **Step 4: The guards**

In `build_from_master()` and in `freeze_study_pull()`, right after the `inherits(pull,
"master_pull")` check, add (with the function's own name in the prefix):

```r
  if (identical(.pull_meta(pull)$status, "awaiting review")) {
    .abort("awaiting_review", "build_from_master(): this pull is awaiting chart review; ",
           "record the decisions with apply_review() first.")
  }
```

Add one sentence to each function's roxygen: "A pull awaiting chart review is refused."

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "master-")'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add R/master_review.R R/master_build.R R/master_freeze.R \
  tests/testthat/test-master-review.R NAMESPACE man/
git commit -m "feat: chart review stages from a decisions file; builds wait for review"
```

---

### Task 9: Reference index, news, and the full gate

**Files:**
- Modify: `_pkgdown.yml`
- Create: `news/feat-cohort-criteria.md`

- [ ] **Step 1: `_pkgdown.yml`.** After the "Pull: Master views to a study" group, add:

```yaml
- title: "Pull: Cohort criteria"
  desc: >
    Declare inclusion and exclusion criteria for a cohort query. Each is evaluated in
    the warehouse inside the pull, counted as its own stage, and states every clinical
    choice itself.
  contents:
  - criterion
  - master_row
  - view_rows
  - any_of
  - local_criterion
  - review_criterion
  - review_list
  - apply_review
```

(`all_of` shares the `any_of` page through `@rdname`.)

- [ ] **Step 2: The news fragment** `news/feat-cohort-criteria.md`

```markdown
* `cohort_query()` takes `criteria`: inclusion and exclusion criteria evaluated in the
  warehouse inside `pull_master()`'s transaction, each a counted cohort stage. A
  criterion (`criterion()`) wraps a test: `master_row()`, `view_rows()` (rows of another
  view in a day window, judged by `pick = "any"`, `"all"` or `"nearest"`), or
  `any_of()` / `all_of()`. Only keys and flags leave the database.
* No clinical defaults: `role`, `undetermined`, `window`, `pick`, `date_col` and, with
  `index = "first"`, `index_on` are required. `index_on = "eligible"` lets a patient's
  later encounter be the index when an earlier one is excluded.
* A unit a criterion cannot decide follows its `undetermined` route: exclude, keep, or
  chart review. `review_criterion()`, `review_list()` and `apply_review()` record review
  decisions from a checksummed file with declared reason codes, as `review` stages.
  `build_from_master()` and `freeze_study_pull()` refuse a pull awaiting review.
* `local_criterion()` decides a criterion in R from a file outside the warehouse, after
  the snapshot, and records the file's SHA-256.
* `review` is a fourth cohort stage source.
```

- [ ] **Step 3: The full gate**

```bash
Rscript -e 'devtools::document()'
Rscript -e 'devtools::test()'
Rscript -e 'devtools::check()'
Rscript -e 'lintr::lint_package()'
Rscript -e 'pkgdown::check_pkgdown()'
```

Expected: tests pass with no new skips (confirm duckdb is installed:
`Rscript -e 'packageVersion("duckdb")'`); check 0/0/0; no lints; pkgdown clean.

- [ ] **Step 4: Commit**

```bash
git add _pkgdown.yml news/feat-cohort-criteria.md man/ NAMESPACE
git commit -m "docs: cohort criteria reference group and news"
```

---

## Not in this plan

- **SQL Server rehearsal.** Every statement is written for both dialects, but only duckdb
  runs them here. Before a study relies on this, run Task 4's and Task 6's tests against a
  SQL Server scratch database (plan 3, with data engineering). Error 8124 (an aggregate
  over an outer reference) is the known trap, avoided by design in Task 4.
- **Indexes on `(mrn, date)`** for the criteria views. Each leaf `UPDATE` runs one
  correlated subquery per active unit (plan 3).
- **Hour-level windows**, a shared criteria library, and reviewer tooling (addendum §7).
