# Study builds from master views: implementation plan (plan 1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a statistical programmer select a cohort and pull it from a master view in one
consistent read, build from it, and freeze the pull with its provenance.

**Architecture:** A cohort unit is an encounter, identified by `cohort_unit_id()`
(`"<mrn>|<YYYY-MM-DD>"`) and carried as the existing `cohort_record`'s `patient_id`.
`cohort_query()` is a definition with no database access. `pull_master()` takes either a
`cohort_query` or a supplied `cohort_record`, and **selects and reads inside one
snapshot-isolation transaction**: a query's epoch, index and earlier-encounter flag are
computed in SQL into a session temp table, so only the cohort's own keys leave the
database. `build_from_master()` turns the pull into the `build_result` that
`derive_vars()` already consumes. `freeze_study_pull()` publishes the pull as parquet with
its provenance **inside the file's own metadata**, so one checksummed artifact carries
both.

**Tech Stack:** R (>= 4.4.0), DBI, duckdb (tests), arrow (parquet), yaml, digest, testthat 3.

**Spec:** `dev/specs/2026-11-16-master-views-design.md`, §5 (study builds) and §6 (freeze
record). **Out of this plan:** §3 corrections intake and candidates, §3.3 generated views,
§7 parity gate (**plan 2**, hvtiRdatabuild), and the SQL model repository and warehouse
setup (**plan 3**, blocked on data engineering). This plan tests against duckdb only.

**Revised 2026-11-16 after the adversarial review on #105:** stage sources use the
constructor's `upstream`/`build` vocabulary; selection and pull share one transaction;
selection runs in the database; a master pull reaches `derive_vars()` through
`build_from_master()`; provenance lives inside the published bytes, so a release can never
exist without it, and a distinct pull with identical data is its own release.

## Global constraints

- Lines are **100 characters** (`.lintr`). Roxygen markdown is enabled.
- testthat **edition 3**; test files are `test-*.R` with a hyphen.
- **No PHI.** Every fixture is invented and says so ("No PHI: identifiers and values are
  invented."). **No identifier or data value appears in any error, warning, message or print
  output.** Counts and verdicts only.
- **DB errors are withheld:** wrap every DBI call in the existing `run_step(name, expr)`
  (`R/sql_dialect.R`), which replaces the driver message.
- **Cohort stage `source` is one of `"upstream"`, `"build"`, `"derive"`**
  (`R/cohort_record.R:270`). What a stage came from goes in its `provenance`.
- `arrow` and `duckdb` are **Suggests**: tests call `skip_if_not_installed()`, and runtime
  code that needs arrow checks `requireNamespace("arrow", quietly = TRUE)` and stops with a
  clear message.
- Dialects are exactly `"mssql"` and `"duckdb"`, as elsewhere (`quoter()`, `sql_types()`).
- **SQL stays in the shared subset** (`ROW_NUMBER() OVER`, `EXISTS`, `CASE`, `BETWEEN`,
  bound `?` parameters) so one statement runs on both dialects.
- **No version bump.** The implementation branch writes one news fragment,
  `news/<branch with / as ->.md`, bullets only, no heading (Task 7). This plan file is under
  `dev/`, which `.Rbuildignore` excludes, so the plan's own PR needs none.
- Done means `devtools::document()` run and committed, `devtools::test()` passing, and
  `devtools::check()` 0 errors, 0 warnings, 0 notes.

## Contracts this plan assumes from plan 3

The SQL model repository (plan 3) must provide these objects for every master. This plan's
tests build them in duckdb; the names are the contract.

| Object | Columns | Rows |
|---|---|---|
| `<master>` | at least the key columns (default `mrn`, `encounter_date`) and the study's columns | one per encounter |
| `<master>_corrections_applied` | `correction_id`, `mrn`, `encounter_date` | one per correction applied to that encounter's row |
| `<master>_deployment` | `sql_commit` | exactly one: the SQL model commit the views were deployed from |

⚠️ The spec (§6.1) names the applied-corrections view per source
(`stg_<source>_corrections_applied`). A study pull reads a master, not its sources, so the
master-keyed rollup above is what the pull needs. Plan 3 generates it from the per-source
views. **Record this as a one-line amendment to spec §6.1 in plan 3.**

## File structure

| File | Responsibility |
|---|---|
| `R/dataset_publication.R` (modify) | accept `.parquet` drafts |
| `R/cohort_unit.R` (new) | `cohort_unit_id()`, `split_cohort_unit()` |
| `R/cohort_query.R` (new) | `cohort_query()`, `print.cohort_query()` |
| `R/master_pull.R` (new) | transaction and SQL helpers, `pull_master()`, `print.master_pull()` |
| `R/master_build.R` (new) | `build_from_master()` |
| `R/master_freeze.R` (new) | `freeze_study_pull()`, `read_pull_provenance()` |
| `tests/testthat/helper-master-pull.R` (new) | duckdb master fixture, unit cohort fixture |
| `tests/testthat/test-cohort-unit.R`, `test-cohort-query.R`, `test-master-pull.R`, `test-master-build.R`, `test-master-freeze.R` (new) | tests |
| `tests/testthat/test-dataset-publication.R` (modify) | parquet publication test |
| `_pkgdown.yml` (modify) | new reference group |

---

### Task 1: `publish_dataset()` accepts parquet

**Files:**
- Modify: `R/dataset_publication.R` (the `supported` vector in
  `.publication_validate_request()`, about line 300; the roxygen paragraph listing formats,
  about line 484)
- Test: `tests/testthat/test-dataset-publication.R`

**Interfaces:**
- Consumes: `hvtiRutilities::read_clinical_data()`, which reads `.parquet` since
  hvtiRutilities 1.5.0 (the floor here is 1.5.20, so no floor change).
- Produces: `publish_dataset(draft = "<file>.parquet", ...)` returns a release whose `file`
  ends `.parquet`.

- [ ] **Step 1: Write the failing test.** Append to `tests/testthat/test-dataset-publication.R`:

```r
test_that("publish_dataset() publishes a parquet draft", {
  skip_if_not_installed("arrow")
  published <- withr::local_tempdir("published-")
  draft <- withr::local_tempfile(fileext = ".parquet")
  # No PHI: identifiers and values are invented.
  arrow::write_parquet(
    data.frame(synthetic_id = c("SYN001", "SYN002"), value = c(1, 2)),
    draft
  )

  release <- publish_dataset(draft, "example_pull", published,
                             extract_date = "2026-11-16")

  expect_identical(tools::file_ext(release$file), "parquet")
  expect_identical(release$n_rows, 2L)
  expect_identical(release$n_cols, 2L)
  expect_true(file.exists(file.path(published, release$file)))
})
```

- [ ] **Step 2: Run it and confirm it fails.**
  Run: `Rscript -e 'devtools::test(filter = "dataset-publication")'`
  Expected: FAIL with `Unsupported draft extension '.parquet'`.

- [ ] **Step 3: Implement.** In `.publication_validate_request()` change

```r
  supported <- c("sas7bdat", "csv", "xlsx", "xls", "rds")
```

to

```r
  supported <- c("sas7bdat", "csv", "xlsx", "xls", "rds", "parquet")
```

and in the `publish_dataset()` roxygen change

```r
#' [hvtiRutilities::read_clinical_data()]: `.sas7bdat`, `.csv`, `.xlsx`,
#' `.xls`, and `.rds`. This verifies that the release is readable and records
```

to

```r
#' [hvtiRutilities::read_clinical_data()]: `.sas7bdat`, `.csv`, `.xlsx`,
#' `.xls`, `.rds`, and `.parquet` (which needs the arrow package). This verifies
#' that the release is readable and records
```

- [ ] **Step 4: Run the tests.**
  Run: `Rscript -e 'devtools::document(); devtools::test(filter = "dataset-publication")'`
  Expected: all PASS, including the existing `"Unsupported"` test (a `.txt` draft).

- [ ] **Step 5: Commit.**

```bash
git add R/dataset_publication.R man/publish_dataset.Rd tests/testthat/test-dataset-publication.R
git commit -m "feat: publish_dataset() accepts parquet drafts"
```

---

### Task 2: cohort units keyed by MRN and encounter date

**Files:**
- Create: `R/cohort_unit.R`
- Test: `tests/testthat/test-cohort-unit.R`

**Interfaces:**
- Produces: `cohort_unit_id(mrn, encounter_date)` → character `"<mrn>|<YYYY-MM-DD>"`;
  `split_cohort_unit(unit)` → `data.frame(mrn = <chr>, encounter_date = <Date>)`.
  A cohort built on units uses `patient_id_col = "cohort_unit"`, and a pulled dataset carries
  a `cohort_unit` column, so `build_dataset()` joins on it unchanged.

- [ ] **Step 1: Write the failing tests.** Create `tests/testthat/test-cohort-unit.R`:

```r
# No PHI: identifiers and values are invented.

test_that("a patient with two encounters is two units", {
  units <- cohort_unit_id(c("SYN101", "SYN101"),
                          as.Date(c("2010-03-01", "2015-06-30")))
  expect_identical(units, c("SYN101|2010-03-01", "SYN101|2015-06-30"))
  expect_false(anyDuplicated(units) > 0L)
})

test_that("units split back into MRN and encounter date", {
  key <- split_cohort_unit(cohort_unit_id("SYN101", as.Date("2010-03-01")))
  expect_identical(key$mrn, "SYN101")
  expect_identical(key$encounter_date, as.Date("2010-03-01"))
})

test_that("an incomplete key is refused without echoing it", {
  expect_error(cohort_unit_id("SYN101", as.Date(NA)), "no missing values")
  expect_error(cohort_unit_id(NA_character_, as.Date("2010-03-01")), "no missing")
  expect_error(cohort_unit_id("SYN|101", as.Date("2010-03-01")), "must not contain")
  expect_error(cohort_unit_id("SYN101", "2010-03-01"), "Date vector")
  expect_error(cohort_unit_id(c("SYN101", "SYN102"), as.Date("2010-03-01")), "same length")
  err <- tryCatch(cohort_unit_id("SYN|101", as.Date("2010-03-01")),
                  error = conditionMessage)
  expect_false(grepl("SYN", err, fixed = TRUE))
})

test_that("a malformed unit is refused", {
  expect_error(split_cohort_unit("SYN101"), "cohort_unit_id")
  expect_error(split_cohort_unit("SYN101|not-a-date"), "cohort_unit_id")
  expect_error(split_cohort_unit(1), "cohort_unit_id")
})
```

- [ ] **Step 2: Run them and confirm they fail.**
  Run: `Rscript -e 'devtools::test(filter = "cohort-unit")'`
  Expected: FAIL, `could not find function "cohort_unit_id"`.

- [ ] **Step 3: Implement.** Create `R/cohort_unit.R`:

```r
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
  if (anyNA(dates) || !identical(format(dates, "%Y-%m-%d"), date_text)) {
    stop(malformed, call. = FALSE)
  }
  data.frame(mrn = mrn, encounter_date = dates, stringsAsFactors = FALSE)
}
```

- [ ] **Step 4: Run the tests.**
  Run: `Rscript -e 'devtools::document(); devtools::test(filter = "cohort-unit")'`
  Expected: all PASS.

- [ ] **Step 5: Commit.**

```bash
git add R/cohort_unit.R man/cohort_unit_id.Rd man/split_cohort_unit.Rd NAMESPACE \
  tests/testthat/test-cohort-unit.R
git commit -m "feat: cohort units keyed by MRN and encounter date"
```

---


### Task 3: `cohort_query()`, a cohort definition with no database access

**Files:**
- Create: `R/cohort_query.R`
- Test: `tests/testthat/test-cohort-query.R`

**Interfaces:**
- Produces: `cohort_query(qualifying, epoch, index = c("first", "all"),
  prior = c("keep", "exclude"))` → object of class `cohort_query`, a list with
  `qualifying` (chr), `epoch` (Date, length 2), `index` (chr), `prior` (chr).
  `print.cohort_query(x, ...)`.

- [ ] **Step 1: Write the failing tests.** Create `tests/testthat/test-cohort-query.R`:

```r
test_that("a cohort query records its definition", {
  q <- cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")))
  expect_s3_class(q, "cohort_query")
  expect_identical(q$index, "first")
  expect_identical(q$prior, "keep")
  expect_identical(q$epoch, as.Date(c("2000-01-01", "2024-07-31")))
})

test_that("a malformed query or epoch is refused", {
  epoch <- as.Date(c("2000-01-01", "2024-07-31"))
  expect_error(cohort_query("", epoch), "qualifying")
  expect_error(cohort_query(c("a", "b"), epoch), "qualifying")
  expect_error(cohort_query("proc = 'CABG'", rev(epoch)), "start")
  expect_error(cohort_query("proc = 'CABG'", "2000-01-01"), "two Dates")
  expect_error(cohort_query("proc = 'CABG'", epoch, index = "last"), "should be one of")
})

test_that("printing shows the definition", {
  out <- capture.output(print(cohort_query("proc = 'CABG'",
                                           as.Date(c("2000-01-01", "2024-07-31")),
                                           index = "all", prior = "exclude")))
  expect_true(any(grepl("proc = 'CABG'", out, fixed = TRUE)))
  expect_true(any(grepl("2000-01-01 to 2024-07-31", out, fixed = TRUE)))
  expect_true(any(grepl("index all", out, fixed = TRUE)))
})
```

- [ ] **Step 2: Run them and confirm they fail.**
  Run: `Rscript -e 'devtools::test(filter = "cohort-query")'`
  Expected: FAIL, `could not find function "cohort_query"`.

- [ ] **Step 3: Implement.** Create `R/cohort_query.R`:

```r
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
```

- [ ] **Step 4: Run the tests.**
  Run: `Rscript -e 'devtools::document(); devtools::test(filter = "cohort-query")'`
  Expected: all PASS.

- [ ] **Step 5: Commit.**

```bash
git add R/cohort_query.R man/cohort_query.Rd man/print.cohort_query.Rd NAMESPACE \
  tests/testthat/test-cohort-query.R
git commit -m "feat: cohort_query() defines a cohort by query, epoch and index"
```

---

### Task 4: `pull_master()`, selection and pull in one transaction

**Files:**
- Create: `R/master_pull.R`
- Create: `tests/testthat/helper-master-pull.R`
- Test: `tests/testthat/test-master-pull.R`

**Interfaces:**
- Consumes: `cohort_unit_id()`, `split_cohort_unit()` (Task 2); `cohort_query()` (Task 3);
  `quoter()`, `run_step()` (`R/sql_dialect.R`); `new_cohort_record()`,
  `append_cohort_stage()`, `cohort_summary()`.
- Produces:
  - `.with_snapshot_txn(con, dialect, code)`: runs `code` in one transaction (SQL Server:
    `SNAPSHOT` isolation), commits, and rolls back on error.
  - `.read_deployment(con, deployment_view, dialect)` → one `sql_commit` string.
  - `pull_master(con, master, cohort, columns, mrn_col = "mrn",
    date_col = "encounter_date", dialect = c("mssql", "duckdb"),
    applied_view = paste0(master, "_corrections_applied"),
    deployment_view = paste0(master, "_deployment"))`, where `cohort` is a `cohort_query`
    or a `cohort_record` built on units (`patient_id_col = "cohort_unit"`). Returns class
    `master_pull`: `list(data, cohort, provenance)`. `data` holds one row per active unit
    with the key columns, `columns` and `cohort_unit`. `cohort` is the cohort record
    with its stages: for a query, `qualifying` and `prior_qualifying`; always a final
    `in_master` stage, which excludes units with no master row. `provenance` is
    `list(master, sql_commit, applied_correction_ids, corrections_in_effect, read_at,
    columns, cohort_definition, n_cohort, n_matched, n_unmatched)`.
    `applied_correction_ids` are those applied to the cohort's own rows;
    `corrections_in_effect` is every correction id applied anywhere in the master in the
    same snapshot, so a correction that changed eligibility, or an earlier encounter's
    row, is on record too. Ids only; no row of the applied view leaves the database.
  - `print.master_pull(x, ...)` and `str.master_pull(object, ...)`, counts only.

- [ ] **Step 1: Write the test helper.** Create `tests/testthat/helper-master-pull.R`:

```r
# No PHI: identifiers and values are invented.

# One master and the two plan-3 contract views. SYN101 had a qualifying CABG in 1998,
# before the test epoch, and another in 2010.
seed_master <- function(con) {
  DBI::dbWriteTable(con, "master_demo", data.frame(
    mrn = c("SYN101", "SYN101", "SYN102", "SYN103", "SYN104"),
    encounter_date = as.Date(c("1998-05-01", "2010-03-01", "2012-07-15",
                               "2015-06-30", "2020-01-10")),
    proc = c("CABG", "CABG", "AVR", "CABG", "CABG"),
    age = c(50, 62, 70, 55, 66),
    stringsAsFactors = FALSE
  ))
  DBI::dbWriteTable(con, "master_demo_corrections_applied", data.frame(
    correction_id = c("C1", "C2"),
    mrn = c("SYN101", "SYN103"),
    encounter_date = as.Date(c("2010-03-01", "2015-06-30")),
    stringsAsFactors = FALSE
  ))
  DBI::dbWriteTable(con, "master_demo_deployment",
                    data.frame(sql_commit = "abc1234", stringsAsFactors = FALSE))
  invisible(con)
}

local_master_db <- function(env = parent.frame()) {
  testthat::skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
  seed_master(con)
}

demo_epoch <- as.Date(c("2000-01-01", "2024-07-31"))

demo_query <- function(...) cohort_query("proc = 'CABG'", demo_epoch, ...)

second_cabg <- "INSERT INTO master_demo VALUES ('SYN103', DATE '2018-02-02', 'CABG', 58)"

# A one-stage cohort of supplied encounter units.
unit_cohort <- function(mrn, dates) {
  units <- cohort_unit_id(mrn, as.Date(dates))
  new_cohort_record(
    members = data.frame(patient_id = units, stage_id = "supplied", included = TRUE,
                         reason = NA_character_, stringsAsFactors = FALSE),
    stages = data.frame(stage_id = "supplied", order = 1L, label = "Supplied cohort",
                        source = "upstream", provenance = "test fixture",
                        stringsAsFactors = FALSE),
    patient_id_col = "cohort_unit"
  )
}

pull_demo <- function(con, cohort, columns = "age") {
  pull_master(con, "master_demo", cohort, columns = columns, dialect = "duckdb")
}

active_units <- function(cohort) {
  last <- utils::tail(cohort$stages$stage_id[order(cohort$stages$order)], 1L)
  cohort$members$patient_id[cohort$members$stage_id == last & cohort$members$included]
}
```

- [ ] **Step 2: Write the failing tests.** Create `tests/testthat/test-master-pull.R`:

```r
# No PHI: identifiers and values are invented. Fixtures in helper-master-pull.R.

test_that("a supplied cohort pulls only its encounters and the study's columns", {
  con <- local_master_db()
  res <- pull_demo(con, unit_cohort(c("SYN101", "SYN102", "SYN999"),
                                    c("2010-03-01", "2012-07-15", "2011-01-01")))

  expect_s3_class(res, "master_pull")
  expect_setequal(names(res$data), c("mrn", "encounter_date", "age", "cohort_unit"))
  expect_identical(nrow(res$data), 2L)
  expect_identical(res$provenance$n_cohort, 3L)
  expect_identical(res$provenance$n_matched, 2L)
  expect_identical(res$provenance$n_unmatched, 1L)
})

test_that("a unit with no master row is excluded at the in_master stage", {
  con <- local_master_db()
  res <- pull_demo(con, unit_cohort(c("SYN101", "SYN999"), c("2010-03-01", "2011-01-01")))

  s <- cohort_summary(res$cohort)$stages
  expect_identical(utils::tail(s$stage_id, 1L), "in_master")
  expect_identical(utils::tail(s$n_excluded, 1L), 1L)
  expect_setequal(active_units(res$cohort), res$data$cohort_unit)
  expect_true(all(res$cohort$stages$source %in% c("upstream", "build", "derive")))
})

test_that("index first takes each patient's earliest qualifying encounter in the epoch", {
  con <- local_master_db()
  DBI::dbExecute(con, second_cabg)
  res <- pull_demo(con, demo_query())

  expect_setequal(res$data$cohort_unit,
                  c("SYN101|2010-03-01", "SYN103|2015-06-30", "SYN104|2020-01-10"))
  expect_identical(cohort_summary(res$cohort)$stages$stage_id,
                   c("qualifying", "prior_qualifying", "in_master"))
})

test_that("index all keeps every qualifying encounter in the epoch", {
  con <- local_master_db()
  DBI::dbExecute(con, second_cabg)
  expect_identical(nrow(pull_demo(con, demo_query(index = "all"))$data), 4L)
})

test_that("an earlier qualifying encounter is counted and kept by default", {
  con <- local_master_db()
  res <- pull_demo(con, demo_query())
  s <- cohort_summary(res$cohort)$stages
  prior <- res$cohort$stages$provenance[res$cohort$stages$stage_id == "prior_qualifying"]

  expect_identical(s$n_remaining[s$stage_id == "prior_qualifying"], 3L)
  expect_match(prior, "1 unit(s)", fixed = TRUE)
  expect_match(prior, "kept", fixed = TRUE)
})

test_that("prior = 'exclude' drops those units and does not pull their data", {
  con <- local_master_db()
  res <- pull_demo(con, demo_query(prior = "exclude"))
  s <- cohort_summary(res$cohort)$stages

  expect_identical(s$n_excluded[s$stage_id == "prior_qualifying"], 1L)
  expect_false("SYN101|2010-03-01" %in% res$data$cohort_unit)
  expect_identical(nrow(res$data), 2L)
})

test_that("keys outside the cohort never leave the database", {
  con <- local_master_db()
  DBI::dbExecute(con,
                 "INSERT INTO master_demo VALUES ('SYN105', DATE '2025-03-03', 'CABG', 60)")
  seen <- list()
  real_get <- DBI::dbGetQuery
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      out <- real_get(conn, statement, ...)
      seen[[length(seen) + 1L]] <<- out
      out
    },
    .package = "DBI"
  )

  pull_demo(con, demo_query())

  returned <- unlist(lapply(seen, function(d) unlist(lapply(d, as.character))))
  expect_false("SYN105" %in% returned)       # qualifying, but after the epoch
  expect_false("SYN102" %in% returned)       # in the epoch, but not qualifying
  expect_false("1998-05-01" %in% returned)   # the earlier encounter's date
})

test_that("a change committed during the pull is invisible to it", {
  skip_if_not_installed("duckdb")
  path <- withr::local_tempfile(fileext = ".duckdb")
  drv <- duckdb::duckdb(path)
  con <- DBI::dbConnect(drv)
  other <- DBI::dbConnect(drv)
  withr::defer({
    DBI::dbDisconnect(other)
    DBI::dbDisconnect(con, shutdown = TRUE)
  })
  seed_master(con)
  real_read <- .read_deployment
  testthat::local_mocked_bindings(.read_deployment = function(...) {
    DBI::dbExecute(other, second_cabg)
    DBI::dbExecute(other, "UPDATE master_demo_deployment SET sql_commit = 'new9999'")
    real_read(...)
  })

  res <- pull_master(con, "master_demo", demo_query(index = "all"), columns = "age",
                     dialect = "duckdb")

  expect_identical(res$provenance$sql_commit, "abc1234")
  expect_false("SYN103|2018-02-02" %in% res$data$cohort_unit)
  expect_false("SYN103|2018-02-02" %in% res$cohort$members$patient_id)
})

test_that("the pull records the deployment and only its own cohort's corrections", {
  con <- local_master_db()
  res <- pull_demo(con, unit_cohort(c("SYN101", "SYN102"), c("2010-03-01", "2012-07-15")))

  expect_identical(res$provenance$sql_commit, "abc1234")
  expect_identical(res$provenance$applied_correction_ids, "C1")
  expect_match(res$provenance$read_at,
               "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{6}Z$")
})

test_that("a unit matching two master rows stops the pull and rolls back", {
  con <- local_master_db()
  DBI::dbExecute(con,
                 "INSERT INTO master_demo VALUES ('SYN102', DATE '2012-07-15', 'AVR', 71)")
  cohort <- unit_cohort("SYN102", "2012-07-15")

  expect_error(pull_demo(con, cohort), "more than one master row")

  DBI::dbExecute(con, "DELETE FROM master_demo WHERE age = 71")
  expect_identical(nrow(pull_demo(con, cohort)$data), 1L)
})

test_that("two pulls on one connection both succeed", {
  con <- local_master_db()
  expect_identical(nrow(pull_demo(con, demo_query())$data), 3L)
  expect_identical(nrow(pull_demo(con, demo_query())$data), 3L)
})

test_that("an epoch with no qualifying encounters is an error", {
  con <- local_master_db()
  q <- cohort_query("proc = 'CABG'", as.Date(c("2021-01-01", "2021-12-31")))
  expect_error(pull_demo(con, q), "No qualifying encounters")
})

test_that("a deployment view without exactly one commit stops the pull", {
  con <- local_master_db()
  DBI::dbExecute(con, "INSERT INTO master_demo_deployment VALUES ('def5678')")
  expect_error(pull_demo(con, demo_query()), "exactly one")
})

test_that("a cohort not built on encounter units, or not a cohort, is refused", {
  con <- local_master_db()
  by_patient <- new_cohort_record(
    members = data.frame(patient_id = "SYN101", stage_id = "s", included = TRUE,
                         reason = NA_character_, stringsAsFactors = FALSE),
    stages = data.frame(stage_id = "s", order = 1L, label = "S", source = "upstream",
                        provenance = "fixture", stringsAsFactors = FALSE),
    patient_id_col = "masterid"
  )
  expect_error(pull_demo(con, by_patient), "cohort_unit")
  expect_error(pull_demo(con, list()), "cohort_query")
})

test_that("bad column requests are refused before any query", {
  con <- local_master_db()
  expect_error(pull_demo(con, demo_query(), columns = character(0)), "at least one")
  expect_error(pull_demo(con, demo_query(), columns = c("age", "age")), "duplicate")
})

test_that("a database error is withheld", {
  con <- local_master_db()
  err <- tryCatch(
    pull_master(con, "no_such_master", demo_query(), columns = "age", dialect = "duckdb"),
    error = conditionMessage
  )
  expect_match(err, "withheld")
})

test_that("print() and str() show counts, never identifiers or values", {
  con <- local_master_db()
  res <- pull_demo(con, demo_query())
  for (out in list(capture.output(print(res)), capture.output(str(res)))) {
    expect_true(any(grepl("matched", out)))
    expect_false(any(grepl("SYN", out, fixed = TRUE)))
    expect_false(any(grepl("2010-03-01", out, fixed = TRUE)))
  }
})

test_that("corrections in effect cover rows outside the cohort", {
  con <- local_master_db()
  DBI::dbExecute(con, paste("INSERT INTO master_demo_corrections_applied",
                            "VALUES ('C9', 'SYN102', DATE '2012-07-15')"))
  res <- pull_demo(con, demo_query())

  expect_false("C9" %in% res$provenance$applied_correction_ids)
  expect_setequal(res$provenance$corrections_in_effect, c("C1", "C2", "C9"))
})
```

- [ ] **Step 3: Run them and confirm they fail.**
  Run: `Rscript -e 'devtools::test(filter = "master-pull")'`
  Expected: FAIL, `could not find function "pull_master"`.

- [ ] **Step 4: Implement.** Create `R/master_pull.R`:

```r
# master_pull.R
#
# Study pulls from a master view. Selection and read run in one transaction, joined
# through a session temp table of cohort keys. Spec: dev/specs/
# 2026-11-16-master-views-design.md §5, §6.1.

# Run `code` in one transaction. On SQL Server the transaction uses SNAPSHOT
# isolation, so every read sees one state of the warehouse; a duckdb transaction is
# a snapshot already. Rolls back on error.
.with_snapshot_txn <- function(con, dialect, code) {
  if (identical(dialect, "mssql")) {
    run_step("set snapshot isolation",
             DBI::dbExecute(con, "SET TRANSACTION ISOLATION LEVEL SNAPSHOT"))
  }
  run_step("begin transaction", DBI::dbBegin(con))
  committed <- FALSE
  on.exit(if (!committed) try(DBI::dbRollback(con), silent = TRUE), add = TRUE)
  out <- force(code)
  run_step("commit transaction", DBI::dbCommit(con))
  committed <- TRUE
  out
}

.qualified_name <- function(name, dialect) {
  q <- quoter(dialect)
  paste(vapply(strsplit(name, ".", fixed = TRUE)[[1]], q, character(1)), collapse = ".")
}

.cohort_temp <- function(dialect) {
  switch(dialect,
         mssql = list(
           name = "#study_cohort",
           create = paste("CREATE TABLE #study_cohort (mrn nvarchar(128) NOT NULL,",
                          "encounter_date date NOT NULL, prior_qualifying tinyint NOT NULL)")
         ),
         duckdb = list(
           name = "study_cohort",
           create = paste("CREATE TEMP TABLE study_cohort (mrn VARCHAR NOT NULL,",
                          "encounter_date DATE NOT NULL, prior_qualifying TINYINT NOT NULL)")
         ))
}

.read_now_sql <- function(dialect) {
  switch(dialect,
         mssql = "SELECT SYSUTCDATETIME() AS read_at",
         duckdb = "SELECT CAST(timezone('UTC', CURRENT_TIMESTAMP) AS TIMESTAMP) AS read_at")
}

.read_deployment <- function(con, deployment_view, dialect) {
  dep <- run_step("read deployment", DBI::dbGetQuery(
    con, paste("SELECT sql_commit FROM", .qualified_name(deployment_view, dialect))
  ))
  commit <- as.character(dep$sql_commit)
  if (length(commit) != 1L || is.na(commit) || !nzchar(commit)) {
    stop("The deployment view must hold exactly one non-empty sql_commit; it holds ",
         length(commit), " row(s). Nothing was pulled.", call. = FALSE)
  }
  commit
}

.unit_cohort_active <- function(cohort) {
  if (!identical(cohort$patient_id_col, "cohort_unit")) {
    stop("A supplied cohort must be built on cohort_unit_id() units ",
         "(patient_id_col = \"cohort_unit\").", call. = FALSE)
  }
  last <- utils::tail(cohort$stages$stage_id[order(cohort$stages$order)], 1L)
  units <- cohort$members$patient_id[cohort$members$stage_id == last &
                                       cohort$members$included]
  if (!length(units)) {
    stop("The cohort's latest stage has no included units. Nothing was pulled.",
         call. = FALSE)
  }
  units
}

# INSERT ... SELECT that puts a query's units into the temp table. Bound parameters,
# in text order: epoch start (the EXISTS), epoch start, epoch end (the BETWEEN).
.select_units_sql <- function(query, master_q, tmp, mrn_q, date_q) {
  paste(
    "INSERT INTO", tmp, "(mrn, encounter_date, prior_qualifying)",
    "SELECT q.mrn, q.encounter_date,",
    sprintf("CASE WHEN EXISTS (SELECT 1 FROM %s p WHERE (%s) AND p.%s = q.mrn AND p.%s < ?)",
            master_q, query$qualifying, mrn_q, date_q),
    "THEN 1 ELSE 0 END",
    "FROM (",
    sprintf("SELECT m.%s AS mrn, m.%s AS encounter_date,", mrn_q, date_q),
    sprintf("ROW_NUMBER() OVER (PARTITION BY m.%s ORDER BY m.%s) AS rn", mrn_q, date_q),
    sprintf("FROM %s m WHERE (%s) AND m.%s IS NOT NULL AND m.%s BETWEEN ? AND ?",
            master_q, query$qualifying, mrn_q, date_q),
    ") q",
    if (identical(query$index, "first")) "WHERE q.rn = 1" else ""
  )
}

.query_cohort <- function(query, selected, master, commit) {
  units <- cohort_unit_id(as.character(selected$mrn), as.Date(selected$encounter_date))
  has_prior <- selected$prior_qualifying == 1L
  exclude <- identical(query$prior, "exclude") & has_prior
  query_prov <- sprintf("%s where %s; epoch %s to %s; index %s; SQL commit %s",
                        master, query$qualifying, format(query$epoch[[1]]),
                        format(query$epoch[[2]]), query$index, commit)
  verdict <- if (identical(query$prior, "keep")) "kept" else "excluded"
  prior_prov <- sprintf("%d unit(s) with a qualifying encounter before the epoch; %s",
                        sum(has_prior), verdict)
  members <- rbind(
    data.frame(patient_id = units, stage_id = "qualifying", included = TRUE,
               reason = NA_character_, stringsAsFactors = FALSE),
    data.frame(patient_id = units, stage_id = "prior_qualifying", included = !exclude,
               reason = ifelse(exclude, "qualifying encounter before the epoch",
                               NA_character_),
               stringsAsFactors = FALSE)
  )
  stages <- data.frame(
    stage_id = c("qualifying", "prior_qualifying"),
    order = c(1L, 2L),
    label = c("Qualifying encounters in the epoch",
              "Qualifying encounter before the epoch"),
    source = "upstream",
    provenance = c(query_prov, prior_prov),
    stringsAsFactors = FALSE
  )
  new_cohort_record(members, stages, patient_id_col = "cohort_unit")
}

#' Pull a study's cohort from a master view
#'
#' Selects a cohort and reads its rows from a master view in **one transaction under
#' snapshot isolation**, so the cohort, its data, the corrections applied to it and the
#' deployment it came from describe one state of the warehouse even while decisions,
#' loads or deployments commit.
#'
#' The cohort's keys go into a **session temp table**, which is joined to the master
#' inside the database. For a [cohort_query()] the epoch, the index and the earlier-
#' encounter flag are computed in SQL, so no key outside the cohort leaves the database.
#' For a supplied [new_cohort_record()] of [cohort_unit_id()] units, its active units are
#' loaded. The temp table is dropped before commit and never outlives the connection, so
#' no patient list persists in the warehouse.
#'
#' The returned cohort ends with an `in_master` stage that excludes units with no master
#' row, so the data match the active cohort exactly. A unit matching more than one
#' master row stops the pull, because the key is meant to be unique. Nothing in an error
#' or in printed output names a patient.
#'
#' @param con A [DBI::DBIConnection-class] to the warehouse, or to duckdb in tests.
#' @param master Character. The master view, optionally schema-qualified
#'   (`"dbo.master_cardiac"`).
#' @param cohort A [cohort_query()], or a [new_cohort_record()] built on
#'   [cohort_unit_id()] units (`patient_id_col = "cohort_unit"`).
#' @param columns Character. The study's columns, besides the key.
#' @param mrn_col,date_col Character. The master's key columns.
#' @param dialect `"mssql"` (the warehouse) or `"duckdb"` (tests).
#' @param applied_view,deployment_view Character. The master's applied-corrections and
#'   deployment views.
#'
#' @return An object of class `master_pull`: a list with `data` (one row per active
#'   unit: the key columns, `columns` and `cohort_unit`), `cohort` (the cohort record,
#'   ending with the `in_master` stage) and `provenance` (`master`, `sql_commit`,
#'   `applied_correction_ids`, `corrections_in_effect`, `read_at`, `columns`,
#'   `cohort_definition`, `n_cohort`, `n_matched`, `n_unmatched`).
#'   `corrections_in_effect` holds every correction id applied anywhere in the master in
#'   the same snapshot, including any that changed who qualified.
#'
#' @seealso [cohort_query()], [build_from_master()], [freeze_study_pull()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   # Synthetic data; no PHI.
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   DBI::dbWriteTable(con, "master_demo", data.frame(
#'     mrn = c("SYN101", "SYN102"),
#'     encounter_date = as.Date(c("2010-03-01", "2012-07-15")),
#'     proc = c("CABG", "AVR"), age = c(62, 70)
#'   ))
#'   DBI::dbWriteTable(con, "master_demo_corrections_applied", data.frame(
#'     correction_id = character(), mrn = character(), encounter_date = as.Date(character())
#'   ))
#'   DBI::dbWriteTable(con, "master_demo_deployment", data.frame(sql_commit = "abc1234"))
#'   q <- cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")))
#'   pull_master(con, "master_demo", q, columns = "age", dialect = "duckdb")
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#' }
#' }
#'
#' @export
pull_master <- function(con, master, cohort, columns, mrn_col = "mrn",
                        date_col = "encounter_date", dialect = c("mssql", "duckdb"),
                        applied_view = paste0(master, "_corrections_applied"),
                        deployment_view = paste0(master, "_deployment")) {
  dialect <- match.arg(dialect)
  if (!is.character(columns) || !length(columns) || anyNA(columns) ||
        any(!nzchar(columns))) {
    stop("'columns' must name at least one column.", call. = FALSE)
  }
  if (anyDuplicated(columns)) {
    stop("'columns' contains a duplicate name.", call. = FALSE)
  }
  is_query <- inherits(cohort, "cohort_query")
  if (!is_query && !inherits(cohort, "cohort_record")) {
    stop("'cohort' must be a cohort_query or a cohort_record.", call. = FALSE)
  }
  supplied <- if (is_query) NULL else split_cohort_unit(.unit_cohort_active(cohort))

  q <- quoter(dialect)
  tmp <- .cohort_temp(dialect)
  master_q <- .qualified_name(master, dialect)
  cols <- unique(c(mrn_col, date_col, columns))
  select_sql <- paste0("m.", vapply(cols, q, character(1)), collapse = ", ")
  join_sql <- sprintf("m.%s = c.mrn AND m.%s = c.encounter_date", q(mrn_col), q(date_col))
  if (is_query && identical(cohort$prior, "exclude")) {
    join_sql <- paste(join_sql, "AND c.prior_qualifying = 0")
  }

  read <- .with_snapshot_txn(con, dialect, {
    read_at <- run_step("read time", DBI::dbGetQuery(con, .read_now_sql(dialect)))$read_at
    commit <- .read_deployment(con, deployment_view, dialect)
    run_step("create cohort temp table", DBI::dbExecute(con, tmp$create))
    if (is_query) {
      run_step("select cohort", DBI::dbExecute(
        con, .select_units_sql(cohort, master_q, tmp$name, q(mrn_col), q(date_col)),
        params = list(cohort$epoch[[1]], cohort$epoch[[1]], cohort$epoch[[2]])
      ))
      selected <- run_step("read cohort keys", DBI::dbGetQuery(
        con, paste("SELECT mrn, encounter_date, prior_qualifying FROM", tmp$name)
      ))
      if (!nrow(selected)) {
        stop("No qualifying encounters fall in the epoch. Check the cohort query.",
             call. = FALSE)
      }
    } else {
      run_step("load cohort keys", DBI::dbExecute(
        con,
        paste("INSERT INTO", tmp$name,
              "(mrn, encounter_date, prior_qualifying) VALUES (?, ?, 0)"),
        params = list(supplied$mrn, supplied$encounter_date)
      ))
      selected <- NULL
    }
    data <- run_step("read master", DBI::dbGetQuery(con, sprintf(
      "SELECT %s FROM %s m INNER JOIN %s c ON %s", select_sql, master_q, tmp$name, join_sql
    )))
    applied <- run_step("read applied corrections", DBI::dbGetQuery(con, sprintf(
      paste("SELECT DISTINCT a.correction_id FROM %s a INNER JOIN %s c",
            "ON a.mrn = c.mrn AND a.encounter_date = c.encounter_date"),
      .qualified_name(applied_view, dialect), tmp$name
    )))
    in_effect <- run_step("read corrections in effect", DBI::dbGetQuery(con, paste(
      "SELECT DISTINCT correction_id FROM", .qualified_name(applied_view, dialect)
    )))
    run_step("drop cohort temp table", DBI::dbExecute(con, paste("DROP TABLE", tmp$name)))

    data$cohort_unit <- cohort_unit_id(as.character(data[[mrn_col]]),
                                       as.Date(data[[date_col]]))
    n_dup <- sum(duplicated(data$cohort_unit))
    if (n_dup) {
      stop(n_dup, " cohort unit(s) matched more than one master row; the key is meant ",
           "to be unique. Nothing was pulled.", call. = FALSE)
    }
    list(data = data, selected = selected, read_at = read_at, commit = commit,
         applied = sort(unique(as.character(applied$correction_id))),
         in_effect = sort(unique(as.character(in_effect$correction_id))))
  })

  base <- if (is_query) .query_cohort(cohort, read$selected, master, read$commit) else cohort
  last <- utils::tail(base$stages$stage_id[order(base$stages$order)], 1L)
  active <- base$members$patient_id[base$members$stage_id == last & base$members$included]
  found <- active %in% read$data$cohort_unit
  read_at <- format(as.POSIXct(read$read_at, tz = "UTC"), "%Y-%m-%dT%H:%M:%OS6Z",
                    tz = "UTC")
  final <- append_cohort_stage(
    base,
    data.frame(stage_id = "in_master", order = max(base$stages$order) + 1L,
               label = "Has a row in the master view", source = "upstream",
               provenance = sprintf("%s at SQL commit %s, read %s", master, read$commit,
                                    read_at),
               stringsAsFactors = FALSE),
    data.frame(patient_id = active, included = found,
               reason = ifelse(found, NA_character_, "no row in the master view"),
               stringsAsFactors = FALSE)
  )
  data <- read$data[read$data$cohort_unit %in% active[found], , drop = FALSE]
  row.names(data) <- NULL

  structure(list(
    data = data,
    cohort = final,
    provenance = list(
      master = master,
      sql_commit = read$commit,
      applied_correction_ids = read$applied,
      corrections_in_effect = read$in_effect,
      read_at = read_at,
      columns = columns,
      cohort_definition = if (is_query) {
        list(qualifying = cohort$qualifying, epoch = format(cohort$epoch),
             index = cohort$index, prior = cohort$prior)
      } else {
        "supplied cohort_record"
      },
      n_cohort = length(active),
      n_matched = sum(found),
      n_unmatched = sum(!found)
    )
  ), class = "master_pull")
}

#' Print a master pull
#'
#' Shows counts and provenance, never a patient value or identifier.
#'
#' @param x A `master_pull` from [pull_master()].
#' @param ... Ignored.
#'
#' @return `x`, invisibly.
#'
#' @export
print.master_pull <- function(x, ...) {
  p <- x$provenance
  cat("Master pull from ", p$master, " at SQL commit ", p$sql_commit, "\n", sep = "")
  cat("  cohort units: ", p$n_cohort, "; matched: ", p$n_matched,
      "; unmatched: ", p$n_unmatched, "\n", sep = "")
  cat("  columns: ", length(p$columns), "; corrections applied: ",
      length(p$applied_correction_ids), "; read at ", p$read_at, "\n", sep = "")
  invisible(x)
}

#' @rdname print.master_pull
#' @param object A `master_pull` from [pull_master()].
#' @export
str.master_pull <- function(object, ...) {
  cat("Structure of master_pull\n")
  print.master_pull(object, ...)
  invisible(NULL)
}
```

- [ ] **Step 5: Run the tests.**
  Run: `Rscript -e 'devtools::document(); devtools::test(filter = "master-pull")'`
  Expected: all PASS. Three things to check against the installed versions rather than
  work around, if they fail:
  - **Vector-bound `INSERT`:** duckdb binds a vector of rows (`?duckdb::duckdb_connection`).
    Never replace the bind by pasting values into SQL.
  - **Two connections to one duckdb file:** they share a driver (`duckdb::duckdb(path)`),
    and duckdb gives each transaction a snapshot. If the concurrency test sees the other
    connection's write, stop and report: the property under test is false, not the test.
  - **Mocking `.read_deployment`:** `testthat::local_mocked_bindings()` (3.3.2 here)
    replaces package internals by default.

- [ ] **Step 6: Commit.**

```bash
git add R/master_pull.R man/pull_master.Rd man/print.master_pull.Rd NAMESPACE \
  tests/testthat/helper-master-pull.R tests/testthat/test-master-pull.R
git commit -m "feat: pull_master() selects and reads a cohort in one snapshot"
```

---

### Task 5: `build_from_master()`, the bridge to `derive_vars()`

**Files:**
- Create: `R/master_build.R`
- Test: `tests/testthat/test-master-build.R`

**Interfaces:**
- Consumes: `master_pull` (Task 4); `append_cohort_stage()`.
- Produces: `build_from_master(pull)` → a `build_result`,
  `list(data = pull$data, cohort = <cohort with a "build" stage>, tables = list())`: the
  same shape `build_dataset()` returns, so `derive_vars()` takes it unchanged.
  `build_dataset()` stays the module-pull path; the master is already wide, so there are
  no modules to join.

- [ ] **Step 1: Write the failing tests.** Create `tests/testthat/test-master-build.R`:

```r
# No PHI: identifiers and values are invented. Fixtures in helper-master-pull.R.

test_that("a master pull becomes a build_result with a build stage", {
  con <- local_master_db()
  pull <- pull_demo(con, unit_cohort(c("SYN101", "SYN999"), c("2010-03-01", "2011-01-01")))

  build <- build_from_master(pull)

  expect_s3_class(build, "build_result")
  expect_identical(names(build), c("data", "cohort", "tables"))
  expect_identical(build$tables, list())
  s <- cohort_summary(build$cohort)$stages
  expect_identical(utils::tail(s$stage_id, 1L), "build")
  expect_identical(utils::tail(s$n_remaining, 1L), 1L)
  expect_setequal(active_units(build$cohort), build$data$cohort_unit)
})

test_that("derive_vars() accepts a master build", {
  con <- local_master_db()
  build <- build_from_master(pull_demo(con, demo_query()))
  config <- structure(list(
    study = "st0000", cohort_table = "unused", warehouse = "unused",
    view_schema = "unused", pull_date = as.Date("2026-11-16"), modules = "base",
    varsets = character(0), derive = stats::setNames(logical(0), character(0))
  ), class = "study_config")

  out <- derive_vars(build, config,
                     function(data, cohort, config) list(data = data, cohort = cohort))

  expect_identical(nrow(out$data), nrow(build$data))
})

test_that("pulled rows that disagree with the cohort are refused", {
  con <- local_master_db()
  pull <- pull_demo(con, demo_query())
  pull$data <- pull$data[-1, , drop = FALSE]
  expect_error(build_from_master(pull), "do not match the active cohort")
})

test_that("only a master_pull is built", {
  expect_error(build_from_master(list()), "master_pull")
})
```

- [ ] **Step 2: Run them and confirm they fail.**
  Run: `Rscript -e 'devtools::test(filter = "master-build")'`
  Expected: FAIL, `could not find function "build_from_master"`.

- [ ] **Step 3: Implement.** Create `R/master_build.R`:

```r
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
#'   q <- cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")))
#'   pull <- pull_master(con, "master_demo", q, columns = "age", dialect = "duckdb")
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
```

- [ ] **Step 4: Run the tests.**
  Run: `Rscript -e 'devtools::document(); devtools::test(filter = "master-build")'`
  Expected: all PASS.

- [ ] **Step 5: Commit.**

```bash
git add R/master_build.R man/build_from_master.Rd NAMESPACE tests/testthat/test-master-build.R
git commit -m "feat: build_from_master() turns a master pull into a build_result"
```

---

### Task 6: `freeze_study_pull()`, provenance inside the published file

**Files:**
- Create: `R/master_freeze.R`
- Test: `tests/testthat/test-master-freeze.R`

**Interfaces:**
- Consumes: `master_pull` (Task 4); `build_from_master()` (Task 5, end-to-end test);
  `publish_dataset()` with parquet (Task 1).
- Produces: `freeze_study_pull(pull, study_config, datasets_dir, dataset_id,
  extract_date = Sys.Date())` → invisibly, the `publish_dataset()` release.
  `read_pull_provenance(path)` → the provenance list stored in the file: `schema` (1),
  every `pull$provenance` field, `cohort_stages` (stage ids and counts) and
  `study_config_sha256`.

Why inside the file: the provenance is written into the parquet's key-value metadata
under `hvtiRdatabuild.pull`, so it is covered by the release's SHA-256. `publish_dataset()`
already moves one file into place under the catalog lock, and recovers an orphan on
retry, so a release can never exist without its provenance. Retrying the same pull writes
the same bytes and returns the same release. A distinct pull with identical data has
different provenance, so different bytes, and becomes its own release (`_r2`, ...): each
observation keeps its own record.

- [ ] **Step 1: Write the failing tests.** Create `tests/testthat/test-master-freeze.R`:

```r
# No PHI: identifiers and values are invented. Fixtures in helper-master-pull.R.

local_freeze_setup <- function(env = parent.frame()) {
  skip_if_not_installed("arrow")
  con <- local_master_db(env)
  config <- withr::local_tempfile(fileext = ".yaml", .local_envir = env)
  writeLines("study: st0000", config)
  list(con = con, config = config,
       dir = withr::local_tempdir("published-", .local_envir = env))
}

test_that("a query cohort runs through pull, build and freeze, end to end", {
  f <- local_freeze_setup()
  pull <- pull_demo(f$con, demo_query())
  build <- build_from_master(pull)
  release <- freeze_study_pull(pull, f$config, f$dir, "st0000_pull",
                               extract_date = "2026-11-16")

  expect_identical(tools::file_ext(release$file), "parquet")
  expect_identical(release$n_rows, nrow(build$data))
  prov <- read_pull_provenance(file.path(f$dir, release$file))
  expect_identical(prov$schema, 1L)
  expect_identical(prov$sql_commit, "abc1234")
  expect_setequal(unlist(prov$applied_correction_ids), c("C1", "C2"))
  expect_setequal(unlist(prov$corrections_in_effect), c("C1", "C2"))
  expect_identical(prov$cohort_definition$index, "first")
  expect_identical(unlist(prov$cohort_stages$stage_id),
                   c("qualifying", "prior_qualifying", "in_master"))
  expect_identical(prov$study_config_sha256,
                   digest::digest(f$config, algo = "sha256", file = TRUE))
})

test_that("retrying the same pull returns the same release", {
  f <- local_freeze_setup()
  pull <- pull_demo(f$con, demo_query())
  a <- freeze_study_pull(pull, f$config, f$dir, "st0000_pull", extract_date = "2026-11-16")
  b <- freeze_study_pull(pull, f$config, f$dir, "st0000_pull", extract_date = "2026-11-16")
  expect_identical(a$release_id, b$release_id)
})

test_that("a distinct pull with identical data keeps its own release and record", {
  f <- local_freeze_setup()
  first <- pull_demo(f$con, demo_query())
  DBI::dbExecute(f$con, paste("INSERT INTO master_demo_corrections_applied",
                              "VALUES ('C3', 'SYN104', DATE '2020-01-10')"))
  second <- pull_demo(f$con, demo_query())
  expect_identical(first$data, second$data)

  a <- freeze_study_pull(first, f$config, f$dir, "st0000_pull", extract_date = "2026-11-16")
  b <- freeze_study_pull(second, f$config, f$dir, "st0000_pull",
                         extract_date = "2026-11-16")

  expect_false(identical(a$release_id, b$release_id))
  expect_identical(b$revision, 2L)
  expect_false("C3" %in% unlist(read_pull_provenance(file.path(f$dir, a$file))$
                                  applied_correction_ids))
  expect_true("C3" %in% unlist(read_pull_provenance(file.path(f$dir, b$file))$
                                 applied_correction_ids))
})

test_that("a file without pull provenance is refused", {
  skip_if_not_installed("arrow")
  path <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(data.frame(x = 1), path)
  expect_error(read_pull_provenance(path), "no pull provenance")
})

test_that("only a master_pull is frozen", {
  expect_error(freeze_study_pull(list(), "x", tempdir(), "x"), "master_pull")
})
```

- [ ] **Step 2: Run them and confirm they fail.**
  Run: `Rscript -e 'devtools::test(filter = "master-freeze")'`
  Expected: FAIL, `could not find function "freeze_study_pull"`.

- [ ] **Step 3: Implement.** Create `R/master_freeze.R`:

```r
.pull_metadata_key <- "hvtiRdatabuild.pull"

#' Freeze a study's pull from a master view
#'
#' Sources are not time-travelable, so the release, not the warehouse, is the record of
#' what a study read. `freeze_study_pull()` publishes the pull as an immutable parquet
#' release with [publish_dataset()], with its provenance written **into the file's own
#' metadata**: the SQL model commit, the ids of the corrections applied, when the pull
#' read, the cohort definition and stage counts, and the study configuration's checksum.
#' Because the provenance is part of the bytes, the release's SHA-256 covers it, and a
#' release can never exist without it. Read it back with [read_pull_provenance()].
#'
#' Retrying the same pull returns the same release. A distinct pull with identical data
#' carries different provenance, so it becomes its own release.
#'
#' The retained pull holds patient values. It belongs in the study's data folder under
#' the same rules as the built dataset, never in a repository.
#'
#' @param pull A `master_pull` from [pull_master()].
#' @param study_config Character. Path to the study configuration file whose checksum is
#'   recorded.
#' @param datasets_dir,dataset_id,extract_date As for [publish_dataset()].
#'
#' @return Invisibly, the release, as returned by [publish_dataset()].
#'
#' @seealso [read_pull_provenance()], [pull_master()], [publish_dataset()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE) &&
#'       requireNamespace("arrow", quietly = TRUE)) {
#'   # Synthetic data; no PHI.
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   DBI::dbWriteTable(con, "master_demo", data.frame(
#'     mrn = "SYN101", encounter_date = as.Date("2010-03-01"), proc = "CABG", age = 62
#'   ))
#'   DBI::dbWriteTable(con, "master_demo_corrections_applied", data.frame(
#'     correction_id = character(), mrn = character(), encounter_date = as.Date(character())
#'   ))
#'   DBI::dbWriteTable(con, "master_demo_deployment", data.frame(sql_commit = "abc1234"))
#'   q <- cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")))
#'   pull <- pull_master(con, "master_demo", q, columns = "age", dialect = "duckdb")
#'   config <- tempfile(fileext = ".yaml")
#'   writeLines("study: st0000", config)
#'   published <- tempfile("published-")
#'   dir.create(published)
#'   release <- freeze_study_pull(pull, config, published, "st0000_pull")
#'   read_pull_provenance(file.path(published, release$file))$sql_commit
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#'   unlink(c(config, published), recursive = TRUE)
#' }
#' }
#'
#' @export
freeze_study_pull <- function(pull, study_config, datasets_dir, dataset_id,
                              extract_date = Sys.Date()) {
  if (!inherits(pull, "master_pull")) {
    stop("'pull' must be a master_pull from pull_master().", call. = FALSE)
  }
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("Freezing a pull writes parquet and needs the arrow package.", call. = FALSE)
  }
  if (!is.character(study_config) || length(study_config) != 1L ||
        !file.exists(study_config)) {
    stop("'study_config' must be the path of an existing study configuration file.",
         call. = FALSE)
  }

  stages <- cohort_summary(pull$cohort)$stages
  prov <- c(
    list(schema = 1L),
    pull$provenance,
    list(cohort_stages = as.list(stages[c("stage_id", "n_in", "n_excluded", "n_remaining")]),
         study_config_sha256 = digest::digest(study_config, algo = "sha256", file = TRUE))
  )
  table <- arrow::arrow_table(pull$data)
  metadata <- table$metadata
  metadata[[.pull_metadata_key]] <- yaml::as.yaml(prov)
  table$metadata <- metadata

  draft <- tempfile(fileext = ".parquet")
  on.exit(unlink(draft), add = TRUE)
  arrow::write_parquet(table, draft)

  release <- publish_dataset(
    draft, dataset_id, datasets_dir, extract_date = extract_date,
    source = sprintf("pull_master() from %s at SQL commit %s",
                     pull$provenance$master, pull$provenance$sql_commit)
  )
  invisible(release)
}

#' Read the provenance a frozen pull carries
#'
#' @param path Character. A parquet file written by [freeze_study_pull()].
#'
#' @return A list: `schema`, `master`, `sql_commit`, `applied_correction_ids`,
#'   `corrections_in_effect`, `read_at`,
#'   `columns`, `cohort_definition`, `n_cohort`, `n_matched`, `n_unmatched`,
#'   `cohort_stages` and `study_config_sha256`.
#'
#' @seealso [freeze_study_pull()]
#'
#' @examples
#' # See freeze_study_pull().
#'
#' @export
read_pull_provenance <- function(path) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("Reading pull provenance needs the arrow package.", call. = FALSE)
  }
  text <- arrow::read_parquet(path, as_data_frame = FALSE)$metadata[[.pull_metadata_key]]
  if (is.null(text)) {
    stop("This file carries no pull provenance.", call. = FALSE)
  }
  yaml::yaml.load(text, eval.expr = FALSE)
}
```

- [ ] **Step 4: Run the tests.**
  Run: `Rscript -e 'devtools::document(); devtools::test(filter = "master-freeze")'`
  Expected: all PASS. If "retrying the same pull" yields `_r2`, the two writes differ in
  bytes: compare their SHA-256s and inspect `arrow::read_parquet(..., as_data_frame =
  FALSE)$metadata` of each for a varying entry before changing anything. Do not weaken the
  test.

- [ ] **Step 5: Commit.**

```bash
git add R/master_freeze.R man/freeze_study_pull.Rd man/read_pull_provenance.Rd NAMESPACE \
  tests/testthat/test-master-freeze.R
git commit -m "feat: freeze_study_pull() publishes the pull with provenance in the file"
```

---

### Task 7: reference index, news fragment and the full gate

**Files:**
- Modify: `_pkgdown.yml` (after the "Pull: Warehouse to R" group)
- Create: `news/<implementation branch with / as ->.md`

- [ ] **Step 1: Add the reference group.** In `_pkgdown.yml`, after the `Pull: Warehouse to
  R` group's contents, insert:

```yaml
- title: "Pull: Master views to a study"
  desc: >
    Define a cohort of encounters, select and pull it from a master view in one consistent
    read, build from the pull, and freeze it with its provenance.
  contents:
  - cohort_unit_id
  - split_cohort_unit
  - cohort_query
  - print.cohort_query
  - pull_master
  - print.master_pull
  - str.master_pull
  - build_from_master
  - freeze_study_pull
  - read_pull_provenance
```

- [ ] **Step 2: Write the news fragment** (named for the implementation branch, for example
  `news/feat-master-study-pull.md`):

```markdown
* New `pull_master()` selects a cohort and reads its rows from a master view in one
  snapshot-isolation transaction, joined through a session temp table, and records the
  SQL commit and the ids of the corrections applied. `cohort_query()` defines a cohort by
  query, epoch and index (`"first"` or `"all"`), computed in the database, with a
  qualifying encounter before the epoch recorded as a counted stage.
  `build_from_master()` turns the pull into the `build_result` that `derive_vars()`
  consumes. `freeze_study_pull()` publishes the pull as a parquet release carrying its
  provenance in the file, read back with `read_pull_provenance()`.
* New `cohort_unit_id()` and `split_cohort_unit()` key a cohort by MRN and encounter date,
  so a patient with two operations is two units.
* `publish_dataset()` accepts `.parquet` drafts.
```

- [ ] **Step 3: Run the full gate.**

```bash
Rscript -e 'devtools::document()'
Rscript -e 'devtools::test()'
Rscript -e 'devtools::check()'
Rscript -e 'lintr::lint_package()'
Rscript -e 'pkgdown::check_pkgdown()'
```

  Expected: tests pass; check 0 errors, 0 warnings, 0 notes; no lints; pkgdown reports
  no missing topics. The new tests skip without duckdb or arrow, so confirm both are
  installed and the skip count did not rise before calling the gate green.

- [ ] **Step 4: Commit.**

```bash
git add _pkgdown.yml news/ man/ NAMESPACE
git commit -m "docs: reference group and news for study pulls from master views"
```

---

## Not in this plan, and why

- **The warehouse side.** Snapshot isolation on the database, `tempdb` rights for
  programmers' logins, and the three contract views per master are plan 3, with data
  engineering. Until they exist, `pull_master()` runs only against duckdb.
- **A SQL Server rehearsal** of the same properties the duckdb tests check: a change
  committed mid-pull is invisible, and no out-of-cohort key leaves the database. It needs
  the warehouse, so it is the first acceptance step of plan 3.
- **A real study's derivation on a master build.** Task 5 proves `derive_vars()` accepts
  the shape with an identity derivation; a real one is plan 3's first study migration.
- **Corrections intake, study candidates, generated corrected views and the parity gate**:
  plan 2.
