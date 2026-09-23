# Cardiac-surgery master view: implementation plan (phases 0 to 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take the cardiac-surgery master from a 36 GB SAS dataset to a SQL Server view with
an append-only corrections layer, verified at every step, as designed in
`dev/specs/2026-09-23-cardiac-master-view-design.md`.

**Architecture:** One package change (chunked `snapshot_oracle()` with a source checksum and
a metadata sidecar) and a set of standalone scripts under `dev/masters/cardiac/`: key
verdicts, DDL generation, a resumable loader, a parity check, the corrections contract (an R
reference resolver plus generated ANSI SQL), correction writers, a legacy-fact parser, and
three runbooks. The scripts become exports only when the mitral master reuses them (spec
§4.1). Script tests are standalone `Rscript` files in the style of
`dev/specs/artifacts/test-*.R`, run against duckdb.

**Tech Stack:** R, haven, arrow (`ParquetFileWriter`, `ParquetFileReader`, `open_dataset`),
DBI, odbc (SQL Server), duckdb (tests only), dplyr (dataset semi-join), jsonlite, digest,
withr, testthat 3e.

## Global Constraints

- **No PHI anywhere in the repository**, in a test message or in printed output. Fixtures
  are invented and say so. Scripts print counts, verdicts, column names and line numbers,
  never a key or a value. Check what every error message prints.
- **Identifiers are read, never transcribed.** The legacy facts are parsed from
  `bd.data.master.sas` at run time and written to the warehouse, never to a file here.
- Lines are **100 characters** (`.lintr`). Roxygen markdown is enabled.
- Test files are `test-*.R` with a hyphen; testthat edition 3.
- `dev/` is in `.Rbuildignore`: script changes earn no version bump and no `NEWS.md`
  entry. The `snapshot_oracle()` change ships, so it earns a `NEWS.md` entry under
  `# hvtiRdatabuild (unreleased)`, added at the top when absent. **Do not touch
  `Version:`**; the bump is a separate commit, per `AGENTS.md`.
- **Never push to `main`.** Work on `spec/cardiac-master-view` (PR #63).
- `arrow` and `jsonlite` stay in `Suggests`, guarded with `requireNamespace()`.
- Generated SQL for the corrections view is restricted to `CASE`, `LEFT JOIN`, `JOIN`,
  `UNION ALL`, CTEs and `ROW_NUMBER()`. Only the view header and quoting differ by dialect.
- Definition of done: `devtools::test()` passes; `devtools::check()` is 0/0/0;
  `devtools::document()` run and `man/` committed; every `dev/masters/cardiac/test-*.R`
  prints `all checks passed`.

## File map

| File | Responsibility |
|---|---|
| `R/read_sas_dataset.R` | gains `skip`, `n_max` |
| `R/snapshot_oracle.R` | `chunk_rows`, source checksum, sidecar |
| `tests/testthat/test-snapshot_oracle.R` | the new behaviour |
| `dev/masters/cardiac/README.md` | order of operations, PHI rules, how to test |
| `dev/masters/cardiac/test-harness.R` | `check()`, `check_error()`, `finish()`, `skip_unless()` |
| `dev/masters/cardiac/key-verdict.R` | is a candidate key unique |
| `dev/masters/cardiac/ddl.R` | arrow schema to SQL Server DDL, with preflight |
| `dev/masters/cardiac/load.R` | resumable row-group load |
| `dev/masters/cardiac/sql-common.R` | quoting, string literals, dialect types, `table_types()` |
| `dev/masters/cardiac/parity.R` | counts, aggregates, sampled value compare |
| `dev/masters/cardiac/value-text.R` | text form of a value, and back |
| `dev/masters/cardiac/corrections.R` | contract DDL, R reference resolver, view and stale SQL |
| `dev/masters/cardiac/propose.R` | `propose_correction()`, `decide_correction()` |
| `dev/masters/cardiac/legacy.R` | parse inline facts, turn them into `bake` rows, record |
| `dev/masters/cardiac/run-phase0.R`, `batch-snapshots.R`, `run-phase1.R`, `run-phase2.R` | runbooks |

---

### Task 1: Amend the spec with what the plan found

The plan found three places where the spec is wrong or underspecified. Fix them before
anything is built against it.

**Files:**
- Modify: `dev/specs/2026-09-23-cardiac-master-view-design.md`

- [ ] **Step 1: Correct the chunked-checksum test (§8).** Replace the bullet beginning
  "**Chunked `snapshot_oracle()`**" with:

```markdown
- **Chunked `snapshot_oracle()`** on the synthetic `oracle_small.sas7bdat` with a tiny
  `chunk_rows`: the output **reads back** identical to the unchunked snapshot, labels
  included. ⚠️ Its bytes differ, because the row groups differ, so its SHA-256 differs by
  design; an earlier draft of this spec said the checksums would match, and they cannot.
  A mismatched chunk schema fails and removes the partial file; the sidecar is right.
```

- [ ] **Step 2: Say where the duckdb tests run (§8).** In the correction-resolution bullet,
  replace "so CI runs it on duckdb and asserts it agrees with the reference" with:

```markdown
so the standalone tests under `dev/masters/cardiac/` run it on duckdb and assert it agrees
with the reference. They run by hand, as the scan tests in `dev/specs/artifacts/` do, not in
CI; CI coverage arrives when the scripts are promoted to exports
```

- [ ] **Step 3: Make the prior tri-state and name the decisions (§5.1).** Replace the
  `expected_prior` row of the `corrections` table with these two rows:

```markdown
| `expected_prior` | the value the corrector saw, as text |
| `expected_prior_missing` | `1` the corrector saw a missing value, `0` a value, `NULL` **unknown**. Unknown is the legacy case (§5.4), and a correction with an unknown prior never applies |
```

  and replace the `correction_decisions` sentence with:

```markdown
**`correction_decisions`**: `accept`, `reject`, `supersede` or `bake`, with who, when and
why. `bake` means recorded but already present in the base, so not applied (§5.4).
```

- [ ] **Step 4: Name the stale reasons (§5.3).** After the stale bullet, add:

```markdown
- The stale view gives one reason per correction, checked in this order: `no_variable` (not
  a correctable column of the master), `no_record` (the key matches no row),
  `prior_unknown`, `prior_mismatch`.
```

- [ ] **Step 5: The historical builds have no log to validate against (§4.2).** After the
  paragraph beginning "**Order:**", add:

```markdown
⚠️ Only the current build's log is retained, so the eleven historical snapshots record their
shape without validating it against SAS. The batch also hashes the undated
`built.sas7bdat` and reports whether it matches a dated build's source checksum.
```

- [ ] **Step 6: Writers report when the view needs regenerating (§5.5).** Append to §5.5:

```markdown
It reports when a variable receives its first correction, because the generated view only
joins variables that already have one and must be regenerated. `decide_correction()` records
a decision the same way.
```

- [ ] **Step 7: Commit**

```bash
git add dev/specs/2026-09-23-cardiac-master-view-design.md
git commit -m "spec: correct the chunked checksum claim, and name the decisions and stale reasons"
```

---

### Task 2: Chunked `snapshot_oracle()`, source checksum and sidecar

**Files:**
- Modify: `R/read_sas_dataset.R`
- Modify: `R/snapshot_oracle.R`
- Modify: `DESCRIPTION` (add `jsonlite` to `Suggests`)
- Modify: `NEWS.md`
- Test: `tests/testthat/test-snapshot_oracle.R`

**Interfaces:**
- Produces: `snapshot_oracle(sas_path, out_path, expect = NULL, manifest = NULL,
  chunk_rows = NULL)` returning invisibly `list(path, n_rows, n_cols, variables, sha256,
  source_sha256, meta_path)`. Sidecar at `<out_path minus .parquet>.meta.json`, JSON with
  `source`, `source_sha256`, `parquet`, `parquet_sha256`, `n_rows`, `n_cols`, and `columns`:
  an array of `{variable, label, sas_format, sas_type, r_class}`.
- Produces (internal): `.read_sas_dataset(path, skip = 0L, n_max = Inf)`,
  `.check_chunk_schema(expected, got, at_row)`.

- [ ] **Step 1: Write the failing tests.** Append to `tests/testthat/test-snapshot_oracle.R`:

```r
test_that("chunked snapshot reads back identical to the unchunked one", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")

  whole <- withr::local_tempfile(fileext = ".parquet")
  parts <- withr::local_tempfile(fileext = ".parquet")
  snapshot_oracle(.fixture_path(), whole)
  res <- snapshot_oracle(.fixture_path(), parts, chunk_rows = 3)

  expect_equal(res$n_rows, 4L)
  expect_equal(arrow::ParquetFileReader$create(parts)$num_row_groups, 2L)
  a <- as.data.frame(arrow::read_parquet(whole))
  b <- as.data.frame(arrow::read_parquet(parts))
  expect_equal(b, a)
  expect_equal(attr(b$age, "label"), "Age at surgery")
})

test_that("a chunk size that divides the rows exactly still counts every row", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")

  out <- withr::local_tempfile(fileext = ".parquet")
  res <- snapshot_oracle(.fixture_path(), out, chunk_rows = 2)
  expect_equal(res$n_rows, 4L)
  expect_equal(arrow::ParquetFileReader$create(out)$num_row_groups, 2L)
})

test_that("the sidecar records both checksums and every column", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")

  out <- withr::local_tempfile(fileext = ".parquet")
  res <- snapshot_oracle(.fixture_path(), out)

  expect_equal(res$source_sha256,
               digest::digest(.fixture_path(), algo = "sha256", file = TRUE))
  expect_true(file.exists(res$meta_path))
  meta <- jsonlite::read_json(res$meta_path, simplifyVector = TRUE)
  expect_equal(meta$source_sha256, res$source_sha256)
  expect_equal(meta$parquet_sha256, res$sha256)
  expect_equal(meta$n_rows, 4L)
  expect_setequal(meta$columns$variable,
                  c("ccfidu", "age", "bmi", "dt_surg", "surgeon"))
  expect_equal(meta$columns$label[meta$columns$variable == "age"], "Age at surgery")
  expect_equal(meta$columns$sas_type[meta$columns$variable == "surgeon"], "character")
})

test_that("snapshot_oracle refuses to overwrite an existing sidecar", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")

  out <- withr::local_tempfile(fileext = ".parquet")
  writeLines("{}", sub("\\.parquet$", ".meta.json", out))
  expect_error(snapshot_oracle(.fixture_path(), out), "sidecar already exists")
})

test_that("chunk_rows must be a single positive number", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")

  out <- withr::local_tempfile(fileext = ".parquet")
  expect_error(snapshot_oracle(.fixture_path(), out, chunk_rows = 0), "chunk_rows")
  expect_error(snapshot_oracle(.fixture_path(), out, chunk_rows = c(1, 2)), "chunk_rows")
})

test_that("a failed validation removes the chunked output", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")

  out <- withr::local_tempfile(fileext = ".parquet")
  expect_error(snapshot_oracle(.fixture_path(), out, expect = list(n_rows = 5),
                               chunk_rows = 3),
               "n_rows is 4")
  expect_false(file.exists(out))
})

test_that("a chunk whose schema differs from the first is an error", {
  skip_if_not_installed("arrow")

  expect_error(
    .check_chunk_schema(arrow::schema(a = arrow::float64()),
                        arrow::schema(a = arrow::utf8()), 10),
    "row 11"
  )
})
```

- [ ] **Step 2: Run them and watch them fail**

Run: `Rscript -e 'devtools::test(filter = "snapshot_oracle")'`
Expected: FAIL: unused argument `chunk_rows`, and `res$source_sha256` is `NULL`.

- [ ] **Step 3: Give `.read_sas_dataset()` a row window.** In `R/read_sas_dataset.R`,
  replace the function and add the two parameters to its roxygen block:

```r
#' @param skip Rows to skip before reading. Passed to [haven::read_sas()].
#' @param n_max Maximum rows to read. Passed to [haven::read_sas()].
.read_sas_dataset <- function(path, skip = 0L, n_max = Inf) {
  if (!file.exists(path)) {
    stop("SAS dataset does not exist: ", path, call. = FALSE)
  }
  ext <- tolower(tools::file_ext(path))
  if (!identical(ext, "sas7bdat")) {
    stop("Unsupported SAS dataset extension '.", ext,
         "'. Expected '.sas7bdat'.", call. = FALSE)
  }
  as.data.frame(haven::read_sas(path, skip = skip, n_max = n_max))
}
```

- [ ] **Step 4: Implement the package change.** In `R/snapshot_oracle.R`:

  Add to the roxygen block, after `@param manifest`:

```r
#' @param chunk_rows Optional single positive number. When supplied, the SAS
#'   dataset is read and written this many rows at a time, as parquet row
#'   groups in one file, so a dataset too large to hold in memory can be
#'   snapshotted. A chunk whose schema differs from the first chunk's is an
#'   error, and the partial file is removed. The chunked file reads back
#'   identical to an unchunked one, but its bytes and checksum differ, because
#'   its row groups differ.
```

  Replace the `@return` block with:

```r
#' @return Invisibly, a list with elements `path`, `n_rows`, `n_cols`,
#'   `variables`, `sha256` (of the parquet file), `source_sha256` (of the SAS
#'   dataset) and `meta_path`. The metadata sidecar at `meta_path` records
#'   both checksums, the shape, and each column's label, SAS format, SAS type
#'   and R class, so the metadata survives into systems that cannot read R's
#'   attributes.
```

  Add to the `@details` prose (after the paragraph about `expect`):

```r
#' Writing the sidecar needs \pkg{jsonlite}.
```

  Replace the function body and add the helpers:

```r
snapshot_oracle <- function(sas_path, out_path, expect = NULL,
                            manifest = NULL, chunk_rows = NULL) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("Package 'arrow' is required to write oracle snapshots. ",
         "Install it with install.packages('arrow').", call. = FALSE)
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package 'jsonlite' is required to write the snapshot's metadata ",
         "sidecar. Install it with install.packages('jsonlite').", call. = FALSE)
  }
  if (!is.null(chunk_rows) &&
      (!is.numeric(chunk_rows) || length(chunk_rows) != 1L ||
       is.na(chunk_rows) || chunk_rows < 1)) {
    stop("'chunk_rows' must be NULL or a single positive number.", call. = FALSE)
  }
  if (file.exists(out_path)) {
    stop("Oracle snapshot already exists: ", out_path,
         ". Refusing to overwrite; delete it explicitly if that is intended.",
         call. = FALSE)
  }
  meta_path <- .snapshot_meta_path(out_path)
  if (file.exists(meta_path)) {
    stop("Snapshot metadata sidecar already exists: ", meta_path,
         ". Refusing to overwrite; delete it explicitly if that is intended.",
         call. = FALSE)
  }

  if (is.null(chunk_rows)) {
    d <- .read_sas_dataset(sas_path)
    info <- list(path = out_path, n_rows = nrow(d), n_cols = ncol(d),
                 variables = names(d))
    .validate_snapshot(info, expect)
    arrow::write_parquet(d, out_path)
  } else {
    written <- .write_chunked(sas_path, out_path, as.integer(chunk_rows))
    d <- written$first
    info <- list(path = out_path, n_rows = written$n_rows, n_cols = ncol(d),
                 variables = names(d))
    tryCatch(.validate_snapshot(info, expect), error = function(e) {
      unlink(out_path)
      stop(e)
    })
  }

  info$sha256 <- digest::digest(out_path, algo = "sha256", file = TRUE)
  info$source_sha256 <- digest::digest(sas_path, algo = "sha256", file = TRUE)
  info$meta_path <- meta_path
  jsonlite::write_json(.snapshot_meta(d, info, sas_path), meta_path,
                       auto_unbox = TRUE, null = "null", pretty = TRUE)

  if (!is.null(manifest)) {
    # n_rows is passed explicitly: hvtiRutilities:::.auto_count_rows() refuses
    # to guess row counts for a '.parquet', and that refusal is correct.
    hvtiRutilities::update_manifest(
      file          = out_path,
      manifest_path = manifest,
      n_rows        = info$n_rows,
      source        = paste0("Oracle snapshot of ", basename(sas_path),
                             " (source sha256 ", info$source_sha256, ")")
    )
  }

  invisible(info)
}

#' Write a SAS dataset to one parquet file, a chunk of rows at a time
#'
#' @param sas_path Path to the SAS dataset.
#' @param out_path Path of the parquet file to create.
#' @param chunk_rows Integer. Rows per chunk, and per row group.
#'
#' @return A list with `n_rows`, the rows written, and `first`, the first
#'   chunk as a data frame, which carries the labels and formats.
#'
#' @keywords internal
#' @noRd
.write_chunked <- function(sas_path, out_path, chunk_rows) {
  first <- .read_sas_dataset(sas_path, skip = 0L, n_max = chunk_rows)
  first_tbl <- arrow::arrow_table(first)
  schema <- first_tbl$schema

  sink <- arrow::FileOutputStream$create(out_path)
  writer <- arrow::ParquetFileWriter$create(
    schema, sink,
    properties = arrow::ParquetWriterProperties$create(names(schema))
  )
  ok <- FALSE
  on.exit({
    writer$Close()
    sink$close()
    if (!ok) unlink(out_path)
  }, add = TRUE)

  writer$WriteTable(first_tbl, chunk_size = chunk_rows)
  n_rows <- nrow(first)
  last_n <- nrow(first)
  while (last_n == chunk_rows) {
    chunk <- .read_sas_dataset(sas_path, skip = n_rows, n_max = chunk_rows)
    last_n <- nrow(chunk)
    if (last_n == 0L) break
    tbl <- arrow::arrow_table(chunk)
    .check_chunk_schema(schema, tbl$schema, n_rows)
    writer$WriteTable(tbl, chunk_size = chunk_rows)
    n_rows <- n_rows + last_n
  }
  ok <- TRUE
  list(n_rows = n_rows, first = first)
}

#' Stop when a chunk's schema differs from the first chunk's
#'
#' @param expected,got Arrow schemas.
#' @param at_row Integer. Rows written before this chunk.
#'
#' @return `NULL`, invisibly. Called for the error it raises.
#'
#' @keywords internal
#' @noRd
.check_chunk_schema <- function(expected, got, at_row) {
  if (!got$Equals(expected, check_metadata = FALSE)) {
    stop("The chunk starting at row ", at_row + 1, " has a different schema ",
         "from the first chunk. A SAS column's type cannot change within a ",
         "file, so this is a reader defect; the partial parquet is removed.",
         call. = FALSE)
  }
  invisible(NULL)
}

#' The sidecar path for a parquet snapshot
#'
#' @param out_path Path of the parquet file.
#'
#' @return The path with `.parquet` replaced by `.meta.json`.
#'
#' @keywords internal
#' @noRd
.snapshot_meta_path <- function(out_path) {
  paste0(sub("\\.parquet$", "", out_path, ignore.case = TRUE), ".meta.json")
}

#' The sidecar contents for a snapshot
#'
#' @param d Data frame holding at least the first rows, with attributes.
#' @param info The snapshot record, with both checksums.
#' @param sas_path Path to the SAS dataset.
#'
#' @return A list ready for [jsonlite::write_json()].
#'
#' @keywords internal
#' @noRd
.snapshot_meta <- function(d, info, sas_path) {
  one_attr <- function(x, which) {
    a <- attr(x, which, exact = TRUE)
    if (is.null(a)) NULL else as.character(a)[[1]]
  }
  columns <- lapply(names(d), function(v) {
    x <- d[[v]]
    list(variable   = v,
         label      = one_attr(x, "label"),
         sas_format = one_attr(x, "format.sas"),
         sas_type   = if (is.character(x)) "character" else "numeric",
         r_class    = class(x)[[1]])
  })
  list(source = basename(sas_path), source_sha256 = info$source_sha256,
       parquet = basename(info$path), parquet_sha256 = info$sha256,
       n_rows = info$n_rows, n_cols = info$n_cols, columns = columns)
}
```

- [ ] **Step 5: Add `jsonlite` to `Suggests`** in `DESCRIPTION`, alphabetically between
  `hvtiPlotR` and `keyring`:

```
    hvtiPlotR,
    jsonlite,
    keyring,
```

- [ ] **Step 6: Run the tests and watch them pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "snapshot_oracle|read_sas")'`
Expected: PASS, 0 failures. The existing idempotent-checksum test still passes, because it
compares two unchunked snapshots.

- [ ] **Step 7: Add the NEWS entry.** At the top of `NEWS.md`, above `# hvtiRdatabuild
  0.2.3`, add:

```markdown
# hvtiRdatabuild (unreleased)

* **`snapshot_oracle()` can snapshot a dataset too large for memory.** The new
  `chunk_rows` argument reads the SAS dataset a chunk at a time and writes the
  chunks as row groups of one parquet file. It also records a SHA-256 of the
  SAS source beside the parquet checksum, and writes a `.meta.json` sidecar
  holding each column's label, SAS format and type, so that metadata survives
  into systems that cannot read R attributes. `jsonlite` joins `Suggests`.

```

- [ ] **Step 8: Run the full suite and the check**

Run: `Rscript -e 'devtools::test(); devtools::check(args = "--no-manual", vignettes = FALSE)'`
Expected: tests PASS; check `0 errors ✔ | 0 warnings ✔ | 0 notes ✔`.

- [ ] **Step 9: Commit**

```bash
git add R/read_sas_dataset.R R/snapshot_oracle.R man/ DESCRIPTION NEWS.md \
  tests/testthat/test-snapshot_oracle.R
git commit -m "feat: snapshot a SAS dataset too large for memory, and record its source checksum"
```

---

### Task 3: Script scaffold and key verdicts

**Files:**
- Create: `dev/masters/cardiac/README.md`
- Create: `dev/masters/cardiac/test-harness.R`
- Create: `dev/masters/cardiac/key-verdict.R`
- Test: `dev/masters/cardiac/test-key-verdict.R`

**Interfaces:**
- Produces: `check(label, ok)`, `check_error(label, expr, pattern = NULL)` (returns the
  message invisibly), `finish()`, `skip_unless(pkgs)`. Each test file finds its directory
  with the `self`/`here` lines shown below and sources `test-harness.R`.
- Produces: `key_verdict(parquet, key, nonnull_only = FALSE)` returning
  `list(key, n_rows, n_null_key, n_duplicates, verdict)`, where `verdict` is `"unique"`,
  `"not unique"` or `"absent"`; and `format_key_verdict(v)` returning one line.

- [ ] **Step 1: Write the README**

```markdown
# The cardiac-surgery master: scripts

Implements phases 0 to 2 of `dev/specs/2026-09-23-cardiac-master-view-design.md`. These are
scripts, not exports. They are promoted into the package when the mitral master reuses
them (spec §4.1).

## Order

1. `run-phase0.R`: snapshot the current build to parquet and test the candidate keys.
2. `batch-snapshots.R`: the other eleven builds, in the background, on the scan host.
3. `run-phase1.R`: DDL, load, parity, and the `master_cardiac` view.
4. `run-phase2.R`: the corrections tables, the legacy facts as `bake` rows, and the
   corrections view.

## PHI

The parquet files, the warehouse tables and the corrections live outside this repository.
Nothing here holds a key or a value, and nothing prints one: output is counts, verdicts,
column names and line numbers. The legacy facts are read from the SAS program at run time
and written straight to the warehouse.

## Tests

Standalone, against duckdb, with invented data. Run them all:

    for f in dev/masters/cardiac/test-*.R; do Rscript "$f" || break; done

Each prints `all checks passed` or exits non-zero. A test skips (exit 0) when a package it
needs is missing; `install.packages("duckdb")` covers the usual case.
```

- [ ] **Step 2: Write the harness**

```r
# test-harness.R
#
# A minimal check harness for the standalone tests in this folder, in the style
# of dev/specs/artifacts/test-*.R. NO PHI.

fail <- 0L

check <- function(label, ok) {
  ok <- isTRUE(ok)
  if (!ok) fail <<- fail + 1L
  message(sprintf("%-68s %s", label, if (ok) "ok" else "FAIL"))
  invisible(ok)
}

check_error <- function(label, expr, pattern = NULL) {
  msg <- tryCatch({
    force(expr)
    NULL
  }, error = function(e) conditionMessage(e))
  check(label, !is.null(msg) && (is.null(pattern) || grepl(pattern, msg)))
  invisible(msg)
}

skip_unless <- function(pkgs) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    message("SKIP: missing ", paste(missing, collapse = ", "))
    quit(save = "no", status = 0)
  }
}

finish <- function() {
  if (fail) {
    message("\n", fail, " failure(s)")
    quit(save = "no", status = 1)
  }
  message("\nall checks passed")
}
```

- [ ] **Step 3: Write the failing test** `dev/masters/cardiac/test-key-verdict.R`:

```r
#!/usr/bin/env Rscript
# test-key-verdict.R: key_verdict() on invented keys. NO PHI.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "test-harness.R"))
skip_unless(c("arrow", "tidyselect"))
source(file.path(here, "key-verdict.R"))

pq <- tempfile(fileext = ".parquet")
arrow::write_parquet(data.frame(
  id      = c("K1", "K1", "K2", "K3", NA),
  dt_surg = as.Date(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-01-01",
                      "2020-01-01")),
  alt     = c("E1", "E2", NA, "E2", "E3"),
  stringsAsFactors = FALSE
), pq)

v <- key_verdict(pq, c("id", "dt_surg"))
check("id + date: one null key part makes it not unique", v$verdict == "not unique")
check("id + date: no duplicates among the rows", v$n_duplicates == 0L)
check("id + date: one row has a null key part", v$n_null_key == 1L)

v <- key_verdict(pq, "id")
check("id alone: duplicates found", v$n_duplicates == 1L)

v <- key_verdict(pq, "alt", nonnull_only = TRUE)
check("alt, non-null only: counts only the non-null rows", v$n_rows == 4L)
check("alt, non-null only: E2 twice is a duplicate", v$verdict == "not unique")

v <- key_verdict(pq, c("id", "missing_col"))
check("a missing column gives verdict 'absent'", v$verdict == "absent")

line <- format_key_verdict(key_verdict(pq, "id"))
check("the formatted line carries no key value", !grepl("K1|K2|K3", line))

finish()
```

- [ ] **Step 4: Run it and watch it fail**

Run: `Rscript dev/masters/cardiac/test-key-verdict.R`
Expected: error, `cannot open file '.../key-verdict.R'`.

- [ ] **Step 5: Implement** `dev/masters/cardiac/key-verdict.R`:

```r
# key-verdict.R
#
# Is a candidate key unique in a parquet snapshot? Reads only the key columns and
# reports counts and a verdict, never a key value.

key_verdict <- function(parquet, key, nonnull_only = FALSE) {
  label <- paste(key, collapse = " + ")
  present <- names(arrow::ParquetFileReader$create(parquet)$GetSchema())
  if (!all(key %in% present)) {
    return(list(key = label, n_rows = NA_integer_, n_null_key = NA_integer_,
                n_duplicates = NA_integer_, verdict = "absent"))
  }
  k <- as.data.frame(arrow::read_parquet(parquet,
                                         col_select = tidyselect::all_of(key)))
  has_null <- !stats::complete.cases(k)
  n_null <- sum(has_null)
  if (nonnull_only) k <- k[!has_null, , drop = FALSE]
  n_dup <- sum(duplicated(k))
  unique_ok <- n_dup == 0L && (nonnull_only || n_null == 0L)
  list(key = label, n_rows = nrow(k), n_null_key = n_null,
       n_duplicates = n_dup, verdict = if (unique_ok) "unique" else "not unique")
}

format_key_verdict <- function(v) {
  sprintf("key %-32s %-10s rows %s, null key parts %s, duplicates %s",
          v$key, v$verdict, v$n_rows, v$n_null_key, v$n_duplicates)
}
```

- [ ] **Step 6: Run it and watch it pass**

Run: `Rscript dev/masters/cardiac/test-key-verdict.R`
Expected: every line `ok`, then `all checks passed`.

- [ ] **Step 7: Commit**

```bash
git add dev/masters/cardiac/README.md dev/masters/cardiac/test-harness.R \
  dev/masters/cardiac/key-verdict.R dev/masters/cardiac/test-key-verdict.R
git commit -m "feat: test candidate master keys, reporting verdicts only"
```

---

### Task 4: DDL generator with a row-size preflight

**Files:**
- Create: `dev/masters/cardiac/ddl.R`
- Test: `dev/masters/cardiac/test-ddl.R`

**Interfaces:**
- Produces: `mssql_type(arrow_type, max_nchar = NA_integer_)` returning
  `list(sql, bytes, variable)`; `ddl_preflight(types, max_row = 8060L, max_cols = 1024L)`
  returning `list(ok, row_bytes, message)`; `master_ddl(parquet, table,
  schema_name = "dbo")` returning `list(sql, types, row_bytes, n_cols)`, where `types` is
  a named character vector of SQL Server types used later by the corrections view.

- [ ] **Step 1: Write the failing test** `dev/masters/cardiac/test-ddl.R`:

```r
#!/usr/bin/env Rscript
# test-ddl.R: DDL generation and the row-size preflight. NO PHI.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "test-harness.R"))
skip_unless(c("arrow", "tidyselect"))
source(file.path(here, "ddl.R"))

pq <- tempfile(fileext = ".parquet")
arrow::write_parquet(data.frame(
  id      = c("K1", "K22"),
  age     = c(60.5, NA),
  n       = c(1L, 2L),
  flag    = c(TRUE, FALSE),
  dt_surg = as.Date(c("2020-01-01", "2021-02-03")),
  note    = c(NA_character_, NA_character_),
  stringsAsFactors = FALSE
), pq)

d <- master_ddl(pq, "master_cardiac_base_test")
check("table is schema-qualified and quoted",
      grepl("CREATE TABLE [dbo].[master_cardiac_base_test]", d$sql, fixed = TRUE))
check("character width is measured", d$types[["id"]] == "nvarchar(3)")
check("an all-missing character column gets width 1", d$types[["note"]] == "nvarchar(1)")
check("double maps to float", d$types[["age"]] == "float")
check("integer maps to int", d$types[["n"]] == "int")
check("logical maps to bit", d$types[["flag"]] == "bit")
check("date maps to date", d$types[["dt_surg"]] == "date")
check("every column is nullable", lengths(regmatches(d$sql, gregexpr(" NULL", d$sql))) == 6L)

check_error("an unknown arrow type is an error", mssql_type("list<item: int32>"), "No SQL")
check("a very long string becomes nvarchar(max)",
      mssql_type("string", 5000L)$sql == "nvarchar(max)")

wide <- rep(list(mssql_type("double")), 1000L)
p <- ddl_preflight(wide)
check("1,000 float columns exceed the 8,060-byte row", !p$ok && p$row_bytes > 8060)
check("the message names the limit", grepl("8060", p$message))

many <- rep(list(mssql_type("bool")), 1100L)
p <- ddl_preflight(many)
check("1,100 columns exceed the column limit", !p$ok && grepl("1024", p$message))

check("a narrow table passes", ddl_preflight(rep(list(mssql_type("double")), 10L))$ok)

finish()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `Rscript dev/masters/cardiac/test-ddl.R`
Expected: error, `cannot open file '.../ddl.R'`.

- [ ] **Step 3: Implement** `dev/masters/cardiac/ddl.R`:

```r
# ddl.R
#
# Arrow schema of a parquet snapshot to SQL Server DDL, with a preflight against
# SQL Server's 8,060-byte in-row limit and its 1,024-column limit. Character
# widths are measured from the data, one column at a time.

mssql_type <- function(arrow_type, max_nchar = NA_integer_) {
  fixed <- function(sql, bytes) list(sql = sql, bytes = bytes, variable = FALSE)
  if (arrow_type == "double") return(fixed("float", 8L))
  if (arrow_type == "int32") return(fixed("int", 4L))
  if (arrow_type == "bool") return(fixed("bit", 1L))
  if (startsWith(arrow_type, "date32")) return(fixed("date", 3L))
  if (startsWith(arrow_type, "timestamp")) return(fixed("datetime2", 8L))
  if (startsWith(arrow_type, "time")) return(fixed("time", 5L))
  if (arrow_type %in% c("string", "large_string", "utf8")) {
    n <- if (is.na(max_nchar)) 1L else max(1L, as.integer(max_nchar))
    sql <- if (n > 4000L) "nvarchar(max)" else sprintf("nvarchar(%d)", n)
    return(list(sql = sql, bytes = 0L, variable = TRUE))
  }
  stop("No SQL Server type for arrow type '", arrow_type, "'.", call. = FALSE)
}

# In-row size: 4-byte header, fixed-width data, 2-byte column count, the null
# bitmap, and 2 bytes per variable-width column plus 2 for their count.
# Variable-width data can overflow off-row, so only its offsets count here.
ddl_preflight <- function(types, max_row = 8060L, max_cols = 1024L) {
  n <- length(types)
  fixed <- sum(vapply(types, `[[`, integer(1), "bytes"))
  n_var <- sum(vapply(types, `[[`, logical(1), "variable"))
  row_bytes <- 4L + fixed + 2L + ceiling(n / 8) + if (n_var) 2L + 2L * n_var else 0L
  if (n > max_cols) {
    return(list(ok = FALSE, row_bytes = row_bytes,
                message = sprintf("%d columns exceed SQL Server's limit of %d.",
                                  n, max_cols)))
  }
  if (row_bytes > max_row) {
    return(list(ok = FALSE, row_bytes = row_bytes,
                message = sprintf(paste0("The fixed-width row is %d bytes, over ",
                                         "SQL Server's %d. Split the table in two ",
                                         "and join the halves in the view."),
                                  row_bytes, max_row)))
  }
  list(ok = TRUE, row_bytes = row_bytes, message = "ok")
}

master_ddl <- function(parquet, table, schema_name = "dbo") {
  sch <- arrow::ParquetFileReader$create(parquet)$GetSchema()
  cols <- names(sch)
  arrow_types <- vapply(cols, function(v) sch[[v]]$type$ToString(), character(1))
  types <- lapply(cols, function(v) {
    at <- arrow_types[[v]]
    if (!at %in% c("string", "large_string", "utf8")) return(mssql_type(at))
    x <- arrow::read_parquet(parquet, col_select = tidyselect::all_of(v))[[1]]
    width <- if (all(is.na(x))) NA_integer_ else max(nchar(x, type = "chars"), na.rm = TRUE)
    mssql_type(at, width)
  })
  pre <- ddl_preflight(types)
  if (!pre$ok) stop(pre$message, call. = FALSE)
  q <- function(x) paste0("[", gsub("]", "]]", x, fixed = TRUE), "]")
  sql_types <- vapply(types, `[[`, character(1), "sql")
  body <- paste(sprintf("  %s %s NULL", q(cols), sql_types), collapse = ",\n")
  list(sql = sprintf("CREATE TABLE %s.%s (\n%s\n);", q(schema_name), q(table), body),
       types = stats::setNames(sql_types, cols),
       row_bytes = pre$row_bytes, n_cols = length(cols))
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `Rscript dev/masters/cardiac/test-ddl.R`
Expected: `all checks passed`.

- [ ] **Step 5: Commit**

```bash
git add dev/masters/cardiac/ddl.R dev/masters/cardiac/test-ddl.R
git commit -m "feat: generate the master's SQL Server DDL, and refuse a row SQL Server cannot hold"
```

---

### Task 5: Resumable loader

**Files:**
- Create: `dev/masters/cardiac/load.R`
- Test: `dev/masters/cardiac/test-load.R`

**Interfaces:**
- Produces: `load_parquet(con, parquet, table, log_table = paste0(table, "__load_log"))`
  returning `list(row_groups, loaded, skipped)`. The target table must already exist; the
  log table is created when absent.

- [ ] **Step 1: Install duckdb for the tests** (development only, not in `DESCRIPTION`)

Run: `Rscript -e 'install.packages("duckdb", repos = "https://cloud.r-project.org")'`
Expected: `* DONE (duckdb)` or a binary install message.

- [ ] **Step 2: Write the failing test** `dev/masters/cardiac/test-load.R`:

```r
#!/usr/bin/env Rscript
# test-load.R: row-group load, and resume after a partial load. NO PHI.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "test-harness.R"))
skip_unless(c("arrow", "duckdb", "DBI", "haven"))
source(file.path(here, "load.R"))

d <- data.frame(id = paste0("K", 1:5), age = c(60, 61, NA, 63, 64),
                dt_surg = as.Date("2020-01-01") + 0:4, stringsAsFactors = FALSE)
attr(d$age, "label") <- "Invented label"
pq <- tempfile(fileext = ".parquet")
arrow::write_parquet(d, pq, chunk_size = 2)   # three row groups: 2, 2, 1

con <- DBI::dbConnect(duckdb::duckdb())
DBI::dbExecute(con, "CREATE TABLE base (id VARCHAR, age DOUBLE, dt_surg DATE)")

check_error("a missing target table is an error",
            load_parquet(con, pq, "nope"), "does not exist")

r <- load_parquet(con, pq, "base")
check("three row groups loaded", r$loaded == 3L && r$row_groups == 3L)
check("five rows in the table",
      DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM base")$n == 5)

r <- load_parquet(con, pq, "base")
check("a second run skips every logged group", r$loaded == 0L && r$skipped == 3L)
check("and adds no rows", DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM base")$n == 5)

# Simulate a crash after the first group: one group logged, its rows present.
DBI::dbExecute(con, "CREATE TABLE base2 (id VARCHAR, age DOUBLE, dt_surg DATE)")
DBI::dbExecute(con, "INSERT INTO base2 SELECT * FROM base WHERE id IN ('K1', 'K2')")
DBI::dbExecute(con, paste("CREATE TABLE base2__load_log",
                          "(row_group INTEGER, n_rows INTEGER, loaded_at VARCHAR)"))
DBI::dbExecute(con, "INSERT INTO base2__load_log VALUES (0, 2, 'earlier')")
r <- load_parquet(con, pq, "base2")
check("resume loads only the missing groups", r$loaded == 2L && r$skipped == 1L)
check("resume ends with every row once",
      DBI::dbGetQuery(con, "SELECT COUNT(DISTINCT id) AS n, COUNT(*) AS m FROM base2")$m == 5)

DBI::dbDisconnect(con, shutdown = TRUE)
finish()
```

- [ ] **Step 3: Run it and watch it fail**

Run: `Rscript dev/masters/cardiac/test-load.R`
Expected: error, `cannot open file '.../load.R'`.

- [ ] **Step 4: Implement** `dev/masters/cardiac/load.R`:

```r
# load.R
#
# Load a parquet snapshot into an existing table one row group at a time. Each
# group and its log row commit in one transaction, so a failure resumes from the
# last committed group rather than restarting.

load_parquet <- function(con, parquet, table, log_table = paste0(table, "__load_log")) {
  if (!DBI::dbExistsTable(con, table)) {
    stop("Target table does not exist: ", table, ". Run the DDL first.", call. = FALSE)
  }
  if (!DBI::dbExistsTable(con, log_table)) {
    DBI::dbCreateTable(con, log_table,
                       data.frame(row_group = integer(), n_rows = integer(),
                                  loaded_at = character()))
  }
  done <- DBI::dbGetQuery(con, paste("SELECT row_group FROM",
                                     DBI::dbQuoteIdentifier(con, log_table)))$row_group

  reader <- arrow::ParquetFileReader$create(parquet)
  n_groups <- reader$num_row_groups
  loaded <- 0L
  skipped <- 0L
  for (g in seq_len(n_groups) - 1L) {
    if (g %in% done) {
      skipped <- skipped + 1L
      next
    }
    d <- as.data.frame(reader$ReadRowGroup(g))
    # SQL Server has no labels or formats; the sidecar carries them instead.
    d <- haven::zap_widths(haven::zap_formats(haven::zap_labels(haven::zap_label(d))))
    DBI::dbWithTransaction(con, {
      DBI::dbAppendTable(con, table, d)
      DBI::dbAppendTable(con, log_table, data.frame(
        row_group = g, n_rows = nrow(d),
        loaded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")))
    })
    loaded <- loaded + 1L
  }
  list(row_groups = n_groups, loaded = loaded, skipped = skipped)
}
```

- [ ] **Step 5: Run it and watch it pass**

Run: `Rscript dev/masters/cardiac/test-load.R`
Expected: `all checks passed`.

- [ ] **Step 6: Commit**

```bash
git add dev/masters/cardiac/load.R dev/masters/cardiac/test-load.R
git commit -m "feat: load a snapshot by row group, resuming from the last committed group"
```

---

### Task 6: SQL helpers and the parity check

**Files:**
- Create: `dev/masters/cardiac/sql-common.R`
- Create: `dev/masters/cardiac/parity.R`
- Test: `dev/masters/cardiac/test-parity.R`

**Interfaces:**
- Produces (`sql-common.R`): `quoter(dialect)` returning a quoting function;
  `sql_string(x)`; `sql_types(dialect)` returning `list(text, id, ts, flag)`;
  `view_header(dialect)`; `table_types(con, table)` returning a named character vector of
  SQL Server column types read from `INFORMATION_SCHEMA.COLUMNS`. `dialect` is always one
  of `"mssql"`, `"duckdb"`.
- Consumes: `compare_built()` from the package (`hvtiRdatabuild::compare_built(oracle, r,
  id, tolerance)`), whose `verdict` column takes `"identical"`, `"within_tolerance"`,
  `"differs"`, `"absent_in_r"`, `"absent_in_sas"`, `"type_mismatch"`.
- Produces (`parity.R`): `parity_sql(table, column, is_numeric, is_character, dialect)`;
  `parity_check(con, table, parquet, key, sample_n = 1000L, seed = 1L,
  dialect = "mssql")` returning `list(verdict, row_count, columns, sample)` where
  `columns` and `sample` are data frames of `variable`, `verdict`; `parity_summary(res)`
  returning one line.

- [ ] **Step 1: Write the failing test** `dev/masters/cardiac/test-parity.R`:

```r
#!/usr/bin/env Rscript
# test-parity.R: parity between a parquet snapshot and its loaded table. NO PHI.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "test-harness.R"))
skip_unless(c("arrow", "duckdb", "DBI", "dplyr", "withr", "tidyselect", "hvtiRdatabuild"))
source(file.path(here, "sql-common.R"))
source(file.path(here, "parity.R"))

check("mssql quoting doubles a closing bracket", quoter("mssql")("a]b") == "[a]]b]")
check("duckdb quoting doubles a quote", quoter("duckdb")("a\"b") == "\"a\"\"b\"")
check("string literals double a single quote", sql_string("O'Neil") == "'O''Neil'")
check("mssql distinct on text uses a hash",
      grepl("HASHBYTES", parity_sql("t", "s", FALSE, TRUE, "mssql")))
check("numeric columns get a sum", grepl("SUM", parity_sql("t", "x", TRUE, FALSE, "duckdb")))

d <- data.frame(id = paste0("K", 1:6), dt_surg = as.Date("2020-01-01") + 0:5,
                age = c(60.25, 61, NA, 63, 64, 65), surgeon = c("A", "a", "A ", NA, "B", "B"),
                stringsAsFactors = FALSE)
pq <- tempfile(fileext = ".parquet")
arrow::write_parquet(d, pq)

con <- DBI::dbConnect(duckdb::duckdb())
DBI::dbWriteTable(con, "base", d)

res <- parity_check(con, "base", pq, c("id", "dt_surg"), sample_n = 4L, dialect = "duckdb")
check("an exact load passes", res$verdict == "pass")
check("every column matches", all(res$columns$verdict == "match"))
check("the sample matches", all(res$sample$verdict == "match"))

DBI::dbExecute(con, "UPDATE base SET age = 99 WHERE id = 'K2'")
res <- parity_check(con, "base", pq, c("id", "dt_surg"), sample_n = 6L, dialect = "duckdb")
check("a changed value fails", res$verdict == "fail")
check("the age column is the mismatch",
      res$columns$verdict[res$columns$variable == "age"] == "mismatch")
check("the summary carries no key or value",
      !grepl("K2|99|60.25", parity_summary(res)))

DBI::dbExecute(con, "DELETE FROM base WHERE id = 'K6'")
res <- parity_check(con, "base", pq, c("id", "dt_surg"), sample_n = 2L, dialect = "duckdb")
check("a missing row fails the row count", res$row_count == "mismatch")

DBI::dbDisconnect(con, shutdown = TRUE)
finish()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `Rscript dev/masters/cardiac/test-parity.R`
Expected: error, `cannot open file '.../sql-common.R'`.

- [ ] **Step 3: Implement** `dev/masters/cardiac/sql-common.R`:

```r
# sql-common.R
#
# Quoting and dialect details shared by the parity check and the corrections
# SQL. Only two dialects exist: SQL Server in production, duckdb in the tests.

quoter <- function(dialect) {
  switch(dialect,
         mssql  = function(x) paste0("[", gsub("]", "]]", x, fixed = TRUE), "]"),
         duckdb = function(x) paste0("\"", gsub("\"", "\"\"", x, fixed = TRUE), "\""),
         stop("Unknown dialect '", dialect, "'.", call. = FALSE))
}

sql_string <- function(x) paste0("'", gsub("'", "''", x, fixed = TRUE), "'")

sql_types <- function(dialect) {
  switch(dialect,
         mssql  = list(text = "nvarchar(4000)", id = "nvarchar(128)",
                       ts = "datetime2", flag = "tinyint"),
         duckdb = list(text = "VARCHAR", id = "VARCHAR", ts = "TIMESTAMP",
                       flag = "TINYINT"),
         stop("Unknown dialect '", dialect, "'.", call. = FALSE))
}

view_header <- function(dialect) {
  switch(dialect,
         mssql  = "CREATE OR ALTER VIEW",
         duckdb = "CREATE OR REPLACE VIEW",
         stop("Unknown dialect '", dialect, "'.", call. = FALSE))
}

# SQL Server column types of a table, as they would be written in a CAST.
table_types <- function(con, table) {
  cols <- DBI::dbGetQuery(con, paste(
    "SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH",
    "FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = ?",
    "ORDER BY ORDINAL_POSITION"), params = list(table))
  len <- cols$CHARACTER_MAXIMUM_LENGTH
  type <- ifelse(is.na(len), cols$DATA_TYPE,
                 sprintf("%s(%s)", cols$DATA_TYPE, ifelse(len == -1, "max", len)))
  stats::setNames(type, cols$COLUMN_NAME)
}
```

- [ ] **Step 4: Implement** `dev/masters/cardiac/parity.R`:

```r
# parity.R
#
# Is the loaded table the parquet snapshot? Row count; per column, non-null
# count, distinct count and numeric sum on both sides; and a full value compare
# on a random sample of rows joined on the key. Aggregates alone pass with
# compensating errors: a sum cannot see two cells swap. Verdicts only.

parity_sql <- function(table, column, is_numeric, is_character, dialect) {
  q <- quoter(dialect)
  col <- q(column)
  # SQL Server's default collation ignores case and trailing spaces in DISTINCT;
  # hashing compares the stored characters exactly, as R does.
  distinct_expr <- if (is_character && dialect == "mssql") {
    sprintf("HASHBYTES('SHA2_256', %s)", col)
  } else {
    col
  }
  total <- if (is_numeric) sprintf(", SUM(CAST(%s AS DOUBLE PRECISION)) AS total", col) else ""
  sprintf("SELECT COUNT(%s) AS n_nonnull, COUNT(DISTINCT %s) AS n_distinct%s FROM %s",
          col, distinct_expr, total, q(table))
}

.zap_all <- function(d) {
  haven::zap_widths(haven::zap_formats(haven::zap_labels(haven::zap_label(d))))
}

parity_check <- function(con, table, parquet, key, sample_n = 1000L, seed = 1L,
                         dialect = "mssql") {
  q <- quoter(dialect)
  reader <- arrow::ParquetFileReader$create(parquet)
  cols <- names(reader$GetSchema())

  db_n <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s", q(table)))$n
  row_count <- if (as.numeric(db_n) == as.numeric(reader$num_rows)) "match" else "mismatch"

  columns <- do.call(rbind, lapply(cols, function(v) {
    x <- arrow::read_parquet(parquet, col_select = tidyselect::all_of(v))[[1]]
    is_num <- is.numeric(unclass(x)) && !inherits(x, c("Date", "POSIXt"))
    is_chr <- is.character(x)
    db <- DBI::dbGetQuery(con, parity_sql(table, v, is_num, is_chr, dialect))
    ok <- as.numeric(db$n_nonnull) == sum(!is.na(x)) &&
      as.numeric(db$n_distinct) == length(unique(x[!is.na(x)]))
    if (is_num) {
      db_total <- if (is.na(db$total)) 0 else as.numeric(db$total)
      ok <- ok && isTRUE(all.equal(sum(as.numeric(x), na.rm = TRUE), db_total,
                                   tolerance = 1e-9))
    }
    data.frame(variable = v, verdict = if (ok) "match" else "mismatch",
               stringsAsFactors = FALSE)
  }))

  keys <- as.data.frame(arrow::read_parquet(parquet, col_select = tidyselect::all_of(key)))
  idx <- withr::with_seed(seed, sample.int(nrow(keys), min(sample_n, nrow(keys))))
  picked <- keys[idx, , drop = FALSE]
  tmp <- if (dialect == "mssql") "#parity_sample_keys" else "parity_sample_keys"
  DBI::dbWriteTable(con, tmp, picked, temporary = TRUE, overwrite = TRUE)
  on.exit(DBI::dbRemoveTable(con, tmp), add = TRUE)
  on <- paste(sprintf("t.%s = s.%s", q(key), q(key)), collapse = " AND ")
  db_rows <- DBI::dbGetQuery(con, sprintf("SELECT t.* FROM %s t JOIN %s s ON %s",
                                          q(table), q(tmp), on))
  pq_rows <- .zap_all(as.data.frame(dplyr::collect(
    dplyr::semi_join(arrow::open_dataset(parquet), picked, by = key))))

  make_id <- function(d) do.call(paste, c(lapply(d[key], as.character), sep = "\r"))
  pq_rows$.parity_key <- make_id(pq_rows)
  db_rows$.parity_key <- make_id(db_rows)
  cmp <- hvtiRdatabuild::compare_built(pq_rows, db_rows, id = ".parity_key")
  rows <- attr(cmp, "rows")
  sample_ok <- cmp$verdict %in% c("identical", "within_tolerance") &
    length(rows$only_oracle) == 0L && length(rows$only_r) == 0L
  sample <- data.frame(variable = cmp$variable,
                       verdict = ifelse(sample_ok, "match", "mismatch"),
                       stringsAsFactors = FALSE)

  pass <- row_count == "match" && all(columns$verdict == "match") &&
    all(sample$verdict == "match")
  list(verdict = if (pass) "pass" else "fail", row_count = row_count,
       columns = columns, sample = sample)
}

parity_summary <- function(res) {
  sprintf("parity %s: row count %s; %d of %d columns mismatch; %d of %d sampled columns mismatch",
          res$verdict, res$row_count,
          sum(res$columns$verdict == "mismatch"), nrow(res$columns),
          sum(res$sample$verdict == "mismatch"), nrow(res$sample))
}
```

- [ ] **Step 5: Run it and watch it pass**

Run: `Rscript dev/masters/cardiac/test-parity.R`
Expected: `all checks passed`. If `hvtiRdatabuild` is not installed, run
`Rscript -e 'devtools::install()'` from the worktree first.

- [ ] **Step 6: Commit**

```bash
git add dev/masters/cardiac/sql-common.R dev/masters/cardiac/parity.R \
  dev/masters/cardiac/test-parity.R
git commit -m "feat: prove a loaded master equals its snapshot, by aggregates and a sampled compare"
```

---

### Task 7: The corrections contract, its reference resolver and its SQL

**Files:**
- Create: `dev/masters/cardiac/value-text.R`
- Create: `dev/masters/cardiac/corrections.R`
- Test: `dev/masters/cardiac/test-corrections.R`

**Interfaces:**
- Consumes: `quoter()`, `sql_string()`, `sql_types()`, `view_header()` from Task 6.
- Produces (`value-text.R`): `value_text(x)` (one value to text; doubles to 17 significant
  digits so a SQL `CAST` returns the same double; dates ISO); `parse_value(text, r_class)`
  (text back to an R value of class `r_class`, one of `numeric`, `integer`,
  `haven_labelled`, `Date`, `POSIXct`, `character`).
- Produces (`corrections.R`):
  - `corrections_ddl(corrections_table, decisions_table, key_types, alt_key_types = NULL,
    dialect = "mssql")` returning a named character vector, `corrections` and `decisions`.
  - `resolve_corrections(base, corrections, decisions, key, master)` returning
    `list(data, stale)`, `stale` a data frame of `correction_id`, `variable`, `reason`.
  - `corrections_view_sql(view, base_table, corrections_table, decisions_table, master,
    key, columns, corrected, types, dialect = "mssql")`.
  - `stale_view_sql(view, base_table, corrections_table, decisions_table, master, key,
    columns, corrected, types, dialect = "mssql")`.
  - `corrected_variables(con, corrections_table, master, dialect = "mssql")`.
- Column names in the contract: `correction_id`, `master`, the key columns, optional
  alternate key columns, `variable`, `expected_prior`, `expected_prior_missing`,
  `new_value`, `new_value_missing`, `evidence_type`, `evidence_ref`, `asserted_by`,
  `asserted_on`; and `decision_id`, `correction_id`, `decision`, `decided_by`,
  `decided_on`, `reason`.

- [ ] **Step 1: Write the failing test** `dev/masters/cardiac/test-corrections.R`:

```r
#!/usr/bin/env Rscript
# test-corrections.R: the R reference resolver, and the generated SQL agreeing
# with it on duckdb. Every id and value is invented. NO PHI.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "test-harness.R"))
skip_unless(c("duckdb", "DBI"))
source(file.path(here, "sql-common.R"))
source(file.path(here, "value-text.R"))
source(file.path(here, "corrections.R"))

check("a double round-trips through text", parse_value(value_text(0.1), "numeric") == 0.1)
check("a date is written ISO", value_text(as.Date("2020-01-15")) == "2020-01-15")
check("missing is NA text", is.na(value_text(NA_real_)))

key <- c("id", "dt_surg")
base <- data.frame(
  id      = c("K1", "K2", "K3", "K4"),
  dt_surg = as.Date(c("2020-01-01", "2020-02-01", "2020-03-01", "2020-04-01")),
  age     = c(65.5, 70.25, 58, NA),
  bmi     = c(31.2, NA, 22.8, 27.4),
  dt_dis  = as.Date(c("2020-01-09", "2020-02-09", "2020-03-09", "2020-04-09")),
  surgeon = c("S1", "S2", "S1", NA),
  stringsAsFactors = FALSE)
t0 <- as.POSIXct("2026-01-01 00:00:00", tz = "UTC")
corr <- function(cid, id, dt, variable, prior, prior_missing, new, new_missing, at) {
  data.frame(correction_id = cid, master = "m", id = id, dt_surg = as.Date(dt),
             variable = variable, expected_prior = prior,
             expected_prior_missing = prior_missing, new_value = new,
             new_value_missing = new_missing, evidence_type = "chart_review",
             evidence_ref = "invented", asserted_by = "tester", asserted_on = t0 + at,
             stringsAsFactors = FALSE)
}
corrections <- rbind(
  corr("c01", "K1", "2020-01-01", "age",     "65.5", 0L, "66",         0L, 1),  # applied
  corr("c02", "K3", "2020-03-01", "bmi",     "99",   0L, "23",         0L, 2),  # prior_mismatch
  corr("c03", "K4", "2020-04-01", "age",     NA,     1L, "61",         0L, 3),  # NA matches NULL
  corr("c04", "K1", "2020-01-01", "bmi",     "31.2", 0L, "30",         0L, 4),  # loses to c05
  corr("c05", "K1", "2020-01-01", "bmi",     "31.2", 0L, "29.5",       0L, 5),  # wins
  corr("c06", "K2", "2020-02-01", "dt_dis",  "2020-02-09", 0L, "2020-02-10", 0L, 6),  # rejected
  corr("c07", "K2", "2020-02-01", "surgeon", "S2",   0L, "S3",         0L, 7),  # baked
  corr("c08", "K9", "2020-09-01", "age",     "1",    0L, "2",          0L, 8),  # no_record
  corr("c09", "K3", "2020-03-01", "surgeon", NA,     NA, "S4",         0L, 9),  # prior_unknown
  corr("c10", "K1", "2020-01-01", "height",  "1",    0L, "2",          0L, 10), # no_variable
  corr("c11", "K1", "2020-01-01", "surgeon", "S1",   0L, NA,           1L, 11), # set missing
  corr("c12", "K2", "2020-02-01", "age",     "70.25", 0L, "71",        0L, 12)) # other master
corrections$master[corrections$correction_id == "c12"] <- "other"
decision <- function(did, cid, what, at) {
  data.frame(decision_id = did, correction_id = cid, decision = what, decided_by = "tester",
             decided_on = t0 + 100 + at, reason = NA_character_, stringsAsFactors = FALSE)
}
decisions <- rbind(
  do.call(rbind, lapply(sprintf("c%02d", c(1:5, 8:12)), function(cid)
    decision(paste0("d", cid), cid, "accept", 0))),
  decision("d06a", "c06", "accept", 0), decision("d06b", "c06", "reject", 1),
  decision("d07", "c07", "bake", 0))

res <- resolve_corrections(base, corrections, decisions, key, "m")
out <- res$data
check("c01 applied", out$age[1] == 66)
check("c05 wins over c04 on the same cell", out$bmi[1] == 29.5)
check("c11 sets a value missing", is.na(out$surgeon[1]))
check("c03: a missing prior matches a missing base", out$age[4] == 61)
check("c02 not applied", out$bmi[3] == 22.8)
check("c06 rejected after accept, not applied", out$dt_dis[2] == as.Date("2020-02-09"))
check("c07 baked, not applied", out$surgeon[2] == "S2")
check("c12 belongs to another master", out$age[2] == 70.25)
stale <- res$stale[order(res$stale$correction_id), ]
check("stale ids", identical(stale$correction_id, c("c02", "c08", "c09", "c10")))
check("stale reasons", identical(stale$reason,
      c("prior_mismatch", "no_record", "prior_unknown", "no_variable")))

con <- DBI::dbConnect(duckdb::duckdb())
DBI::dbWriteTable(con, "base", base)
ddl <- corrections_ddl("corr", "dec",
                       key_types = c(id = "VARCHAR", dt_surg = "DATE"), dialect = "duckdb")
DBI::dbExecute(con, ddl[["corrections"]])
DBI::dbExecute(con, ddl[["decisions"]])
DBI::dbAppendTable(con, "corr", corrections)
DBI::dbAppendTable(con, "dec", decisions)

types <- c(id = "VARCHAR", dt_surg = "DATE", age = "DOUBLE", bmi = "DOUBLE",
           dt_dis = "DATE", surgeon = "VARCHAR")
corrected <- corrected_variables(con, "corr", "m", dialect = "duckdb")
check("corrected variables are the master's own",
      setequal(corrected, c("age", "bmi", "dt_dis", "surgeon", "height")))
DBI::dbExecute(con, corrections_view_sql("v", "base", "corr", "dec", "m", key,
                                         names(base), corrected, types, "duckdb"))
DBI::dbExecute(con, stale_view_sql("v_stale", "base", "corr", "dec", "m", key,
                                   names(base), corrected, types, "duckdb"))

sql_out <- DBI::dbGetQuery(con, "SELECT * FROM v ORDER BY id")
check("the SQL view agrees with the R reference",
      isTRUE(all.equal(sql_out, out[order(out$id), ], check.attributes = FALSE)))
sql_stale <- DBI::dbGetQuery(con, "SELECT * FROM v_stale ORDER BY correction_id")
check("the stale view agrees with the R reference",
      identical(sql_stale$correction_id, stale$correction_id) &&
        identical(sql_stale$reason, stale$reason))

DBI::dbDisconnect(con, shutdown = TRUE)
finish()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `Rscript dev/masters/cardiac/test-corrections.R`
Expected: error, `cannot open file '.../value-text.R'`.

- [ ] **Step 3: Implement** `dev/masters/cardiac/value-text.R`:

```r
# value-text.R
#
# A value's text form in the corrections table, and back. Doubles are written
# with 17 significant digits, which is enough for CAST(text AS float) in SQL, or
# as.numeric() in R, to return exactly the same double.

value_text <- function(x) {
  stopifnot(length(x) == 1L)
  if (is.na(x)) return(NA_character_)
  if (inherits(x, "Date")) return(format(x, "%Y-%m-%d"))
  if (inherits(x, "POSIXct")) return(format(x, "%Y-%m-%d %H:%M:%OS6", tz = "UTC"))
  if (is.numeric(unclass(x))) return(sprintf("%.17g", as.numeric(x)))
  as.character(x)
}

parse_value <- function(text, r_class) {
  if (is.na(text)) {
    return(switch(r_class, Date = as.Date(NA), POSIXct = as.POSIXct(NA),
                  character = NA_character_, NA_real_))
  }
  switch(r_class,
         numeric = , integer = , haven_labelled = suppressWarnings(as.numeric(text)),
         Date = as.Date(text, format = "%Y-%m-%d"),
         POSIXct = as.POSIXct(text, tz = "UTC"),
         character = text,
         stop("No text form for class '", r_class, "'.", call. = FALSE))
}
```

- [ ] **Step 4: Implement** `dev/masters/cardiac/corrections.R`:

```r
# corrections.R
#
# The corrections contract (spec §5): two append-only tables, an R reference
# resolver, and the generated SQL that implements the same rules as a view. The
# SQL uses CTEs, CASE, JOIN, LEFT JOIN, UNION ALL and ROW_NUMBER() only, so the
# duckdb test proves the logic SQL Server will run.

corrections_ddl <- function(corrections_table, decisions_table, key_types,
                            alt_key_types = NULL, dialect = "mssql") {
  q <- quoter(dialect)
  ty <- sql_types(dialect)
  col <- function(name, type, null = TRUE) {
    sprintf("  %s %s %s", q(name), type, if (null) "NULL" else "NOT NULL")
  }
  key_cols <- unname(mapply(col, names(key_types), key_types, MoreArgs = list(null = FALSE)))
  alt_cols <- if (length(alt_key_types)) {
    unname(mapply(col, names(alt_key_types), alt_key_types))
  } else {
    character()
  }
  corr <- c(col("correction_id", ty$id, FALSE), col("master", ty$id, FALSE),
            key_cols, alt_cols,
            col("variable", ty$id, FALSE),
            col("expected_prior", ty$text), col("expected_prior_missing", ty$flag),
            col("new_value", ty$text), col("new_value_missing", ty$flag, FALSE),
            col("evidence_type", ty$id, FALSE), col("evidence_ref", ty$text, FALSE),
            col("asserted_by", ty$id, FALSE), col("asserted_on", ty$ts, FALSE))
  dec <- c(col("decision_id", ty$id, FALSE), col("correction_id", ty$id, FALSE),
           col("decision", ty$id, FALSE), col("decided_by", ty$id, FALSE),
           col("decided_on", ty$ts, FALSE), col("reason", ty$text))
  c(corrections = sprintf("CREATE TABLE %s (\n%s\n);", q(corrections_table),
                          paste(corr, collapse = ",\n")),
    decisions   = sprintf("CREATE TABLE %s (\n%s\n);", q(decisions_table),
                          paste(dec, collapse = ",\n")))
}

# The R reference. Rules, in order: a correction's latest decision (by
# decided_on, then decision_id) must be 'accept'; among accepted corrections to
# one cell the latest (by asserted_on, then correction_id) wins; the winner is
# stale if its variable is not a correctable column, its key matches no row, its
# prior is unknown, or the base no longer holds its prior. Otherwise it applies.
resolve_corrections <- function(base, corrections, decisions, key, master) {
  dec <- decisions[order(decisions$correction_id, -xtfrm(decisions$decided_on),
                         -xtfrm(decisions$decision_id)), ]
  latest <- dec[!duplicated(dec$correction_id), ]
  accepted <- latest$correction_id[latest$decision == "accept"]
  acc <- corrections[corrections$master == master &
                       corrections$correction_id %in% accepted, ]
  acc <- acc[order(-xtfrm(acc$asserted_on), -xtfrm(acc$correction_id)), ]
  cell <- function(d, cols) do.call(paste, c(lapply(d[cols], as.character), sep = "\r"))
  winners <- acc[!duplicated(cell(acc, c(key, "variable"))), ]

  out <- base
  valid <- setdiff(names(base), key)
  base_id <- cell(base, key)
  stale <- list()
  for (i in seq_len(nrow(winners))) {
    w <- winners[i, ]
    row <- match(cell(w, key), base_id)
    reason <- if (!w$variable %in% valid) {
      "no_variable"
    } else if (is.na(row)) {
      "no_record"
    } else if (is.na(w$expected_prior_missing)) {
      "prior_unknown"
    } else {
      cls <- class(base[[w$variable]])[[1]]
      cur <- base[[w$variable]][row]
      prior_ok <- if (w$expected_prior_missing == 1L) {
        is.na(cur)
      } else {
        !is.na(cur) && isTRUE(cur == parse_value(w$expected_prior, cls))
      }
      if (prior_ok) {
        out[[w$variable]][row] <- if (w$new_value_missing == 1L) NA else
          parse_value(w$new_value, cls)
        NULL
      } else {
        "prior_mismatch"
      }
    }
    if (!is.null(reason)) {
      stale[[length(stale) + 1L]] <- data.frame(correction_id = w$correction_id,
                                                variable = w$variable, reason = reason,
                                                stringsAsFactors = FALSE)
    }
  }
  stale <- if (length(stale)) do.call(rbind, stale) else
    data.frame(correction_id = character(), variable = character(), reason = character())
  list(data = out, stale = stale)
}

.winners_cte <- function(q, corrections_table, decisions_table, master, key) {
  paste0(
    "WITH latest AS (\n",
    "  SELECT correction_id, decision,\n",
    "         ROW_NUMBER() OVER (PARTITION BY correction_id\n",
    "                            ORDER BY decided_on DESC, decision_id DESC) AS rn\n",
    "  FROM ", q(decisions_table), "\n",
    "), accepted AS (\n",
    "  SELECT c.* FROM ", q(corrections_table), " c\n",
    "  JOIN latest l ON l.correction_id = c.correction_id\n",
    "  WHERE l.rn = 1 AND l.decision = 'accept' AND c.master = ", sql_string(master), "\n",
    "), ranked AS (\n",
    "  SELECT a.*, ROW_NUMBER() OVER (PARTITION BY ",
    paste0("a.", q(key), collapse = ", "), ", a.variable\n",
    "                     ORDER BY a.asserted_on DESC, a.correction_id DESC) AS rn\n",
    "  FROM accepted a\n",
    "), w AS (\n",
    "  SELECT * FROM ranked WHERE rn = 1\n",
    ")\n")
}

# Only variables in `corrected` get a join and a CASE; the rest pass through.
# Regenerate the view when a variable receives its first correction.
corrections_view_sql <- function(view, base_table, corrections_table, decisions_table,
                                 master, key, columns, corrected, types,
                                 dialect = "mssql") {
  q <- quoter(dialect)
  corrected <- intersect(corrected, setdiff(columns, key))
  stopifnot(all(key %in% columns), all(corrected %in% names(types)))
  alias <- stats::setNames(sprintf("c%d", seq_along(corrected)), corrected)
  select <- vapply(columns, function(v) {
    b <- paste0("b.", q(v))
    if (!v %in% corrected) return(b)
    sprintf(paste0("CASE WHEN %1$s.correction_id IS NOT NULL AND (",
                   "(%1$s.expected_prior_missing = 1 AND %2$s IS NULL) OR ",
                   "(%1$s.expected_prior_missing = 0 AND %2$s = CAST(%1$s.expected_prior AS %3$s)))",
                   " THEN CASE WHEN %1$s.new_value_missing = 1 THEN NULL",
                   " ELSE CAST(%1$s.new_value AS %3$s) END",
                   " ELSE %2$s END AS %4$s"),
            alias[[v]], b, types[[v]], q(v))
  }, character(1))
  joins <- vapply(corrected, function(v) {
    a <- alias[[v]]
    on <- paste(sprintf("%s.%s = b.%s", a, q(key), q(key)), collapse = " AND ")
    sprintf("LEFT JOIN w %s ON %s AND %s.variable = %s", a, on, a, sql_string(v))
  }, character(1))
  paste0(view_header(dialect), " ", q(view), " AS\n",
         .winners_cte(q, corrections_table, decisions_table, master, key),
         "SELECT\n  ", paste(select, collapse = ",\n  "), "\n",
         "FROM ", q(base_table), " b",
         if (length(joins)) paste0("\n", paste(joins, collapse = "\n")) else "",
         ";")
}

stale_view_sql <- function(view, base_table, corrections_table, decisions_table,
                           master, key, columns, corrected, types, dialect = "mssql") {
  q <- quoter(dialect)
  valid <- setdiff(columns, key)
  corrected <- intersect(corrected, valid)
  in_valid <- paste(sql_string(valid), collapse = ", ")
  on <- paste(sprintf("b.%s = w.%s", q(key), q(key)), collapse = " AND ")
  parts <- c(
    sprintf(paste("SELECT w.correction_id, w.variable, 'no_variable' AS reason FROM w",
                  "WHERE w.variable NOT IN (%s)"), in_valid),
    sprintf(paste("SELECT w.correction_id, w.variable, 'no_record' AS reason FROM w",
                  "LEFT JOIN %s b ON %s WHERE w.variable IN (%s) AND b.%s IS NULL"),
            q(base_table), on, in_valid, q(key[[1]])),
    sprintf(paste("SELECT w.correction_id, w.variable, 'prior_unknown' AS reason FROM w",
                  "JOIN %s b ON %s WHERE w.variable IN (%s)",
                  "AND w.expected_prior_missing IS NULL"),
            q(base_table), on, in_valid),
    vapply(corrected, function(v) {
      b <- paste0("b.", q(v))
      sprintf(paste("SELECT w.correction_id, w.variable, 'prior_mismatch' AS reason FROM w",
                    "JOIN %s b ON %s WHERE w.variable = %s AND (",
                    "(w.expected_prior_missing = 1 AND %s IS NOT NULL) OR",
                    "(w.expected_prior_missing = 0 AND (%s IS NULL OR",
                    "%s <> CAST(w.expected_prior AS %s))))"),
              q(base_table), on, sql_string(v), b, b, b, types[[v]])
    }, character(1)))
  paste0(view_header(dialect), " ", q(view), " AS\n",
         .winners_cte(q, corrections_table, decisions_table, master, key),
         "SELECT correction_id, variable, reason FROM (\n",
         paste(parts, collapse = "\nUNION ALL\n"),
         "\n) s;")
}

corrected_variables <- function(con, corrections_table, master, dialect = "mssql") {
  q <- quoter(dialect)
  DBI::dbGetQuery(con, sprintf("SELECT DISTINCT variable FROM %s WHERE master = ?",
                               q(corrections_table)), params = list(master))$variable
}
```

- [ ] **Step 5: Run it and watch it pass**

Run: `Rscript dev/masters/cardiac/test-corrections.R`
Expected: `all checks passed`. If the view check alone fails, print
`all.equal(sql_out, out[order(out$id), ], check.attributes = FALSE)` for the column and
fix the generator, never the reference: the reference is the specification.

- [ ] **Step 6: Commit**

```bash
git add dev/masters/cardiac/value-text.R dev/masters/cardiac/corrections.R \
  dev/masters/cardiac/test-corrections.R
git commit -m "feat: the corrections contract, with a generated view proved against an R reference"
```

---

### Task 8: Writing corrections and decisions

**Files:**
- Create: `dev/masters/cardiac/propose.R`
- Test: `dev/masters/cardiac/test-propose.R`

**Interfaces:**
- Consumes: `quoter()` (Task 6), `value_text()`, `parse_value()` (Task 7),
  `corrections_ddl()` (Task 7, in the test).
- Produces: `EVIDENCE_TYPES`; `propose_correction(con, master, base_table,
  corrections_table, key_values, variable, expected_prior, new_value, evidence_type,
  evidence_ref, asserted_by, meta, dialect = "mssql")` returning invisibly
  `list(verdict = "appended", correction_id, new_variable)`; `decide_correction(con,
  decisions_table, corrections_table, correction_id, decision, decided_by,
  reason = NA_character_, dialect = "mssql")` returning invisibly
  `list(verdict = "recorded", decision_id)`. `meta` is a data frame with `variable` and
  `r_class`, as in the sidecar's `columns`.

- [ ] **Step 1: Write the failing test** `dev/masters/cardiac/test-propose.R`:

```r
#!/usr/bin/env Rscript
# test-propose.R: propose_correction() and decide_correction(). NO PHI.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "test-harness.R"))
skip_unless(c("duckdb", "DBI", "digest"))
for (f in c("sql-common.R", "value-text.R", "corrections.R", "propose.R")) {
  source(file.path(here, f))
}

con <- DBI::dbConnect(duckdb::duckdb())
DBI::dbWriteTable(con, "base", data.frame(
  id = c("K1", "K2"), dt_surg = as.Date(c("2020-01-01", "2020-02-01")),
  age = c(65.5, NA), stringsAsFactors = FALSE))
ddl <- corrections_ddl("corr", "dec", c(id = "VARCHAR", dt_surg = "DATE"),
                       dialect = "duckdb")
DBI::dbExecute(con, ddl[["corrections"]])
DBI::dbExecute(con, ddl[["decisions"]])
meta <- data.frame(variable = c("id", "dt_surg", "age"),
                   r_class = c("character", "Date", "numeric"))
k1 <- list(id = "K1", dt_surg = as.Date("2020-01-01"))

propose <- function(...) {
  args <- utils::modifyList(list(
    con = con, master = "m", base_table = "base", corrections_table = "corr",
    key_values = k1, variable = "age", expected_prior = 65.5, new_value = 66,
    evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester",
    meta = meta, dialect = "duckdb"), list(...))
  suppressMessages(do.call(propose_correction, args))
}

r <- propose()
check("a valid correction is appended", r$verdict == "appended")
check("the first correction to a variable asks for a regenerated view", isTRUE(r$new_variable))
check("second one does not", !isTRUE(propose(new_value = 67)$new_variable))
check("two rows stored", DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM corr")$n == 2)
row <- DBI::dbGetQuery(con, sprintf("SELECT * FROM corr WHERE correction_id = '%s'",
                                    r$correction_id))
check("the prior is stored as exact text", row$expected_prior == "65.5")
check("a missing prior is flagged",
      propose(key_values = list(id = "K2", dt_surg = as.Date("2020-02-01")),
              expected_prior = NA)$verdict == "appended")

check_error("an unknown variable is an error", propose(variable = "height"), "metadata")
check_error("a key column cannot be corrected", propose(variable = "id"), "key column")
check_error("an unknown evidence type is an error", propose(evidence_type = "hunch"),
            "evidence")
msg <- check_error("a key that matches no row is an error",
                   propose(key_values = list(id = "K9", dt_surg = as.Date("2020-01-01"))),
                   "matched 0 rows")
check("and its message carries no key value", !grepl("K9", msg))
check_error("a value that does not cast is an error", propose(new_value = "abc"),
            "does not cast")

d <- suppressMessages(decide_correction(con, "dec", "corr", r$correction_id, "accept",
                                        "tester", dialect = "duckdb"))
check("a decision is recorded", d$verdict == "recorded")
check_error("an unknown decision is an error",
            decide_correction(con, "dec", "corr", r$correction_id, "maybe", "tester",
                              dialect = "duckdb"), "decision")
check_error("a decision on an unknown correction is an error",
            decide_correction(con, "dec", "corr", "cnope", "accept", "tester",
                              dialect = "duckdb"), "no correction")

DBI::dbDisconnect(con, shutdown = TRUE)
finish()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `Rscript dev/masters/cardiac/test-propose.R`
Expected: error, `cannot open file '.../propose.R'`.

- [ ] **Step 3: Implement** `dev/masters/cardiac/propose.R`:

```r
# propose.R
#
# Append a correction, or a decision on one. Both validate before writing, and
# neither prints a key or a value: messages name the table, the variable and the
# correction id only.

EVIDENCE_TYPES <- c("chart_review", "source_document", "investigator_return",
                    "legacy_sas_inline")
DECISIONS <- c("accept", "reject", "supersede", "bake")

.checked_text <- function(x, r_class, what) {
  if (length(x) != 1L) stop("'", what, "' must be a single value.", call. = FALSE)
  if (is.na(x)) return(NA_character_)
  text <- value_text(x)
  back <- parse_value(text, r_class)
  if (is.na(back) || !isTRUE(back == x)) {
    stop("'", what, "' does not cast to the variable's type (", r_class, ").",
         call. = FALSE)
  }
  text
}

propose_correction <- function(con, master, base_table, corrections_table, key_values,
                               variable, expected_prior, new_value, evidence_type,
                               evidence_ref, asserted_by, meta, dialect = "mssql") {
  q <- quoter(dialect)
  if (!variable %in% meta$variable) {
    stop("Variable is not in the master's metadata: ", variable, call. = FALSE)
  }
  if (variable %in% names(key_values)) {
    stop("A key column cannot be corrected through this path: ", variable, call. = FALSE)
  }
  if (!evidence_type %in% EVIDENCE_TYPES) {
    stop("Unknown evidence type '", evidence_type, "'. Expected one of: ",
         paste(EVIDENCE_TYPES, collapse = ", "), call. = FALSE)
  }
  r_class <- meta$r_class[match(variable, meta$variable)]
  prior_text <- .checked_text(expected_prior, r_class, "expected_prior")
  new_text <- .checked_text(new_value, r_class, "new_value")

  where <- paste(sprintf("%s = ?", q(names(key_values))), collapse = " AND ")
  n <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s WHERE %s",
                                    q(base_table), where),
                       params = unname(key_values))$n
  if (!identical(as.integer(n), 1L)) {
    stop("The key matched ", n, " rows in ", base_table, "; expected exactly 1.",
         call. = FALSE)
  }
  seen <- DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS n FROM %s WHERE master = ? AND variable = ?",
    q(corrections_table)), params = list(master, variable))$n

  now <- Sys.time()
  id <- paste0("c", substr(digest::digest(
    list(master, key_values, variable, prior_text, new_text, asserted_by,
         format(now, "%Y-%m-%d %H:%M:%OS6")), algo = "sha1"), 1, 16))
  row <- data.frame(correction_id = id, master = master, stringsAsFactors = FALSE)
  for (k in names(key_values)) row[[k]] <- key_values[[k]]
  row$variable <- variable
  row$expected_prior <- prior_text
  row$expected_prior_missing <- as.integer(is.na(expected_prior))
  row$new_value <- new_text
  row$new_value_missing <- as.integer(is.na(new_value))
  row$evidence_type <- evidence_type
  row$evidence_ref <- evidence_ref
  row$asserted_by <- asserted_by
  row$asserted_on <- now
  DBI::dbAppendTable(con, corrections_table, row)

  new_variable <- as.integer(seen) == 0L
  message("Correction ", id, " appended.",
          if (new_variable) " First correction to this variable: regenerate the view.")
  invisible(list(verdict = "appended", correction_id = id, new_variable = new_variable))
}

decide_correction <- function(con, decisions_table, corrections_table, correction_id,
                              decision, decided_by, reason = NA_character_,
                              dialect = "mssql") {
  q <- quoter(dialect)
  if (!decision %in% DECISIONS) {
    stop("Unknown decision '", decision, "'. Expected one of: ",
         paste(DECISIONS, collapse = ", "), call. = FALSE)
  }
  n <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s WHERE correction_id = ?",
                                    q(corrections_table)), params = list(correction_id))$n
  if (as.integer(n) != 1L) {
    stop("There is no correction ", correction_id, ".", call. = FALSE)
  }
  now <- Sys.time()
  did <- paste0("d", substr(digest::digest(
    list(correction_id, decision, decided_by, format(now, "%Y-%m-%d %H:%M:%OS6")),
    algo = "sha1"), 1, 16))
  DBI::dbAppendTable(con, decisions_table, data.frame(
    decision_id = did, correction_id = correction_id, decision = decision,
    decided_by = decided_by, decided_on = now, reason = reason,
    stringsAsFactors = FALSE))
  message("Decision ", did, " (", decision, ") recorded on ", correction_id, ".")
  invisible(list(verdict = "recorded", decision_id = did))
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `Rscript dev/masters/cardiac/test-propose.R`
Expected: `all checks passed`.

- [ ] **Step 5: Commit**

```bash
git add dev/masters/cardiac/propose.R dev/masters/cardiac/test-propose.R
git commit -m "feat: append corrections and decisions, validated, printing no value"
```

---

### Task 9: Legacy facts, parsed at run time and recorded as `bake`

**Files:**
- Create: `dev/masters/cardiac/legacy.R`
- Test: `dev/masters/cardiac/test-legacy.R`

**Interfaces:**
- Consumes: `value_text()`, `parse_value()` (Task 7); `quoter()` (Task 6);
  `corrections_ddl()` (Task 7, in the test).
- Produces: `parse_legacy_facts(lines, key_var = "ccfid")` returning
  `list(facts, unparsed)`, where `facts` has `line`, `key_value`, `variable`,
  `value_text`, `value_missing`, and `unparsed` is an integer vector of line numbers;
  `legacy_rows(facts, base_keys, key, master, meta, source_file, asserted_on = Sys.time())`
  returning `list(corrections, decisions, unresolved)`, `unresolved` a data frame of
  `line`, `reason`; `record_legacy_facts(con, rows, corrections_table, decisions_table,
  dialect = "mssql")` returning `list(appended, already_present)`.

- [ ] **Step 1: Write the failing test** `dev/masters/cardiac/test-legacy.R`:

```r
#!/usr/bin/env Rscript
# test-legacy.R: parsing inline SAS fixes, and recording them as 'bake'.
# The SAS below is invented; the ids are not anyone's. NO PHI.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "test-harness.R"))
skip_unless(c("duckdb", "DBI", "digest"))
for (f in c("sql-common.R", "value-text.R", "corrections.R", "legacy.R")) {
  source(file.path(here, f))
}

sas <- c(
  "data master; set base;",                        # 1
  "/* invented fixes */",                          # 2
  "if ccfid = 1001 then age = 66;",                # 3  fact
  "if ccfid eq '1002' then surgeon = 'Jones';",    # 4  fact
  "if ccfid = 1003 then do;",                      # 5  block: two facts
  "  bmi = .;",                                    # 6
  "  dt_dis = '15JAN2020'd;",                      # 7
  "end;",                                          # 8
  "if ccfid in (1004, 1005) then age = 70;",       # 9  two facts
  "if ccfid = 1006 and age > 90 then age = .;",    # 10 unparsed: compound
  "* if ccfid = 1007 then age = 1;",               # 11 comment statement
  "if age < 0 then age = .;",                      # 12 a rule, not a fact
  "run;")                                          # 13

p <- parse_legacy_facts(sas)
f <- p$facts
check("six facts parsed", nrow(f) == 6L)
check("the compound condition is reported unparsed", identical(p$unparsed, 10L))
check("line numbers survive the comment", identical(f$line, c(3L, 4L, 5L, 5L, 9L, 9L)))
check("a SAS date literal becomes ISO", f$value_text[f$variable == "dt_dis"] == "2020-01-15")
check("'.' is a missing value", f$value_missing[f$variable == "bmi"] == 1L)
check("a quoted value is unquoted", f$value_text[f$variable == "surgeon"] == "Jones")
check("an IN list gives one fact per key", setequal(f$key_value[f$line == 9L],
                                                    c("1004", "1005")))

base_keys <- data.frame(ccfid = c(1001, 1002, 1003, 1004, 1004),
                        dt_surg = as.Date("2020-01-01") + 0:4)
meta <- data.frame(variable = c("ccfid", "dt_surg", "age", "surgeon", "bmi", "dt_dis"),
                   r_class = c("numeric", "Date", "numeric", "character", "numeric", "Date"))
at <- as.POSIXct("2026-09-23 12:00:00", tz = "UTC")
rows <- legacy_rows(f, base_keys, c("ccfid", "dt_surg"), "m", meta, "bd.data.master.sas", at)
check("four facts resolve to one record", nrow(rows$corrections) == 4L)
check("the surgery date is filled from the base",
      rows$corrections$dt_surg[rows$corrections$variable == "age"] == as.Date("2020-01-01"))
check("two surgeries make a fact ambiguous", "ambiguous" %in% rows$unresolved$reason)
check("an absent key is no_record", "no_record" %in% rows$unresolved$reason)
check("the prior is unknown on every legacy row", all(is.na(rows$corrections$expected_prior_missing)))
check("every legacy row is baked", all(rows$decisions$decision == "bake"))
check("evidence points at the file and line",
      all(grepl("^bd\\.data\\.master\\.sas:[0-9]+$", rows$corrections$evidence_ref)))

con <- DBI::dbConnect(duckdb::duckdb())
ddl <- corrections_ddl("corr", "dec", c(ccfid = "DOUBLE", dt_surg = "DATE"),
                       dialect = "duckdb")
DBI::dbExecute(con, ddl[["corrections"]])
DBI::dbExecute(con, ddl[["decisions"]])
r1 <- record_legacy_facts(con, rows, "corr", "dec", dialect = "duckdb")
r2 <- record_legacy_facts(con, rows, "corr", "dec", dialect = "duckdb")
check("first run appends four", r1$appended == 4L)
check("a rerun appends nothing", r2$appended == 0L && r2$already_present == 4L)
DBI::dbDisconnect(con, shutdown = TRUE)
finish()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `Rscript dev/masters/cardiac/test-legacy.R`
Expected: error, `cannot open file '.../legacy.R'`.

- [ ] **Step 3: Implement** `dev/masters/cardiac/legacy.R`:

```r
# legacy.R
#
# The inline patient-level fixes in a master's SAS build, read at run time and
# recorded as corrections with an unknown prior and a 'bake' decision: present
# in the snapshot, activated by the phase 3 port (spec §5.4). Nothing here
# writes a key or a value to a file or to the console.

.LIT <- paste0("('(?:[^']|'')*'d?|\"(?:[^\"]|\"\")*\"d?|",
               "-?(?:\\d+\\.?\\d*|\\.\\d+)(?:e[+-]?\\d+)?|\\.)")
.VAR <- "([a-z_][a-z0-9_]*)"

# A SAS literal as text, with a missing flag; NULL when it cannot be read.
.lit_text <- function(lit) {
  if (lit == ".") return(list(text = NA_character_, missing = 1L))
  if (grepl("^['\"].*['\"]d$", lit, ignore.case = TRUE)) {
    m <- regmatches(lit, regexec("^['\"](\\d{1,2})([a-z]{3})(\\d{4})['\"]d$", lit,
                                 ignore.case = TRUE))[[1]]
    if (!length(m)) return(NULL)
    mon <- match(tolower(m[[3]]), tolower(month.abb))
    if (is.na(mon)) return(NULL)
    d <- as.Date(sprintf("%s-%02d-%02d", m[[4]], mon, as.integer(m[[2]])))
    return(list(text = value_text(d), missing = 0L))
  }
  if (grepl("^['\"]", lit)) {
    q <- substr(lit, 1, 1)
    inner <- gsub(paste0(q, q), q, substr(lit, 2, nchar(lit) - 1), fixed = TRUE)
    if (!nzchar(trimws(inner))) return(list(text = NA_character_, missing = 1L))
    return(list(text = inner, missing = 0L))
  }
  list(text = value_text(as.numeric(lit)), missing = 0L)
}

.statements <- function(lines) {
  text <- paste(lines, collapse = "\n")
  m <- gregexpr("/\\*[\\s\\S]*?\\*/", text, perl = TRUE)
  regmatches(text, m) <- list(gsub("[^\n]", " ", regmatches(text, m)[[1]]))
  pieces <- strsplit(text, ";", fixed = TRUE)[[1]]
  nl <- nchar(gsub("[^\n]", "", pieces))
  lead <- sub("^(\\s*)[\\s\\S]*$", "\\1", pieces, perl = TRUE)
  line <- 1L + c(0L, cumsum(nl)[-length(nl)]) + nchar(gsub("[^\n]", "", lead))
  stmt <- trimws(gsub("\\s+", " ", pieces))
  keep <- nzchar(stmt) & !startsWith(stmt, "*")
  data.frame(line = as.integer(line[keep]), stmt = stmt[keep], stringsAsFactors = FALSE)
}

parse_legacy_facts <- function(lines, key_var = "ccfid") {
  st <- .statements(lines)
  grab <- function(p, s) regmatches(s, regexec(p, s, perl = TRUE, ignore.case = TRUE))[[1]]
  k <- key_var
  p_simple <- paste0("^if\\s*\\(?\\s*", k, "\\s*(?:=|eq)\\s*", .LIT,
                     "\\s*\\)?\\s*then\\s+", .VAR, "\\s*=\\s*", .LIT, "$")
  p_in <- paste0("^if\\s*\\(?\\s*", k, "\\s+in\\s*\\(([^)]*)\\)\\s*\\)?\\s*then\\s+",
                 .VAR, "\\s*=\\s*", .LIT, "$")
  p_do <- paste0("^if\\s*\\(?\\s*", k, "\\s*(?:=|eq)\\s*", .LIT, "\\s*\\)?\\s*then\\s+do$")
  p_assign <- paste0("^", .VAR, "\\s*=\\s*", .LIT, "$")
  p_mentions <- paste0("^if\\b.*\\b", k, "\\b")

  facts <- list()
  unparsed <- integer()
  add <- function(line, key_lit, var, val_lit) {
    kv <- .lit_text(key_lit)
    vv <- .lit_text(val_lit)
    if (is.null(kv) || is.null(vv) || kv$missing == 1L) return(FALSE)
    facts[[length(facts) + 1L]] <<- data.frame(
      line = line, key_value = kv$text, variable = tolower(var),
      value_text = vv$text, value_missing = vv$missing, stringsAsFactors = FALSE)
    TRUE
  }

  i <- 1L
  while (i <= nrow(st)) {
    s <- st$stmt[[i]]
    line <- st$line[[i]]
    if (length(m <- grab(p_simple, s))) {
      if (!add(line, m[[2]], m[[3]], m[[4]])) unparsed <- c(unparsed, line)
    } else if (length(m <- grab(p_in, s))) {
      keys <- regmatches(m[[2]], gregexpr(.LIT, m[[2]], perl = TRUE))[[1]]
      ok <- vapply(keys, function(kl) add(line, kl, m[[3]], m[[4]]), logical(1))
      if (!all(ok)) unparsed <- c(unparsed, line)
    } else if (length(m <- grab(p_do, s))) {
      block <- list()
      good <- TRUE
      i <- i + 1L
      while (i <= nrow(st) && !grepl("^end$", st$stmt[[i]], ignore.case = TRUE)) {
        a <- grab(p_assign, st$stmt[[i]])
        if (length(a)) block[[length(block) + 1L]] <- a else good <- FALSE
        i <- i + 1L
      }
      if (good && length(block)) {
        ok <- vapply(block, function(a) add(line, m[[2]], a[[2]], a[[3]]), logical(1))
        if (!all(ok)) unparsed <- c(unparsed, line)
      } else {
        unparsed <- c(unparsed, line)
      }
    } else if (grepl(p_mentions, s, perl = TRUE, ignore.case = TRUE)) {
      unparsed <- c(unparsed, line)
    }
    i <- i + 1L
  }
  facts <- if (length(facts)) do.call(rbind, facts) else
    data.frame(line = integer(), key_value = character(), variable = character(),
               value_text = character(), value_missing = integer())
  list(facts = facts, unparsed = unique(unparsed))
}

.key_text <- function(x) {
  # Element by element: format() on a vector would pad to a common width.
  if (is.numeric(x)) {
    vapply(x, format, character(1), scientific = FALSE, trim = TRUE, digits = 15)
  } else {
    trimws(as.character(x))
  }
}

legacy_rows <- function(facts, base_keys, key, master, meta, source_file,
                        asserted_on = Sys.time()) {
  kt <- .key_text(base_keys[[key[[1]]]])
  out <- list()
  unresolved <- list()
  for (i in seq_len(nrow(facts))) {
    f <- facts[i, ]
    v <- meta$variable[match(tolower(f$variable), tolower(meta$variable))]
    hits <- which(kt == f$key_value)
    r_class <- if (is.na(v)) NA_character_ else meta$r_class[match(v, meta$variable)]
    casts <- !is.na(v) && (f$value_missing == 1L ||
                             !is.na(parse_value(f$value_text, r_class)))
    reason <- if (is.na(v)) "no_variable" else if (v %in% key) "key_variable" else
      if (!length(hits)) "no_record" else if (length(hits) > 1L) "ambiguous" else
        if (!casts) "does_not_cast" else NULL
    if (!is.null(reason)) {
      unresolved[[length(unresolved) + 1L]] <- data.frame(line = f$line, reason = reason)
      next
    }
    id <- paste0("L", substr(digest::digest(list(master, source_file, f$line, i),
                                            algo = "sha1"), 1, 15))
    out[[length(out) + 1L]] <- cbind(
      data.frame(correction_id = id, master = master, stringsAsFactors = FALSE),
      base_keys[hits, key, drop = FALSE],
      data.frame(variable = v, expected_prior = NA_character_,
                 expected_prior_missing = NA_integer_, new_value = f$value_text,
                 new_value_missing = f$value_missing, evidence_type = "legacy_sas_inline",
                 evidence_ref = paste0(source_file, ":", f$line),
                 asserted_by = "unknown (legacy)", asserted_on = asserted_on,
                 stringsAsFactors = FALSE))
  }
  corrections <- if (length(out)) do.call(rbind, out) else NULL
  if (!is.null(corrections)) rownames(corrections) <- NULL
  decisions <- if (is.null(corrections)) NULL else data.frame(
    decision_id = paste0("D", substr(vapply(corrections$correction_id, digest::digest,
                                            character(1), algo = "sha1"), 1, 15)),
    correction_id = corrections$correction_id, decision = "bake",
    decided_by = "legacy backfill", decided_on = asserted_on,
    reason = "Present in the snapshot; activated by the phase 3 port.",
    stringsAsFactors = FALSE)
  unresolved <- if (length(unresolved)) do.call(rbind, unresolved) else
    data.frame(line = integer(), reason = character())
  list(corrections = corrections, decisions = decisions, unresolved = unresolved)
}

record_legacy_facts <- function(con, rows, corrections_table, decisions_table,
                                dialect = "mssql") {
  q <- quoter(dialect)
  if (is.null(rows$corrections)) return(list(appended = 0L, already_present = 0L))
  have <- DBI::dbGetQuery(con, sprintf(
    "SELECT correction_id FROM %s WHERE evidence_type = 'legacy_sas_inline'",
    q(corrections_table)))$correction_id
  new <- !rows$corrections$correction_id %in% have
  if (any(new)) {
    DBI::dbWithTransaction(con, {
      DBI::dbAppendTable(con, corrections_table, rows$corrections[new, , drop = FALSE])
      DBI::dbAppendTable(con, decisions_table,
                         rows$decisions[rows$decisions$correction_id %in%
                                          rows$corrections$correction_id[new], ,
                                        drop = FALSE])
    })
  }
  list(appended = sum(new), already_present = sum(!new))
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `Rscript dev/masters/cardiac/test-legacy.R`
Expected: `all checks passed`.

- [ ] **Step 5: Commit**

```bash
git add dev/masters/cardiac/legacy.R dev/masters/cardiac/test-legacy.R
git commit -m "feat: read a master's inline SAS fixes and record them as baked corrections"
```

---

### Task 10: Runbooks

Thin orchestration over Tasks 2 to 9. They touch real data, so they are not unit-tested;
each prints counts and verdicts only, and each is dry by default where a write is involved.

**Files:**
- Create: `dev/masters/cardiac/run-phase0.R`
- Create: `dev/masters/cardiac/batch-snapshots.R`
- Create: `dev/masters/cardiac/run-phase1.R`
- Create: `dev/masters/cardiac/run-phase2.R`

**Interfaces:**
- Consumes: everything above, exactly as named in each task's Produces block.

- [ ] **Step 1: Write** `dev/masters/cardiac/run-phase0.R`:

```r
#!/usr/bin/env Rscript
# run-phase0.R: snapshot one master build and test its candidate keys.
#
#   Rscript run-phase0.R <sas_path> <out_dir> <n_rows> <n_cols> <keys> [chunk_rows]
#
# <n_rows> and <n_cols> are read by hand from the build's .log. <keys> is a
# semicolon-separated list of comma-separated key columns; prefix a candidate
# with '?' to test it on non-null rows only, e.g.
#   "ccfid,dt_surg;ccfidu;?emrn,dt_enc"
# Prints shape, checksums and key verdicts. No key or value is printed.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "key-verdict.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 5L) stop("usage: run-phase0.R <sas> <out_dir> <n_rows> <n_cols> <keys>")
chunk <- if (length(args) >= 6L) as.numeric(args[[6]]) else 1e5
out <- file.path(args[[2]], sub("\\.sas7bdat$", ".parquet", basename(args[[1]])))

info <- hvtiRdatabuild::snapshot_oracle(
  args[[1]], out, chunk_rows = chunk,
  expect = list(n_rows = as.numeric(args[[3]]), n_cols = as.numeric(args[[4]])))
message("snapshot  ", info$n_rows, " rows x ", info$n_cols, " columns")
message("parquet   sha256 ", info$sha256)
message("source    sha256 ", info$source_sha256)
message("sidecar   ", info$meta_path)

for (cand in strsplit(args[[5]], ";", fixed = TRUE)[[1]]) {
  nonnull <- startsWith(cand, "?")
  cols <- strsplit(sub("^\\?", "", cand), ",", fixed = TRUE)[[1]]
  message(format_key_verdict(key_verdict(out, cols, nonnull_only = nonnull)))
}
```

- [ ] **Step 2: Write** `dev/masters/cardiac/batch-snapshots.R`:

```r
#!/usr/bin/env Rscript
# batch-snapshots.R: snapshot every dated build in a folder, resumably.
#
#   Rscript batch-snapshots.R <snapshot_dir> <out_dir> [chunk_rows]
#
# Skips a build whose parquet already exists. Historical builds have no retained
# log, so their shape is recorded, not validated (spec §4.2). Appends one row per
# build to <out_dir>/batch-log.csv, then reports whether the undated
# built.sas7bdat matches a dated build's source checksum. Run on the scan host.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) stop("usage: batch-snapshots.R <snapshot_dir> <out_dir> [chunk_rows]")
chunk <- if (length(args) >= 3L) as.numeric(args[[3]]) else 1e5
log_path <- file.path(args[[2]], "batch-log.csv")
files <- sort(list.files(args[[1]], pattern = "^built_.*\\.sas7bdat$", full.names = TRUE))

for (f in files) {
  out <- file.path(args[[2]], sub("\\.sas7bdat$", ".parquet", basename(f)))
  if (file.exists(out)) {
    message("skip  ", basename(f))
    next
  }
  row <- tryCatch({
    info <- hvtiRdatabuild::snapshot_oracle(f, out, chunk_rows = chunk)
    data.frame(file = basename(f), n_rows = info$n_rows, n_cols = info$n_cols,
               sha256 = info$sha256, source_sha256 = info$source_sha256, status = "ok")
  }, error = function(e) {
    message("FAIL  ", basename(f), ": ", conditionMessage(e))
    data.frame(file = basename(f), n_rows = NA, n_cols = NA, sha256 = NA,
               source_sha256 = NA, status = "failed")
  })
  row$finished <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  utils::write.table(row, log_path, sep = ",", row.names = FALSE,
                     col.names = !file.exists(log_path), append = file.exists(log_path))
  message(row$status, "    ", basename(f), "  ", row$n_rows, " x ", row$n_cols)
}

undated <- file.path(args[[1]], "built.sas7bdat")
if (file.exists(undated) && file.exists(log_path)) {
  sha <- digest::digest(undated, algo = "sha256", file = TRUE)
  log <- utils::read.csv(log_path, stringsAsFactors = FALSE)
  hit <- log$file[log$source_sha256 %in% sha]
  message("built.sas7bdat ", if (length(hit)) paste("is a copy of", hit[[1]]) else
    "matches no dated build")
}
```

- [ ] **Step 3: Write** `dev/masters/cardiac/run-phase1.R`:

```r
#!/usr/bin/env Rscript
# run-phase1.R: DDL, load, parity, and the master view.
#
#   Rscript run-phase1.R <parquet> <base_table> <view> <key> <server> <database> \
#     [dsn] [--execute]
#
# <key> is comma-separated, e.g. "ccfid,dt_surg". Without --execute it writes
# the DDL to <parquet>.ddl.sql for a hand-off and stops. With --execute it runs
# the DDL, loads, checks parity, and creates the view only if parity passes.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
for (f in c("ddl.R", "load.R", "sql-common.R", "parity.R")) source(file.path(here, f))

args <- commandArgs(trailingOnly = TRUE)
execute <- "--execute" %in% args
args <- setdiff(args, "--execute")
if (length(args) < 6L) stop("usage: run-phase1.R <parquet> <base> <view> <key> <server> <db>")
parquet <- args[[1]]
base <- args[[2]]
view <- args[[3]]
key <- strsplit(args[[4]], ",", fixed = TRUE)[[1]]

ddl <- master_ddl(parquet, base)
message("ddl  ", ddl$n_cols, " columns, fixed-width row ", ddl$row_bytes, " bytes")
if (!execute) {
  writeLines(ddl$sql, paste0(parquet, ".ddl.sql"))
  message("dry run: DDL written to ", paste0(parquet, ".ddl.sql"), "; rerun with --execute")
  quit(save = "no", status = 0)
}

con <- hvtiRdatabuild::dw_connect(server = args[[5]], database = args[[6]],
                                  dsn = if (length(args) >= 7L) args[[7]] else NULL)
on.exit(DBI::dbDisconnect(con), add = TRUE)
if (!DBI::dbExistsTable(con, base)) DBI::dbExecute(con, ddl$sql)

r <- load_parquet(con, parquet, base)
message("load  ", r$loaded, " row groups loaded, ", r$skipped, " already present, of ",
        r$row_groups)

res <- parity_check(con, base, parquet, key)
message(parity_summary(res))
if (res$verdict != "pass") {
  message("mismatched columns: ",
          paste(res$columns$variable[res$columns$verdict == "mismatch"], collapse = ", "))
  stop("Parity failed; the view was not created.", call. = FALSE)
}

meta <- jsonlite::read_json(sub("\\.parquet$", ".meta.json", parquet),
                            simplifyVector = TRUE)$columns
DBI::dbWriteTable(con, paste0(view, "_meta"), meta, overwrite = TRUE)
q <- quoter("mssql")
DBI::dbExecute(con, sprintf("CREATE OR ALTER VIEW %s AS SELECT * FROM %s;", q(view), q(base)))
message("view  ", view, " -> ", base)
```

- [ ] **Step 4: Write** `dev/masters/cardiac/run-phase2.R`:

```r
#!/usr/bin/env Rscript
# run-phase2.R: corrections tables, legacy facts as 'bake', corrections view.
#
#   Rscript run-phase2.R <meta_json> <base_table> <view> <key> <build_sas> \
#     <server> <database> [dsn] [--execute]
#
# The legacy facts are read from <build_sas> here and written only to the
# warehouse, so this step needs write access and has no file hand-off. Without
# --execute it parses and resolves, prints counts, and writes nothing.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
for (f in c("sql-common.R", "value-text.R", "corrections.R", "legacy.R")) {
  source(file.path(here, f))
}

args <- commandArgs(trailingOnly = TRUE)
execute <- "--execute" %in% args
args <- setdiff(args, "--execute")
if (length(args) < 7L) stop("usage: run-phase2.R <meta> <base> <view> <key> <sas> <server> <db>")
meta <- jsonlite::read_json(args[[1]], simplifyVector = TRUE)$columns
base <- args[[2]]
view <- args[[3]]
key <- strsplit(args[[4]], ",", fixed = TRUE)[[1]]
corr_t <- paste0(view, "_corrections")
dec_t <- paste0(view, "_correction_decisions")
stale_v <- paste0(view, "_corrections_stale")

con <- hvtiRdatabuild::dw_connect(server = args[[6]], database = args[[7]],
                                  dsn = if (length(args) >= 8L) args[[8]] else NULL)
on.exit(DBI::dbDisconnect(con), add = TRUE)
q <- quoter("mssql")
types <- table_types(con, base)

parsed <- parse_legacy_facts(readLines(args[[5]], warn = FALSE), key_var = key[[1]])
base_keys <- DBI::dbGetQuery(con, sprintf("SELECT %s FROM %s",
                                          paste(q(key), collapse = ", "), q(base)))
rows <- legacy_rows(parsed$facts, base_keys, key, view, meta, basename(args[[5]]))
message("legacy  ", nrow(parsed$facts), " facts parsed; ",
        NROW(rows$corrections), " resolved; ", nrow(rows$unresolved), " unresolved")
if (nrow(rows$unresolved)) {
  tab <- table(rows$unresolved$reason)
  message("  unresolved by reason: ", paste(names(tab), tab, sep = " ", collapse = ", "))
  message("  at lines: ", paste(sort(unique(rows$unresolved$line)), collapse = ", "))
}
if (length(parsed$unparsed)) {
  message("  unparsed statements at lines: ", paste(parsed$unparsed, collapse = ", "))
}
if (!execute) {
  message("dry run: nothing written; rerun with --execute")
  quit(save = "no", status = 0)
}

if (!DBI::dbExistsTable(con, corr_t)) {
  ddl <- corrections_ddl(corr_t, dec_t, key_types = types[key])
  DBI::dbExecute(con, ddl[["corrections"]])
  DBI::dbExecute(con, ddl[["decisions"]])
}
r <- record_legacy_facts(con, rows, corr_t, dec_t)
message("record  ", r$appended, " appended, ", r$already_present, " already present")

corrected <- corrected_variables(con, corr_t, view)
DBI::dbExecute(con, corrections_view_sql(view, base, corr_t, dec_t, view, key,
                                         names(types), corrected, types))
DBI::dbExecute(con, stale_view_sql(stale_v, base, corr_t, dec_t, view, key,
                                   names(types), corrected, types))
n_stale <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s", q(stale_v)))$n
message("views   ", view, " regenerated over ", length(corrected),
        " corrected variables; ", n_stale, " stale corrections")
```

- [ ] **Step 5: Syntax-check all four**

Run: `for f in dev/masters/cardiac/run-phase*.R dev/masters/cardiac/batch-snapshots.R; do Rscript -e "invisible(parse('$f'))" && echo "ok $f"; done`
Expected: four `ok` lines.

- [ ] **Step 6: Commit**

```bash
git add dev/masters/cardiac/run-phase0.R dev/masters/cardiac/batch-snapshots.R \
  dev/masters/cardiac/run-phase1.R dev/masters/cardiac/run-phase2.R
git commit -m "feat: runbooks for phases 0 to 2, dry by default and printing verdicts only"
```

---

### Task 11: Final verification

- [ ] **Step 1: All script tests**

Run: `for f in dev/masters/cardiac/test-*.R; do Rscript "$f" || break; done`
Expected: each ends `all checks passed`; no `SKIP`. A `SKIP` is a failure to verify, not
a pass: install what it names and rerun.

- [ ] **Step 2: Package tests, check and lint**

Run: `Rscript -e 'devtools::test(); devtools::check(args = "--no-manual", vignettes = FALSE); print(lintr::lint_package())'`
Expected: tests pass; check 0/0/0; no lints.

- [ ] **Step 3: PHI sweep of the diff**

Run: `git diff origin/main --stat && git diff origin/main | grep -n -i -E "qhsstudies|/Volumes/|saslpass" || echo "clean"`
Expected: `clean`. Read the diff's test data once more: every id must be an invented
`K`, `A` or four-digit test value.

- [ ] **Step 4: Push**

```bash
git push
```

Expected: PR #63 updates. The real-data runs (phase 0 on `built_2026mar27`, then phases
1 and 2) are the maintainer's to run, with the runbooks, against data that never enters
this repository.
