# Study builds from master views: implementation plan (plan 1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a statistical programmer pull a study's cohort from a master view in one
consistent read, define a cohort by query, and freeze the pull with its provenance.

**Architecture:** Five new exports in hvtiRdatabuild. A cohort unit is an encounter, identified
by `cohort_unit_id()` (`"<mrn>|<YYYY-MM-DD>"`) and carried as the existing `cohort_record`'s
`patient_id`, so `new_cohort_record()`, `append_cohort_stage()` and `build_dataset()` work
unchanged. `pull_master()` and `define_cohort()` read inside one snapshot-isolation
transaction, joining a session temp table of cohort keys to the master view.
`freeze_study_pull()` publishes the pull as a parquet release, with a provenance sidecar.

**Tech Stack:** R (>= 4.4.0), DBI, duckdb (tests), arrow (parquet), yaml, digest, testthat 3.

**Spec:** `dev/specs/2026-11-16-master-views-design.md`, §5 (study builds) and §6 (freeze
record). **Out of this plan:** §3 corrections intake and candidates, §3.3 generated views,
§7 parity gate (**plan 2**, hvtiRdatabuild), and the SQL model repository and warehouse
setup (**plan 3**, blocked on data engineering). This plan tests against duckdb only; nothing
here needs the warehouse.

## Global constraints

- Lines are **100 characters** (`.lintr`). Roxygen markdown is enabled.
- testthat **edition 3**; test files are `test-*.R` with a hyphen.
- **No PHI.** Every fixture is invented and says so ("No PHI: identifiers and values are
  invented."). **No identifier or data value appears in any error, warning, message or print
  output.** Counts and verdicts only.
- **DB errors are withheld:** wrap every DBI call in the existing `run_step(name, expr)`
  (`R/sql_dialect.R`), which replaces the driver message.
- `arrow` and `duckdb` are **Suggests**: tests call `skip_if_not_installed()`, and runtime
  code that needs arrow checks `requireNamespace("arrow", quietly = TRUE)` and stops with a
  clear message.
- Dialects are exactly `"mssql"` and `"duckdb"`, as elsewhere (`quoter()`, `sql_types()`).
- **No version bump.** The implementation branch writes one news fragment,
  `news/<branch with / as ->.md`, bullets only, no heading (Task 6). This plan file is under
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
| `R/master_pull.R` (new) | `.with_snapshot_txn()`, `.qualified_name()`, `pull_master()`, `print.master_pull()` |
| `R/master_cohort.R` (new) | `define_cohort()` |
| `R/master_freeze.R` (new) | `freeze_study_pull()` |
| `tests/testthat/helper-master-pull.R` (new) | duckdb master fixture, unit cohort fixture |
| `tests/testthat/test-cohort-unit.R`, `test-master-pull.R`, `test-master-cohort.R`, `test-master-freeze.R` (new) | tests |
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
#' @seealso [split_cohort_unit()], [pull_master()], [define_cohort()]
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

### Task 3: `pull_master()`, one consistent read through a session temp table

**Files:**
- Create: `R/master_pull.R`
- Create: `tests/testthat/helper-master-pull.R`
- Test: `tests/testthat/test-master-pull.R`

**Interfaces:**
- Consumes: `cohort_unit_id()`, `split_cohort_unit()` (Task 2); `quoter()`, `run_step()`
  (`R/sql_dialect.R`); `new_cohort_record()`.
- Produces:
  - `.with_snapshot_txn(con, dialect, code)`: runs `code` in one transaction (SQL Server:
    `SNAPSHOT` isolation), commits, and rolls back on error. Returns `code`'s value.
  - `.qualified_name(name, dialect)`: quotes each dot-separated part.
  - `pull_master(con, master, cohort, columns, mrn_col = "mrn", date_col = "encounter_date",
    dialect = c("mssql", "duckdb"), applied_view = paste0(master, "_corrections_applied"),
    deployment_view = paste0(master, "_deployment"))` → object of class `master_pull`:
    `list(data = <data.frame with mrn_col, date_col, columns, cohort_unit>,
    provenance = list(master, sql_commit, applied_correction_ids <chr>, read_at <chr ISO-8601
    UTC>, columns, n_cohort, n_matched, n_unmatched))`.
  - `print.master_pull(x, ...)`.

- [ ] **Step 1: Write the test helper.** Create `tests/testthat/helper-master-pull.R`:

```r
# No PHI: identifiers and values are invented.

# A duckdb stand-in for one master and the two plan-3 contract views.
# SYN101 has a qualifying CABG before 2000 and another in 2010.
local_master_db <- function(env = parent.frame()) {
  testthat::skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
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
  con
}

# A one-stage cohort of encounter units.
unit_cohort <- function(mrn, dates) {
  units <- cohort_unit_id(mrn, as.Date(dates))
  new_cohort_record(
    members = data.frame(patient_id = units, stage_id = "selected", included = TRUE,
                         reason = NA_character_, stringsAsFactors = FALSE),
    stages = data.frame(stage_id = "selected", order = 1L, label = "Selected",
                        source = "synthetic", provenance = "test fixture",
                        stringsAsFactors = FALSE),
    patient_id_col = "cohort_unit"
  )
}
```

- [ ] **Step 2: Write the failing tests.** Create `tests/testthat/test-master-pull.R`:

```r
# No PHI: identifiers and values are invented.

pull_demo <- function(con, cohort, columns = "age") {
  pull_master(con, "master_demo", cohort, columns = columns, dialect = "duckdb")
}

test_that("only the cohort's encounters and the study's columns come back", {
  con <- local_master_db()
  cohort <- unit_cohort(c("SYN101", "SYN102", "SYN999"),
                        c("2010-03-01", "2012-07-15", "2011-01-01"))

  res <- pull_demo(con, cohort)

  expect_s3_class(res, "master_pull")
  expect_setequal(names(res$data), c("mrn", "encounter_date", "age", "cohort_unit"))
  expect_identical(nrow(res$data), 2L)
  expect_false("proc" %in% names(res$data))
  expect_identical(res$provenance$n_cohort, 3L)
  expect_identical(res$provenance$n_matched, 2L)
  expect_identical(res$provenance$n_unmatched, 1L)
})

test_that("the pull records the deployment and only its own cohort's corrections", {
  con <- local_master_db()
  res <- pull_demo(con, unit_cohort(c("SYN101", "SYN102"),
                                    c("2010-03-01", "2012-07-15")))

  expect_identical(res$provenance$sql_commit, "abc1234")
  expect_identical(res$provenance$applied_correction_ids, "C1")
  expect_match(res$provenance$read_at, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
})

test_that("a cohort unit matching two master rows stops the pull and rolls back", {
  con <- local_master_db()
  DBI::dbExecute(con, paste(
    "INSERT INTO master_demo VALUES ('SYN102', DATE '2012-07-15', 'AVR', 71)"
  ))
  cohort <- unit_cohort("SYN102", "2012-07-15")

  expect_error(pull_demo(con, cohort), "more than one master row")

  # The temp table was rolled back, so a clean pull on the same connection works.
  DBI::dbExecute(con, "DELETE FROM master_demo WHERE age = 71")
  expect_identical(nrow(pull_demo(con, cohort)$data), 1L)
})

test_that("two pulls on one connection both succeed", {
  con <- local_master_db()
  cohort <- unit_cohort("SYN103", "2015-06-30")
  expect_identical(nrow(pull_demo(con, cohort)$data), 1L)
  expect_identical(nrow(pull_demo(con, cohort)$data), 1L)
})

test_that("a deployment view without exactly one commit stops the pull", {
  con <- local_master_db()
  DBI::dbExecute(con, "INSERT INTO master_demo_deployment VALUES ('def5678')")
  expect_error(pull_demo(con, unit_cohort("SYN103", "2015-06-30")), "exactly one")
})

test_that("a cohort not built on encounter units is refused", {
  con <- local_master_db()
  cohort <- new_cohort_record(
    members = data.frame(patient_id = "SYN101", stage_id = "s", included = TRUE,
                         reason = NA_character_, stringsAsFactors = FALSE),
    stages = data.frame(stage_id = "s", order = 1L, label = "S", source = "x",
                        provenance = "y", stringsAsFactors = FALSE),
    patient_id_col = "masterid"
  )
  expect_error(pull_demo(con, cohort), "cohort_unit")
})

test_that("bad column requests are refused before any query", {
  con <- local_master_db()
  cohort <- unit_cohort("SYN103", "2015-06-30")
  expect_error(pull_demo(con, cohort, columns = character(0)), "at least one")
  expect_error(pull_demo(con, cohort, columns = c("age", "age")), "duplicate")
  expect_error(pull_demo(con, cohort, columns = NA_character_), "at least one")
})

test_that("a database error is withheld", {
  con <- local_master_db()
  err <- tryCatch(
    pull_master(con, "no_such_master", unit_cohort("SYN103", "2015-06-30"),
                columns = "age", dialect = "duckdb"),
    error = conditionMessage
  )
  expect_match(err, "withheld")
})

test_that("printing shows counts, never identifiers", {
  con <- local_master_db()
  res <- pull_demo(con, unit_cohort("SYN103", "2015-06-30"))
  out <- capture.output(print(res))
  expect_true(any(grepl("matched", out)))
  expect_false(any(grepl("SYN", out, fixed = TRUE)))
})
```

- [ ] **Step 3: Run them and confirm they fail.**
  Run: `Rscript -e 'devtools::test(filter = "master-pull")'`
  Expected: FAIL, `could not find function "pull_master"`.

- [ ] **Step 4: Implement.** Create `R/master_pull.R`:

```r
# master_pull.R
#
# Study pulls from a master view: one consistent read, joined through a session
# temp table of cohort keys. Spec: dev/specs/2026-11-16-master-views-design.md §5, §6.1.

# Run `code` in one transaction. On SQL Server the transaction uses SNAPSHOT
# isolation, so every read sees one state of the warehouse; duckdb transactions
# are snapshots already. Rolls back on error.
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
                          "encounter_date date NOT NULL)")
         ),
         duckdb = list(
           name = "study_cohort",
           create = paste("CREATE TEMP TABLE study_cohort (mrn VARCHAR NOT NULL,",
                          "encounter_date DATE NOT NULL)")
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

.active_units <- function(cohort) {
  if (!inherits(cohort, "cohort_record") ||
        !identical(cohort$patient_id_col, "cohort_unit")) {
    stop("'cohort' must be a cohort_record built on cohort_unit_id() units ",
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

#' Pull a study's cohort from a master view
#'
#' Reads only the cohort's encounters and the study's columns from a master view, in
#' one consistent read. The cohort's keys go into a **session temp table**, which is
#' joined to the master inside the database, so only the study's slice crosses the
#' network. The temp table is dropped before the transaction commits and never
#' outlives the connection, so no patient list persists in the warehouse.
#'
#' Every statement runs in one transaction under snapshot isolation: the data, the
#' corrections applied to it and the deployment it came from describe one state of
#' the warehouse even while decisions or deployments commit. The pull records the ids
#' of the corrections applied to its cohort's rows, never their values.
#'
#' A cohort unit matching more than one master row stops the pull, because the key is
#' meant to be unique. Units matching no row are counted. Nothing in an error or in
#' printed output names a patient.
#'
#' @param con A [DBI::DBIConnection-class] to the warehouse, or to duckdb in tests.
#' @param master Character. The master view, optionally schema-qualified
#'   (`"dbo.master_cardiac"`).
#' @param cohort A [new_cohort_record()] built on [cohort_unit_id()] units
#'   (`patient_id_col = "cohort_unit"`). Its latest stage's included units are pulled.
#' @param columns Character. The study's columns, besides the key.
#' @param mrn_col,date_col Character. The master's key columns.
#' @param dialect `"mssql"` (the warehouse) or `"duckdb"` (tests).
#' @param applied_view,deployment_view Character. The master's applied-corrections and
#'   deployment views (spec §6.1).
#'
#' @return An object of class `master_pull`: a list with `data` (the key columns, the
#'   requested columns and a `cohort_unit` column) and `provenance` (`master`,
#'   `sql_commit`, `applied_correction_ids`, `read_at`, `columns`, `n_cohort`,
#'   `n_matched`, `n_unmatched`).
#'
#' @seealso [define_cohort()], [freeze_study_pull()], [cohort_unit_id()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   # Synthetic data; no PHI.
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   DBI::dbWriteTable(con, "master_demo", data.frame(
#'     mrn = c("SYN101", "SYN102"),
#'     encounter_date = as.Date(c("2010-03-01", "2012-07-15")), age = c(62, 70)
#'   ))
#'   DBI::dbWriteTable(con, "master_demo_corrections_applied", data.frame(
#'     correction_id = character(), mrn = character(), encounter_date = as.Date(character())
#'   ))
#'   DBI::dbWriteTable(con, "master_demo_deployment", data.frame(sql_commit = "abc1234"))
#'   cohort <- new_cohort_record(
#'     members = data.frame(patient_id = cohort_unit_id("SYN101", as.Date("2010-03-01")),
#'                          stage_id = "selected", included = TRUE, reason = NA_character_),
#'     stages = data.frame(stage_id = "selected", order = 1L, label = "Selected",
#'                         source = "synthetic", provenance = "example"),
#'     patient_id_col = "cohort_unit"
#'   )
#'   pull_master(con, "master_demo", cohort, columns = "age", dialect = "duckdb")
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
  units <- .active_units(cohort)
  keys <- split_cohort_unit(units)
  q <- quoter(dialect)
  tmp <- .cohort_temp(dialect)
  master_q <- .qualified_name(master, dialect)
  cols <- unique(c(mrn_col, date_col, columns))
  select_sql <- paste0("m.", vapply(cols, q, character(1)), collapse = ", ")
  join_sql <- sprintf("m.%s = c.mrn AND m.%s = c.encounter_date", q(mrn_col), q(date_col))

  pulled <- .with_snapshot_txn(con, dialect, {
    read_at <- run_step("read time", DBI::dbGetQuery(con, .read_now_sql(dialect)))$read_at
    commit <- .read_deployment(con, deployment_view, dialect)
    run_step("create cohort temp table", DBI::dbExecute(con, tmp$create))
    run_step("load cohort keys", DBI::dbExecute(
      con, paste("INSERT INTO", tmp$name, "(mrn, encounter_date) VALUES (?, ?)"),
      params = list(keys$mrn, keys$encounter_date)
    ))
    data <- run_step("read master", DBI::dbGetQuery(con, sprintf(
      "SELECT %s FROM %s m INNER JOIN %s c ON %s", select_sql, master_q, tmp$name, join_sql
    )))
    applied <- run_step("read applied corrections", DBI::dbGetQuery(con, sprintf(
      paste("SELECT DISTINCT a.correction_id FROM %s a INNER JOIN %s c",
            "ON a.mrn = c.mrn AND a.encounter_date = c.encounter_date"),
      .qualified_name(applied_view, dialect), tmp$name
    )))
    run_step("drop cohort temp table",
             DBI::dbExecute(con, paste("DROP TABLE", tmp$name)))

    data$cohort_unit <- cohort_unit_id(as.character(data[[mrn_col]]),
                                       as.Date(data[[date_col]]))
    n_dup <- sum(duplicated(data$cohort_unit))
    if (n_dup) {
      stop(n_dup, " cohort unit(s) matched more than one master row; the key is meant ",
           "to be unique. Nothing was pulled.", call. = FALSE)
    }
    list(data = data, read_at = read_at, commit = commit,
         applied = sort(unique(as.character(applied$correction_id))))
  })

  n_matched <- length(unique(pulled$data$cohort_unit))
  structure(list(
    data = pulled$data,
    provenance = list(
      master = master,
      sql_commit = pulled$commit,
      applied_correction_ids = pulled$applied,
      read_at = format(as.POSIXct(pulled$read_at, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ",
                       tz = "UTC"),
      columns = columns,
      n_cohort = length(units),
      n_matched = n_matched,
      n_unmatched = length(units) - n_matched
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
```

- [ ] **Step 5: Run the tests.**
  Run: `Rscript -e 'devtools::document(); devtools::test(filter = "master-pull")'`
  Expected: all PASS. If the duplicate-match test fails because duckdb rejects the
  vector-bound `INSERT`, check the installed duckdb's DBI docs
  (`?duckdb::duckdb_connection`) before changing the bind; do not replace it with string
  pasting of values.

- [ ] **Step 6: Commit.**

```bash
git add R/master_pull.R man/pull_master.Rd man/print.master_pull.Rd NAMESPACE \
  tests/testthat/helper-master-pull.R tests/testthat/test-master-pull.R
git commit -m "feat: pull_master() reads a cohort from a master view in one consistent read"
```

---

### Task 4: `define_cohort()`, a cohort defined by a query on the master

**Files:**
- Create: `R/master_cohort.R`
- Test: `tests/testthat/test-master-cohort.R`

**Interfaces:**
- Consumes: `.with_snapshot_txn()`, `.qualified_name()`, `.read_deployment()`,
  `.read_now_sql()` (Task 3); `cohort_unit_id()` (Task 2); `new_cohort_record()`.
- Produces: `define_cohort(con, master, qualifying, epoch, index = c("first", "all"),
  prior = c("keep", "exclude"), mrn_col = "mrn", date_col = "encounter_date",
  dialect = c("mssql", "duckdb"), deployment_view = paste0(master, "_deployment"))` → a
  `cohort_record` with `patient_id_col = "cohort_unit"` and two stages, `qualifying` and
  `prior_qualifying`.

- [ ] **Step 1: Write the failing tests.** Create `tests/testthat/test-master-cohort.R`:

```r
# No PHI: identifiers and values are invented. Fixture in helper-master-pull.R.

epoch <- as.Date(c("2000-01-01", "2024-07-31"))
second_cabg <- "INSERT INTO master_demo VALUES ('SYN103', DATE '2018-02-02', 'CABG', 58)"

define_demo <- function(con, ...) {
  define_cohort(con, "master_demo", qualifying = "proc = 'CABG'", epoch = epoch,
                dialect = "duckdb", ...)
}

test_that("index first takes each patient's earliest qualifying encounter in the epoch", {
  con <- local_master_db()
  DBI::dbExecute(con, second_cabg)

  cohort <- define_demo(con)

  expect_s3_class(cohort, "cohort_record")
  expect_identical(cohort$patient_id_col, "cohort_unit")
  first <- cohort$members$patient_id[cohort$members$stage_id == "qualifying"]
  expect_setequal(first, c("SYN101|2010-03-01", "SYN103|2015-06-30", "SYN104|2020-01-10"))
})

test_that("index all keeps every qualifying encounter in the epoch", {
  con <- local_master_db()
  DBI::dbExecute(con, second_cabg)

  cohort <- define_demo(con, index = "all")

  expect_identical(sum(cohort$members$stage_id == "qualifying"), 4L)
})

test_that("a qualifying encounter before the epoch is a counted, kept stage by default", {
  con <- local_master_db()
  cohort <- define_demo(con)
  s <- cohort_summary(cohort)$stages

  expect_identical(s$stage_id, c("qualifying", "prior_qualifying"))
  expect_identical(s$n_remaining[[2]], 3L)
  prov <- cohort$stages$provenance[cohort$stages$stage_id == "prior_qualifying"]
  expect_match(prov, "1 unit\\(s\\)")
  expect_match(prov, "kept")
})

test_that("prior = 'exclude' drops those units with a reason", {
  con <- local_master_db()
  s <- cohort_summary(define_demo(con, prior = "exclude"))$stages
  expect_identical(s$n_excluded[[2]], 1L)
  expect_identical(s$n_remaining[[2]], 2L)
})

test_that("provenance names the query, epoch, index and SQL commit", {
  con <- local_master_db()
  prov <- define_demo(con)$stages$provenance[[1]]
  expect_match(prov, "proc = 'CABG'", fixed = TRUE)
  expect_match(prov, "2000-01-01 to 2024-07-31", fixed = TRUE)
  expect_match(prov, "index first", fixed = TRUE)
  expect_match(prov, "abc1234", fixed = TRUE)
})

test_that("an epoch with no qualifying encounters is an error", {
  con <- local_master_db()
  expect_error(
    define_cohort(con, "master_demo", "proc = 'CABG'",
                  epoch = as.Date(c("2021-01-01", "2021-12-31")), dialect = "duckdb"),
    "No qualifying encounters"
  )
})

test_that("a malformed epoch or query is refused", {
  con <- local_master_db()
  expect_error(define_cohort(con, "master_demo", "proc = 'CABG'",
                             epoch = rev(epoch), dialect = "duckdb"), "start")
  expect_error(define_cohort(con, "master_demo", "proc = 'CABG'",
                             epoch = "2000-01-01", dialect = "duckdb"), "two Dates")
  expect_error(define_cohort(con, "master_demo", "", epoch = epoch, dialect = "duckdb"),
               "qualifying")
})
```

- [ ] **Step 2: Run them and confirm they fail.**
  Run: `Rscript -e 'devtools::test(filter = "master-cohort")'`
  Expected: FAIL, `could not find function "define_cohort"`.

- [ ] **Step 3: Implement.** Create `R/master_cohort.R`:

```r
#' Define a cohort by a query on a master view
#'
#' Finds every encounter in a master view that meets a qualifying condition, keeps those
#' inside an epoch, and returns them as a [new_cohort_record()] of [cohort_unit_id()]
#' units, ready for [pull_master()].
#'
#' `index` sets the unit of the study. `"first"` keeps each patient's earliest qualifying
#' encounter in the epoch, one row per patient; later encounters remain reachable as
#' follow-up events. `"all"` keeps every qualifying encounter in the epoch.
#'
#' A patient whose qualifying encounter in the epoch was preceded by one **before** the
#' epoch is a redo, not a first. Those units are always recorded as a second stage,
#' `prior_qualifying`, and the study chooses: `prior = "keep"` keeps them and records
#' their count in the stage's provenance; `prior = "exclude"` drops them with a reason.
#' Nothing is dropped silently.
#'
#' `qualifying` is SQL written by the study programmer, run as a `WHERE` clause on the
#' master. It must never be built from data. Only the key columns are read.
#'
#' @inheritParams pull_master
#' @param qualifying Character. A SQL boolean expression over the master's columns, for
#'   example `"proc = 'CABG'"`.
#' @param epoch A `Date` vector of length two: first and last encounter date, inclusive.
#' @param index `"first"` or `"all"`.
#' @param prior `"keep"` or `"exclude"`, for units with a qualifying encounter before
#'   the epoch.
#'
#' @return A `cohort_record` with `patient_id_col = "cohort_unit"` and the stages
#'   `qualifying` and `prior_qualifying`.
#'
#' @seealso [pull_master()], [cohort_unit_id()], [cohort_summary()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   # Synthetic data; no PHI.
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   DBI::dbWriteTable(con, "master_demo", data.frame(
#'     mrn = c("SYN101", "SYN101", "SYN102"),
#'     encounter_date = as.Date(c("1998-05-01", "2010-03-01", "2012-07-15")),
#'     proc = c("CABG", "CABG", "CABG")
#'   ))
#'   DBI::dbWriteTable(con, "master_demo_deployment", data.frame(sql_commit = "abc1234"))
#'   cohort <- define_cohort(con, "master_demo", "proc = 'CABG'",
#'                           epoch = as.Date(c("2000-01-01", "2024-07-31")),
#'                           dialect = "duckdb")
#'   cohort_summary(cohort)$stages
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#' }
#' }
#'
#' @export
define_cohort <- function(con, master, qualifying, epoch, index = c("first", "all"),
                          prior = c("keep", "exclude"), mrn_col = "mrn",
                          date_col = "encounter_date", dialect = c("mssql", "duckdb"),
                          deployment_view = paste0(master, "_deployment")) {
  index <- match.arg(index)
  prior <- match.arg(prior)
  dialect <- match.arg(dialect)
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
  q <- quoter(dialect)
  sql <- sprintf(
    paste("SELECT %s AS mrn, %s AS encounter_date FROM %s",
          "WHERE (%s) AND %s IS NOT NULL AND %s IS NOT NULL"),
    q(mrn_col), q(date_col), .qualified_name(master, dialect), qualifying,
    q(mrn_col), q(date_col)
  )

  read <- .with_snapshot_txn(con, dialect, {
    commit <- .read_deployment(con, deployment_view, dialect)
    rows <- run_step("read qualifying encounters", DBI::dbGetQuery(con, sql))
    list(commit = commit, rows = rows)
  })

  rows <- unique(data.frame(mrn = as.character(read$rows$mrn),
                            encounter_date = as.Date(read$rows$encounter_date),
                            stringsAsFactors = FALSE))
  in_epoch <- rows[rows$encounter_date >= epoch[[1]] & rows$encounter_date <= epoch[[2]], ,
                   drop = FALSE]
  if (!nrow(in_epoch)) {
    stop("No qualifying encounters fall in the epoch. Check 'qualifying' and 'epoch'.",
         call. = FALSE)
  }
  in_epoch <- in_epoch[order(in_epoch$mrn, in_epoch$encounter_date), , drop = FALSE]
  if (identical(index, "first")) {
    in_epoch <- in_epoch[!duplicated(in_epoch$mrn), , drop = FALSE]
  }
  units <- cohort_unit_id(in_epoch$mrn, in_epoch$encounter_date)
  has_prior <- in_epoch$mrn %in% unique(rows$mrn[rows$encounter_date < epoch[[1]]])
  n_prior <- sum(has_prior)

  query_prov <- sprintf("%s where %s; epoch %s to %s; index %s; SQL commit %s",
                        master, qualifying, format(epoch[[1]]), format(epoch[[2]]),
                        index, read$commit)
  prior_prov <- sprintf("%d unit(s) with a qualifying encounter before the epoch; %s",
                        n_prior, if (identical(prior, "keep")) "kept" else "excluded")
  exclude <- identical(prior, "exclude") & has_prior

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
    source = master,
    provenance = c(query_prov, prior_prov),
    stringsAsFactors = FALSE
  )
  new_cohort_record(members, stages, patient_id_col = "cohort_unit")
}
```

- [ ] **Step 4: Run the tests.**
  Run: `Rscript -e 'devtools::document(); devtools::test(filter = "master-cohort")'`
  Expected: all PASS.

- [ ] **Step 5: Commit.**

```bash
git add R/master_cohort.R man/define_cohort.Rd NAMESPACE tests/testthat/test-master-cohort.R
git commit -m "feat: define_cohort() selects encounters by query, epoch and index"
```

---

### Task 5: `freeze_study_pull()`, the retained pull and its provenance

**Files:**
- Create: `R/master_freeze.R`
- Test: `tests/testthat/test-master-freeze.R`

**Interfaces:**
- Consumes: `pull_master()` → `master_pull` (Task 3); `publish_dataset()` with parquet
  (Task 1).
- Produces: `freeze_study_pull(pull, study_config, datasets_dir, dataset_id,
  extract_date = Sys.Date())` → invisibly `list(release = <publish_dataset() release>,
  provenance_file = <path>)`. The sidecar `<release stem>.pull.yml` sits beside the release
  and holds `schema: 1`, `release_id`, `release_sha256`, `master`, `sql_commit`,
  `applied_correction_ids`, `read_at`, `columns`, `n_cohort`, `n_matched`, `n_unmatched`,
  `study_config_sha256`.

- [ ] **Step 1: Write the failing tests.** Create `tests/testthat/test-master-freeze.R`:

```r
# No PHI: identifiers and values are invented. Fixture in helper-master-pull.R.

local_frozen_pull <- function(env = parent.frame()) {
  skip_if_not_installed("arrow")
  con <- local_master_db(env)
  pull <- pull_master(con, "master_demo",
                      unit_cohort(c("SYN101", "SYN103"), c("2010-03-01", "2015-06-30")),
                      columns = "age", dialect = "duckdb")
  config <- withr::local_tempfile(fileext = ".yaml", .local_envir = env)
  writeLines("study: st0000", config)
  list(pull = pull, config = config,
       dir = withr::local_tempdir("published-", .local_envir = env))
}

test_that("the pull is published as parquet with a provenance sidecar", {
  f <- local_frozen_pull()
  out <- freeze_study_pull(f$pull, f$config, f$dir, "st0000_pull",
                           extract_date = "2026-11-16")

  expect_identical(tools::file_ext(out$release$file), "parquet")
  expect_identical(out$release$n_rows, 2L)
  side <- yaml::read_yaml(out$provenance_file)
  expect_identical(side$schema, 1L)
  expect_identical(side$release_id, out$release$release_id)
  expect_identical(side$sql_commit, "abc1234")
  expect_setequal(unlist(side$applied_correction_ids), c("C1", "C2"))
  expect_identical(side$study_config_sha256,
                   digest::digest(f$config, algo = "sha256", file = TRUE))
})

test_that("freezing the same pull twice returns the same release", {
  f <- local_frozen_pull()
  a <- freeze_study_pull(f$pull, f$config, f$dir, "st0000_pull", extract_date = "2026-11-16")
  b <- freeze_study_pull(f$pull, f$config, f$dir, "st0000_pull", extract_date = "2026-11-16")
  expect_identical(a$release$release_id, b$release$release_id)
  expect_identical(a$provenance_file, b$provenance_file)
})

test_that("a changed sidecar is never overwritten", {
  f <- local_frozen_pull()
  out <- freeze_study_pull(f$pull, f$config, f$dir, "st0000_pull",
                           extract_date = "2026-11-16")
  side <- yaml::read_yaml(out$provenance_file)
  side$sql_commit <- "tampered"
  yaml::write_yaml(side, out$provenance_file)

  expect_error(
    freeze_study_pull(f$pull, f$config, f$dir, "st0000_pull", extract_date = "2026-11-16"),
    "never overwritten"
  )
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
#' Freeze a study's pull from a master view
#'
#' Sources are not time-travelable, so the release, not the warehouse, is the record of
#' what a study read. `freeze_study_pull()` publishes the pull as an immutable parquet
#' release with [publish_dataset()] and writes a provenance sidecar beside it: the SQL
#' model commit the master was deployed from, the ids of the corrections applied, when
#' the pull read, its shape, and the study configuration's checksum.
#'
#' The retained pull holds patient values. It belongs in the study's data folder under
#' the same rules as the built dataset, never in a repository.
#'
#' Freezing the same pull again is idempotent. A sidecar that exists and differs is an
#' integrity error and is never overwritten.
#'
#' @param pull A `master_pull` from [pull_master()].
#' @param study_config Character. Path to the study configuration file whose checksum is
#'   recorded.
#' @param datasets_dir,dataset_id,extract_date As for [publish_dataset()].
#'
#' @return Invisibly, a list with `release` (as returned by [publish_dataset()]) and
#'   `provenance_file`, the sidecar's path.
#'
#' @seealso [pull_master()], [publish_dataset()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE) &&
#'       requireNamespace("arrow", quietly = TRUE)) {
#'   # Synthetic data; no PHI.
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   DBI::dbWriteTable(con, "master_demo", data.frame(
#'     mrn = "SYN101", encounter_date = as.Date("2010-03-01"), age = 62
#'   ))
#'   DBI::dbWriteTable(con, "master_demo_corrections_applied", data.frame(
#'     correction_id = character(), mrn = character(), encounter_date = as.Date(character())
#'   ))
#'   DBI::dbWriteTable(con, "master_demo_deployment", data.frame(sql_commit = "abc1234"))
#'   cohort <- new_cohort_record(
#'     members = data.frame(patient_id = cohort_unit_id("SYN101", as.Date("2010-03-01")),
#'                          stage_id = "selected", included = TRUE, reason = NA_character_),
#'     stages = data.frame(stage_id = "selected", order = 1L, label = "Selected",
#'                         source = "synthetic", provenance = "example"),
#'     patient_id_col = "cohort_unit"
#'   )
#'   pull <- pull_master(con, "master_demo", cohort, columns = "age", dialect = "duckdb")
#'   config <- tempfile(fileext = ".yaml")
#'   writeLines("study: st0000", config)
#'   published <- tempfile("published-")
#'   dir.create(published)
#'   frozen <- freeze_study_pull(pull, config, published, "st0000_pull")
#'   basename(frozen$provenance_file)
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

  draft <- tempfile(fileext = ".parquet")
  on.exit(unlink(draft), add = TRUE)
  arrow::write_parquet(pull$data, draft)

  p <- pull$provenance
  release <- publish_dataset(
    draft, dataset_id, datasets_dir, extract_date = extract_date,
    source = sprintf("pull_master() from %s at SQL commit %s", p$master, p$sql_commit)
  )

  side <- list(
    schema = 1L,
    release_id = release$release_id,
    release_sha256 = release$sha256,
    master = p$master,
    sql_commit = p$sql_commit,
    applied_correction_ids = as.list(p$applied_correction_ids),
    read_at = p$read_at,
    columns = as.list(p$columns),
    n_cohort = p$n_cohort,
    n_matched = p$n_matched,
    n_unmatched = p$n_unmatched,
    study_config_sha256 = digest::digest(study_config, algo = "sha256", file = TRUE)
  )
  text <- yaml::as.yaml(side)
  path <- file.path(datasets_dir,
                    paste0(tools::file_path_sans_ext(release$file), ".pull.yml"))

  if (file.exists(path)) {
    if (!identical(paste(readLines(path), collapse = "\n"), sub("\n$", "", text))) {
      stop("The provenance sidecar for release ", release$release_id, " exists and ",
           "differs from this pull. A sidecar is never overwritten.", call. = FALSE)
    }
  } else {
    staged <- tempfile(".pull-", tmpdir = datasets_dir, fileext = ".yml")
    writeLines(sub("\n$", "", text), staged)
    if (!file.rename(staged, path)) {
      unlink(staged)
      stop("Could not move the provenance sidecar into place.", call. = FALSE)
    }
  }
  invisible(list(release = release, provenance_file = path))
}
```

- [ ] **Step 4: Run the tests.**
  Run: `Rscript -e 'devtools::document(); devtools::test(filter = "master-freeze")'`
  Expected: all PASS. If "freezing the same pull twice" fails because `publish_dataset()`
  makes an `_r2` revision, the parquet bytes differ between writes: compare the two
  drafts' SHA-256s, and if arrow embeds a varying value, write with
  `arrow::write_parquet(..., compression = "snappy")` and recheck before changing anything
  else. Do not weaken the idempotence test.

- [ ] **Step 5: Commit.**

```bash
git add R/master_freeze.R man/freeze_study_pull.Rd NAMESPACE tests/testthat/test-master-freeze.R
git commit -m "feat: freeze_study_pull() publishes the pull with a provenance sidecar"
```

---

### Task 6: reference index, news fragment and the full gate

**Files:**
- Modify: `_pkgdown.yml` (after the "Pull: Warehouse to R" group)
- Create: `news/<implementation branch with / as ->.md`

- [ ] **Step 1: Add the reference group.** In `_pkgdown.yml`, after the `Pull: Warehouse to
  R` group's contents, insert:

```yaml
- title: "Pull: Master views to a study"
  desc: >
    Define a cohort of encounters by query, pull its rows and the study's columns from a
    master view in one consistent read, and freeze the pull with its provenance.
  contents:
  - cohort_unit_id
  - split_cohort_unit
  - define_cohort
  - pull_master
  - print.master_pull
  - freeze_study_pull
```

- [ ] **Step 2: Write the news fragment** (named for the implementation branch, for example
  `news/feat-master-study-pull.md`):

```markdown
* New `pull_master()` reads a study's cohort and columns from a master view in one
  consistent read, joined through a session temp table, and records the SQL commit and
  the ids of the corrections applied. `define_cohort()` selects encounters by query,
  epoch and index (`"first"` or `"all"`), recording a qualifying encounter before the
  epoch as a counted stage. `freeze_study_pull()` publishes the pull as a parquet release
  with a provenance sidecar.
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
- **A real SQL Server rehearsal** of the consistent pull (a decision committed during a pull
  must be absent from both the data and the applied ids; spec §9). It needs the warehouse,
  so it is the first acceptance step of plan 3, not a unit test here.
- **Corrections intake, study candidates, generated corrected views and the parity gate**:
  plan 2.
