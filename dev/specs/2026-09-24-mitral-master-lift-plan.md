# Mitral master lift and master machinery promotion: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the cardiac master scripts into six exported functions driven by a
`master.yml` config, with lineage between masters, so the mitral master (and cardiac) can be
lifted with package calls, as designed in `dev/specs/2026-09-24-mitral-master-lift-design.md`.

**Architecture:** Task 1 moves the existing, already-reviewed script code from
`dev/masters/cardiac/` into internal files under `R/` and its standalone tests into testthat,
unchanged in behaviour. Tasks 2 to 5 add the exported layer on top: config, snapshot with
lineage, lift, and the corrections API. Task 6 documents, Task 7 verifies.

**Tech Stack:** R, haven, arrow, DBI, odbc (SQL Server), duckdb (tests), dplyr, tidyselect,
jsonlite, yaml, digest, withr, testthat 3e, roxygen2 markdown, Quarto vignettes.

## Global Constraints

- **No PHI anywhere in the repository**, in a test message or in printed output. Fixtures are
  invented and say so. Output is counts, verdicts, column names and line numbers, never a key
  or a value. Check what every error message prints.
- **Identifiers are read, never transcribed.** Legacy facts are parsed at run time.
- **No share paths in the repository.** Examples and fixtures use temporary directories.
- Lines are **100 characters** (`.lintr`). Roxygen markdown is enabled.
- Test files are `test-*.R` with a hyphen; testthat edition 3.
- **Six exports only:** `read_master_config()`, `snapshot_master()`, `lift_master()`,
  `backfill_corrections()`, `propose_correction()`, `decide_correction()`. Everything else is
  internal (`@noRd`).
- **Dry run by default** on `lift_master()` and `backfill_corrections()`; the correction
  writers default to `dry_run = FALSE`.
- **No new Imports.** `duckdb` and `tidyselect` join `Suggests`. Each export checks the
  Suggests it needs with `requireNamespace()` and a message naming the package.
- `NEWS.md`: one entry under `# hvtiRdatabuild (unreleased)` (add the heading at the top if
  absent). **Do not touch `Version:`.**
- **Never push to `main`.** Work on `spec/mitral-master-lift` (PR #65).
- Definition of done: `devtools::test()` passes; `devtools::check()` is 0/0/0 **including the
  manual** (no `--no-manual`); `lintr::lint_package()` clean with the branch source loaded;
  `devtools::document()` run and `man/`, `NAMESPACE` committed.

## File map

| File | Responsibility | Task |
|---|---|---|
| `R/sql_dialect.R` | `quoter`, `sql_string`, `sql_types`, `view_header`, `sql_timestamp_literal`, `run_step`, `table_types` | 1 |
| `R/corrections_sql.R` | `value_text`, `parse_value`, `corrections_ddl`, `resolve_corrections`, `.string_eq_sql`, `.winners_cte`, `corrections_view_sql`, `stale_view_sql`, `corrected_variables` | 1 |
| `R/master_steps.R` | `key_verdict`, `format_key_verdict`, `mssql_type`, `ddl_preflight`, `master_ddl`, `load_parquet`, `parity_sql`, `.zap_all`, `parity_check`, `parity_summary`, `parity_full`, `full_summary` | 1 |
| `R/legacy_facts.R` | `.lit_text`, `.statements`, `parse_legacy_facts`, `.key_text`, `legacy_rows`, `record_legacy_facts` | 1 |
| `R/master_config.R` | `read_master_config()`, `.master_tables()` | 2 |
| `R/master_snapshot.R` | `snapshot_master()`, history search, parent detection | 3 |
| `R/master_lift.R` | `lift_master()`, `.base_table_name()`, `.current_base()`, `.publish_views()` | 4 |
| `R/master_corrections.R` | `backfill_corrections()`, `propose_correction()`, `decide_correction()` | 5 |
| `tests/testthat/test-master-*.R` | tests | 1-5 |
| `inst/extdata/master-example.yml` | a synthetic config for examples | 2 |
| `vignettes/master-datasets.qmd` | the vignette | 6 |

---

### Task 1: Move the script code into internal package files, and its tests into testthat

Behaviour does not change in this task. The code in `dev/masters/cardiac/` has been reviewed
and tested; this task relocates it.

**Files:**
- Create: `R/sql_dialect.R`, `R/corrections_sql.R`, `R/master_steps.R`, `R/legacy_facts.R`
- Create: `tests/testthat/test-master-sql.R` (from `test-parity.R`'s quoting checks and
  `test-corrections.R`), `tests/testthat/test-master-steps.R` (from `test-key-verdict.R`,
  `test-ddl.R`, `test-load.R`, the parity checks of `test-parity.R`),
  `tests/testthat/test-master-legacy.R` (from `test-legacy.R`)
- Modify: `DESCRIPTION` (Suggests)
- Delete: `dev/masters/cardiac/` entirely, including `propose.R` and `test-propose.R`
  (Task 5 re-creates both, config-driven) and the four runbooks (replaced by exports)

**Interfaces:**
- Produces: every function in the File map rows for Task 1, with **exactly the signatures they
  have today** in `dev/masters/cardiac/`. Later tasks call them by those names.
- Keep a copy of `dev/masters/cardiac/propose.R` and `test-propose.R` readable for Task 5:
  before deleting, copy them to `.superpowers/sdd/legacy-propose.R` and
  `.superpowers/sdd/legacy-test-propose.R` (git-ignored scratch).

- [ ] **Step 1: Copy the two files Task 5 needs into scratch**

```bash
mkdir -p .superpowers/sdd
cp dev/masters/cardiac/propose.R .superpowers/sdd/legacy-propose.R
cp dev/masters/cardiac/test-propose.R .superpowers/sdd/legacy-test-propose.R
```

- [ ] **Step 2: Move the code.** For each target file, copy the functions named in the File
  map verbatim from their source script (`sql-common.R`, `value-text.R` and
  `corrections.R`, `key-verdict.R` + `ddl.R` + `load.R` + `parity.R`, `legacy.R`). Then apply
  exactly these edits and no others:
  1. Give every function a roxygen block ending `#' @keywords internal` and `#' @noRd`, with
     a one-line title and `@param`/`@return` lines taken from the script's comments. Keep the
     scripts' explanatory comments.
  2. In `parity_full()` and `parity_check()`, replace `hvtiRdatabuild::compare_built(` with
     `compare_built(`.
  3. In `table_types()`, normalise the result columns' case so duckdb (which returns lower-case
     `column_name`) and SQL Server (upper-case) both work. Replace the body's first statement
     with:

```r
  cols <- DBI::dbGetQuery(con, paste(
    "SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH",
    "FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = ?",
    "ORDER BY ORDINAL_POSITION"), params = list(table))
  names(cols) <- toupper(names(cols))
```

  (keep the rest of the function as it is).
  4. Remove every `source(...)` line.

- [ ] **Step 3: Add to `Suggests`** in `DESCRIPTION`, alphabetically: `duckdb` (after `dplyr`)
  and `tidyselect` (after `testthat (>= 3.0.0)`).

- [ ] **Step 4: Convert the tests.** Each standalone test becomes testthat with these rules:
  - Drop the `self`/`here` lines, `source()` calls, `skip_unless()` and `finish()`.
  - Group consecutive checks into `test_that("<the section's subject>", { ... })` blocks, one
    per fixture or behaviour.
  - Start each block with `skip_if_not_installed()` for each package the block uses
    (`arrow`, `duckdb`, `DBI`, `dplyr`, `withr`, `tidyselect`, `digest`, `haven`).
  - `check("label", cond)` becomes `expect_true(cond, label = "label")`.
  - `check_error("label", expr, "pattern")` becomes `expect_error(expr, "pattern")`; where the
    old test kept the message (`msg <- check_error(...)`), use
    `msg <- tryCatch(expr, error = conditionMessage)` then `expect_match(msg, "pattern")` and
    keep the following `!grepl(...)` check as `expect_false(grepl(...))`.
  - Replace `invisible(DBI::dbExecute(...))` with `DBI::dbExecute(...)` (testthat does not
    print), and close connections with `withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))`.
  - Keep every fixture and expected value exactly.

  Example, from `test-key-verdict.R`:

```r
test_that("key_verdict reports uniqueness, nulls and absence without values", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("tidyselect")
  pq <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(data.frame(
    id      = c("K1", "K1", "K2", "K3", NA),
    dt_surg = as.Date(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-01-01",
                        "2020-01-01")),
    alt     = c("E1", "E2", NA, "E2", "E3"),
    stringsAsFactors = FALSE
  ), pq)
  v <- key_verdict(pq, c("id", "dt_surg"))
  expect_true(v$verdict == "not unique", label = "one null key part makes it not unique")
  expect_true(v$n_duplicates == 0L, label = "no duplicates among the rows")
  # ... every remaining check from the file, converted the same way
})
```

- [ ] **Step 5: Delete the scripts**

```bash
git rm -r -q dev/masters/cardiac
```

- [ ] **Step 6: Document and test**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "master")'`
Expected: every `test-master-*` file passes with the same number of expectations as the old
scripts had checks (report both counts). No `SKIP` when duckdb is installed.

- [ ] **Step 7: Full suite and lint**

Run: `Rscript -e 'devtools::test(); devtools::load_all(); print(lintr::lint_package())'`
Expected: all pass; no lints.

- [ ] **Step 8: Commit**

```bash
git add -A R/ tests/testthat/ DESCRIPTION man/ NAMESPACE dev/masters
git commit -m "refactor: move the master scripts into the package, and their tests into testthat"
```

---

### Task 2: `read_master_config()`

**Files:**
- Create: `R/master_config.R`
- Create: `inst/extdata/master-example.yml`
- Test: `tests/testthat/test-master-config.R`

**Interfaces:**
- Produces: `read_master_config(path)` returning an object of class `master_config`: a list
  with `name` (chr), `key` (chr vector), `alt_keys` (named list of chr vectors, possibly
  empty), `parent` (`NULL` or `list(master = chr, libref = chr)`), `parent_release` (`NULL` or
  chr), `snapshots` (chr), `current` (chr), `history` (chr or `NULL`), `build_program` (chr),
  `file` (chr, the config's path).
- Produces (internal): `.master_tables(config)` returning a list of table names:
  `corrections`, `decisions`, `stale`, `parity`, `meta`, each `paste0(config$name, suffix)`
  with suffixes `_corrections`, `_correction_decisions`, `_corrections_stale`, `_parity`,
  `_meta`.

- [ ] **Step 1: Write the example config** `inst/extdata/master-example.yml`:

```yaml
# A synthetic master configuration, for examples and tests. No real paths.
name: master_example
key: [ccfid, dt_surg]
alt_keys:
  epic: [emrn, encounter_date]
parent:
  master: master_parent
  libref: master
snapshots: /tmp/master-example
current: built.sas7bdat
history: "^built_.*\\.sas7bdat$"
build_program: /tmp/master-example/bd.data.sas
```

- [ ] **Step 2: Write the failing tests** `tests/testthat/test-master-config.R`:

```r
# Tests for read_master_config(). Every config here is synthetic. No PHI.

write_cfg <- function(lines) {
  p <- withr::local_tempfile(fileext = ".yml", .local_envir = parent.frame())
  writeLines(lines, p)
  p
}

base_cfg <- c(
  "name: master_x",
  "key: [ccfid, dt_surg]",
  "snapshots: /tmp/x",
  "current: built.sas7bdat",
  "build_program: /tmp/x/bd.sas"
)

test_that("a minimal config reads, with empty alt_keys and no parent", {
  cfg <- read_master_config(write_cfg(base_cfg))
  expect_s3_class(cfg, "master_config")
  expect_equal(cfg$key, c("ccfid", "dt_surg"))
  expect_equal(length(cfg$alt_keys), 0L)
  expect_null(cfg$parent)
  expect_null(cfg$parent_release)
})

test_that("the example config reads, with a named alternate key and a parent", {
  cfg <- read_master_config(system.file("extdata", "master-example.yml",
                                        package = "hvtiRdatabuild"))
  expect_equal(cfg$alt_keys$epic, c("emrn", "encounter_date"))
  expect_equal(cfg$parent$libref, "master")
})

test_that("each required field is required", {
  for (f in c("name", "key", "snapshots", "current", "build_program")) {
    lines <- base_cfg[!startsWith(base_cfg, paste0(f, ":"))]
    expect_error(read_master_config(write_cfg(lines)), f)
  }
})

test_that("a parent needs both master and libref", {
  expect_error(read_master_config(write_cfg(c(base_cfg, "parent:", "  master: p"))),
               "libref")
  expect_error(read_master_config(write_cfg(c(base_cfg, "parent:", "  libref: m"))),
               "master")
})

test_that("parent_release must be one string and needs a parent", {
  expect_error(read_master_config(write_cfg(c(base_cfg, "parent_release: r1"))),
               "parent")
  expect_error(read_master_config(write_cfg(c(base_cfg, "parent:", "  master: p",
                                              "  libref: m",
                                              "parent_release: [a, b]"))),
               "single string")
})

test_that("a column named twice across key and alt_keys is refused", {
  expect_error(read_master_config(write_cfg(c(base_cfg, "alt_keys:",
                                              "  epic: [ccfid, encounter_date]"))),
               "more than once")
})

test_that("a history pattern that does not compile is refused", {
  expect_error(read_master_config(write_cfg(c(base_cfg, "history: \"[unclosed\""))),
               "history")
})

test_that(".master_tables derives every table name from the master's name", {
  cfg <- read_master_config(write_cfg(base_cfg))
  t <- .master_tables(cfg)
  expect_equal(t$corrections, "master_x_corrections")
  expect_equal(t$decisions, "master_x_correction_decisions")
  expect_equal(t$stale, "master_x_corrections_stale")
  expect_equal(t$parity, "master_x_parity")
  expect_equal(t$meta, "master_x_meta")
})
```

- [ ] **Step 3: Run them and watch them fail**

Run: `Rscript -e 'devtools::test(filter = "master-config")'`
Expected: FAIL, `could not find function "read_master_config"`.

- [ ] **Step 4: Implement** `R/master_config.R`:

```r
#' Read a master dataset's configuration
#'
#' A master dataset is a clinical dataset that other builds read, such as the
#' cardiac-surgery master or the mitral master built on top of it. Each is
#' described by a `master.yml` kept outside the package, because it names paths
#' on a shared volume. The file declares the master's view name, its one
#' primary key, any alternate keys, its parent master, and where its SAS
#' snapshots and build program live.
#'
#' The primary key is what corrections match on and what the view joins on.
#' Alternate keys are bridges to other systems: each is checked unique where it
#' is non-null, and its columns are carried on every correction, but nothing
#' matches on them.
#'
#' @param path Path to the `master.yml` file.
#'
#' @return An object of class `master_config`: a list with `name`, `key`,
#'   `alt_keys` (a named list, possibly empty), `parent` (`NULL` or a list with
#'   `master` and `libref`), `parent_release` (`NULL` or a string), `snapshots`,
#'   `current`, `history` (`NULL` or a regular expression), `build_program`,
#'   and `file`.
#'
#' @seealso [snapshot_master()], [lift_master()], [backfill_corrections()]
#'
#' @examples
#' cfg <- read_master_config(system.file("extdata", "master-example.yml",
#'                                       package = "hvtiRdatabuild"))
#' cfg$key
#'
#' @export
read_master_config <- function(path) {
  if (!file.exists(path)) {
    stop("Master configuration does not exist: ", path, call. = FALSE)
  }
  raw <- yaml::read_yaml(path)
  required <- c("name", "key", "snapshots", "current", "build_program")
  missing <- required[!vapply(required, function(f) !is.null(raw[[f]]), logical(1))]
  if (length(missing)) {
    stop("Master configuration is missing required field(s): ",
         paste(missing, collapse = ", "), ".", call. = FALSE)
  }

  alt_keys <- raw$alt_keys
  if (is.null(alt_keys)) alt_keys <- list()
  alt_keys <- lapply(alt_keys, as.character)

  all_cols <- c(as.character(raw$key), unlist(alt_keys, use.names = FALSE))
  twice <- unique(all_cols[duplicated(all_cols)])
  if (length(twice)) {
    stop("Column(s) named more than once across key and alt_keys: ",
         paste(twice, collapse = ", "), ".", call. = FALSE)
  }

  parent <- raw$parent
  if (!is.null(parent)) {
    absent <- c("master", "libref")[!c(!is.null(parent$master), !is.null(parent$libref))]
    if (length(absent)) {
      stop("'parent' must name both master and libref; missing: ",
           paste(absent, collapse = ", "), ".", call. = FALSE)
    }
    parent <- list(master = as.character(parent$master),
                   libref = as.character(parent$libref))
  }

  parent_release <- raw$parent_release
  if (!is.null(parent_release)) {
    if (is.null(parent)) {
      stop("'parent_release' is set but there is no 'parent'.", call. = FALSE)
    }
    if (!is.character(parent_release) || length(parent_release) != 1L) {
      stop("'parent_release' must be a single string.", call. = FALSE)
    }
  }

  history <- raw$history
  if (!is.null(history)) {
    ok <- tryCatch({
      grepl(history, "")
      TRUE
    }, error = function(e) FALSE, warning = function(w) FALSE)
    if (!ok) stop("'history' is not a valid regular expression.", call. = FALSE)
  }

  structure(list(
    name = as.character(raw$name), key = as.character(raw$key), alt_keys = alt_keys,
    parent = parent, parent_release = parent_release,
    snapshots = as.character(raw$snapshots), current = as.character(raw$current),
    history = history, build_program = as.character(raw$build_program), file = path
  ), class = "master_config")
}

#' Table names derived from a master's name
#'
#' @param config A `master_config`.
#'
#' @return A list of table and view names.
#'
#' @keywords internal
#' @noRd
.master_tables <- function(config) {
  n <- config$name
  list(corrections = paste0(n, "_corrections"),
       decisions   = paste0(n, "_correction_decisions"),
       stale       = paste0(n, "_corrections_stale"),
       parity      = paste0(n, "_parity"),
       meta        = paste0(n, "_meta"))
}
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "master-config")'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add R/master_config.R inst/extdata/master-example.yml \
  tests/testthat/test-master-config.R man/ NAMESPACE
git commit -m "feat: read and validate a master's configuration"
```

---

### Task 3: `snapshot_master()`, with lineage between masters

**Files:**
- Create: `R/master_snapshot.R`
- Test: `tests/testthat/test-master-snapshot.R`

**Interfaces:**
- Consumes: `read_master_config()` (Task 2); `snapshot_oracle(sas_path, out_path, expect =
  NULL, manifest = NULL, chunk_rows = NULL)` (package), which returns `list(path, n_rows,
  n_cols, variables, sha256, source_sha256, meta_path)` and writes a `.meta.json` sidecar;
  `key_verdict(parquet, key, nonnull_only)` and `format_key_verdict(v)` (Task 1).
- Produces: `snapshot_master(config, out_dir, which = c("current", "history"),
  chunk_rows = 1e5, expect = NULL)` returning, invisibly, a data frame with one row per
  dataset: `file`, `status` (`"written"`, `"skipped"`, `"failed"`), `n_rows`, `n_cols`,
  `sha256`, `source_sha256`, `parent_release`, `parent_source`, `key_verdict`. It adds a
  `lineage` object (`parent_master`, `parent_release`, `parent_source`) and a `keys` object
  (one verdict per key name) to each sidecar.
- Produces (internal): `.find_history(config)` (character vector of paths),
  `.parent_from_log(dataset, config)` and `.parent_from_program(config)` (each a character
  vector of distinct parent members, lower case), `.bracketing_log(dataset, dirs,
  window_hours = 6)` (a path or `NA`).

- [ ] **Step 1: Write the failing tests** `tests/testthat/test-master-snapshot.R`:

```r
# Tests for snapshot_master(). The SAS fixture is the package's synthetic
# oracle_small.sas7bdat; logs and programs are invented text. No PHI.

make_master <- function(env = parent.frame(), log_member = "built_2026mar27",
                        prog_member = "built_2026mar27", with_log = TRUE) {
  dir <- withr::local_tempdir(.local_envir = env)
  src <- system.file("extdata", "oracle_small.sas7bdat", package = "hvtiRdatabuild")
  file.copy(src, file.path(dir, "built.sas7bdat"))
  dir.create(file.path(dir, "2023"))
  file.copy(src, file.path(dir, "2023", "built_2023jan.sas7bdat"))
  # An old build: no log is written within hours of it.
  Sys.setFileTime(file.path(dir, "2023", "built_2023jan.sas7bdat"),
                  Sys.time() - 30 * 86400)
  writeLines(c("data m;", paste0("  set master.", prog_member, ";"), "run;"),
             file.path(dir, "bd.data.sas"))
  if (with_log) {
    log <- file.path(dir, "bd.data.log")
    writeLines(c("NOTE: invented log.",
                 paste0("NOTE: There were 4 observations read from the data set MASTER.",
                        toupper(log_member), ".")), log)
    t <- file.mtime(file.path(dir, "built.sas7bdat")) + 60
    Sys.setFileTime(log, t)
  }
  cfg_path <- file.path(dir, "master.yml")
  writeLines(c("name: master_x", "key: [ccfidu]", "alt_keys:", "  bridge: [surgeon]",
               "parent:", "  master: master_parent", "  libref: master",
               paste0("snapshots: ", dir), "current: built.sas7bdat",
               "history: \"^built_.*\\\\.sas7bdat$\"",
               paste0("build_program: ", file.path(dir, "bd.data.sas"))), cfg_path)
  list(dir = dir, cfg = read_master_config(cfg_path))
}

test_that("the current snapshot records the parent release from the log", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  m <- make_master()
  out <- withr::local_tempdir()
  res <- snapshot_master(m$cfg, out, which = "current")
  expect_equal(res$status, "written")
  expect_equal(res$parent_release, "built_2026mar27")
  expect_equal(res$parent_source, "log")
  expect_equal(res$key_verdict, "unique")
  meta <- jsonlite::read_json(file.path(out, "built.meta.json"), simplifyVector = TRUE)
  expect_equal(meta$lineage$parent_release, "built_2026mar27")
  expect_equal(meta$keys$bridge, "not unique")
})

test_that("the log beats a program that names a different parent release", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  m <- make_master(log_member = "built_2026mar27", prog_member = "built_2025mar31")
  res <- snapshot_master(m$cfg, withr::local_tempdir(), which = "current")
  expect_equal(res$parent_release, "built_2026mar27")
  expect_equal(res$parent_source, "log")
})

test_that("without a bracketing log the program decides", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  m <- make_master(with_log = FALSE)
  res <- snapshot_master(m$cfg, withr::local_tempdir(), which = "current")
  expect_equal(res$parent_source, "program")
})

test_that("an ambiguous parent stops unless parent_release is declared", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  m <- make_master(with_log = FALSE)
  writeLines(c("set master.built_a;", "set master.built_b;"), m$cfg$build_program)
  expect_error(snapshot_master(m$cfg, withr::local_tempdir(), which = "current"),
               "parent_release")
  m$cfg$parent_release <- "built_a"
  res <- snapshot_master(m$cfg, withr::local_tempdir(), which = "current")
  expect_equal(res$parent_source, "declared")
})

test_that("history is found in subfolders, and its unknown parent does not stop", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  m <- make_master()
  expect_equal(basename(.find_history(m$cfg)), "built_2023jan.sas7bdat")
  res <- snapshot_master(m$cfg, withr::local_tempdir(), which = "history")
  expect_equal(res$status, "written")
  expect_equal(res$parent_source, "unknown")
})

test_that("a second run skips what is already written", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  m <- make_master()
  out <- withr::local_tempdir()
  snapshot_master(m$cfg, out, which = "current")
  res <- snapshot_master(m$cfg, out, which = "current")
  expect_equal(res$status, "skipped")
})

test_that("a master with no parent records no lineage", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  m <- make_master()
  m$cfg$parent <- NULL
  res <- snapshot_master(m$cfg, withr::local_tempdir(), which = "current")
  expect_true(is.na(res$parent_release))
  expect_equal(res$parent_source, "none")
})
```

- [ ] **Step 2: Run them and watch them fail**

Run: `Rscript -e 'devtools::test(filter = "master-snapshot")'`
Expected: FAIL, `could not find function "snapshot_master"`.

- [ ] **Step 3: Implement** `R/master_snapshot.R`:

```r
#' Snapshot a master dataset to parquet, with its lineage
#'
#' Freezes a master's current SAS build, or its historical builds, as parquet
#' with [snapshot_oracle()], then checks its keys and records which release of
#' its parent master it was built from.
#'
#' The parent release is read from evidence of what ran, in this order: the log
#' of the run that produced the dataset (a `.log` whose timestamp falls within
#' six hours after the dataset's), where SAS records every dataset it read;
#' then, for the current build only, the build program's `set` statements; then
#' `parent_release` in the configuration. The log comes first because a
#' program can be edited after the run. A current build whose parent cannot be
#' decided stops; a historical one records `"unknown"`.
#'
#' Only `NOTE:` lines naming datasets are read from a log, never data lines.
#' Nothing printed carries a key or a value.
#'
#' @param config A `master_config` from [read_master_config()].
#' @param out_dir Directory to write the parquet snapshots and their sidecars.
#' @param which `"current"`, `"history"`, or both.
#' @param chunk_rows Rows per chunk, passed to [snapshot_oracle()].
#' @param expect Optional validation for the current build, passed to
#'   [snapshot_oracle()]. Historical builds are not validated, because their
#'   logs are rarely retained.
#'
#' @return Invisibly, a data frame with one row per dataset: `file`, `status`
#'   (`"written"`, `"skipped"` or `"failed"`), `n_rows`, `n_cols`, `sha256`,
#'   `source_sha256`, `parent_release`, `parent_source` (`"log"`, `"program"`,
#'   `"declared"`, `"unknown"` or `"none"`) and `key_verdict`.
#'
#' @seealso [read_master_config()], [lift_master()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("arrow", quietly = TRUE) &&
#'     requireNamespace("jsonlite", quietly = TRUE) &&
#'     requireNamespace("tidyselect", quietly = TRUE)) {
#'   dir <- tempfile("master")
#'   dir.create(dir)
#'   file.copy(system.file("extdata", "oracle_small.sas7bdat",
#'                         package = "hvtiRdatabuild"),
#'             file.path(dir, "built.sas7bdat"))
#'   writeLines("data m; run;", file.path(dir, "bd.data.sas"))
#'   cfg_path <- file.path(dir, "master.yml")
#'   writeLines(c("name: master_demo", "key: [ccfidu]",
#'                paste0("snapshots: ", dir), "current: built.sas7bdat",
#'                paste0("build_program: ", file.path(dir, "bd.data.sas"))),
#'              cfg_path)
#'   snapshot_master(read_master_config(cfg_path), tempfile("out"),
#'                   which = "current")
#' }
#' }
#'
#' @export
snapshot_master <- function(config, out_dir, which = c("current", "history"),
                            chunk_rows = 1e5, expect = NULL) {
  for (p in c("arrow", "jsonlite", "tidyselect")) {
    if (!requireNamespace(p, quietly = TRUE)) {
      stop("Package '", p, "' is required to snapshot a master. ",
           "Install it with install.packages('", p, "').", call. = FALSE)
    }
  }
  if (!inherits(config, "master_config")) {
    stop("'config' must come from read_master_config().", call. = FALSE)
  }
  which <- match.arg(which, several.ok = TRUE)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  targets <- character()
  if ("current" %in% which) targets <- file.path(config$snapshots, config$current)
  if ("history" %in% which) targets <- c(targets, .find_history(config))

  rows <- lapply(targets, function(sas) {
    is_current <- identical(normalizePath(sas, mustWork = FALSE),
                            normalizePath(file.path(config$snapshots, config$current),
                                          mustWork = FALSE))
    out <- file.path(out_dir, sub("\\.sas7bdat$", ".parquet", basename(sas)))
    row <- data.frame(file = basename(sas), status = "skipped", n_rows = NA_real_,
                      n_cols = NA_real_, sha256 = NA_character_,
                      source_sha256 = NA_character_, parent_release = NA_character_,
                      parent_source = NA_character_, key_verdict = NA_character_,
                      stringsAsFactors = FALSE)
    if (file.exists(out)) return(row)

    lineage <- .resolve_parent(sas, config, is_current)
    info <- snapshot_oracle(sas, out, expect = if (is_current) expect else NULL,
                            chunk_rows = chunk_rows)
    verdicts <- c(key = key_verdict(out, config$key)$verdict,
                  vapply(config$alt_keys, function(cols)
                    key_verdict(out, cols, nonnull_only = TRUE)$verdict, character(1)))
    meta <- jsonlite::read_json(info$meta_path)
    meta$lineage <- list(parent_master = if (is.null(config$parent)) NULL else
                           config$parent$master,
                         parent_release = if (is.na(lineage$release)) NULL else
                           lineage$release,
                         parent_source = lineage$source)
    meta$keys <- as.list(verdicts)
    jsonlite::write_json(meta, info$meta_path, auto_unbox = TRUE, null = "null",
                         pretty = TRUE)

    row$status <- "written"
    row$n_rows <- info$n_rows
    row$n_cols <- info$n_cols
    row$sha256 <- info$sha256
    row$source_sha256 <- info$source_sha256
    row$parent_release <- lineage$release
    row$parent_source <- lineage$source
    row$key_verdict <- verdicts[["key"]]
    message(sprintf("%-40s %s rows x %s columns; key %s; parent %s (%s)",
                    basename(sas), info$n_rows, info$n_cols, verdicts[["key"]],
                    lineage$release, lineage$source))
    row
  })
  invisible(do.call(rbind, rows))
}

#' Historical builds matching the configuration's pattern
#'
#' @param config A `master_config`.
#'
#' @return Paths in `snapshots/` and its immediate subfolders whose file name
#'   matches `history`, excluding the current build.
#'
#' @keywords internal
#' @noRd
.find_history <- function(config) {
  if (is.null(config$history)) return(character())
  dirs <- c(config$snapshots, list.dirs(config$snapshots, recursive = FALSE))
  files <- unlist(lapply(dirs, list.files, pattern = config$history, full.names = TRUE))
  files <- files[basename(files) != config$current]
  sort(unique(files))
}

#' The log whose timestamp brackets a dataset's
#'
#' @param dataset Path to the dataset.
#' @param dirs Directories to search for `.log` files.
#' @param window_hours Hours after the dataset's modification time within which
#'   the log must have been written.
#'
#' @return The closest qualifying log's path, or `NA`.
#'
#' @keywords internal
#' @noRd
.bracketing_log <- function(dataset, dirs, window_hours = 6) {
  logs <- unique(unlist(lapply(unique(dirs), list.files, pattern = "\\.log$",
                               full.names = TRUE, ignore.case = TRUE)))
  if (!length(logs)) return(NA_character_)
  t0 <- file.mtime(dataset)
  dt <- as.numeric(difftime(file.mtime(logs), t0, units = "hours"))
  ok <- !is.na(dt) & dt >= 0 & dt <= window_hours
  if (!any(ok)) return(NA_character_)
  logs[ok][which.min(dt[ok])]
}

#' Parent members named in a log's dataset-read NOTEs
#'
#' @param log Path to a SAS log.
#' @param libref The libref the parent is read through.
#'
#' @return Distinct members, lower case.
#'
#' @keywords internal
#' @noRd
.parent_from_log <- function(log, libref) {
  lines <- readLines(log, warn = FALSE)
  notes <- grep("^NOTE:", lines, value = TRUE)
  pat <- paste0("read from the data set ", libref, "\\.([A-Za-z0-9_]+)")
  m <- regmatches(notes, regexec(pat, notes, ignore.case = TRUE))
  unique(tolower(vapply(Filter(length, m), `[[`, character(1), 2)))
}

#' Parent members named in a build program's reads
#'
#' @param program Path to the SAS build program.
#' @param libref The libref the parent is read through.
#'
#' @return Distinct members, lower case.
#'
#' @keywords internal
#' @noRd
.parent_from_program <- function(program, libref) {
  if (!file.exists(program)) return(character())
  text <- readLines(program, warn = FALSE)
  pat <- paste0("\\b(set|merge|from|join)\\s+", libref, "\\.([A-Za-z0-9_]+)")
  m <- regmatches(text, regexec(pat, text, ignore.case = TRUE))
  unique(tolower(vapply(Filter(length, m), `[[`, character(1), 3)))
}

#' Decide a dataset's parent release, and how it was decided
#'
#' @param sas Path to the dataset.
#' @param config A `master_config`.
#' @param is_current Whether this is the current build.
#'
#' @return A list with `release` (a string or `NA`) and `source`.
#'
#' @keywords internal
#' @noRd
.resolve_parent <- function(sas, config, is_current) {
  if (is.null(config$parent)) return(list(release = NA_character_, source = "none"))
  libref <- config$parent$libref
  log <- .bracketing_log(sas, c(dirname(sas), dirname(config$build_program)))
  found <- if (!is.na(log)) .parent_from_log(log, libref) else character()
  source <- "log"
  if (!length(found) && is_current) {
    found <- .parent_from_program(config$build_program, libref)
    source <- "program"
  }
  declared <- config$parent_release
  if (length(found) == 1L) {
    if (!is.null(declared) && !identical(tolower(declared), found)) {
      stop("The declared parent_release disagrees with the ", source,
           ", which names ", found, ".", call. = FALSE)
    }
    return(list(release = found, source = source))
  }
  if (!is.null(declared)) return(list(release = tolower(declared), source = "declared"))
  if (is_current) {
    stop("Could not decide which release of ", config$parent$master, " ",
         basename(sas), " was built from (", length(found), " candidates). ",
         "Set 'parent_release' in ", basename(config$file), ".", call. = FALSE)
  }
  list(release = NA_character_, source = "unknown")
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "master-snapshot")'`
Expected: PASS. If the history test finds the current build too, check `.find_history()`
excludes `config$current`.

- [ ] **Step 5: Commit**

```bash
git add R/master_snapshot.R tests/testthat/test-master-snapshot.R man/ NAMESPACE
git commit -m "feat: snapshot a master, recording its parent release from the run's log"
```

---

### Task 4: `lift_master()`

**Files:**
- Create: `R/master_lift.R`
- Test: `tests/testthat/test-master-lift.R`

**Interfaces:**
- Consumes: `.master_tables()` (Task 2); `key_verdict()`, `format_key_verdict()`,
  `master_ddl(parquet, table, schema_name)`, `load_parquet(con, parquet, table, log_table)`,
  `parity_check(con, table, parquet, key, sample_n, seed, dialect)`, `parity_summary()`,
  `parity_full(con, table, parquet, key, dialect)`, `full_summary()`, `quoter()`,
  `view_header()`, `table_types()`, `run_step()`, `corrections_view_sql()`,
  `stale_view_sql()`, `corrected_variables()` (Task 1).
- Produces: `lift_master(config, con, parquet, dry_run = TRUE, dialect = "mssql")` returning
  invisibly `list(dry_run, base_table, ddl_path, verdict)`.
- Produces (internal, used by Task 5): `.base_table_name(config, parquet)`;
  `.current_base(con, config, dialect)` (the base table of the latest passing parity record,
  or an error); `.publish_views(config, con, base_table, dialect)` (creates the master view:
  the corrections view and stale view when the corrections table exists, otherwise
  `SELECT *`).

- [ ] **Step 1: Write the failing tests** `tests/testthat/test-master-lift.R`:

```r
# Tests for lift_master(), on duckdb with invented data. No PHI.

lift_fixture <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  d <- data.frame(id = paste0("K", 1:6), dt_surg = as.Date("2020-01-01") + 0:5,
                  age = c(60.25, 61, NA, 63, 64, 65),
                  surgeon = c("A", "a", "A ", NA, "B", "B"), stringsAsFactors = FALSE)
  pq <- file.path(dir, "built_2026.parquet")
  arrow::write_parquet(d, pq)
  jsonlite::write_json(list(parquet_sha256 = "invented", columns = list(
    list(variable = "id", r_class = "character"),
    list(variable = "dt_surg", r_class = "Date"),
    list(variable = "age", r_class = "numeric"),
    list(variable = "surgeon", r_class = "character"))),
    file.path(dir, "built_2026.meta.json"), auto_unbox = TRUE)
  cfg <- structure(list(name = "master_t", key = c("id", "dt_surg"), alt_keys = list(),
                        parent = NULL, parent_release = NULL, snapshots = dir,
                        current = "built_2026.sas7bdat", history = NULL,
                        build_program = file.path(dir, "bd.sas"),
                        file = file.path(dir, "master.yml")), class = "master_config")
  list(dir = dir, pq = pq, cfg = cfg, data = d)
}

test_that("the dry run writes the DDL and touches nothing", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  f <- lift_fixture()
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  res <- lift_master(f$cfg, con, f$pq, dialect = "duckdb")
  expect_true(res$dry_run)
  expect_true(file.exists(res$ddl_path))
  expect_equal(res$base_table, "master_t_base_built_2026")
  expect_equal(length(DBI::dbListTables(con)), 0L)
})

test_that("an executed lift loads, passes parity, records it, and creates the view", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("dplyr")
  skip_if_not_installed("withr")
  skip_if_not_installed("tidyselect")
  f <- lift_fixture()
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  res <- lift_master(f$cfg, con, f$pq, dry_run = FALSE, dialect = "duckdb")
  expect_equal(res$verdict, "pass")
  v <- DBI::dbGetQuery(con, "SELECT * FROM master_t ORDER BY id")
  expect_equal(nrow(v), 6L)
  expect_equal(.current_base(con, f$cfg, "duckdb"), "master_t_base_built_2026")
  expect_true(DBI::dbExistsTable(con, "master_t_meta"))
})

test_that("a key that is not unique stops before any table is created", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  f <- lift_fixture()
  f$cfg$key <- "surgeon"
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  expect_error(lift_master(f$cfg, con, f$pq, dry_run = FALSE, dialect = "duckdb"),
               "not unique")
  expect_equal(length(DBI::dbListTables(con)), 0L)
})

test_that(".current_base stops when no parity has passed", {
  skip_if_not_installed("duckdb")
  f <- list(cfg = structure(list(name = "master_none"), class = "master_config"))
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  expect_error(.current_base(con, f$cfg, "duckdb"), "no passing parity")
})
```

- [ ] **Step 2: Run them and watch them fail**

Run: `Rscript -e 'devtools::test(filter = "master-lift")'`
Expected: FAIL, `could not find function "lift_master"`.

- [ ] **Step 3: Implement** `R/master_lift.R`:

```r
#' Lift a master's parquet snapshot into the warehouse as a view
#'
#' Checks the primary key, creates a base table named for the snapshot's
#' release, loads it row group by row group, and proves it equal to the
#' snapshot: counts, aggregates and a sampled compare first, then a full
#' comparison of every column joined on the key. Only then is a parity record
#' written and the master's view created. If the master already has a
#' corrections table, the view is regenerated with corrections applied.
#'
#' A dry run, the default, writes the table's DDL next to the snapshot for a
#' hand-off and touches nothing else. Warehouse errors are reported by step,
#' with the driver's message withheld, because it can carry a data value.
#'
#' @param config A `master_config` from [read_master_config()].
#' @param con A DBI connection, such as one from [dw_connect()].
#' @param parquet Path to a snapshot written by [snapshot_master()]; its
#'   `.meta.json` sidecar must sit beside it.
#' @param dry_run If `TRUE`, the default, write the DDL and nothing else.
#' @param dialect `"mssql"` for the warehouse, or `"duckdb"`, used in tests.
#'
#' @return Invisibly, a list with `dry_run`, `base_table`, `ddl_path` and
#'   `verdict` (`"pass"`, or `NA` for a dry run).
#'
#' @seealso [snapshot_master()], [backfill_corrections()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE) &&
#'     requireNamespace("arrow", quietly = TRUE) &&
#'     requireNamespace("tidyselect", quietly = TRUE)) {
#'   dir <- tempfile("lift")
#'   dir.create(dir)
#'   pq <- file.path(dir, "built_demo.parquet")
#'   arrow::write_parquet(data.frame(id = c("K1", "K2"), x = c(1, 2)), pq)
#'   cfg_path <- file.path(dir, "master.yml")
#'   writeLines(c("name: master_demo", "key: [id]", paste0("snapshots: ", dir),
#'                "current: built_demo.sas7bdat",
#'                paste0("build_program: ", file.path(dir, "bd.sas"))), cfg_path)
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   lift_master(read_master_config(cfg_path), con, pq, dialect = "duckdb")
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#' }
#' }
#'
#' @export
lift_master <- function(config, con, parquet, dry_run = TRUE, dialect = "mssql") {
  for (p in c("arrow", "tidyselect")) {
    if (!requireNamespace(p, quietly = TRUE)) {
      stop("Package '", p, "' is required to lift a master. ",
           "Install it with install.packages('", p, "').", call. = FALSE)
    }
  }
  if (!inherits(config, "master_config")) {
    stop("'config' must come from read_master_config().", call. = FALSE)
  }
  base <- .base_table_name(config, parquet)

  kv <- key_verdict(parquet, config$key)
  message(format_key_verdict(kv))
  if (kv$verdict != "unique") {
    stop("The primary key is not unique in the snapshot; nothing was created.",
         call. = FALSE)
  }

  ddl <- master_ddl(parquet, base)
  ddl_path <- paste0(parquet, ".ddl.sql")
  if (dry_run) {
    writeLines(ddl$sql, ddl_path)
    message("dry run: DDL for ", base, " written to ", ddl_path)
    return(invisible(list(dry_run = TRUE, base_table = base, ddl_path = ddl_path,
                          verdict = NA_character_)))
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package 'jsonlite' is required to lift a master. ",
         "Install it with install.packages('jsonlite').", call. = FALSE)
  }

  tabs <- .master_tables(config)
  if (!DBI::dbExistsTable(con, base)) {
    run_step("create base table", {
      if (dialect == "mssql") {
        DBI::dbExecute(con, ddl$sql)
      } else {
        proto <- as.data.frame(arrow::ParquetFileReader$create(parquet)$ReadRowGroup(0L))
        DBI::dbCreateTable(con, base, .zap_all(proto)[0, , drop = FALSE])
      }
    })
  }
  r <- run_step("load", load_parquet(con, parquet, base))
  message("load: ", r$loaded, " row groups loaded, ", r$skipped, " already present")

  res <- run_step("parity check", parity_check(con, base, parquet, config$key,
                                               dialect = dialect))
  message(parity_summary(res))
  full <- if (res$verdict == "pass") {
    run_step("full parity check", parity_full(con, base, parquet, config$key,
                                              dialect = dialect))
  } else {
    NULL
  }
  if (!is.null(full)) message(full_summary(full))
  if (res$verdict != "pass" || any(full$verdict != "match")) {
    stop("Parity failed; the view was not created.", call. = FALSE)
  }

  meta_path <- sub("\\.parquet$", ".meta.json", parquet)
  meta <- jsonlite::read_json(meta_path, simplifyVector = TRUE)
  # dbWriteTable(append = TRUE) creates the parity table on the first lift.
  run_step("record parity", DBI::dbWriteTable(con, tabs$parity, data.frame(
    base_table = base, parquet_sha256 = as.character(meta$parquet_sha256),
    verdict = "pass", checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3")),
    append = TRUE))
  run_step("write metadata", DBI::dbWriteTable(con, tabs$meta, as.data.frame(meta$columns),
                                               overwrite = TRUE))
  .publish_views(config, con, base, dialect)
  message("view ", config$name, " -> ", base)
  invisible(list(dry_run = FALSE, base_table = base, ddl_path = NA_character_,
                 verdict = "pass"))
}

#' The base table's name, from the master's name and the snapshot's stem
#'
#' @param config A `master_config`.
#' @param parquet Path to the snapshot.
#'
#' @return A lower-case identifier.
#'
#' @keywords internal
#' @noRd
.base_table_name <- function(config, parquet) {
  stem <- tolower(gsub("[^A-Za-z0-9]+", "_", sub("\\.parquet$", "", basename(parquet))))
  paste0(config$name, "_base_", stem)
}

#' The base table of the latest passing parity record
#'
#' @param con A DBI connection.
#' @param config A `master_config`.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return The base table's name. Stops when no parity has passed.
#'
#' @keywords internal
#' @noRd
.current_base <- function(con, config, dialect) {
  tab <- .master_tables(config)$parity
  if (!DBI::dbExistsTable(con, tab)) {
    stop("Master ", config$name, " has no passing parity record; run lift_master() first.",
         call. = FALSE)
  }
  q <- quoter(dialect)
  rec <- DBI::dbGetQuery(con, sprintf(
    "SELECT base_table, checked_at FROM %s WHERE verdict = 'pass'", q(tab)))
  if (!nrow(rec)) {
    stop("Master ", config$name, " has no passing parity record; run lift_master() first.",
         call. = FALSE)
  }
  rec$base_table[order(rec$checked_at, decreasing = TRUE)][[1]]
}

#' Create or regenerate the master's view over a base table
#'
#' @param config A `master_config`.
#' @param con A DBI connection.
#' @param base_table The base table.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
.publish_views <- function(config, con, base_table, dialect) {
  q <- quoter(dialect)
  tabs <- .master_tables(config)
  if (!DBI::dbExistsTable(con, tabs$corrections)) {
    run_step("create view", DBI::dbExecute(con, sprintf(
      "%s %s AS SELECT * FROM %s;", view_header(dialect), q(config$name), q(base_table))))
    return(invisible(NULL))
  }
  types <- table_types(con, base_table)
  corrected <- corrected_variables(con, tabs$corrections, config$name, dialect)
  run_step("create corrections view", DBI::dbExecute(con, corrections_view_sql(
    config$name, base_table, tabs$corrections, tabs$decisions, config$name, config$key,
    names(types), corrected, types, dialect)))
  run_step("create stale view", DBI::dbExecute(con, stale_view_sql(
    tabs$stale, base_table, tabs$corrections, tabs$decisions, config$name, config$key,
    names(types), corrected, types, dialect)))
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "master-lift")'`
Expected: PASS. If `corrections_view_sql()`'s signature differs from the call above, match the
call to the Task 1 signature, not the reverse, and report it.

- [ ] **Step 5: Commit**

```bash
git add R/master_lift.R tests/testthat/test-master-lift.R man/ NAMESPACE
git commit -m "feat: lift a master into the warehouse behind key and parity gates"
```

---

### Task 5: The corrections API

**Files:**
- Create: `R/master_corrections.R`
- Test: `tests/testthat/test-master-corrections.R`
- Read (scratch, from Task 1): `.superpowers/sdd/legacy-propose.R`,
  `.superpowers/sdd/legacy-test-propose.R`

**Interfaces:**
- Consumes: `.master_tables()` (Task 2); `.current_base()`, `.publish_views()` (Task 4);
  `quoter()`, `sql_types()`, `table_types()`, `run_step()`, `value_text()`, `parse_value()`,
  `corrections_ddl(corrections_table, decisions_table, key_types, alt_key_types, dialect)`,
  `parse_legacy_facts(lines, key_var)`, `legacy_rows(facts, base_keys, key, master, meta,
  source_file, asserted_on)`, `record_legacy_facts(con, rows, corrections_table,
  decisions_table, dialect)` (Task 1).
- Produces:
  - `backfill_corrections(config, con, dry_run = TRUE, dialect = "mssql")` returning
    invisibly `list(dry_run, facts, resolved, unresolved, appended, stale)` (counts).
  - `propose_correction(config, con, key_values, variable, expected_prior, new_value,
    evidence_type, evidence_ref, asserted_by, alt_key = NULL, dry_run = FALSE,
    dialect = "mssql")` returning invisibly `list(verdict, correction_id, new_variable, row)`.
  - `decide_correction(config, con, correction_id, decision, decided_by,
    reason = NA_character_, dry_run = FALSE, dialect = "mssql")` returning invisibly
    `list(verdict, decision_id, row)`.
  - `verdict` is `"appended"`/`"recorded"`, or `"validated"` on a dry run.

- [ ] **Step 1: Write the failing tests** `tests/testthat/test-master-corrections.R`. Carry
  every check from `.superpowers/sdd/legacy-test-propose.R`, converted to testthat as in
  Task 1 and to the new signatures (config and connection instead of table names; `meta` and
  `widths` now come from the warehouse). Set the fixture up by lifting, so the parity record
  and meta table exist:

```r
# Tests for backfill_corrections(), propose_correction() and decide_correction().
# Every id and value is invented. No PHI.

corr_fixture <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  d <- data.frame(ccfid = c("K1", "K2", "K3"), dt_surg = as.Date("2020-01-01") + 0:2,
                  emrn = c("E1", NA, "E3"), age = c(65.5, NA, 70),
                  surgeon = c("S1", "S2", "S3"), stringsAsFactors = FALSE)
  pq <- file.path(dir, "built_t.parquet")
  arrow::write_parquet(d, pq)
  jsonlite::write_json(list(parquet_sha256 = "invented", columns = list(
    list(variable = "ccfid", r_class = "character"),
    list(variable = "dt_surg", r_class = "Date"),
    list(variable = "emrn", r_class = "character"),
    list(variable = "age", r_class = "numeric"),
    list(variable = "surgeon", r_class = "character"))),
    file.path(dir, "built_t.meta.json"), auto_unbox = TRUE)
  writeLines(c("data m; set base;",
               "if ccfid = 'K1' then age = 66;",
               "if ccfid = 'K2' then ccfid = 'K9';",
               "run;"), file.path(dir, "bd.sas"))
  cfg <- structure(list(name = "master_c", key = c("ccfid", "dt_surg"),
                        alt_keys = list(epic = "emrn"), parent = NULL,
                        parent_release = NULL, snapshots = dir, current = "built_t.sas7bdat",
                        history = NULL, build_program = file.path(dir, "bd.sas"),
                        file = file.path(dir, "master.yml")), class = "master_config")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
  suppressMessages(lift_master(cfg, con, pq, dry_run = FALSE, dialect = "duckdb"))
  list(cfg = cfg, con = con)
}

skip_corr <- function() {
  for (p in c("arrow", "duckdb", "jsonlite", "dplyr", "withr", "tidyselect", "digest")) {
    skip_if_not_installed(p)
  }
}

test_that("the backfill dry run counts and writes nothing", {
  skip_corr()
  f <- corr_fixture()
  r <- suppressMessages(backfill_corrections(f$cfg, f$con, dialect = "duckdb"))
  expect_true(r$dry_run)
  expect_equal(r$resolved, 1L)
  expect_false(DBI::dbExistsTable(f$con, "master_c_corrections"))
})

test_that("an executed backfill records baked facts, surfaces the key remap, and
          regenerates the view", {
  skip_corr()
  f <- corr_fixture()
  r <- suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE,
                                             dialect = "duckdb"))
  expect_equal(r$appended, 1L)
  expect_equal(r$unresolved, 1L)
  dec <- DBI::dbGetQuery(f$con, "SELECT decision FROM master_c_correction_decisions")
  expect_equal(dec$decision, "bake")
  v <- DBI::dbGetQuery(f$con, "SELECT age FROM master_c WHERE ccfid = 'K1'")
  expect_equal(v$age, 65.5)
  expect_true(DBI::dbExistsTable(f$con, "master_c_corrections_stale"))
})

test_that("a proposal found by alternate key is stored against the primary key", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  r <- suppressMessages(propose_correction(
    f$cfg, f$con, key_values = list(emrn = "E3"), alt_key = "epic", variable = "age",
    expected_prior = 70, new_value = 71, evidence_type = "chart_review",
    evidence_ref = "invented", asserted_by = "tester", dialect = "duckdb"))
  row <- DBI::dbGetQuery(f$con, sprintf(
    "SELECT ccfid, emrn FROM master_c_corrections WHERE correction_id = '%s'",
    r$correction_id))
  expect_equal(row$ccfid, "K3")
  expect_equal(row$emrn, "E3")
})

test_that("an alternate key with a null part or no match stops without a value", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  msg <- tryCatch(propose_correction(
    f$cfg, f$con, key_values = list(emrn = "E404"), alt_key = "epic", variable = "age",
    expected_prior = 70, new_value = 71, evidence_type = "chart_review",
    evidence_ref = "invented", asserted_by = "tester", dialect = "duckdb"),
    error = conditionMessage)
  expect_match(msg, "matched 0 rows")
  expect_false(grepl("E404", msg))
  expect_error(propose_correction(
    f$cfg, f$con, key_values = list(emrn = NA), alt_key = "epic", variable = "age",
    expected_prior = 70, new_value = 71, evidence_type = "chart_review",
    evidence_ref = "invented", asserted_by = "tester", dialect = "duckdb"), "null")
})

test_that("writer dry runs return the row and leave both tables unchanged", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  n0 <- DBI::dbGetQuery(f$con, "SELECT COUNT(*) AS n FROM master_c_corrections")$n
  r <- propose_correction(
    f$cfg, f$con, key_values = list(ccfid = "K3", dt_surg = as.Date("2020-01-03")),
    variable = "age", expected_prior = 70, new_value = 71, evidence_type = "chart_review",
    evidence_ref = "invented", asserted_by = "tester", dry_run = TRUE, dialect = "duckdb")
  expect_equal(r$verdict, "validated")
  expect_equal(nrow(r$row), 1L)
  expect_equal(DBI::dbGetQuery(f$con, "SELECT COUNT(*) AS n FROM master_c_corrections")$n,
               n0)
  d <- decide_correction(f$cfg, f$con, DBI::dbGetQuery(
    f$con, "SELECT correction_id FROM master_c_corrections")$correction_id[[1]],
    "accept", "tester", dry_run = TRUE, dialect = "duckdb")
  expect_equal(d$verdict, "validated")
})

# Then: every remaining check from .superpowers/sdd/legacy-test-propose.R, converted to the
# new signatures (unknown variable, key column refused, unknown evidence type, key matching
# 0 rows with no value in the message, uncastable value, factor refused, over-width value,
# id collision via a mocked Sys.time, first-correction new_variable flag, missing-prior
# flag, unknown decision, decision on an unknown correction).
```

- [ ] **Step 2: Run them and watch them fail**

Run: `Rscript -e 'devtools::test(filter = "master-corrections")'`
Expected: FAIL, `could not find function "backfill_corrections"`.

- [ ] **Step 3: Implement** `R/master_corrections.R`. Start from
  `.superpowers/sdd/legacy-propose.R` (keep `EVIDENCE_TYPES`, `DECISIONS`, `.checked_text()`,
  the id-collision check, the factor refusal, the width check after the cast check, and every
  message's wording) and change it to:

```r
#' Backfill a master's corrections from its SAS build, and regenerate its view
#'
#' Creates the master's corrections and decisions tables if absent, reads the
#' inline patient-level fixes from the SAS build program, records each one that
#' resolves to exactly one record as a correction with an unknown prior and a
#' `bake` decision (present in the snapshot, not applied), and regenerates the
#' view and its stale view. Fixes that change a key column, match no record,
#' match several, or cannot be read are reported by reason and line number and
#' never recorded.
#'
#' Requires a passing parity record from [lift_master()]. A dry run, the
#' default, parses and resolves and writes nothing.
#'
#' @param config A `master_config` from [read_master_config()].
#' @param con A DBI connection.
#' @param dry_run If `TRUE`, the default, report what would be recorded.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return Invisibly, a list of counts: `dry_run`, `facts`, `resolved`,
#'   `unresolved`, `appended` and `stale`.
#'
#' @seealso [propose_correction()], [decide_correction()]
#'
#' @export
backfill_corrections <- function(config, con, dry_run = TRUE, dialect = "mssql") {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required.", call. = FALSE)
  }
  tabs <- .master_tables(config)
  base <- .current_base(con, config, dialect)
  q <- quoter(dialect)
  meta <- DBI::dbReadTable(con, tabs$meta)
  types <- table_types(con, base)

  parsed <- parse_legacy_facts(readLines(config$build_program, warn = FALSE),
                               key_var = config$key[[1]])
  base_keys <- DBI::dbGetQuery(con, sprintf("SELECT %s FROM %s",
                                            paste(q(config$key), collapse = ", "), q(base)))
  rows <- legacy_rows(parsed$facts, base_keys, config$key, config$name, meta,
                      basename(config$build_program))
  n_res <- NROW(rows$corrections)
  message("legacy: ", nrow(parsed$facts), " facts parsed; ", n_res, " resolved; ",
          nrow(rows$unresolved), " unresolved")
  if (nrow(rows$unresolved)) {
    tab <- table(rows$unresolved$reason)
    message("  unresolved by reason: ", paste(names(tab), tab, sep = " ", collapse = ", "))
    message("  at lines: ", paste(sort(unique(rows$unresolved$line)), collapse = ", "))
  }
  if (length(parsed$unparsed)) {
    message("  unparsed statements at lines: ", paste(parsed$unparsed, collapse = ", "))
  }
  out <- list(dry_run = dry_run, facts = nrow(parsed$facts), resolved = n_res,
              unresolved = nrow(rows$unresolved), appended = 0L, stale = NA_integer_)
  if (dry_run) {
    message("dry run: nothing written")
    return(invisible(out))
  }

  if (!DBI::dbExistsTable(con, tabs$corrections)) {
    alt_cols <- intersect(unique(unlist(config$alt_keys, use.names = FALSE)), names(types))
    ddl <- corrections_ddl(tabs$corrections, tabs$decisions, key_types = types[config$key],
                           alt_key_types = if (length(alt_cols)) types[alt_cols] else NULL,
                           dialect = dialect)
    run_step("create corrections table", DBI::dbExecute(con, ddl[["corrections"]]))
    run_step("create decisions table", DBI::dbExecute(con, ddl[["decisions"]]))
  }
  r <- run_step("record legacy facts",
                record_legacy_facts(con, rows, tabs$corrections, tabs$decisions, dialect))
  .publish_views(config, con, base, dialect)
  out$appended <- as.integer(r$appended)
  out$stale <- as.integer(DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s",
                                                       q(tabs$stale)))$n)
  message("recorded ", out$appended, "; ", out$stale, " stale corrections")
  invisible(out)
}
```

  For `propose_correction()`: signature as in the Interfaces block. Derive
  `base <- .current_base(con, config, dialect)`, `meta <- DBI::dbReadTable(con, .master_tables(config)$meta)`,
  and `widths` from `table_types(con, base)`: for each `nvarchar(n)`/`varchar(n)` type, `n`
  as an integer, named by column. When `alt_key` is given:

```r
  if (!is.null(alt_key)) {
    cols <- config$alt_keys[[alt_key]]
    if (is.null(cols)) stop("Unknown alternate key '", alt_key, "'.", call. = FALSE)
    if (!setequal(names(key_values), cols)) {
      stop("'key_values' must name exactly the columns of alternate key '", alt_key, "'.",
           call. = FALSE)
    }
    if (any(vapply(key_values, function(v) length(v) != 1L || is.na(v), logical(1)))) {
      stop("Alternate key '", alt_key, "' has a null part, which never matches.",
           call. = FALSE)
    }
    where <- paste(sprintf("%s = ?", q(cols)), collapse = " AND ")
    hits <- DBI::dbGetQuery(con, sprintf("SELECT %s FROM %s WHERE %s",
                                         paste(q(config$key), collapse = ", "), q(base), where),
                            params = unname(key_values[cols]))
    if (nrow(hits) != 1L) {
      stop("Alternate key '", alt_key, "' matched ", nrow(hits), " rows in ", base,
           "; expected exactly 1.", call. = FALSE)
    }
    alt_values <- key_values
    key_values <- as.list(hits[1, config$key, drop = FALSE])
  } else {
    alt_values <- list()
  }
```

  then validate and build the row as the legacy code did, add the alternate-key columns from
  `alt_values` to the row, and when `dry_run` return
  `invisible(list(verdict = "validated", correction_id = id, new_variable = new_variable,
  row = row))` before `dbAppendTable()`. `decide_correction()` follows the same pattern with
  table names from `.master_tables(config)`. Give each exported function a roxygen block with
  `@param` for every argument, `@return`, `@seealso`, and `@export`; describe in `@details`
  that `dry_run = TRUE` validates without writing, that a single correction is written by
  default because it is a deliberate act, and that no message ever carries a key or value.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "master")'`
Expected: PASS for every `test-master-*` file.

- [ ] **Step 5: Add the gated SQL Server test** `tests/testthat/test-master-integration.R`.
  It reruns the lift and corrections path against a scratch schema on the real warehouse, with
  the same invented fixture, and skips unless both environment variables are set. It asserts
  verdicts only.

```r
# Gated: runs only against a scratch warehouse schema, with invented data. No PHI.
# Set HVTI_MASTER_TEST_DSN (an ODBC DSN whose login already defaults to a scratch schema)
# and HVTI_MASTER_TEST_SCHEMA (that schema's name). The test never changes the login: it
# skips unless the login's default schema is the scratch one.

test_that("lift and corrections behave on SQL Server as on duckdb", {
  dsn <- Sys.getenv("HVTI_MASTER_TEST_DSN")
  schema <- Sys.getenv("HVTI_MASTER_TEST_SCHEMA")
  skip_if(!nzchar(dsn) || !nzchar(schema), "no scratch warehouse configured")
  for (p in c("arrow", "odbc", "jsonlite", "dplyr", "withr", "tidyselect", "digest")) {
    skip_if_not_installed(p)
  }
  con <- DBI::dbConnect(odbc::odbc(), dsn = dsn)
  withr::defer(DBI::dbDisconnect(con))
  current <- DBI::dbGetQuery(con, "SELECT SCHEMA_NAME() AS s")$s
  skip_if(!identical(current, schema), "the DSN's default schema is not the scratch schema")
  dir <- withr::local_tempdir()
  d <- data.frame(ccfid = c("K1", "K2"), dt_surg = as.Date("2020-01-01") + 0:1,
                  age = c(65.5, 1 / 3), surgeon = c("s1", "S1 "), stringsAsFactors = FALSE)
  pq <- file.path(dir, "built_it.parquet")
  arrow::write_parquet(d, pq)
  jsonlite::write_json(list(parquet_sha256 = "invented", columns = list(
    list(variable = "ccfid", r_class = "character"),
    list(variable = "dt_surg", r_class = "Date"),
    list(variable = "age", r_class = "numeric"),
    list(variable = "surgeon", r_class = "character"))),
    file.path(dir, "built_it.meta.json"), auto_unbox = TRUE)
  writeLines("data m; run;", file.path(dir, "bd.sas"))
  cfg <- structure(list(name = paste0("master_it_", format(Sys.time(), "%H%M%S")),
                        key = c("ccfid", "dt_surg"), alt_keys = list(), parent = NULL,
                        parent_release = NULL, snapshots = dir, current = "built_it.sas7bdat",
                        history = NULL, build_program = file.path(dir, "bd.sas"),
                        file = file.path(dir, "master.yml")), class = "master_config")
  res <- suppressMessages(lift_master(cfg, con, pq, dry_run = FALSE))
  expect_equal(res$verdict, "pass")
  suppressMessages(backfill_corrections(cfg, con, dry_run = FALSE))
  r <- suppressMessages(propose_correction(
    cfg, con, key_values = list(ccfid = "K2", dt_surg = as.Date("2020-01-02")),
    variable = "age", expected_prior = 1 / 3, new_value = 2 / 3,
    evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester"))
  suppressMessages(decide_correction(cfg, con, r$correction_id, "accept", "tester"))
  suppressMessages(backfill_corrections(cfg, con, dry_run = FALSE))
  v <- DBI::dbGetQuery(con, paste0("SELECT age FROM [", cfg$name, "] WHERE ccfid = 'K2'"))
  expect_equal(v$age, 2 / 3)
})
```

  Run it once locally only if a scratch schema exists; otherwise confirm it skips:
  `Rscript -e 'devtools::test(filter = "master-integration")'` prints a skip.

- [ ] **Step 6: Commit**

```bash
git add R/master_corrections.R tests/testthat/test-master-corrections.R \
  tests/testthat/test-master-integration.R man/ NAMESPACE
git commit -m "feat: backfill, propose and decide corrections against a master's config"
```

---

### Task 6: Vignette, pkgdown and NEWS

**Files:**
- Create: `vignettes/master-datasets.qmd`
- Modify: `_pkgdown.yml`, `NEWS.md`

- [ ] **Step 1: Write the vignette.** Model its front matter on an existing vignette in
  `vignettes/` (read one first; the package uses the Quarto builder). Title: "Master
  datasets". Sections, in the house voice, synthetic data only, code chunks that run on duckdb
  and skip cleanly when duckdb, arrow or tidyselect is absent:
  1. What a master is, and why a view (one paragraph; cite the design spec by path).
  2. `master.yml`, field by field, using `inst/extdata/master-example.yml`.
  3. Phase 0, `snapshot_master()`, and lineage from the log.
  4. Phases 1 and 2, `lift_master()` and `backfill_corrections()`, dry run first.
  5. The everyday workflow: `propose_correction()`, `decide_correction()`, the stale view.
  6. What is not done yet: the port, identity corrections, and the lifted-state limit that a
     parent's later corrections do not reach a child until its port.

- [ ] **Step 2: Add the pkgdown section.** In `_pkgdown.yml`, under `reference:`, add:

```yaml
  - title: Master datasets
    desc: Snapshot, lift and correct the master datasets studies read.
    contents:
      - read_master_config
      - snapshot_master
      - lift_master
      - backfill_corrections
      - propose_correction
      - decide_correction
```

  and add `master-datasets` to the `articles:` section if the file lists articles.

- [ ] **Step 3: Add the NEWS entry** under `# hvtiRdatabuild (unreleased)` (add the heading at
  the top of `NEWS.md` if it is absent):

```markdown
* **Master datasets.** Six new functions snapshot, lift and correct the master
  datasets that study builds read. `read_master_config()` reads a `master.yml`
  declaring a master's key, alternate keys and parent. `snapshot_master()`
  freezes its SAS builds as parquet and records which parent release each was
  built from, read from the run's log first. `lift_master()` loads a snapshot
  into the warehouse behind key and full-parity gates and creates the master's
  view. `backfill_corrections()`, `propose_correction()` and
  `decide_correction()` keep an append-only record of corrections the view
  applies. The bulk functions dry-run by default. See
  `vignette("master-datasets")`. `duckdb` and `tidyselect` join `Suggests`.
```

- [ ] **Step 4: Build the site and vignette locally**

Run: `Rscript -e 'devtools::document(); pkgdown::check_pkgdown(); devtools::build_vignettes()'`
Expected: no errors; the vignette renders.

- [ ] **Step 5: Commit**

```bash
git add vignettes/master-datasets.qmd _pkgdown.yml NEWS.md
git commit -m "docs: the master datasets vignette, reference section and NEWS entry"
```

---

### Task 7: Final verification

- [ ] **Step 1: Full tests, lint**

Run: `Rscript -e 'devtools::test(); devtools::load_all(); print(lintr::lint_package())'`
Expected: 0 failures; no lints.

- [ ] **Step 2: Check with the manual, from a clean export**

```bash
rm -rf /tmp/hvtirdb-check && mkdir /tmp/hvtirdb-check
git archive HEAD | tar -x -C /tmp/hvtirdb-check
cd /tmp/hvtirdb-check && R CMD build . && R CMD check --as-cran hvtiRdatabuild_*.tar.gz
```

Expected: `Status: OK` (0 errors, 0 warnings, 0 notes). A NOTE about new submission or
internet access to CRAN is environmental; report it verbatim and do not suppress others.

- [ ] **Step 3: PHI and path sweep**

Run: `git diff origin/main | grep -n -i -E "qhsstudies|/Volumes/|saslpass|/studies/" || echo clean`
Expected: `clean`, apart from lines inside this plan quoting the sweep itself.

- [ ] **Step 4: Push**

```bash
git push
```
