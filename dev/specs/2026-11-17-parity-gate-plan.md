# The parity gate: implementation plan (plan 2b of the master-views design)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate a master's deployed rules against a SAS build of the same source state, so
that only a master whose deployment passed is offered to study builds, and a gate run can
never pass on data that moved underneath it.

**Architecture:** Three exports run in order. `open_gate_run()` opens a run **before** the
SAS build: in fallback mode it records a change marker per source (row count and an XOR of
row hashes). `load_oracle()` loads the SAS build's parquet as `<master>_oracle_<YYYYMMDD>`
through the load step it now shares with `lift_master()`, and records **oracle integrity**,
never parity. `parity_gate()` compares the rules view in a gate schema with the oracle, every
cell joined on the key, **inside the database** (only counts come back), explains differing
cells by activated legacy corrections, retakes the markers, and records the outcome. A pass
or a fail is written to `<master>_parity`, against the commit in the gate schema's
`<master>_deployment`; `pull_master()` already fails closed on that table, so a fail blocks
the commit it tested until a later pass. A void run writes only to the gate's own tables.

**Tech Stack:** R (>= 4.4.0), DBI, duckdb 2.0.0 (tests), arrow, jsonlite, digest,
testthat 3.

**Spec:** `dev/specs/2026-11-16-master-views-design.md` §7 (the parity gate), the §8 bullets
on the gate, and the §9 bullets "Gate isolation" and "Gate rehearsal". The contract tables
come from plan 1 (`2026-11-16-master-study-pull-plan.md`, "Contracts this plan assumes from
plan 3"). **Out of this plan:** correction intake and candidates (plan 2a), and everything
that needs SQL Server or data engineering (plan 3, listed at the end).

**Verified before writing.** Every code block in Tasks 1 to 6 was run in a scratch copy of
the package at `ea9f788` with duckdb 2.0.0 (revised and re-run after decision 2 changed): the
new and neighbouring test files pass (72 tests across the gate, lift, steps and pull files,
no skips); `lintr` reports nothing on the
new files apart from `object_usage_linter`, which needs the package installed and was not
run; and `devtools::check(args = "--no-manual")`, which runs the full suite, is 0 errors,
0 warnings, 0 notes. The examples of the three exports run. The state between Task 5 and
Task 6 was also run, extracted from this file: the parity-gate tests pass and the four
void tests fail as Task 6 Step 2 says, and Task 6's replacements applied to Task 5's code
reproduce the verified file. Nothing here was run on SQL Server.

### Decisions the spec left open, made here

1. **An activated legacy correction** is a row of `<master>_corrections` with
   `evidence_type = 'legacy_sas_inline'` (as `backfill_corrections()` records it) whose latest
   decision in `<master>_correction_decisions` is `accept`. A `bake` decision records a fix
   without activating it. A differing cell is **explained** when an activated legacy
   correction names that row's key and that column, and its new value is the oracle's value
   (same cast and tolerance as the comparison; `new_value_missing = 1` matches a missing
   oracle value). These are the only legacy corrections stored today. Plan 2a
   (`2026-11-17-corrections-plan.md`) adds per-source correction tables; once plan 3
   re-expresses the legacy fixes against source columns, the gate's reader moves to those
   tables, and until then it reads the master-keyed record.
2. **A failed run writes a `"fail"` row to `<master>_parity`** (with its `run_id`) for the
   commit it tested, and a pass writes a `"pass"` row. `pull_master()` takes the latest
   verdict for the deployed commit, so a fail blocks that commit until a later pass. **A
   void run writes nothing to `<master>_parity`**: it says nothing about the rules, so an
   earlier verdict for the commit stands. Every run's evidence also goes to four gate
   tables: `<master>_gate_runs`, `<master>_gate_markers`, `<master>_gate_verdicts` and
   `<master>_gate_outcomes`. This amends §8, which said failing the gate never changes the
   parity records (Task 7). The gate never changes the master's view or its metadata.
3. **`<master>_parity` is the name `lift_master()` already uses** for a table of a different
   shape (`base_table`, `parquet_sha256`, `verdict`, `checked_at`). The gate refuses such a
   table (`parity_table_shape`) rather than append to it, and writes `sql_commit`, `verdict`,
   `verified_at` and `run_id`. `pull_master()` reads only the first three.
4. **A third export, `open_gate_run()`.** The spec names two functions, but the fallback's
   first marker must be taken before the SAS run, which is before either of them.
5. **A rules column SAS never produced** is reported `not_in_oracle` and does not fail the
   gate: there is nothing to compare it with. An oracle column the rules lack is
   `missing_in_rules` and fails it.
6. **The oracle's date** is the SAS run date, supplied by the caller, as `YYYYMMDD`.
7. **The gate refuses an oracle without a passing integrity record** (`oracle_not_verified`),
   so a half-loaded or mismatched oracle can never be gated against.
8. **Cells are compared after `TRY_CAST` of both sides to the oracle column's class** (number,
   date, timestamp or text). A rules value that does not cast differs, even from a missing
   oracle value, so a failed cast never passes as a missing value. Numbers use the absolute
   tolerance `1e-8`, as `compare_built()` does.
9. **The marker is the same shape on both dialects**: an XOR of row hashes, which is what
   `CHECKSUM_AGG` is, and `bit_xor(hash(row))` on duckdb (probed on 2.0.0). An empty source
   reads `'empty'`. Change tracking (§7.1 "where enabled") is not implemented; it is a
   plan 3 option.

## Global constraints

- Lines are **100 characters** (`.lintr`). Roxygen markdown is enabled.
- testthat **edition 3**. Test files are `test-*.R`, with a hyphen.
- **No PHI.** Every fixture is invented and says so ("No PHI: identifiers and values are
  invented."). **No identifier or data value appears in any error, warning, message or print
  output.** Counts, verdicts, table names and run ids only.
- **Errors a caller may catch use `.abort(condition, ...)`** (`R/rubric.R`), class
  `hvtiRdatabuild_<condition>`, with the message prefixed `fn(): `. Wrap every DBI call in
  `run_step(name, expr)` (`R/sql_dialect.R`), which withholds the driver's message.
- **Informational messages go through `.hvti_inform()`**, so `hvti.quiet` silences them.
- Dialects are exactly `"mssql"` and `"duckdb"`, as elsewhere (`quoter()`, `sql_types()`).
- **SQL stays in the shared subset** so one statement runs on both dialects: `CASE`, `EXISTS`,
  `NOT EXISTS`, `TRY_CAST`, `ROW_NUMBER() OVER`, `COUNT`/`SUM`, `GROUP BY ... HAVING`, CTEs.
  A subquery never sits inside an aggregate (SQL Server error 130): the per-cell `CASE` is
  computed in a derived table and summed outside it. The marker is the one dialect-specific
  statement, built by `.gate_marker_sql()`.
- `arrow`, `duckdb`, `jsonlite`, `tidyselect` and `withr` are **Suggests**. Tests call
  `skip_if_not_installed()`; runtime code checks `requireNamespace()` and stops with a clear
  message, as `lift_master()` does.
- **No version bump.** One news fragment, `news/feat-parity-gate.md` (for the implementation
  branch `feat/parity-gate`), bullets only, no heading (Task 7). This plan is under `dev/`,
  which `.Rbuildignore` excludes, so the plan's own PR needs none.
- Done means: `devtools::document()` run and committed; `devtools::test()` passing with no new
  skips; `devtools::check()` 0 errors, 0 warnings, 0 notes; `lintr::lint_package()` clean;
  `pkgdown::check_pkgdown()` clean.

## Contracts

From plan 1, unchanged: `<master>_deployment` (`sql_commit`, one row) and `<master>_parity`
(`sql_commit`, `verdict`, `verified_at`), which `pull_master()` reads in its snapshot and
fails closed on. This plan adds:

| Object | Columns | Written by |
|---|---|---|
| `<gate_schema>.<master>` | the rules view, deployed for the gate, **reading the uncorrected `stg_<source>` views, not `stg_<source>_corrected`** | plan 3's deploy step |
| `<gate_schema>.<master>_deployment` | `sql_commit` (one row) | plan 3's deploy step |
| `<master>_oracle_<YYYYMMDD>` | the SAS build's columns | `load_oracle()` |
| `<master>_oracle_integrity` | `oracle_table`, `parquet_sha256`, `source_sha256`, `verdict`, `checked_at` | `load_oracle()` |
| `<master>_gate_runs` | `run_id`, `master`, `mode`, `snapshot_name`, `n_sources`, `opened_at` | `open_gate_run()` |
| `<master>_gate_markers` | `run_id`, `phase` (`before`/`after`), `source`, `n_rows`, `checksum`, `taken_at` | `open_gate_run()`, `parity_gate()` |
| `<master>_gate_verdicts` | `run_id`, `variable`, `verdict`, `n_compared`, `n_differ`, `n_explained` | `parity_gate()` |
| `<master>_gate_outcomes` | `run_id`, `sql_commit`, `gate_schema`, `oracle_table`, `outcome` (`pass`/`fail`/`void`), `closed_at` | `parity_gate()` |
| `<master>_parity` | adds `run_id` | `parity_gate()`, on a pass or a fail; never on a void run |

**Plan 3 contract: the gate's rules read uncorrected sources.** The gate schema's rules
models select from the `stg_<source>` views, never `stg_<source>_corrected`. The SAS build
applies only its own inline fixes, so a non-legacy correction accepted after the SAS build
would otherwise appear as an unexplained difference and fail the gate. With uncorrected
inputs, the legacy inline fixes are the only differences the gate explains, and the
production deployment of the same commit reads the corrected views as usual.

## File structure

| File | Responsibility |
|---|---|
| `R/master_lift.R` (modify) | `lift_master()` calls the shared step; new `.read_verified_meta()`, `.load_and_verify()` |
| `R/master_steps.R` (modify) | `load_parquet()` names its caller in the load-log error |
| `R/master_config.R` (modify) | `.master_tables()` names the oracle and gate tables |
| `R/oracle_load.R` (new) | `load_oracle()` |
| `R/gate_markers.R` (new) | marker SQL, `.take_markers()`, `.markers_changed()`, `.read_markers()`, `open_gate_run()` |
| `R/gate_compare.R` (new) | the comparison SQL and `.gate_compare()` |
| `R/parity_gate.R` (new) | run, oracle and parity-table checks; `parity_gate()` |
| `tests/testthat/helper-parity-gate.R` (new) | duckdb gate fixture, oracle parquet, legacy corrections, `gate_run()` |
| `tests/testthat/test-master-lift.R` (modify) | the shared load step |
| `tests/testthat/test-oracle-load.R`, `test-gate-markers.R`, `test-gate-compare.R`, `test-parity-gate.R`, `test-gate-void.R` (new) | tests |
| `dev/specs/2026-11-16-master-views-design.md` (modify) | the §7.2 record of the parity view |
| `_pkgdown.yml` (modify), `news/feat-parity-gate.md` (new) | reference group, news |

---

### Task 1: factor the shared load step out of `lift_master()`

`load_oracle()` must load and check a table exactly as `lift_master()` does, and must not
reach `lift_master()`'s publishing tail (parity record, metadata, `.publish_views()`). So the
load is moved into its own function, and `lift_master()` calls it. Behaviour of
`lift_master()` does not change; its existing tests are the guard.

**Files:**
- Modify: `R/master_lift.R` (the sidecar block, about lines 77–87; the create/load/check
  block, about lines 113–141; append two helpers at the end)
- Modify: `R/master_steps.R` (`load_parquet()`, about lines 190–220)
- Test: `tests/testthat/test-master-lift.R`

**Interfaces:**
- Consumes: `load_parquet()`, `parity_check()`, `parity_full()`, `parity_summary()`,
  `full_summary()`, `.zap_all()`, `master_ddl()` (all `R/master_steps.R`).
- Produces: `.read_verified_meta(parquet, remedy)` returns the sidecar list, stopping when it
  is missing or its `parquet_sha256` is stale. `.load_and_verify(con, parquet, table, ddl,
  sha256, key, dialect, label, caller)` returns `TRUE` or `FALSE` and writes only `table` and
  `<table>__load_log`. `label` is `"parity"` or `"oracle integrity"` and names the steps and
  messages. `load_parquet(..., caller = "lift_master")` gains `caller`.

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-master-lift.R`
  (it already defines `lift_fixture()`):

```r
test_that("the shared load step loads and verifies a table and publishes nothing", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("dplyr")
  skip_if_not_installed("withr")
  skip_if_not_installed("tidyselect")
  f <- lift_fixture()
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  meta <- .read_verified_meta(f$pq, "snapshot_master()")
  ddl <- master_ddl(f$pq, "t_loaded")
  msgs <- capture_messages(
    ok <- .load_and_verify(con, f$pq, "t_loaded", ddl, meta$parquet_sha256, f$cfg$key,
                           "duckdb", label = "oracle integrity", caller = "load_oracle")
  )
  expect_true(ok)
  expect_setequal(DBI::dbListTables(con), c("t_loaded", "t_loaded__load_log"))
  expect_false(any(grepl("parity", msgs)))
})

test_that("the shared load step reports a failed check without the full compare", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("dplyr")
  skip_if_not_installed("withr")
  skip_if_not_installed("tidyselect")
  f <- lift_fixture()
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  local_mocked_bindings(
    parity_check = function(...) {
      list(verdict = "fail", row_count = "mismatch",
           columns = data.frame(variable = "age", verdict = "mismatch"),
           sample = data.frame(variable = character(), verdict = character()))
    },
    parity_full = function(...) stop("the full compare must not run")
  )
  ok <- suppressMessages(.load_and_verify(con, f$pq, "t_loaded", master_ddl(f$pq, "t_loaded"),
                                          .file_sha256(f$pq), f$cfg$key, "duckdb",
                                          label = "parity", caller = "lift_master"))
  expect_false(ok)
})
```

- [ ] **Step 2: Run them and confirm they fail.**
  Run: `Rscript -e 'devtools::test(filter = "master-lift")'`
  Expected: 2 errors, `could not find function ".read_verified_meta"` and
  `could not find function ".load_and_verify"`; the existing lift tests pass.

- [ ] **Step 3: Give `load_parquet()` its caller.** In `R/master_steps.R`, add to its roxygen
  block after the `@param sha256` line:

```r
#' @param caller Character. The exported function that loads, named in the load-log error.
```

  Replace its signature's second line

```r
                         sha256 = .file_sha256(parquet)) {
```

  with

```r
                         sha256 = .file_sha256(parquet), caller = "lift_master") {
```

  and in the `load_log_mismatch` abort replace

```r
           "lift_master(): target table ", table, " holds row groups loaded from a ",
```

  with

```r
           caller, "(): target table ", table, " holds row groups loaded from a ",
```

- [ ] **Step 4: Append the two helpers to `R/master_lift.R`.**

```r

#' A snapshot's sidecar, after checking the parquet still matches it
#'
#' @param parquet Path to a parquet snapshot with a `.meta.json` sidecar.
#' @param remedy Character. The function to re-run, named in the message.
#'
#' @return The sidecar, as a list. Stops when the sidecar is missing or its
#'   `parquet_sha256` is not the parquet's checksum.
#'
#' @keywords internal
#' @noRd
.read_verified_meta <- function(parquet, remedy) {
  meta_path <- .snapshot_meta_path(parquet)
  if (!file.exists(meta_path)) {
    stop("The parquet's metadata sidecar is missing: ", meta_path,
         ". Re-run ", remedy, ".", call. = FALSE)
  }
  meta <- jsonlite::read_json(meta_path, simplifyVector = TRUE)
  if (!identical(.file_sha256(parquet), as.character(meta$parquet_sha256))) {
    stop("The parquet does not match its sidecar checksum; re-run ", remedy, ".",
         call. = FALSE)
  }
  meta
}

#' Create a table, load a parquet into it, and prove the two equal
#'
#' The load step `lift_master()` and `load_oracle()` share. It creates the
#' table when absent, loads the parquet a row group at a time, then checks
#' aggregates and a sample, and, only when those pass, every cell joined on
#' the key. It publishes nothing: no view, metadata or record is written here.
#'
#' @param con A DBI connection.
#' @param parquet Path to the parquet snapshot.
#' @param table Character. The table to create and load.
#' @param ddl A list as returned by `master_ddl()`.
#' @param sha256 Character. The parquet's sha256, as its sidecar records it.
#' @param key Character. The key columns.
#' @param dialect `"mssql"` or `"duckdb"`.
#' @param label Character. What the check is called in messages and step names:
#'   `"parity"` for a lift, `"oracle integrity"` for an oracle.
#' @param caller Character. The exported function, for the load log's message.
#'
#' @return `TRUE` when both checks pass, `FALSE` otherwise.
#'
#' @keywords internal
#' @noRd
.load_and_verify <- function(con, parquet, table, ddl, sha256, key, dialect, label, caller) {
  if (!DBI::dbExistsTable(con, table)) {
    run_step("create table", {
      if (dialect == "mssql") {
        # The hand-off DDL names dbo; executed, the table belongs in the login's
        # default schema. Reuse it rather than re-measure every text column.
        DBI::dbExecute(con, sub("CREATE TABLE [dbo].", "CREATE TABLE ", ddl$sql,
                                fixed = TRUE))
      } else {
        proto <- as.data.frame(arrow::ParquetFileReader$create(parquet)$ReadRowGroup(0L))
        DBI::dbCreateTable(con, table, .zap_all(proto)[0, , drop = FALSE])
      }
    })
  }
  r <- run_step("load", load_parquet(con, parquet, table, sha256 = sha256, caller = caller))
  .hvti_inform("load: ", r$loaded, " row groups loaded, ", r$skipped, " already present")

  # The summaries say "parity"; an oracle's check is not parity and must not say so.
  relabel <- function(x) if (label == "parity") x else sub("^parity(_full)?", label, x)
  res <- run_step(paste(label, "check"),
                  parity_check(con, table, parquet, key, dialect = dialect))
  .hvti_inform(relabel(parity_summary(res)))
  if (res$verdict != "pass") return(FALSE)
  full <- run_step(paste("full", label, "check"),
                   parity_full(con, table, parquet, key, dialect = dialect))
  .hvti_inform(relabel(full_summary(full)))
  all(full$verdict == "match")
}
```

- [ ] **Step 5: Make `lift_master()` use them.** In `R/master_lift.R`, replace

```r
  meta_path <- .snapshot_meta_path(parquet)
  if (!file.exists(meta_path)) {
    stop("The parquet's metadata sidecar is missing: ", meta_path,
         ". Re-run snapshot_master().", call. = FALSE)
  }
  meta <- jsonlite::read_json(meta_path, simplifyVector = TRUE)
  if (!identical(.file_sha256(parquet), as.character(meta$parquet_sha256))) {
    stop("The parquet does not match its sidecar checksum; re-run snapshot_master().",
         call. = FALSE)
  }
  .check_source_current(config, meta)
```

  with

```r
  meta <- .read_verified_meta(parquet, "snapshot_master()")
  .check_source_current(config, meta)
```

  and replace the block from `tabs <- .master_tables(config)` through the `parity_failed`
  abort:

```r
  tabs <- .master_tables(config)
  if (!DBI::dbExistsTable(con, base)) {
    run_step("create base table", {
      if (dialect == "mssql") {
        # The hand-off DDL names dbo; executed, the table belongs in the login's
        # default schema. Reuse it rather than re-measure every text column.
        DBI::dbExecute(con, sub("CREATE TABLE [dbo].", "CREATE TABLE ", ddl$sql,
                                fixed = TRUE))
      } else {
        proto <- as.data.frame(arrow::ParquetFileReader$create(parquet)$ReadRowGroup(0L))
        DBI::dbCreateTable(con, base, .zap_all(proto)[0, , drop = FALSE])
      }
    })
  }
  r <- run_step("load", load_parquet(con, parquet, base,
                                     sha256 = as.character(meta$parquet_sha256)))
  .hvti_inform("load: ", r$loaded, " row groups loaded, ", r$skipped, " already present")

  res <- run_step("parity check", parity_check(con, base, parquet, config[["key"]],
                                               dialect = dialect))
  .hvti_inform(parity_summary(res))
  full <- if (res$verdict == "pass") {
    run_step("full parity check", parity_full(con, base, parquet, config[["key"]],
                                              dialect = dialect))
  } else {
    NULL
  }
  if (!is.null(full)) .hvti_inform(full_summary(full))
  if (res$verdict != "pass" || any(full$verdict != "match")) {
    .abort("parity_failed", "lift_master(): Parity failed; the view was not created.")
  }
```

  with

```r
  tabs <- .master_tables(config)
  ok <- .load_and_verify(con, parquet, base, ddl, as.character(meta$parquet_sha256),
                         config[["key"]], dialect, label = "parity", caller = "lift_master")
  if (!ok) {
    .abort("parity_failed", "lift_master(): Parity failed; the view was not created.")
  }
```

  Everything after (`parity_row`, `record parity`, `write metadata`, `.publish_views()`)
  stays as it is: that is the publishing tail, and only `lift_master()` has it.

- [ ] **Step 6: Run the tests.**
  Run: `Rscript -e 'devtools::test(filter = "master-lift|master-steps|master-corrections|master-e2e")'`
  Expected: all pass, including the two new tests and every existing lift test.

- [ ] **Step 7: Commit.**

```bash
git add R/master_lift.R R/master_steps.R tests/testthat/test-master-lift.R
git commit -m "refactor: share lift_master()'s load and checks, not its publishing"
```

---

### Task 2: `load_oracle()`, an answer key that publishes nothing

**Files:**
- Modify: `R/master_config.R` (`.master_tables()`, last function)
- Create: `R/oracle_load.R`
- Create: `tests/testthat/helper-parity-gate.R`
- Test: `tests/testthat/test-oracle-load.R`

**Interfaces:**
- Consumes: `.read_verified_meta()`, `.load_and_verify()` (Task 1); `key_verdict()`,
  `format_key_verdict()`, `master_ddl()`.
- Produces: `load_oracle(config, con, parquet, run_date, dry_run = TRUE, dialect = "mssql")`,
  returning invisibly `list(dry_run, oracle_table, ddl_path, verdict)`. `.master_tables()`
  gains `oracle_integrity`, `gate_runs`, `gate_markers`, `gate_verdicts`, `gate_outcomes`
  (all names Tasks 3 to 6 use). The test helpers `gate_config()`, `gate_source()`,
  `write_oracle_parquet()`, `seed_gate_db()`, `local_gate_db()` (returns
  `list(con, dir, cfg)`) and `production_state()`.

- [ ] **Step 1: Write the test helper.** Create `tests/testthat/helper-parity-gate.R`:

```r
# No PHI: identifiers and values are invented.

# The master's configuration, with the master_demo name the pull fixtures use.
gate_config <- function(dir) {
  structure(list(name = "master_demo", key = c("mrn", "encounter_date"), alt_keys = list(),
                 parent = NULL, parent_release = NULL, snapshots = dir,
                 current = "built.sas7bdat", history = NULL,
                 build_program = file.path(dir, "bd.sas"),
                 file = file.path(dir, "master.yml")), class = "master_config")
}

# The source the SAS build and the rules both read. The rules reproduce it as is.
gate_source <- function() {
  data.frame(
    mrn = c("SYN201", "SYN202", "SYN203", "SYN204"),
    encounter_date = as.Date(c("2011-01-05", "2013-04-20", "2016-09-09", "2019-12-01")),
    age = c(61, 72, 58, 66), lvef = c(55, 40, NA, 35),
    proc = c("CABG", "AVR", "CABG", "MVR"), stringsAsFactors = FALSE
  )
}

# A SAS build's parquet snapshot, with the sidecar snapshot_oracle() writes.
write_oracle_parquet <- function(dir, d = gate_source(), name = "gate_build.parquet") {
  pq <- file.path(dir, name)
  arrow::write_parquet(d, pq)
  jsonlite::write_json(list(parquet_sha256 = .file_sha256(pq), source = "gate_build.sas7bdat",
                            source_sha256 = strrep("a", 64)),
                       .snapshot_meta_path(pq), auto_unbox = TRUE)
  pq
}

# The source; a gate schema holding the rules view and its deployment; and the
# production master with its metadata, deployment and one earlier parity pass.
seed_gate_db <- function(con) {
  DBI::dbWriteTable(con, "stg_demo", gate_source())
  DBI::dbWriteTable(con, "stg_other", data.frame(code = c("A", "B")))
  DBI::dbExecute(con, "CREATE SCHEMA gate")
  DBI::dbExecute(con, paste("CREATE VIEW gate.master_demo AS",
                            "SELECT mrn, encounter_date, age, lvef, proc FROM stg_demo"))
  DBI::dbExecute(con, "CREATE TABLE gate.master_demo_deployment AS SELECT 'def5678' AS sql_commit")
  DBI::dbExecute(con, "CREATE VIEW master_demo AS SELECT * FROM stg_demo")
  DBI::dbWriteTable(con, "master_demo_meta",
                    data.frame(variable = c("mrn", "age"), r_class = c("character", "numeric")))
  DBI::dbWriteTable(con, "master_demo_deployment", data.frame(sql_commit = "def5678"))
  DBI::dbWriteTable(con, "master_demo_parity", data.frame(
    sql_commit = "abc1234", verdict = "pass",
    verified_at = as.POSIXct("2026-11-01 12:00:00", tz = "UTC"), run_id = "G0"
  ))
  DBI::dbWriteTable(con, "master_demo_corrections_applied", data.frame(
    correction_id = character(), mrn = character(), encounter_date = as.Date(character())
  ))
  invisible(con)
}

local_gate_db <- function(env = parent.frame()) {
  for (p in c("duckdb", "arrow", "jsonlite", "tidyselect", "dplyr", "withr")) {
    testthat::skip_if_not_installed(p)
  }
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
  seed_gate_db(con)
  dir <- withr::local_tempdir(.local_envir = env)
  list(con = con, dir = dir, cfg = gate_config(dir))
}

# What the gate must never change: the production view's definition and rows,
# its metadata and its parity records.
production_state <- function(con) {
  list(
    view_sql = DBI::dbGetQuery(con, paste("SELECT sql FROM duckdb_views()",
                                          "WHERE view_name = 'master_demo'",
                                          "AND schema_name = 'main'"))$sql,
    view = DBI::dbGetQuery(con, "SELECT * FROM master_demo ORDER BY mrn"),
    meta = DBI::dbGetQuery(con, "SELECT * FROM master_demo_meta ORDER BY variable"),
    parity = DBI::dbGetQuery(con, "SELECT * FROM master_demo_parity ORDER BY verified_at")
  )
}
```

- [ ] **Step 2: Write the failing tests.** Create `tests/testthat/test-oracle-load.R`:

```r
# Tests for load_oracle(), on duckdb with invented data. No PHI.

test_that("the dry run writes the DDL and creates nothing", {
  g <- local_gate_db()
  pq <- write_oracle_parquet(g$dir)
  before <- DBI::dbListTables(g$con)
  res <- load_oracle(g$cfg, g$con, pq, "2026-11-17", dialect = "duckdb")
  expect_true(res$dry_run)
  expect_identical(res$oracle_table, "master_demo_oracle_20261117")
  expect_true(file.exists(res$ddl_path))
  expect_setequal(DBI::dbListTables(g$con), before)
})

test_that("an executed load records oracle integrity and publishes nothing", {
  g <- local_gate_db()
  pq <- write_oracle_parquet(g$dir)
  state <- production_state(g$con)
  msgs <- capture_messages(
    res <- load_oracle(g$cfg, g$con, pq, as.Date("2026-11-17"), dry_run = FALSE,
                       dialect = "duckdb")
  )
  expect_identical(res$verdict, "pass")
  expect_false(any(grepl("parity", msgs)))
  expect_true(any(grepl("^oracle integrity pass", msgs)))
  n <- DBI::dbGetQuery(g$con, "SELECT COUNT(*) AS n FROM master_demo_oracle_20261117")$n
  expect_equal(as.numeric(n), 4)
  rec <- DBI::dbGetQuery(g$con, "SELECT * FROM master_demo_oracle_integrity")
  expect_identical(rec$oracle_table, "master_demo_oracle_20261117")
  expect_identical(rec$verdict, "pass")
  expect_identical(rec$parquet_sha256, .file_sha256(pq))
  expect_identical(production_state(g$con), state)
  expect_false(any(grepl("^master_demo_base_", DBI::dbListTables(g$con))))
})

test_that("a key that is not unique stops before the oracle table is created", {
  g <- local_gate_db()
  d <- gate_source()
  d$mrn[[2]] <- d$mrn[[1]]
  d$encounter_date[[2]] <- d$encounter_date[[1]]
  pq <- write_oracle_parquet(g$dir, d)
  expect_error(
    suppressMessages(load_oracle(g$cfg, g$con, pq, "2026-11-17", dry_run = FALSE,
                                 dialect = "duckdb")),
    class = "hvtiRdatabuild_key_not_unique"
  )
  expect_false(DBI::dbExistsTable(g$con, "master_demo_oracle_20261117"))
})

test_that("a failed integrity check is recorded, stops, and leaves production alone", {
  g <- local_gate_db()
  pq <- write_oracle_parquet(g$dir)
  state <- production_state(g$con)
  local_mocked_bindings(parity_check = function(...) {
    list(verdict = "fail", row_count = "mismatch",
         columns = data.frame(variable = "age", verdict = "mismatch"),
         sample = data.frame(variable = character(), verdict = character()))
  })
  expect_error(
    suppressMessages(load_oracle(g$cfg, g$con, pq, "2026-11-17", dry_run = FALSE,
                                 dialect = "duckdb")),
    class = "hvtiRdatabuild_oracle_integrity_failed"
  )
  rec <- DBI::dbGetQuery(g$con, "SELECT verdict FROM master_demo_oracle_integrity")
  expect_identical(rec$verdict, "fail")
  expect_identical(production_state(g$con), state)
})

test_that("run_date must be one date", {
  g <- local_gate_db()
  pq <- write_oracle_parquet(g$dir)
  expect_error(load_oracle(g$cfg, g$con, pq, "not a date", dialect = "duckdb"), "run_date")
  expect_error(load_oracle(g$cfg, g$con, pq, as.Date(c("2026-11-17", "2026-11-18")),
                           dialect = "duckdb"), "run_date")
})
```

- [ ] **Step 3: Run them and confirm they fail.**
  Run: `Rscript -e 'devtools::test(filter = "oracle-load")'`
  Expected: 5 errors, `could not find function "load_oracle"`.

- [ ] **Step 4: Name the new tables.** In `R/master_config.R`, `.master_tables()`, replace

```r
       meta        = paste0(n, "_meta"))
```

  with

```r
       meta        = paste0(n, "_meta"),
       oracle_integrity = paste0(n, "_oracle_integrity"),
       gate_runs     = paste0(n, "_gate_runs"),
       gate_markers  = paste0(n, "_gate_markers"),
       gate_verdicts = paste0(n, "_gate_verdicts"),
       gate_outcomes = paste0(n, "_gate_outcomes"))
```

- [ ] **Step 5: Write `load_oracle()`.** Create `R/oracle_load.R`:

```r
# oracle_load.R
#
# Loading a SAS build of a master into the warehouse as the parity gate's
# answer key. Spec: dev/specs/2026-11-16-master-views-design.md §7.2.

#' Load a SAS build of a master as the parity gate's answer key
#'
#' Loads a parquet snapshot of a SAS build, taken with [snapshot_oracle()], into
#' a table named `<master>_oracle_<YYYYMMDD>` and proves the table equal to the
#' parquet: counts, aggregates and a sampled compare, then every cell joined on
#' the master's key. The result is recorded in `<master>_oracle_integrity` as
#' **oracle integrity**: it says the table holds what SAS wrote, nothing about
#' whether the master's rules reproduce it. That is [parity_gate()]'s question.
#'
#' `load_oracle()` shares its load and checks with [lift_master()] but none of
#' its publishing: it never creates or changes the master's view, its metadata
#' or its parity records.
#'
#' A dry run, the default, writes the table's DDL next to the parquet for a
#' hand-off and touches nothing else. Warehouse errors are reported by step,
#' with the driver's message withheld, because it can carry a data value.
#'
#' @param config A `master_config` from [read_master_config()].
#' @param con A DBI connection, such as one from [dw_connect()].
#' @param parquet Path to the SAS build's parquet snapshot; its `.meta.json`
#'   sidecar must sit beside it, and its checksum must match the sidecar's
#'   `parquet_sha256`.
#' @param run_date The date the SAS build ran, as a `Date` or `"YYYY-MM-DD"`. It
#'   names the table.
#' @param dry_run If `TRUE`, the default, write the DDL and nothing else.
#' @param dialect `"mssql"` for the warehouse, or `"duckdb"`, used in tests.
#'
#' @return Invisibly, a list with `dry_run`, `oracle_table`, `ddl_path` and
#'   `verdict` (`"pass"`, or `NA` for a dry run). A failed integrity check is
#'   recorded and then stops with class `hvtiRdatabuild_oracle_integrity_failed`.
#'
#' @seealso [open_gate_run()], [parity_gate()], [snapshot_oracle()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE) &&
#'     requireNamespace("arrow", quietly = TRUE) &&
#'     requireNamespace("jsonlite", quietly = TRUE) &&
#'     requireNamespace("tidyselect", quietly = TRUE) &&
#'     requireNamespace("withr", quietly = TRUE)) {
#'   # Synthetic data; no PHI.
#'   dir <- tempfile("oracle")
#'   dir.create(dir)
#'   pq <- file.path(dir, "gate_build.parquet")
#'   arrow::write_parquet(data.frame(id = c("K1", "K2"), x = c(1, 2)), pq)
#'   jsonlite::write_json(
#'     list(parquet_sha256 = digest::digest(pq, algo = "sha256", file = TRUE)),
#'     sub("\\.parquet$", ".meta.json", pq), auto_unbox = TRUE)
#'   cfg_path <- file.path(dir, "master.yml")
#'   writeLines(c("name: master_demo", "key: [id]", paste0("snapshots: ", dir),
#'                "current: built_demo.sas7bdat",
#'                paste0("build_program: ", file.path(dir, "bd.sas"))), cfg_path)
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   load_oracle(read_master_config(cfg_path), con, pq, "2026-11-17",
#'               dry_run = FALSE, dialect = "duckdb")
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#' }
#' }
#'
#' @export
load_oracle <- function(config, con, parquet, run_date, dry_run = TRUE, dialect = "mssql") {
  for (p in c("arrow", "tidyselect", "jsonlite")) {
    if (!requireNamespace(p, quietly = TRUE)) {
      stop("Package '", p, "' is required to load an oracle. ",
           "Install it with install.packages('", p, "').", call. = FALSE)
    }
  }
  if (!inherits(config, "master_config")) {
    stop("'config' must come from read_master_config().", call. = FALSE)
  }
  run_date <- tryCatch(as.Date(run_date), error = function(e) as.Date(NA))
  if (length(run_date) != 1L || is.na(run_date)) {
    stop("load_oracle(): `run_date` must be one date, as a Date or \"YYYY-MM-DD\".",
         call. = FALSE)
  }
  meta <- .read_verified_meta(parquet, "snapshot_oracle()")
  oracle <- paste0(config[["name"]], "_oracle_", format(run_date, "%Y%m%d"))

  kv <- key_verdict(parquet, config[["key"]])
  .hvti_inform(format_key_verdict(kv))
  if (kv$verdict != "unique") {
    .abort("key_not_unique",
           "load_oracle(): The primary key is not unique in the oracle; nothing was created.")
  }

  ddl <- master_ddl(parquet, oracle)
  ddl_path <- paste0(parquet, ".ddl.sql")
  if (dry_run) {
    writeLines(ddl$sql, ddl_path)
    .hvti_inform("dry run: DDL for ", oracle, " written to ", ddl_path)
    return(invisible(list(dry_run = TRUE, oracle_table = oracle, ddl_path = ddl_path,
                          verdict = NA_character_)))
  }
  for (p in c("dplyr", "withr")) {
    if (!requireNamespace(p, quietly = TRUE)) {
      stop("Package '", p, "' is required to load an oracle. ",
           "Install it with install.packages('", p, "').", call. = FALSE)
    }
  }

  sha <- as.character(meta$parquet_sha256)
  ok <- .load_and_verify(con, parquet, oracle, ddl, sha, config[["key"]], dialect,
                         label = "oracle integrity", caller = "load_oracle")
  verdict <- if (ok) "pass" else "fail"
  record <- data.frame(
    oracle_table = oracle, parquet_sha256 = sha,
    source_sha256 = if (is.null(meta$source_sha256)) NA_character_ else
      as.character(meta$source_sha256),
    verdict = verdict, checked_at = as.POSIXct(Sys.time(), tz = "UTC"),
    stringsAsFactors = FALSE
  )
  # dbWriteTable(append = TRUE) creates the integrity table on the first load.
  run_step("record oracle integrity",
           DBI::dbWriteTable(con, .master_tables(config)$oracle_integrity, record,
                             append = TRUE))
  if (!ok) {
    .abort("oracle_integrity_failed",
           "load_oracle(): The oracle table does not match its parquet; the failure is ",
           "recorded and the gate will refuse this oracle.")
  }
  .hvti_inform("oracle ", oracle, ": integrity pass")
  invisible(list(dry_run = FALSE, oracle_table = oracle, ddl_path = NA_character_,
                 verdict = "pass"))
}
```

- [ ] **Step 6: Document and run the tests.**
  Run: `Rscript -e 'devtools::document(); devtools::test(filter = "oracle-load|master-lift")'`
  Expected: all pass; `man/load_oracle.Rd` written and `export(load_oracle)` in `NAMESPACE`.
  The roxygen links to `open_gate_run()` and `parity_gate()` warn until Tasks 3 and 5 exist;
  that is expected here and gone by Task 5.

- [ ] **Step 7: Commit.**

```bash
git add R/oracle_load.R R/master_config.R man/load_oracle.Rd NAMESPACE \
  tests/testthat/helper-parity-gate.R tests/testthat/test-oracle-load.R
git commit -m "feat: load_oracle() loads a SAS build as the gate's answer key"
```

---

### Task 3: change markers and `open_gate_run()`

**Files:**
- Create: `R/gate_markers.R`
- Test: `tests/testthat/test-gate-markers.R`

**Interfaces:**
- Consumes: `.qualified_name()` (`R/master_pull.R`), `.master_tables()` (Task 2).
- Produces: `.gate_marker_sql(source, dialect)`; `.take_markers(con, sources, dialect)`
  returning `data.frame(source, n_rows, checksum)`; `.markers_changed(before, after)`
  returning one logical; `open_gate_run(config, con, mode = c("fallback", "snapshot"),
  sources = character(), snapshot_name = NA_character_, dialect = "mssql")` returning the
  run id invisibly, a string matching `^G[0-9]{8}T[0-9]{6}_[0-9a-f]{8}$`.

- [ ] **Step 1: Write the failing tests.** Create `tests/testthat/test-gate-markers.R`:

```r
# Tests for the gate's change markers and open_gate_run(). No PHI.

test_that("the SQL Server marker is a count and a CHECKSUM_AGG of BINARY_CHECKSUM", {
  expect_identical(
    .gate_marker_sql("dw.stg_demo", "mssql"),
    paste0("SELECT COUNT_BIG(*) AS n_rows, COALESCE(CAST(CHECKSUM_AGG(BINARY_CHECKSUM(*)) ",
           "AS nvarchar(40)), 'empty') AS checksum FROM [dw].[stg_demo] s")
  )
})

test_that("a duckdb marker changes with an update or an insert, and only then", {
  g <- local_gate_db()
  m0 <- .take_markers(g$con, c("stg_demo", "stg_other"), "duckdb")
  expect_identical(m0$n_rows, c(4, 2))
  expect_identical(.take_markers(g$con, c("stg_demo", "stg_other"), "duckdb"), m0)
  DBI::dbExecute(g$con, "UPDATE stg_demo SET age = age + 1 WHERE mrn = 'SYN201'")
  m1 <- .take_markers(g$con, "stg_demo", "duckdb")
  expect_identical(m1$n_rows, 4)
  expect_false(identical(m1$checksum, m0$checksum[[1]]))
  expect_true(.markers_changed(m0[1, ], m1))
  DBI::dbExecute(g$con, "INSERT INTO stg_other VALUES ('C')")
  expect_true(.markers_changed(m0[2, ], .take_markers(g$con, "stg_other", "duckdb")))
  DBI::dbExecute(g$con, "CREATE TABLE stg_empty (code VARCHAR)")
  expect_identical(.take_markers(g$con, "stg_empty", "duckdb")$checksum, "empty")
})

test_that("a fallback run records its run and a marker per source before the SAS run", {
  g <- local_gate_db()
  run_id <- suppressMessages(open_gate_run(g$cfg, g$con, "fallback",
                                           sources = c("stg_demo", "stg_other"),
                                           dialect = "duckdb"))
  expect_match(run_id, "^G[0-9]{8}T[0-9]{6}_[0-9a-f]{8}$")
  run <- DBI::dbGetQuery(g$con, "SELECT * FROM master_demo_gate_runs")
  expect_identical(run$mode, "fallback")
  m <- DBI::dbGetQuery(g$con, "SELECT * FROM master_demo_gate_markers ORDER BY source")
  expect_identical(m$source, c("stg_demo", "stg_other"))
  expect_identical(unique(m$phase), "before")
  expect_identical(unique(m$run_id), run_id)
})

test_that("a fallback run needs sources and a snapshot run needs a snapshot name", {
  g <- local_gate_db()
  expect_error(open_gate_run(g$cfg, g$con, "fallback", dialect = "duckdb"),
               class = "hvtiRdatabuild_gate_sources")
  expect_error(open_gate_run(g$cfg, g$con, "fallback", sources = c("stg_demo", "stg_demo"),
                             dialect = "duckdb"),
               class = "hvtiRdatabuild_gate_sources")
  expect_error(open_gate_run(g$cfg, g$con, "snapshot", dialect = "duckdb"),
               class = "hvtiRdatabuild_gate_snapshot")
  expect_error(open_gate_run(g$cfg, g$con, "snapshot", sources = "stg_demo",
                             snapshot_name = "dw_gate_snap", dialect = "duckdb"),
               class = "hvtiRdatabuild_gate_sources")
  run_id <- suppressMessages(open_gate_run(g$cfg, g$con, "snapshot",
                                           snapshot_name = "dw_gate_snap",
                                           dialect = "duckdb"))
  expect_false(DBI::dbExistsTable(g$con, "master_demo_gate_markers"))
  run <- DBI::dbGetQuery(g$con, "SELECT * FROM master_demo_gate_runs")
  expect_identical(run$snapshot_name, "dw_gate_snap")
  expect_identical(run$run_id, run_id)
})
```

- [ ] **Step 2: Run them and confirm they fail.**
  Run: `Rscript -e 'devtools::test(filter = "gate-markers")'`
  Expected: 4 errors, `could not find function ".gate_marker_sql"` and the like.

- [ ] **Step 3: Write the markers and `open_gate_run()`.** Create `R/gate_markers.R`:

```r
# gate_markers.R
#
# Opening a parity gate run, and the per-source change markers that make the
# fallback gate fail closed. Spec: dev/specs/2026-11-16-master-views-design.md
# §7.1.

#' The SQL for one source's change marker
#'
#' A row count and an order-independent aggregate of a row hash. Both
#' dialects XOR the row hashes, so the marker does not depend on row order.
#' An empty source has a checksum of `"empty"` rather than NULL.
#'
#' @param source Character. The source table or view, optionally
#'   schema-qualified (`"schema.name"`).
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return A length-one character: a `SELECT` returning `n_rows` and `checksum`.
#'
#' @keywords internal
#' @noRd
.gate_marker_sql <- function(source, dialect) {
  checksum <- switch(dialect,
                     mssql = "CAST(CHECKSUM_AGG(BINARY_CHECKSUM(*)) AS nvarchar(40))",
                     duckdb = "CAST(bit_xor(hash(s)) AS VARCHAR)",
                     stop("Unknown dialect '", dialect, "'.", call. = FALSE))
  count <- if (dialect == "mssql") "COUNT_BIG(*)" else "COUNT(*)"
  sprintf("SELECT %s AS n_rows, COALESCE(%s, 'empty') AS checksum FROM %s s",
          count, checksum, .qualified_name(source, dialect))
}

#' Take a change marker for each source
#'
#' @param con A DBI connection.
#' @param sources Character. The source tables or views.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return A data frame of `source`, `n_rows` (numeric) and `checksum`
#'   (character), one row per source. Counts and hashes only, never a value.
#'
#' @keywords internal
#' @noRd
.take_markers <- function(con, sources, dialect) {
  rows <- lapply(sources, function(s) {
    m <- run_step("take change marker",
                  DBI::dbGetQuery(con, .gate_marker_sql(s, dialect)))
    data.frame(source = s, n_rows = as.numeric(m$n_rows),
               checksum = as.character(m$checksum), stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

#' Did any source change between two sets of markers?
#'
#' @param before,after Data frames of `source`, `n_rows`, `checksum`.
#'
#' @return `TRUE` when a source's row count or checksum differs, or a source is
#'   on one side only.
#'
#' @keywords internal
#' @noRd
.markers_changed <- function(before, after) {
  m <- merge(before, after, by = "source", all = TRUE, suffixes = c("_b", "_a"))
  any(is.na(m$n_rows_b) | is.na(m$n_rows_a) |
        as.numeric(m$n_rows_b) != as.numeric(m$n_rows_a) |
        as.character(m$checksum_b) != as.character(m$checksum_a))
}

#' Open a parity gate run
#'
#' A gate run starts **before** the SAS build that becomes its oracle. Both sides
#' of the gate must read one source state (spec §7.1):
#'
#' * `mode = "snapshot"`: data engineering has created a read-only database
#'   snapshot; the SAS build and the gate schema both read it. Name it in
#'   `snapshot_name`, which is recorded as evidence.
#' * `mode = "fallback"`: no snapshot is available. A change marker (row count
#'   and a hash aggregate) is taken now for every source the master reads, and
#'   again by [parity_gate()] after its comparison. **Any change voids the run.**
#'
#' The run and its markers are recorded in `<master>_gate_runs` and
#' `<master>_gate_markers`. Markers are counts and hashes, never values.
#'
#' @param config A `master_config` from [read_master_config()].
#' @param con A DBI connection.
#' @param mode `"fallback"` or `"snapshot"`.
#' @param sources Character. For `"fallback"`, every warehouse source the
#'   master's SAS build and rules read, optionally schema-qualified. Must be
#'   empty for `"snapshot"`.
#' @param snapshot_name Character. For `"snapshot"`, the database snapshot's
#'   name.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return Invisibly, the run's id, a character string to pass to
#'   [parity_gate()].
#'
#' @seealso [load_oracle()], [parity_gate()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   # Synthetic data; no PHI.
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   DBI::dbWriteTable(con, "stg_demo", data.frame(id = c("K1", "K2"), x = c(1, 2)))
#'   cfg <- read_master_config(system.file("extdata", "master-example.yml",
#'                                         package = "hvtiRdatabuild"))
#'   run_id <- open_gate_run(cfg, con, "fallback", sources = "stg_demo",
#'                           dialect = "duckdb")
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#' }
#' }
#'
#' @export
open_gate_run <- function(config, con, mode = c("fallback", "snapshot"),
                          sources = character(), snapshot_name = NA_character_,
                          dialect = "mssql") {
  if (!inherits(config, "master_config")) {
    stop("'config' must come from read_master_config().", call. = FALSE)
  }
  mode <- match.arg(mode)
  sources <- as.character(sources)
  if (mode == "fallback") {
    if (!length(sources) || anyNA(sources) || any(!nzchar(sources)) ||
          anyDuplicated(sources)) {
      .abort("gate_sources",
             "open_gate_run(): a fallback run needs `sources`: every source the master ",
             "reads, each named once.")
    }
  } else {
    if (length(sources)) {
      .abort("gate_sources",
             "open_gate_run(): `sources` apply to a fallback run only; a snapshot run ",
             "reads one frozen state and takes no markers.")
    }
    if (length(snapshot_name) != 1L || is.na(snapshot_name) || !nzchar(snapshot_name)) {
      .abort("gate_snapshot",
             "open_gate_run(): a snapshot run needs `snapshot_name`, the database ",
             "snapshot both sides read.")
    }
  }
  tabs <- .master_tables(config)
  opened_at <- as.POSIXct(Sys.time(), tz = "UTC")
  run_id <- paste0("G", format(opened_at, "%Y%m%dT%H%M%S", tz = "UTC"), "_",
                   substr(digest::digest(list(config[["name"]], format(opened_at, "%OS6"),
                                              sources, Sys.getpid()), algo = "sha1"), 1, 8))
  markers <- if (mode == "fallback") .take_markers(con, sources, dialect) else NULL
  run <- data.frame(run_id = run_id, master = config[["name"]], mode = mode,
                    snapshot_name = as.character(snapshot_name),
                    n_sources = length(sources), opened_at = opened_at,
                    stringsAsFactors = FALSE)
  run_step("record gate run", DBI::dbWithTransaction(con, {
    DBI::dbWriteTable(con, tabs$gate_runs, run, append = TRUE)
    if (!is.null(markers)) {
      DBI::dbWriteTable(con, tabs$gate_markers,
                        cbind(data.frame(run_id = run_id, phase = "before",
                                         stringsAsFactors = FALSE),
                              markers, data.frame(taken_at = opened_at)),
                        append = TRUE)
    }
  }))
  .hvti_inform("gate run ", run_id, " opened (", mode, ", ", length(sources),
               " source marker(s))")
  invisible(run_id)
}
```

- [ ] **Step 4: Document and run the tests.**
  Run: `Rscript -e 'devtools::document(); devtools::test(filter = "gate-markers")'`
  Expected: all pass.

- [ ] **Step 5: Commit.**

```bash
git add R/gate_markers.R man/open_gate_run.Rd NAMESPACE tests/testthat/test-gate-markers.R
git commit -m "feat: open_gate_run() records per-source change markers before the SAS run"
```

---

### Task 4: the comparison, in the database

**Files:**
- Create: `R/gate_compare.R`
- Modify: `tests/testthat/helper-parity-gate.R` (append)
- Test: `tests/testthat/test-gate-compare.R`

**Interfaces:**
- Consumes: `quoter()`, `sql_string()`, `sql_types()`, `.string_eq_sql()`
  (`R/sql_dialect.R`, `R/corrections_sql.R`), `.qualified_name()`, `corrections_ddl()`
  (helper only).
- Produces: `.gate_compare(con, rules, oracle, key, master, corrections_table,
  decisions_table, dialect, tolerance = 1e-8, batch = 200L)` returning
  `data.frame(variable, verdict, n_compared, n_differ, n_explained)`, the key row last and
  named `paste(key, collapse = "+")`. Verdicts: `match`, `explained`, `mismatch`,
  `missing_in_rules`, `not_in_oracle`. Test helpers `add_legacy(con, mrn, date, variable,
  new_value, decision = "accept", new_value_missing = 0L)` and `fixed_oracle()`.

- [ ] **Step 1: Extend the helper.** Append to `tests/testthat/helper-parity-gate.R`:

```r

# One legacy correction with the given latest decision ("accept" activates it).
add_legacy <- function(con, mrn, date, variable, new_value, decision = "accept",
                       new_value_missing = 0L) {
  if (!DBI::dbExistsTable(con, "master_demo_corrections")) {
    ddl <- corrections_ddl("master_demo_corrections", "master_demo_correction_decisions",
                           c(mrn = "VARCHAR", encounter_date = "DATE"), dialect = "duckdb")
    for (s in ddl) DBI::dbExecute(con, s)
  }
  id <- paste0("L", mrn, variable, decision)
  at <- as.POSIXct("2026-03-01", tz = "UTC")
  DBI::dbAppendTable(con, "master_demo_corrections", data.frame(
    correction_id = id, master = "master_demo", mrn = mrn, encounter_date = as.Date(date),
    variable = variable, expected_prior = NA_character_, expected_prior_missing = NA_integer_,
    new_value = new_value, new_value_missing = new_value_missing,
    evidence_type = "legacy_sas_inline", evidence_ref = "bd.sas:1",
    asserted_by = "unknown (legacy)", asserted_on = at
  ))
  DBI::dbAppendTable(con, "master_demo_correction_decisions", data.frame(
    decision_id = paste0("D", id), correction_id = id, decision = decision,
    decided_by = "legacy backfill", decided_on = at, reason = "test fixture"
  ))
}

# The SAS build with one inline fix applied: SYN202's age is 73, not 72.
fixed_oracle <- function() {
  d <- gate_source()
  d$age[d$mrn == "SYN202"] <- 73
  d
}
```

- [ ] **Step 2: Write the failing tests.** Create `tests/testthat/test-gate-compare.R`:

```r
# Tests for the gate's in-database comparison, on duckdb with invented data. No PHI.

compare_demo <- function(con, oracle = gate_source(), rules_sql = NULL, ...) {
  DBI::dbWriteTable(con, "oracle_t", oracle, overwrite = TRUE)
  if (!is.null(rules_sql)) {
    DBI::dbExecute(con, paste("CREATE OR REPLACE VIEW gate.master_demo AS", rules_sql))
  }
  .gate_compare(con, "gate.master_demo", "oracle_t", c("mrn", "encounter_date"),
                "master_demo", "master_demo_corrections", "master_demo_correction_decisions",
                "duckdb", ...)
}

verdict_of <- function(v, variable) v$verdict[v$variable == variable]

test_that("identical sides give a match for every column and the key", {
  g <- local_gate_db()
  v <- compare_demo(g$con)
  expect_identical(names(v), c("variable", "verdict", "n_compared", "n_differ", "n_explained"))
  expect_identical(v$variable, c("age", "lvef", "proc", "mrn+encounter_date"))
  expect_true(all(v$verdict == "match"))
  expect_identical(v$n_compared[[1]], 4)
})

test_that("a differing cell is a mismatch, counted, and a tiny difference is not", {
  g <- local_gate_db()
  v <- compare_demo(g$con, fixed_oracle())
  expect_identical(verdict_of(v, "age"), "mismatch")
  expect_identical(v$n_differ[v$variable == "age"], 1)
  expect_identical(verdict_of(v, "lvef"), "match")
  d <- gate_source()
  d$age <- d$age + 1e-10
  expect_identical(verdict_of(compare_demo(g$con, d), "age"), "match")
})

test_that("missing against present differs, and text compares exactly", {
  g <- local_gate_db()
  d <- gate_source()
  d$lvef[d$mrn == "SYN201"] <- NA
  d$proc[d$mrn == "SYN203"] <- "cabg"
  v <- compare_demo(g$con, d)
  expect_identical(verdict_of(v, "lvef"), "mismatch")
  expect_identical(verdict_of(v, "proc"), "mismatch")
})

test_that("a rules value that does not cast differs, even against a missing value", {
  g <- local_gate_db()
  v <- compare_demo(g$con, rules_sql = paste(
    "SELECT mrn, encounter_date, age,",
    "CASE WHEN mrn = 'SYN203' THEN 'n/a' ELSE CAST(lvef AS VARCHAR) END AS lvef, proc",
    "FROM stg_demo"
  ))
  expect_identical(verdict_of(v, "lvef"), "mismatch")
  expect_identical(v$n_differ[v$variable == "lvef"], 1)
})

test_that("only an activated legacy correction with the oracle's value explains a cell", {
  g <- local_gate_db()
  add_legacy(g$con, "SYN202", "2013-04-20", "age", "73", decision = "bake")
  expect_identical(verdict_of(compare_demo(g$con, fixed_oracle()), "age"), "mismatch")
  add_legacy(g$con, "SYN202", "2013-04-20", "age", "74", decision = "accept")
  expect_identical(verdict_of(compare_demo(g$con, fixed_oracle()), "age"), "mismatch")
  DBI::dbExecute(g$con, "DELETE FROM master_demo_correction_decisions")
  DBI::dbExecute(g$con, "DELETE FROM master_demo_corrections")
  add_legacy(g$con, "SYN202", "2013-04-20", "age", "73", decision = "accept")
  v <- compare_demo(g$con, fixed_oracle())
  expect_identical(verdict_of(v, "age"), "explained")
  expect_identical(v$n_explained[v$variable == "age"], 1)
})

test_that("absent columns and absent keys are reported", {
  g <- local_gate_db()
  v <- compare_demo(g$con, rules_sql = paste(
    "SELECT mrn, encounter_date, age, proc, 1 AS new_flag FROM stg_demo WHERE mrn <> 'SYN204'"
  ))
  expect_identical(verdict_of(v, "lvef"), "missing_in_rules")
  expect_identical(verdict_of(v, "new_flag"), "not_in_oracle")
  expect_identical(verdict_of(v, "mrn+encounter_date"), "mismatch")
  expect_identical(v$n_differ[v$variable == "mrn+encounter_date"], 1)
})

test_that("comparing one column per query gives the same verdicts", {
  g <- local_gate_db()
  expect_identical(compare_demo(g$con, fixed_oracle(), batch = 1L),
                   compare_demo(g$con, fixed_oracle()))
})
```

- [ ] **Step 3: Run them and confirm they fail.**
  Run: `Rscript -e 'devtools::test(filter = "gate-compare")'`
  Expected: 7 errors, `could not find function ".gate_compare"`.

- [ ] **Step 4: Write the comparison.** Create `R/gate_compare.R`:

```r
# gate_compare.R
#
# The parity gate's comparison: every cell of the deployed rules view against
# the oracle, joined on the master's key, computed in the database. Only counts
# come back to R. Spec: dev/specs/2026-11-16-master-views-design.md §7.2.

#' The comparison class of a column, from its zero-row R prototype
#'
#' @param x A zero-length column from a `SELECT ... WHERE 1 = 0`.
#'
#' @return One of `"num"`, `"date"`, `"ts"` or `"text"`.
#'
#' @keywords internal
#' @noRd
.gate_class <- function(x) {
  if (inherits(x, "Date")) return("date")
  if (inherits(x, "POSIXt")) return("ts")
  if (is.numeric(x) || is.logical(x)) return("num")
  "text"
}

#' The SQL type both sides of a comparison are cast to
#'
#' @param cls A class from `.gate_class()`.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return A length-one character SQL type.
#'
#' @keywords internal
#' @noRd
.gate_cast_type <- function(cls, dialect) {
  switch(cls,
         num = "DOUBLE PRECISION",
         date = "DATE",
         ts = sql_types(dialect)$ts,
         text = sql_types(dialect)$text)
}

#' A SQL predicate: two non-null cast values are equal
#'
#' Numbers are equal within an absolute `tolerance`, as [compare_built()]
#' judges them. Text on SQL Server compares the stored characters exactly.
#'
#' @param a,b Character. SQL expressions, already cast.
#' @param cls A class from `.gate_class()`.
#' @param dialect `"mssql"` or `"duckdb"`.
#' @param tolerance Numeric. The absolute numeric tolerance.
#'
#' @return A length-one character SQL predicate.
#'
#' @keywords internal
#' @noRd
.gate_eq_sql <- function(a, b, cls, dialect, tolerance) {
  switch(cls,
         num = sprintf("(ABS(%s - %s) <= %s)", a, b, sprintf("%.17g", tolerance)),
         text = paste0("(", .string_eq_sql(a, b, "nvarchar", dialect), ")"),
         sprintf("(%s = %s)", a, b))
}

#' A SQL predicate: a rules cell differs from its oracle cell
#'
#' Both sides are cast to the oracle column's class with `TRY_CAST`. A rules
#' value that does not cast differs, so a failed cast can never pass as a
#' missing value. Two missing values are equal.
#'
#' @param r,o Character. The rules and oracle column references.
#' @param cls A class from `.gate_class()`, of the oracle column.
#' @param dialect `"mssql"` or `"duckdb"`.
#' @param tolerance Numeric. The absolute numeric tolerance.
#'
#' @return A length-one character SQL predicate.
#'
#' @keywords internal
#' @noRd
.gate_differs_sql <- function(r, o, cls, dialect, tolerance) {
  type <- .gate_cast_type(cls, dialect)
  rc <- sprintf("TRY_CAST(%s AS %s)", r, type)
  oc <- sprintf("TRY_CAST(%s AS %s)", o, type)
  sprintf(paste0("((%1$s IS NOT NULL AND %2$s IS NULL) OR (%2$s IS NULL AND %3$s IS NOT NULL)",
                 " OR (%2$s IS NOT NULL AND %3$s IS NULL)",
                 " OR (%2$s IS NOT NULL AND %3$s IS NOT NULL AND NOT %4$s))"),
          r, rc, oc, .gate_eq_sql(rc, oc, cls, dialect, tolerance))
}

#' A SQL predicate: an activated legacy correction explains an oracle cell
#'
#' True when the `legacy` CTE holds a correction for this row's key and this
#' column whose new value is the oracle's value.
#'
#' @param variable Character. The oracle column's name.
#' @param o Character. The oracle column reference.
#' @param cls A class from `.gate_class()`.
#' @param key_on Character. The predicate joining `l` to `o` on the key.
#' @param dialect `"mssql"` or `"duckdb"`.
#' @param tolerance Numeric. The absolute numeric tolerance.
#'
#' @return A length-one character SQL predicate.
#'
#' @keywords internal
#' @noRd
.gate_explained_sql <- function(variable, o, cls, key_on, dialect, tolerance) {
  type <- .gate_cast_type(cls, dialect)
  nv <- sprintf("TRY_CAST(l.new_value AS %s)", type)
  oc <- sprintf("TRY_CAST(%s AS %s)", o, type)
  sprintf(paste0("EXISTS (SELECT 1 FROM legacy l WHERE l.variable = %s AND %s AND (",
                 "(l.new_value_missing = 1 AND %s IS NULL) OR ",
                 "(l.new_value_missing = 0 AND %s)))"),
          sql_string(variable), key_on, o, .gate_eq_sql(nv, oc, cls, dialect, tolerance))
}

#' The CTE of a master's activated legacy corrections
#'
#' A legacy correction is a row of the master's corrections table with
#' evidence `legacy_sas_inline` (see `backfill_corrections()`). It is
#' **activated** when its latest decision is `accept`; a `bake` decision
#' records it without activating it.
#'
#' @param q A quoting function from `quoter()`.
#' @param corrections_table,decisions_table Character. The tables' names.
#' @param master Character. The master's name.
#'
#' @return A length-one character: `WITH latest AS (...), legacy AS (...)`.
#'
#' @keywords internal
#' @noRd
.legacy_cte <- function(q, corrections_table, decisions_table, master) {
  paste0(
    "WITH latest AS (\n",
    "  SELECT correction_id, decision,\n",
    "         ROW_NUMBER() OVER (PARTITION BY correction_id\n",
    "                            ORDER BY decided_on DESC, decision_id DESC) AS rn\n",
    "  FROM ", q(decisions_table), "\n",
    "), legacy AS (\n",
    "  SELECT c.* FROM ", q(corrections_table), " c\n",
    "  JOIN latest d ON d.correction_id = c.correction_id\n",
    "  WHERE d.rn = 1 AND d.decision = 'accept' AND c.master = ", sql_string(master),
    " AND c.evidence_type = 'legacy_sas_inline'\n",
    ")\n"
  )
}

#' A key-join predicate between two aliases
#'
#' @param q A quoting function from `quoter()`.
#' @param a,b Character. The two aliases.
#' @param a_key,b_key Character. The key columns' names on each side, in order.
#' @param cls Character. Each key column's class, from `.gate_class()`.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return A length-one character SQL predicate.
#'
#' @keywords internal
#' @noRd
.gate_key_on <- function(q, a, b, a_key, b_key, cls, dialect) {
  parts <- vapply(seq_along(a_key), function(i) {
    lhs <- paste0(a, ".", q(a_key[[i]]))
    rhs <- paste0(b, ".", q(b_key[[i]]))
    if (cls[[i]] == "text") .string_eq_sql(lhs, rhs, "nvarchar", dialect) else
      sprintf("%s = %s", lhs, rhs)
  }, character(1))
  paste(parts, collapse = " AND ")
}

#' Compare a rules view with an oracle, cell by cell, in the database
#'
#' Columns are matched by name, ignoring case. Every non-key oracle column is
#' compared over the rows the two sides share on the key, in batches of
#' `batch` columns per query. Keys present on one side only, and keys the
#' rules view repeats, are counted. Only counts are read back.
#'
#' Verdicts: `match` (no cell differs), `explained` (every differing cell is
#' explained by an activated legacy correction), `mismatch`, `missing_in_rules`
#' (an oracle column the rules view lacks) and `not_in_oracle` (a rules column
#' SAS never produced; reported, and not a failure). The key row's verdict is
#' `match` or `mismatch`.
#'
#' @param con A DBI connection.
#' @param rules Character. The rules view, optionally schema-qualified.
#' @param oracle Character. The oracle table.
#' @param key Character. The master's key columns.
#' @param master Character. The master's name.
#' @param corrections_table,decisions_table Character. The master's corrections
#'   tables; when either is absent, no difference is explained.
#' @param dialect `"mssql"` or `"duckdb"`.
#' @param tolerance Numeric. The absolute numeric tolerance.
#' @param batch Integer. Columns per comparison query.
#'
#' @return A data frame of `variable`, `verdict`, `n_compared`, `n_differ` and
#'   `n_explained`, the key row last.
#'
#' @keywords internal
#' @noRd
.gate_compare <- function(con, rules, oracle, key, master, corrections_table,
                          decisions_table, dialect, tolerance = 1e-8, batch = 200L) {
  q <- quoter(dialect)
  rules_q <- .qualified_name(rules, dialect)
  oracle_q <- .qualified_name(oracle, dialect)
  o0 <- run_step("read oracle columns",
                 DBI::dbGetQuery(con, sprintf("SELECT * FROM %s WHERE 1 = 0", oracle_q)))
  r0 <- run_step("read rules columns",
                 DBI::dbGetQuery(con, sprintf("SELECT * FROM %s WHERE 1 = 0", rules_q)))
  in_rules <- function(v) names(r0)[match(tolower(v), tolower(names(r0)))]
  in_oracle <- function(v) names(o0)[match(tolower(v), tolower(names(o0)))]
  o_key <- in_oracle(key)
  r_key <- in_rules(key)
  if (anyNA(o_key) || anyNA(r_key)) {
    .abort("gate_key_absent",
           "parity_gate(): the master's key is not present in both the rules view and ",
           "the oracle; nothing was compared.")
  }
  key_cls <- vapply(o0[o_key], .gate_class, character(1))
  join_on <- .gate_key_on(q, "r", "o", r_key, o_key, key_cls, dialect)

  o_cols <- setdiff(names(o0), o_key)
  r_match <- in_rules(o_cols)
  missing <- o_cols[is.na(r_match)]
  extra <- setdiff(names(r0), c(r_key, r_match))
  cmp <- data.frame(oracle = o_cols[!is.na(r_match)], rules = r_match[!is.na(r_match)],
                    stringsAsFactors = FALSE)
  cmp$cls <- vapply(o0[cmp$oracle], .gate_class, character(1))

  has_legacy <- run_step("check corrections tables",
                         DBI::dbExistsTable(con, corrections_table) &&
                           DBI::dbExistsTable(con, decisions_table))
  cte <- if (has_legacy) .legacy_cte(q, corrections_table, decisions_table, master) else ""
  legacy_on <- .gate_key_on(q, "l", "o", o_key, o_key, key_cls, dialect)

  counts <- lapply(split(seq_len(nrow(cmp)), ceiling(seq_len(nrow(cmp)) / batch)), function(i) {
    inner <- vapply(seq_along(i), function(j) {
      row <- cmp[i[[j]], ]
      differs <- .gate_differs_sql(paste0("r.", q(row$rules)), paste0("o.", q(row$oracle)),
                                   row$cls, dialect, tolerance)
      explained <- if (has_legacy) {
        .gate_explained_sql(row$oracle, paste0("o.", q(row$oracle)), row$cls, legacy_on,
                            dialect, tolerance)
      } else {
        "1 = 0"
      }
      sprintf(paste0("CASE WHEN %1$s THEN 1 ELSE 0 END AS d%3$d, ",
                     "CASE WHEN %1$s AND %2$s THEN 1 ELSE 0 END AS e%3$d"),
              differs, explained, j)
    }, character(1))
    outer <- paste0("SUM(d", seq_along(i), ") AS d", seq_along(i), ", SUM(e", seq_along(i),
                    ") AS e", seq_along(i), collapse = ", ")
    sql <- paste0(cte, "SELECT COUNT(*) AS n_compared, ", outer, " FROM (SELECT ",
                  paste(inner, collapse = ", "), " FROM ", rules_q, " r JOIN ", oracle_q,
                  " o ON ", join_on, ") x")
    res <- run_step("compare rules with oracle", DBI::dbGetQuery(con, sql))
    num <- function(x) {
      x <- as.numeric(x)
      ifelse(is.na(x), 0, x)
    }
    data.frame(variable = cmp$oracle[i], n_compared = num(res$n_compared),
               n_differ = num(unlist(res[paste0("d", seq_along(i))])),
               n_explained = num(unlist(res[paste0("e", seq_along(i))])),
               stringsAsFactors = FALSE)
  })
  compared <- do.call(rbind, c(list(data.frame(variable = character(), n_compared = numeric(),
                                               n_differ = numeric(), n_explained = numeric())),
                               counts))
  compared$verdict <- ifelse(compared$n_differ == 0, "match",
                             ifelse(compared$n_differ == compared$n_explained, "explained",
                                    "mismatch"))
  absent <- function(v, verdict) {
    data.frame(variable = v, n_compared = rep(NA_real_, length(v)),
               n_differ = rep(NA_real_, length(v)), n_explained = rep(NA_real_, length(v)),
               verdict = rep(verdict, length(v)), stringsAsFactors = FALSE)
  }

  key_list <- paste(q(r_key), collapse = ", ")
  keys_sql <- sprintf(paste0(
    "SELECT (SELECT COUNT(*) FROM %1$s o WHERE NOT EXISTS (SELECT 1 FROM %2$s r WHERE %3$s))",
    " AS only_oracle, (SELECT COUNT(*) FROM %2$s r WHERE NOT EXISTS (SELECT 1 FROM %1$s o",
    " WHERE %3$s)) AS only_rules, (SELECT COUNT(*) FROM (SELECT %4$s FROM %2$s GROUP BY %4$s",
    " HAVING COUNT(*) > 1) d) AS dup_rules"
  ), oracle_q, rules_q, join_on, key_list)
  keys <- run_step("compare keys", DBI::dbGetQuery(con, keys_sql))
  n_key <- sum(as.numeric(unlist(keys)))
  key_row <- data.frame(variable = paste(o_key, collapse = "+"),
                        n_compared = if (nrow(compared)) compared$n_compared[[1]] else NA_real_,
                        n_differ = n_key, n_explained = 0,
                        verdict = if (n_key == 0) "match" else "mismatch",
                        stringsAsFactors = FALSE)
  out <- rbind(compared[c("variable", "n_compared", "n_differ", "n_explained", "verdict")],
               absent(missing, "missing_in_rules"), absent(extra, "not_in_oracle"), key_row)
  rownames(out) <- NULL
  out[c("variable", "verdict", "n_compared", "n_differ", "n_explained")]
}
```

- [ ] **Step 5: Run the tests.**
  Run: `Rscript -e 'devtools::test(filter = "gate-compare")'`
  Expected: all pass.

- [ ] **Step 6: Commit.**

```bash
git add R/gate_compare.R tests/testthat/helper-parity-gate.R tests/testthat/test-gate-compare.R
git commit -m "feat: the parity gate's cell-by-cell comparison, computed in the database"
```

---

### Task 5: `parity_gate()`: record the verdicts, bind the verdict to its commit

**Files:**
- Create: `R/parity_gate.R`
- Modify: `tests/testthat/helper-parity-gate.R` (append)
- Test: `tests/testthat/test-parity-gate.R`

**Interfaces:**
- Consumes: `.gate_compare()` (Task 4); `open_gate_run()` (Task 3); `load_oracle()`
  (Task 2); `pull_master()`, `cohort_query()` (plan 1, tests only).
- Produces: `parity_gate(config, con, run_id, oracle_table, gate_schema, dialect = "mssql",
  tolerance = 1e-8)` returning invisibly `list(run_id, outcome, sql_commit, verdicts)`;
  writing a `"pass"` or `"fail"` row (`sql_commit`, `verdict`, `verified_at`, `run_id`) to
  `<master>_parity`; stopping with `parity_gate_failed`, `gate_run_unknown`, `gate_run_closed`,
  `oracle_not_verified`, `parity_table_shape`, `gate_deployment` or `gate_key_absent`.
  Internal `.open_run()` returns the run's row (Task 6 reads its `mode`). Test helper
  `gate_run(g, oracle = gate_source(), mode = "fallback", sources = c("stg_demo",
  "stg_other"), between = NULL, run_date = "2026-11-17")`.

- [ ] **Step 1: Extend the helper.** Append to `tests/testthat/helper-parity-gate.R`:

```r

# Open a run, load an oracle, and run the gate, in a real gate run's order.
# `between` runs after the SAS build is loaded and before the comparison. A
# second run in one test needs its own `run_date`, which names its oracle.
gate_run <- function(g, oracle = gate_source(), mode = "fallback",
                     sources = c("stg_demo", "stg_other"), between = NULL,
                     run_date = "2026-11-17") {
  run_id <- if (mode == "fallback") {
    open_gate_run(g$cfg, g$con, "fallback", sources = sources, dialect = "duckdb")
  } else {
    open_gate_run(g$cfg, g$con, "snapshot", snapshot_name = "dw_gate_snap",
                  dialect = "duckdb")
  }
  pq <- write_oracle_parquet(g$dir, oracle, name = paste0("gate_build_", run_date, ".parquet"))
  ora <- load_oracle(g$cfg, g$con, pq, run_date, dry_run = FALSE, dialect = "duckdb")
  if (!is.null(between)) between(g$con)
  parity_gate(g$cfg, g$con, run_id, ora$oracle_table, "gate", dialect = "duckdb")
}
```

- [ ] **Step 2: Write the failing tests.** Create `tests/testthat/test-parity-gate.R`:

```r
# Tests for parity_gate(), on duckdb with invented data. No PHI.

test_that("a pass is recorded against the gate deployment's commit", {
  g <- local_gate_db()
  res <- suppressMessages(gate_run(g))
  expect_identical(res$outcome, "pass")
  expect_identical(res$sql_commit, "def5678")
  parity <- DBI::dbGetQuery(g$con, paste("SELECT * FROM master_demo_parity",
                                         "WHERE sql_commit = 'def5678'"))
  expect_identical(parity$verdict, "pass")
  expect_identical(parity$run_id, res$run_id)
  out <- DBI::dbGetQuery(g$con, "SELECT * FROM master_demo_gate_outcomes")
  expect_identical(out$outcome, "pass")
  expect_identical(out$oracle_table, "master_demo_oracle_20261117")
})

test_that("a pass gates only a master deployed from the commit it tested", {
  g <- local_gate_db()
  suppressMessages(gate_run(g))
  q <- cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")))
  path <- withr::local_tempfile(fileext = ".yaml")
  writeLines("study: st0000", path)
  pull <- suppressMessages(pull_master(g$con, "master_demo", q, var_cols = "age",
                                       path = path, dialect = "duckdb"))
  expect_s3_class(pull, "master_pull")
  DBI::dbExecute(g$con, "UPDATE master_demo_deployment SET sql_commit = 'fff0000'")
  expect_error(pull_master(g$con, "master_demo", q, var_cols = "age", path = path,
                           dialect = "duckdb"),
               class = "hvtiRdatabuild_parity_gate")
})

test_that("a failing gate records a fail verdict and leaves the view and metadata alone", {
  g <- local_gate_db()
  state <- production_state(g$con)
  err <- expect_error(suppressMessages(gate_run(g, fixed_oracle())),
                      class = "hvtiRdatabuild_parity_gate_failed")
  after <- production_state(g$con)
  expect_identical(after[c("view_sql", "view", "meta")], state[c("view_sql", "view", "meta")])
  expect_identical(after$parity[after$parity$run_id == "G0", ], state$parity)
  fail <- after$parity[after$parity$run_id != "G0", ]
  expect_identical(fail$verdict, "fail")
  expect_identical(fail$sql_commit, "def5678")
  v <- DBI::dbGetQuery(g$con, "SELECT variable, verdict FROM master_demo_gate_verdicts")
  expect_identical(v$verdict[v$variable == "age"], "mismatch")
  out <- DBI::dbGetQuery(g$con, "SELECT run_id, outcome FROM master_demo_gate_outcomes")
  expect_identical(out$outcome, "fail")
  expect_identical(out$run_id, fail$run_id)
  # The run id is random hex and may hold any digits; judge the rest of the message.
  msg <- gsub(fail$run_id, "", conditionMessage(err), fixed = TRUE)
  expect_false(grepl("SYN", msg))
  expect_false(grepl("73|72", msg))
})

test_that("a fail after a pass on the same commit blocks study builds", {
  g <- local_gate_db()
  suppressMessages(gate_run(g))
  q <- cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")))
  path <- withr::local_tempfile(fileext = ".yaml")
  writeLines("study: st0000", path)
  expect_s3_class(suppressMessages(pull_master(g$con, "master_demo", q, var_cols = "age",
                                               path = path, dialect = "duckdb")),
                  "master_pull")
  expect_error(suppressMessages(gate_run(g, fixed_oracle(), run_date = "2026-11-18")),
               class = "hvtiRdatabuild_parity_gate_failed")
  expect_error(pull_master(g$con, "master_demo", q, var_cols = "age", path = path,
                           dialect = "duckdb"),
               class = "hvtiRdatabuild_parity_gate")
})

test_that("an activated legacy correction lets the gate pass", {
  g <- local_gate_db()
  add_legacy(g$con, "SYN202", "2013-04-20", "age", "73")
  res <- suppressMessages(gate_run(g, fixed_oracle()))
  expect_identical(res$outcome, "pass")
  expect_identical(res$verdicts$verdict[res$verdicts$variable == "age"], "explained")
})

test_that("a run is gated once, and only against a verified oracle", {
  g <- local_gate_db()
  res <- suppressMessages(gate_run(g))
  expect_error(parity_gate(g$cfg, g$con, res$run_id, "master_demo_oracle_20261117", "gate",
                           dialect = "duckdb"),
               class = "hvtiRdatabuild_gate_run_closed")
  run_id <- suppressMessages(open_gate_run(g$cfg, g$con, "fallback", sources = "stg_demo",
                                           dialect = "duckdb"))
  DBI::dbWriteTable(g$con, "master_demo_oracle_unverified", gate_source())
  expect_error(parity_gate(g$cfg, g$con, run_id, "master_demo_oracle_unverified", "gate",
                           dialect = "duckdb"),
               class = "hvtiRdatabuild_oracle_not_verified")
  expect_error(parity_gate(g$cfg, g$con, "G-none", "master_demo_oracle_20261117", "gate",
                           dialect = "duckdb"),
               class = "hvtiRdatabuild_gate_run_unknown")
})

test_that("a lift_master() parity table is refused before anything is compared", {
  g <- local_gate_db()
  DBI::dbRemoveTable(g$con, "master_demo_parity")
  DBI::dbWriteTable(g$con, "master_demo_parity", data.frame(
    base_table = "b", parquet_sha256 = "x", verdict = "pass", checked_at = "2026-01-01"
  ))
  expect_error(suppressMessages(gate_run(g)), class = "hvtiRdatabuild_parity_table_shape")
  expect_false(DBI::dbExistsTable(g$con, "master_demo_gate_verdicts"))
})

test_that("a snapshot run takes no markers and is judged on its verdicts", {
  g <- local_gate_db()
  res <- suppressMessages(gate_run(g, mode = "snapshot"))
  expect_identical(res$outcome, "pass")
  expect_false(DBI::dbExistsTable(g$con, "master_demo_gate_markers"))
})
```

- [ ] **Step 3: Run them and confirm they fail.**
  Run: `Rscript -e 'devtools::test(filter = "parity-gate")'`
  Expected: 8 errors, `could not find function "parity_gate"`.

- [ ] **Step 4: Write `parity_gate()`.** Create `R/parity_gate.R`:

```r
# parity_gate.R
#
# The parity gate: the deployed rules view in a gate schema against the
# oracle, recorded per column, and a pass bound to the SQL model commit it
# tested. Spec: dev/specs/2026-11-16-master-views-design.md §7, §8.

#' The SQL model commit deployed to the gate schema
#'
#' @param con A DBI connection.
#' @param deployment Character. The gate schema's deployment view.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return The commit, a length-one character.
#'
#' @keywords internal
#' @noRd
.gate_commit <- function(con, deployment, dialect) {
  sql <- paste("SELECT sql_commit FROM", .qualified_name(deployment, dialect))
  commit <- as.character(run_step("read gate deployment", DBI::dbGetQuery(con, sql))$sql_commit)
  if (length(commit) != 1L || is.na(commit) || !nzchar(commit)) {
    .abort("gate_deployment",
           "parity_gate(): the gate schema's deployment view must hold exactly one ",
           "non-empty sql_commit; it holds ", length(commit), " row(s). Nothing was compared.")
  }
  commit
}

#' The rows of a table matching one id, or none when the table is absent
#'
#' @param con A DBI connection.
#' @param table Character. The table.
#' @param column Character. The id column.
#' @param id Character. The id.
#' @param dialect `"mssql"` or `"duckdb"`.
#' @param order Character. An `ORDER BY` clause, or `""`.
#'
#' @return A data frame, possibly with no rows and no columns.
#'
#' @keywords internal
#' @noRd
.rows_for <- function(con, table, column, id, dialect, order = "") {
  if (!run_step("check table exists", DBI::dbExistsTable(con, table))) return(data.frame())
  q <- quoter(dialect)
  sql <- paste("SELECT * FROM", q(table), "WHERE", q(column), "= ?", order)
  run_step("read gate record", DBI::dbGetQuery(con, sql, params = list(id)))
}

#' Stop unless a gate run exists and has no outcome yet
#'
#' @param con A DBI connection.
#' @param tabs The master's tables, from `.master_tables()`.
#' @param run_id Character. The run's id.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return The run's row, a one-row data frame.
#'
#' @keywords internal
#' @noRd
.open_run <- function(con, tabs, run_id, dialect) {
  run <- .rows_for(con, tabs$gate_runs, "run_id", run_id, dialect)
  if (nrow(run) != 1L) {
    .abort("gate_run_unknown",
           "parity_gate(): no gate run has that id; open one with open_gate_run().")
  }
  if (nrow(.rows_for(con, tabs$gate_outcomes, "run_id", run_id, dialect))) {
    .abort("gate_run_closed",
           "parity_gate(): this gate run already has an outcome; open a new run.")
  }
  run
}

#' Stop unless the oracle's latest integrity record is a pass
#'
#' @param con A DBI connection.
#' @param tabs The master's tables, from `.master_tables()`.
#' @param oracle Character. The oracle table.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
.check_oracle_integrity <- function(con, tabs, oracle, dialect) {
  rec <- .rows_for(con, tabs$oracle_integrity, "oracle_table", oracle, dialect,
                   order = "ORDER BY checked_at DESC")
  if (!nrow(rec) || !identical(as.character(rec$verdict[[1]]), "pass")) {
    .abort("oracle_not_verified",
           "parity_gate(): the oracle has no passing integrity record; load it with ",
           "load_oracle() first.")
  }
  invisible(NULL)
}

#' Stop when an existing parity table cannot take a gate's record
#'
#' @param con A DBI connection.
#' @param table Character. The master's parity table.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
.check_parity_table <- function(con, table, dialect) {
  if (!run_step("check parity table", DBI::dbExistsTable(con, table))) {
    return(invisible(NULL))
  }
  sql <- sprintf("SELECT * FROM %s WHERE 1 = 0", quoter(dialect)(table))
  have <- names(run_step("read parity columns", DBI::dbGetQuery(con, sql)))
  need <- c("sql_commit", "verdict", "verified_at", "run_id")
  if (!all(need %in% have)) {
    .abort("parity_table_shape",
           "parity_gate(): the master's parity table lacks ",
           paste(setdiff(need, have), collapse = ", "),
           "; it may be a lift_master() parity table. Nothing was compared.")
  }
  invisible(NULL)
}

#' Run the parity gate on a master's deployed rules
#'
#' Compares the master's **deployed rules view in a gate schema** with the
#' oracle loaded by [load_oracle()], every cell joined on the master's key,
#' inside the database. Only counts come back. A cell that differs must be
#' explained by an **activated legacy correction**: a row of the master's
#' corrections table with evidence `legacy_sas_inline` whose latest decision
#' is `accept` and whose new value is the oracle's value.
#'
#' The gate passes when every column is `match` or `explained` (a rules
#' column SAS never produced is reported as `not_in_oracle` and does not fail
#' it), and no key is on one side only or repeated in the rules view.
#'
#' Every run records its per-column verdicts in `<master>_gate_verdicts` and
#' its outcome in `<master>_gate_outcomes`. **A pass or a fail is also recorded
#' in `<master>_parity`**, against the SQL model commit the gate schema's
#' `<master>_deployment` names. [pull_master()] accepts a master only while the
#' latest verdict for its production deployment's commit is a pass, so a fail
#' blocks that commit until a later pass. The gate never changes the master's
#' view or its metadata.
#'
#' @param config A `master_config` from [read_master_config()].
#' @param con A DBI connection.
#' @param run_id Character. The id [open_gate_run()] returned.
#' @param oracle_table Character. The oracle table [load_oracle()] loaded.
#' @param gate_schema Character. The schema the rules models were deployed into
#'   for the gate; it holds the master's view and `<master>_deployment`.
#' @param dialect `"mssql"` or `"duckdb"`.
#' @param tolerance Numeric. Absolute tolerance for numeric cells, as in
#'   [compare_built()].
#'
#' @return Invisibly, a list with `run_id`, `outcome` (`"pass"`), `sql_commit`
#'   and `verdicts` (a data frame of `variable`, `verdict`, `n_compared`,
#'   `n_differ`, `n_explained`; counts only). A failed run is recorded, with a
#'   `"fail"` verdict in `<master>_parity`, and then stops with class
#'   `hvtiRdatabuild_parity_gate_failed`.
#'
#' @seealso [open_gate_run()], [load_oracle()], [pull_master()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE) &&
#'     requireNamespace("arrow", quietly = TRUE) &&
#'     requireNamespace("jsonlite", quietly = TRUE) &&
#'     requireNamespace("tidyselect", quietly = TRUE) &&
#'     requireNamespace("withr", quietly = TRUE)) {
#'   # Synthetic data; no PHI.
#'   dir <- tempfile("gate")
#'   dir.create(dir)
#'   pq <- file.path(dir, "gate_build.parquet")
#'   arrow::write_parquet(data.frame(id = c("K1", "K2"), x = c(1, 2)), pq)
#'   jsonlite::write_json(
#'     list(parquet_sha256 = digest::digest(pq, algo = "sha256", file = TRUE)),
#'     sub("\\.parquet$", ".meta.json", pq), auto_unbox = TRUE)
#'   cfg_path <- file.path(dir, "master.yml")
#'   writeLines(c("name: master_demo", "key: [id]", paste0("snapshots: ", dir),
#'                "current: built_demo.sas7bdat",
#'                paste0("build_program: ", file.path(dir, "bd.sas"))), cfg_path)
#'   cfg <- read_master_config(cfg_path)
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   DBI::dbWriteTable(con, "stg_demo", data.frame(id = c("K1", "K2"), x = c(1, 2)))
#'   DBI::dbExecute(con, "CREATE SCHEMA gate")
#'   DBI::dbExecute(con, "CREATE VIEW gate.master_demo AS SELECT id, x FROM stg_demo")
#'   DBI::dbExecute(con, paste("CREATE TABLE gate.master_demo_deployment AS",
#'                             "SELECT 'abc1234' AS sql_commit"))
#'   run_id <- open_gate_run(cfg, con, "fallback", sources = "stg_demo",
#'                           dialect = "duckdb")
#'   ora <- load_oracle(cfg, con, pq, "2026-11-17", dry_run = FALSE, dialect = "duckdb")
#'   parity_gate(cfg, con, run_id, ora$oracle_table, "gate", dialect = "duckdb")
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#' }
#' }
#'
#' @export
parity_gate <- function(config, con, run_id, oracle_table, gate_schema, dialect = "mssql",
                        tolerance = 1e-8) {
  if (!inherits(config, "master_config")) {
    stop("'config' must come from read_master_config().", call. = FALSE)
  }
  for (a in list(run_id, oracle_table, gate_schema)) {
    if (!is.character(a) || length(a) != 1L || is.na(a) || !nzchar(a)) {
      stop("parity_gate(): `run_id`, `oracle_table` and `gate_schema` must each be one ",
           "non-empty string.", call. = FALSE)
    }
  }
  tabs <- .master_tables(config)
  master <- config[["name"]]
  .open_run(con, tabs, run_id, dialect)
  .check_oracle_integrity(con, tabs, oracle_table, dialect)
  .check_parity_table(con, tabs$parity, dialect)
  commit <- .gate_commit(con, paste0(gate_schema, ".", master, "_deployment"), dialect)

  verdicts <- .gate_compare(con, paste0(gate_schema, ".", master), oracle_table,
                            config[["key"]], master, tabs$corrections, tabs$decisions,
                            dialect, tolerance)
  failing <- !verdicts$verdict %in% c("match", "explained", "not_in_oracle")
  outcome <- if (any(failing)) "fail" else "pass"
  closed_at <- as.POSIXct(Sys.time(), tz = "UTC")

  verdict_rows <- cbind(data.frame(run_id = run_id, stringsAsFactors = FALSE), verdicts)
  outcome_row <- data.frame(run_id = run_id, sql_commit = commit, gate_schema = gate_schema,
                            oracle_table = oracle_table, outcome = outcome,
                            closed_at = closed_at, stringsAsFactors = FALSE)
  # A fail is recorded too, so it blocks the commit it tested.
  parity_row <- data.frame(sql_commit = commit, verdict = outcome, verified_at = closed_at,
                           run_id = run_id, stringsAsFactors = FALSE)
  run_step("record gate outcome", DBI::dbWithTransaction(con, {
    DBI::dbWriteTable(con, tabs$gate_verdicts, verdict_rows, append = TRUE)
    DBI::dbWriteTable(con, tabs$gate_outcomes, outcome_row, append = TRUE)
    DBI::dbWriteTable(con, tabs$parity, parity_row, append = TRUE)
  }))
  .hvti_inform("parity gate ", outcome, ": ", sum(failing), " of ", nrow(verdicts),
               " verdicts failing; run ", run_id)
  if (outcome == "fail") {
    .abort("parity_gate_failed",
           "parity_gate(): the rules view does not reproduce the oracle: ", sum(failing),
           " of ", nrow(verdicts), " verdicts fail. Verdicts are in ", tabs$gate_verdicts,
           " under run ", run_id, ". A fail verdict was recorded; commit ", commit,
           " is blocked from study builds until a later pass.")
  }
  invisible(list(run_id = run_id, outcome = outcome, sql_commit = commit,
                 verdicts = verdicts))
}
```

- [ ] **Step 5: Document and run the tests.**
  Run: `Rscript -e 'devtools::document(); devtools::test(filter = "parity-gate|oracle-load|gate-|master-pull")'`
  Expected: all pass, and `document()` no longer warns about unresolved links.

- [ ] **Step 6: Commit.**

```bash
git add R/parity_gate.R man/parity_gate.Rd NAMESPACE \
  tests/testthat/helper-parity-gate.R tests/testthat/test-parity-gate.R
git commit -m "feat: parity_gate() records per-column verdicts and binds its verdict to the commit"
```

---

### Task 6: the fallback fails closed

A fallback run retakes every source's marker **after** the comparison. Any change voids the
run, its verdicts and both sets of markers are kept as evidence, and nothing is written to
`<master>_parity`, so an earlier pass or fail for the commit stands. Void wins over fail,
because a run whose sources moved says nothing about the rules either way.

**Files:**
- Modify: `R/gate_markers.R` (add `.read_markers()` after `.markers_changed()`)
- Modify: `R/parity_gate.R` (`parity_gate()` and its roxygen)
- Test: `tests/testthat/test-gate-void.R`

**Interfaces:**
- Consumes: `.take_markers()`, `.markers_changed()` (Task 3); `.open_run()`'s returned row
  and its `mode` (Task 5).
- Produces: `.read_markers(con, tabs, run_id, dialect)` returning the `before` markers or
  stopping with `gate_markers_missing`; `parity_gate()` stops with `parity_gate_void`.

- [ ] **Step 1: Write the failing tests.** Create `tests/testthat/test-gate-void.R`:

```r
# The fallback gate fails closed: a source change during the run voids it. No PHI.

test_that("a change to an unread source voids a run whose verdicts all pass", {
  g <- local_gate_db()
  state <- production_state(g$con)
  expect_error(
    suppressMessages(gate_run(g, between = function(con) {
      DBI::dbExecute(con, "INSERT INTO stg_other VALUES ('C')")
    })),
    class = "hvtiRdatabuild_parity_gate_void"
  )
  expect_identical(production_state(g$con), state)
  out <- DBI::dbGetQuery(g$con, "SELECT outcome FROM master_demo_gate_outcomes")
  expect_identical(out$outcome, "void")
  v <- DBI::dbGetQuery(g$con, "SELECT verdict FROM master_demo_gate_verdicts")
  expect_true(all(v$verdict == "match"))
  m <- DBI::dbGetQuery(g$con, "SELECT phase, source FROM master_demo_gate_markers")
  expect_identical(sort(paste(m$phase, m$source)),
                   c("after stg_demo", "after stg_other", "before stg_demo",
                     "before stg_other"))
})

test_that("an upstream write between the SAS run and the comparison voids, not fails", {
  g <- local_gate_db()
  err <- expect_error(
    suppressMessages(gate_run(g, between = function(con) {
      DBI::dbExecute(con, "UPDATE stg_demo SET age = 90 WHERE mrn = 'SYN204'")
    })),
    class = "hvtiRdatabuild_parity_gate_void"
  )
  # The run id is random hex and may hold any digits; judge the rest of the message.
  run_id <- DBI::dbGetQuery(g$con, "SELECT run_id FROM master_demo_gate_outcomes")$run_id
  expect_false(grepl("SYN|90", gsub(run_id, "", conditionMessage(err), fixed = TRUE)))
  parity <- DBI::dbGetQuery(g$con, "SELECT * FROM master_demo_parity")
  expect_identical(parity$run_id, "G0")
})

test_that("a void run after a pass leaves the pass in force", {
  g <- local_gate_db()
  passed <- suppressMessages(gate_run(g))
  expect_error(
    suppressMessages(gate_run(g, run_date = "2026-11-18", between = function(con) {
      DBI::dbExecute(con, "INSERT INTO stg_other VALUES ('C')")
    })),
    class = "hvtiRdatabuild_parity_gate_void"
  )
  parity <- DBI::dbGetQuery(g$con, paste("SELECT run_id, verdict FROM master_demo_parity",
                                         "WHERE sql_commit = 'def5678'"))
  expect_identical(parity$run_id, passed$run_id)
  expect_identical(parity$verdict, "pass")
  q <- cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")))
  path <- withr::local_tempfile(fileext = ".yaml")
  writeLines("study: st0000", path)
  expect_s3_class(suppressMessages(pull_master(g$con, "master_demo", q, var_cols = "age",
                                               path = path, dialect = "duckdb")),
                  "master_pull")
})

test_that("a fallback run without its before markers cannot be gated", {
  g <- local_gate_db()
  expect_error(
    suppressMessages(gate_run(g, between = function(con) {
      DBI::dbExecute(con, "DELETE FROM master_demo_gate_markers")
    })),
    class = "hvtiRdatabuild_gate_markers_missing"
  )
})
```

- [ ] **Step 2: Run them and confirm they fail.**
  Run: `Rscript -e 'devtools::test(filter = "gate-void")'`
  Expected: all 4 tests fail. The first, third and fourth: the gate passes, so no error is
  raised (and in the third, the second run's pass is recorded beside the first). The
  second reports an error: `parity_gate_failed` is raised where `_void` was expected.

- [ ] **Step 3: Read a run's first markers.** In `R/gate_markers.R`, insert before
  `#' Open a parity gate run`:

```r
#' A run's `before` markers
#'
#' @param con A DBI connection.
#' @param tabs The master's tables, from `.master_tables()`.
#' @param run_id Character. The run's id.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return A data frame of `source`, `n_rows`, `checksum`.
#'
#' @keywords internal
#' @noRd
.read_markers <- function(con, tabs, run_id, dialect) {
  sql <- paste("SELECT source, n_rows, checksum FROM", quoter(dialect)(tabs$gate_markers),
               "WHERE run_id = ? AND phase = 'before' ORDER BY source")
  m <- run_step("read change markers", DBI::dbGetQuery(con, sql, params = list(run_id)))
  if (!nrow(m)) {
    .abort("gate_markers_missing",
           "parity_gate(): this fallback run has no markers from before the SAS run; ",
           "it cannot be gated. Open a new run.")
  }
  m
}

```

- [ ] **Step 4: Retake the markers and void on change.** In `R/parity_gate.R`, make these
  replacements in order.

  Keep the run's row: replace

```r
  .open_run(con, tabs, run_id, dialect)
```

  with

```r
  run <- .open_run(con, tabs, run_id, dialect)
```

  Decide the outcome from the markers too: replace

```r
  outcome <- if (any(failing)) "fail" else "pass"
```

  with

```r
  # The fallback's second marker is taken after the comparison, so a write at any
  # point between the SAS run and the end of the comparison is seen.
  before <- if (identical(run$mode, "fallback")) .read_markers(con, tabs, run_id, dialect)
  after <- if (!is.null(before)) .take_markers(con, before$source, dialect)
  void <- !is.null(after) && .markers_changed(before, after)
  outcome <- if (void) "void" else if (any(failing)) "fail" else "pass"
```

  Keep the second markers as evidence: replace

```r
    DBI::dbWriteTable(con, tabs$gate_verdicts, verdict_rows, append = TRUE)
```

  with

```r
    DBI::dbWriteTable(con, tabs$gate_verdicts, verdict_rows, append = TRUE)
    if (!is.null(after)) {
      after_rows <- cbind(data.frame(run_id = run_id, phase = "after"), after,
                          data.frame(taken_at = closed_at))
      DBI::dbWriteTable(con, tabs$gate_markers, after_rows, append = TRUE)
    }
```

  Write no parity verdict for a void run: replace

```r
    DBI::dbWriteTable(con, tabs$parity, parity_row, append = TRUE)
```

  with

```r
    if (outcome != "void") DBI::dbWriteTable(con, tabs$parity, parity_row, append = TRUE)
```

  Stop on a void run before the fail check: replace

```r
  if (outcome == "fail") {
```

  with

```r
  if (outcome == "void") {
    .abort("parity_gate_void",
           "parity_gate(): a source changed during this fallback run, so the two sides ",
           "may have read different data. The run is void: its verdicts and markers are ",
           "kept under run ", run_id, ", and no parity record was written. Open a new run.")
  }
  if (outcome == "fail") {
```

- [ ] **Step 5: Document the void outcome.** In the roxygen block of `parity_gate()`, replace

```r
#' Every run records its per-column verdicts in `<master>_gate_verdicts` and
```

  with

```r
#' A fallback run (see [open_gate_run()]) takes its second change marker for
#' every source after the comparison. If any source changed, the run is
#' **void** whatever its verdicts: both sides may have read different data. A
#' void run writes nothing to `<master>_parity`, so an earlier verdict for the
#' commit stands.
#'
#' Every run records its per-column verdicts in `<master>_gate_verdicts` and
```

  and replace

```r
#'   `hvtiRdatabuild_parity_gate_failed`.
```

  with

```r
#'   `hvtiRdatabuild_parity_gate_failed`; a void one, recorded in the gate
#'   tables only, with class `hvtiRdatabuild_parity_gate_void`.
```

- [ ] **Step 6: Document and run the tests.**
  Run: `Rscript -e 'devtools::document(); devtools::test(filter = "gate-void|parity-gate|gate-markers")'`
  Expected: all pass. The snapshot-mode test in `test-parity-gate.R` still passes: a
  snapshot run has no markers, so it is judged on its verdicts alone.

- [ ] **Step 7: Commit.**

```bash
git add R/gate_markers.R R/parity_gate.R man/parity_gate.Rd tests/testthat/test-gate-void.R
git commit -m "feat: a source change during a fallback gate run voids it"
```

---

### Task 7: spec record, reference index, news and the full gate

**Files:**
- Modify: `dev/specs/2026-11-16-master-views-design.md` (§7.2)
- Modify: `_pkgdown.yml` (after the "Master datasets" group)
- Create: `news/feat-parity-gate.md`

- [ ] **Step 1: Amend spec §7.2 and §8**, recording the parity view as plan 1 asked and
  the fail-verdict decision (decision 2). In `dev/specs/2026-11-16-master-views-design.md`,
  three replacements. In §7.2, replace

```markdown
So the gate gets its own two steps, and neither touches the master view, its metadata or its
parity records:
```

  with

```markdown
So the gate gets its own two steps. Neither touches the master view or its metadata;
`load_oracle()` writes no parity record, and `parity_gate()` writes only its verdict:
```

  Still in §7.2, replace

```markdown
The twelve historical snapshots remain the record of what SAS produced. They are not the gate.
```

  with

```markdown
**Recorded 2026-11-17 (plan 2b).** The gate's record is `<master>_parity` (`sql_commit`,
`verdict`, `verified_at`, `run_id`), written only by `parity_gate()` against the commit named
in the gate schema's `<master>_deployment`: a `pass` row for a pass and a `fail` row for a
fail. `pull_master()` reads it with the production `<master>_deployment` inside the pull's
snapshot and fails closed: no verdict for the deployed commit, a latest verdict that is not a
pass, or a pass only for another commit stops the pull. **A failed gate therefore blocks the
commit it tested until a later pass.** A void run writes nothing there, so an earlier verdict
stands. Every run's evidence is kept in `<master>_gate_runs`, `<master>_gate_markers`,
`<master>_gate_verdicts` and `<master>_gate_outcomes`, and the oracle's load check in
`<master>_oracle_integrity`. The gate schema's rules read the **uncorrected** `stg_<source>`
views, not `stg_<source>_corrected`, so a correction accepted after the SAS build cannot
appear as an unexplained difference. An **activated legacy correction** is a
`legacy_sas_inline` row of the master's corrections table whose latest decision is `accept`;
it explains a differing cell when its new value is the oracle's, and legacy inline fixes are
the only differences the gate explains. The fallback's change marker is a row count and an
XOR of row hashes: `CHECKSUM_AGG(BINARY_CHECKSUM(*))` on SQL Server, `bit_xor(hash(row))` on
duckdb.

The twelve historical snapshots remain the record of what SAS produced. They are not the gate.
```

  In §8, replace

```markdown
- Loading the oracle or failing the gate never changes the master view, its metadata or its
  parity records (§7.2).
```

  with

```markdown
- Loading the oracle or failing the gate never changes the master view or its metadata
  (§7.2). Loading the oracle writes no parity record; a failed gate records a `fail` verdict
  that blocks the commit it tested until a later pass, and a void run records none.
```

- [ ] **Step 2: Add the reference group.** In `_pkgdown.yml`, after the `Master datasets`
  group's last entry (`- lift_master`), insert:

```yaml

- title: "Parity gate: rules against SAS"
  desc: >
    Gate a master's deployed rules against a SAS build of the same source state. Only a
    master whose deployment passed is offered to study builds.
  contents:
  - open_gate_run
  - load_oracle
  - parity_gate
```

- [ ] **Step 3: Write the news fragment** `news/feat-parity-gate.md`:

```markdown
* New parity gate for master views. `open_gate_run()` opens a run before the SAS build and,
  when no database snapshot is available, records a change marker per source.
  `load_oracle()` loads the SAS build as `<master>_oracle_<date>` and records its load check
  as oracle integrity; it never touches the master's view, metadata or parity records.
  `parity_gate()` compares the rules view in a gate schema with the oracle cell by cell in
  the database, accepts a difference only where an activated legacy correction explains it,
  and records a verdict per column, never a value. A pass or a fail is written to
  `<master>_parity` against the SQL model commit it tested, so a fail blocks that commit
  from study builds until a later pass; a source change during a fallback run voids it,
  and a void run records no verdict.
* `lift_master()` now shares its load and checks with `load_oracle()`; its behaviour is
  unchanged.
```

- [ ] **Step 4: Run the full gate.**

```bash
Rscript -e 'devtools::document()'
Rscript -e 'devtools::test()'
Rscript -e 'devtools::check()'
Rscript -e 'lintr::lint_package()'
Rscript -e 'pkgdown::check_pkgdown()'
```

  Expected: tests pass with the same 12 skips as on `main` (real-study, SQL Server and odbc
  gates); check 0 errors, 0 warnings, 0 notes; no lints; pkgdown reports no missing topics.
  The new tests skip without duckdb, arrow, jsonlite, tidyselect, dplyr or withr, so confirm
  all six are installed and the skip count did not rise before calling the gate green.

- [ ] **Step 5: Commit.**

```bash
git add dev/specs/2026-11-16-master-views-design.md _pkgdown.yml news/feat-parity-gate.md \
  man/ NAMESPACE
git commit -m "docs: record the parity view in spec 7.2; reference group and news"
```

---

## Not in this plan, and why

Everything below needs SQL Server or data engineering, so it is **plan 3's rehearsal**, run
on the warehouse before the gate is trusted there:

- **Creating the database snapshot** (`CREATE DATABASE ... AS SNAPSHOT OF`), deploying the
  rules into the gate schema over it, and confirming SAS reads it through its existing
  connection (spec §10). `open_gate_run(mode = "snapshot")` records the snapshot's name; it
  cannot check that both sides read it.
- **The marker on SQL Server.** `.gate_marker_sql()` is tested as text only.
  `BINARY_CHECKSUM(*)` skips columns of non-comparable types (`text`, `ntext`, `image`,
  `xml`, `cursor`, `sql_variant` holding those), so a change confined to such a column is
  invisible to it; the rehearsal must list each source's column types, and a source with
  such columns needs change tracking or an explicit column list. Change tracking itself
  (§7.1 "where enabled") is not implemented.
- **The comparison SQL on SQL Server**: `TRY_CAST` to `DOUBLE PRECISION`, the
  `Latin1_General_BIN2` text comparison after casting both sides to `nvarchar(4000)` (text
  longer than 4000 characters is truncated by that cast), the CTE before a derived table,
  and the width of a 200-column batch. Each runs on duckdb 2.0.0 here.
- **The gate rehearsal of §9**: an upstream write between the SAS run and the comparison
  voids a fallback run (tested here on duckdb), and under a database snapshot cannot reach
  either side (needs the snapshot).
- **The gate schema reads uncorrected sources** (the contract above). Plan 3's deploy step
  must build the gate schema's rules over `stg_<source>`, not `stg_<source>_corrected`,
  while the production deployment of the same commit reads the corrected views. The
  rehearsal confirms it by accepting a non-legacy correction before a gate run and seeing no
  unexplained difference.
- **Legacy fixes against source columns.** Once plan 3 re-expresses the legacy inline fixes
  against source columns (§3.2), `.legacy_cte()` moves from the master-keyed record to
  plan 2a's per-source correction tables.

## Self-review

- **Spec coverage.** §7.1 one source state: snapshot mode (Task 3) and the fail-closed
  fallback (Tasks 3, 6). §7.2 `load_oracle()` sharing the DDL and load but not the tail
  (Tasks 1, 2); `parity_gate()` in the database, per-column verdicts, explained by activated
  legacy corrections, pass bound to commit and deployment (Tasks 4, 5); the §7.2 record of
  the view (Task 7). §8 as amended: a mismatch records a fail that blocks the tested commit,
  even after an earlier pass (Task 5, via `pull_master()`); a void run never passes and
  leaves an earlier pass in force (Task 6); oracle loading and a failing gate leave the view
  and metadata untouched, and loading writes no parity record (Tasks 2, 5, 6,
  `production_state()`). §9 gate isolation
  (Tasks 2, 5) and gate rehearsal (Task 6 on duckdb; SQL Server in plan 3).
- **No values in messages.** Every new message is built from counts, table names, run ids
  and class names. Tasks 5 and 6 assert that failure messages carry no identifier and no
  differing value.
- **Names across tasks.** `.master_tables()` names (Task 2) are the ones Tasks 3 to 6 use;
  `.open_run()` returns the run row that Task 6 reads; `gate_run()` (Task 5 helper) is what
  Task 6's tests call; `local_gate_db()` returns `list(con, dir, cfg)` everywhere.
