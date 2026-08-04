# hvtiRdatasets S0 (Verify) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the equivalence ruler — convert a SAS-built dataset into a checksummed parquet oracle, and report per-variable whether an R rebuild matches it.

**Architecture:** Two public functions plus a migration vignette. `snapshot_oracle()` reads a SAS dataset once via `haven`, writes parquet via `arrow`, and records a SHA-256 checksum through `hvtiRutilities::update_manifest()`. `compare_built()` joins an R data frame to the oracle on a study identifier and classifies every variable into one of six verdicts, returning a table and deliberately never a scalar pass/fail. No database, no SAS, no PHI anywhere in this slice.

**Tech Stack:** R (>= 4.1.0), haven, arrow (Suggests), digest, dplyr, testthat edition 3, quarto vignettes, roxygen2.

**Spec:** `specs/2026-08-04-hvtiRdatasets-design.md`

## Global Constraints

- Package version starts at `0.0.0.9000`. Bump the patch/dev digit only; never the minor or major.
- `R (>= 4.1.0)` in `Depends`. Licence `GPL (>= 3)`. Maintainer `John Ehrlinger <john.ehrlinger@gmail.com>`.
- `arrow` is in **Suggests**, not Imports. Every use is guarded by `requireNamespace("arrow", quietly = TRUE)`; every test touching it calls `skip_if_not_installed("arrow")`.
- `testthat` edition 3 (`Config/testthat/edition: 3`).
- Vignettes are `.qmd` with `VignetteBuilder: quarto`, matching `hvtiRutilities`.
- Every exported object has a roxygen `@return`. Examples that are slow or need optional packages use `\donttest{}` and `requireNamespace()` guards.
- Maximum 2 cores anywhere.
- **No PHI in any fixture, test, or vignette.** All data is synthetic.
- **No credential value in any file, log line, error message, or commit.**
- **Plain `R CMD check` must finish 0 errors / 0 warnings / 0 notes** before each commit that touches package code. **Not `--as-cran`:** that flag runs CRAN incoming feasibility, which emits an unavoidable "New submission" NOTE for any package never published to CRAN, plus notes on the `.9000` version component and not-yet-public URLs. `hvtiRdatasets` is not a CRAN target (see the spec), so `--as-cran` sets a gate no task can pass. It is still required at release time, per the group's release gate.
- **Add a package to `Imports` in the same task that first uses it, never earlier.** `R CMD check` notes any declared import that no code uses, so a speculative dependency list breaks the 0/0/0 gate. See Task 1.
- Work happens on branch `feat/s0-verify`. Never commit to `main`.
- **This package never writes SAS files.** `snapshot_oracle()` reads SAS and writes parquet; nothing else touches a SAS format. `haven::write_sas()` is deprecated as of haven 2.5.2 and is called exactly once, by a manual `data-raw/` script, to generate the committed test fixture. **No haven writer runs in the test suite.**
- Only `.sas7bdat` is supported. The oracle is `library.built`. The `.xpt` files on disk are output of `tp.bd.SAStoR.sas`, the bridge this package replaces, and are not an input.
- **Development is on macOS; execution is on the SAS server.** No task in this slice touches a database. When S1 arrives, warehouse connections are mocked in tests and real pulls run on the server, never on a laptop.

---

### Task 1: Package scaffold

**Files:**
- Create: `DESCRIPTION`
- Create: `LICENSE.md`
- Create: `.Rbuildignore`
- Create: `R/hvtiRdatasets-package.R`
- Create: `tests/testthat.R`
- Create: `tests/testthat/test-package.R`

**Interfaces:**
- Consumes: nothing.
- Produces: an installable package named `hvtiRdatasets` that `R CMD check` passes at 0/0/0.

- [ ] **Step 1: Write `DESCRIPTION`**

```
Package: hvtiRdatasets
Type: Package
Title: Build and Verify Analytic Datasets for the HVTI CORR Group
Version: 0.0.0.9000
Date: 2026-08-04
Authors@R: c(
    person(
      "John", "Ehrlinger",
      email = "ehrlinj@ccf.org",
      role = c("aut", "cre")
    )
  )
License: GPL (>= 3)
Encoding: UTF-8
URL: https://github.com/ehrlinger/hvtiRdatasets
BugReports: https://github.com/ehrlinger/hvtiRdatasets/issues
Description: Builds analysis-ready clinical datasets for the clinical
  investigations statistics group within The Heart and Vascular Institute at
  the Cleveland Clinic, and verifies them against the legacy 'SAS' datasets
  they replace.
Depends:
    R (>= 4.1.0)
Suggests:
    arrow,
    knitr,
    quarto,
    testthat (>= 3.0.0),
    withr
Config/testthat/edition: 3
```

**No `Maintainer:` field.** When `Authors@R` is present, R derives the
maintainer from the `cre` role. Declaring both — with different addresses, as
`hvtiRutilities` does — produces a `checking DESCRIPTION meta-information`
NOTE. The `cre` address in `Authors@R` is the maintainer.

**No `VignetteBuilder:` field yet.** Declaring it with no vignettes present
notes. Task 9 adds it along with the first vignette, consistent with the
per-task dependency rule below.

**Task 1 declares no `Imports`, deliberately.** `R CMD check` emits
`Namespaces in Imports field not imported from: ...` for any declared import
that no code uses, and Task 1 contains no R code at all. Declaring the full
dependency list here would make the 0/0/0 gate unreachable on the very first
task. Each later task adds the package it actually uses:

| Task | Adds to `Imports` |
|---|---|
| 3 | `haven`, `tools` |
| 4 | `digest`, `hvtiRutilities` |
| 8 | `utils` |

`RoxygenNote` is omitted; `roxygen2::roxygenise()` writes it in Step 7 with
whatever version is installed. Do not hand-set it.

- [ ] **Step 2: Write `.Rbuildignore`**

```
^.*\.Rproj$
^\.Rproj\.user$
^\.github$
^specs$
^LICENSE\.md$
^data-raw$
^\.vscode$
```

- [ ] **Step 3: Write `R/hvtiRdatasets-package.R`**

```r
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
## usethis namespace: end
NULL
```

- [ ] **Step 4: Write `LICENSE.md`**

Copy the GPL-3 text from `../hvtiRutilities/LICENSE.md` verbatim:

```bash
cp ../hvtiRutilities/LICENSE.md LICENSE.md
```

- [ ] **Step 5: Write `tests/testthat.R`**

```r
library(testthat)
library(hvtiRdatasets)

test_check("hvtiRdatasets")
```

- [ ] **Step 6: Write a smoke test at `tests/testthat/test-package.R`**

```r
test_that("package loads and declares its dependencies", {
  expect_true(requireNamespace("hvtiRdatasets", quietly = TRUE))
  expect_true(requireNamespace("hvtiRutilities", quietly = TRUE))
})
```

- [ ] **Step 7: Generate `NAMESPACE` and run check**

Run:
```bash
Rscript -e 'roxygen2::roxygenise()'
R CMD build . && R CMD check hvtiRdatasets_0.0.0.9000.tar.gz
```
Expected: `Status: OK`, 0 errors / 0 warnings / 0 notes.

- [ ] **Step 8: Commit**

```bash
git add DESCRIPTION NAMESPACE LICENSE.md .Rbuildignore R/ tests/
git commit -m "feat: package scaffold for hvtiRdatasets"
```

---

### Task 2: Synthetic oracle fixtures

**Files:**
- Create: `data-raw/make_fixtures.R`
- Create: `inst/extdata/oracle_small.sas7bdat` (generated once, committed)
- Create: `tests/testthat/helper-fixtures.R`

**Interfaces:**
- Consumes: nothing.
- Produces: `.fixture_frame()` returning the canonical synthetic data frame used by every later test; a committed `oracle_small.sas7bdat` reachable via `system.file("extdata", "oracle_small.sas7bdat", package = "hvtiRdatasets")`.

The fixture carries a character id, a plain numeric, a labelled numeric, a `Date`, a character column, and `NA` in each.

**Known limitation — two comparison paths cannot be exercised through a SAS file, and this is a property of SAS, not of the fixture.** Verified by reading the committed fixture back:

| Written | Reads back as |
|---|---|
| `"Jones "` | `"Jones"` — trailing blank stripped |
| `NA_character_` | `""` — empty string, **not** `NA` |
| `NA_real_` | `NA` — numeric missing survives |

**SAS has no character `NA`. Missing character *is* the empty string.** This is load-bearing for Task 5: on a real study, every missing character value in the oracle reads as `""` while the R rebuild holds `NA`. Compared naively, every character column containing any missing value reports `differs` — false positives in bulk, drowning real findings. `.as_comparable()` must therefore treat `""` and `NA` as the same value for character columns.

Trailing-blank and character-`NA` behaviour must be tested with in-memory vectors in Task 5, never through this fixture, because the fixture physically cannot carry them.

It lives in `inst/extdata/` rather than `tests/testthat/fixtures/` so that roxygen examples can reach it too, not only tests.

**Known limitation, recorded deliberately.** A fixture written by haven's writer proves this package's logic, not haven's ability to read files that real SAS produced. Real `library.built` files carry compression, formats, and legacy encodings this fixture does not — a class of problem that has already bitten this codebase once (Latin-1, `hvtiRutilities@183a1cb`). The first run of `snapshot_oracle()` against an actual `library.built` is the real proof, and it is a task in S2, not here.

- [ ] **Step 1: Write `data-raw/make_fixtures.R`**

```r
# Generates inst/extdata/oracle_small.sas7bdat.
#
# Run manually, never at test time. haven::write_sas() is deprecated
# (haven 2.5.2); this is the only place in the project that calls it, and
# the resulting binary is committed so no test ever needs a SAS writer.
#
# Usage: Rscript data-raw/make_fixtures.R

source(file.path("tests", "testthat", "helper-fixtures.R"))

d <- .fixture_frame()
dir.create(file.path("inst", "extdata"), showWarnings = FALSE, recursive = TRUE)
target <- file.path("inst", "extdata", "oracle_small.sas7bdat")
suppressWarnings(haven::write_sas(d, target))

# Fail loudly if the writer was not faithful.
back <- haven::read_sas(target)
stopifnot(
  nrow(back) == nrow(d),
  ncol(back) == ncol(d),
  isTRUE(all.equal(as.numeric(back$age), d$age))
)
cat("wrote", target, "with", nrow(d), "rows\n")
```

- [ ] **Step 2: Write `tests/testthat/helper-fixtures.R`**

```r
# Canonical synthetic fixture. No PHI: ids and values are invented.
.fixture_frame <- function() {
  d <- data.frame(
    ccfidu   = c("A001", "A002", "A003", "A004"),
    age      = c(65.5, 70.25, 58.0, NA),
    bmi      = c(31.2, NA, 22.8, 27.4),
    dt_surg  = as.Date(c("2020-01-15", "2021-06-30", NA, "2019-11-02")),
    surgeon  = c("Smith", "Jones ", "Smith", NA),
    stringsAsFactors = FALSE
  )
  attr(d$age, "label") <- "Age at surgery"
  attr(d$bmi, "label") <- "Body mass index"
  d
}
```

- [ ] **Step 3: Generate the fixture**

Run:
```bash
Rscript data-raw/make_fixtures.R
```
Expected: `wrote inst/extdata/oracle_small.sas7bdat with 4 rows`

- [ ] **Step 4: Verify the committed fixture reads back faithfully**

Run:
```bash
Rscript -e 'x <- haven::read_sas("inst/extdata/oracle_small.sas7bdat"); str(x); stopifnot(nrow(x) == 4L, ncol(x) == 5L)'
```
Expected: 4 obs. of 5 variables, no error.

- [ ] **Step 5: Add a test helper that locates the fixture**

Append to `tests/testthat/helper-fixtures.R`:

```r
# Resolves whether the package is loaded via pkgload (devtools::test) or
# installed (R CMD check).
.fixture_path <- function() {
  system.file("extdata", "oracle_small.sas7bdat", package = "hvtiRdatasets")
}
```

- [ ] **Step 6: Commit**

```bash
git add data-raw/ tests/testthat/helper-fixtures.R inst/
git commit -m "test: synthetic oracle fixture, no PHI, no test-time SAS writer"
```

---

### Task 3: `.read_sas_dataset()` — the SAS reader

**Files:**
- Create: `R/read_sas_dataset.R`
- Test: `tests/testthat/test-read_sas_dataset.R`

**Interfaces:**
- Consumes: `.fixture_frame()` and `.fixture_path()` from Task 2.
- Produces: `.read_sas_dataset(path)` → `data.frame`. Internal, not exported. Reads `.sas7bdat` via `haven::read_sas()`. Errors on any other extension and on a missing file.

Only `.sas7bdat` is supported. The oracle is `library.built`. `.xpt` files exist on disk, but they are the output of `tp.bd.SAStoR.sas` — the bridge this package replaces — not an input to it. Adding a branch is three lines if a real `.xpt` oracle ever appears.

- [ ] **Step 1: Write the failing test**

```r
test_that(".read_sas_dataset reads a sas7bdat faithfully", {
  expected <- .fixture_frame()
  got <- .read_sas_dataset(.fixture_path())

  expect_s3_class(got, "data.frame")
  expect_equal(nrow(got), 4L)
  # Strip both sides: expected$age carries a "label" attribute and
  # expect_equal() compares attributes, so comparing a stripped vector
  # against a labelled one fails on the attribute rather than the values.
  # Do NOT "fix" this by removing the labels from .fixture_frame() -- the
  # labelled numeric is the case .cmp_class() exists to collapse in Task 5.
  expect_equal(as.numeric(got$age), as.numeric(expected$age))
  expect_equal(as.character(got$ccfidu), as.character(expected$ccfidu))
})

test_that(".read_sas_dataset rejects unknown extensions and missing files", {
  bad <- withr::local_tempfile(fileext = ".csv")
  writeLines("a,b", bad)
  expect_error(.read_sas_dataset(bad), "Unsupported")

  expect_error(.read_sas_dataset("no/such/file.sas7bdat"), "does not exist")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "read_sas_dataset")'`
Expected: FAIL with `could not find function ".read_sas_dataset"`

- [ ] **Step 3: Write the implementation**

```r
#' Read a SAS dataset
#'
#' Internal reader used by [snapshot_oracle()]. Reads the `.sas7bdat` files a
#' SAS `libname` writes. This is the only point in the package where a SAS
#' format is touched, and it is read-only: nothing here ever writes SAS.
#'
#' @param path Path to a `.sas7bdat` file.
#'
#' @return A data frame.
#'
#' @keywords internal
#' @noRd
.read_sas_dataset <- function(path) {
  if (!file.exists(path)) {
    stop("SAS dataset does not exist: ", path, call. = FALSE)
  }
  ext <- tolower(tools::file_ext(path))
  if (!identical(ext, "sas7bdat")) {
    stop("Unsupported SAS dataset extension '.", ext,
         "'. Expected '.sas7bdat'.", call. = FALSE)
  }
  as.data.frame(haven::read_sas(path))
}
```

Add `tools` to `Imports` in `DESCRIPTION`.

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e 'devtools::test(filter = "read_sas_dataset")'`
Expected: `[ FAIL 0 | PASS 6 ]`

- [ ] **Step 5: Commit**

```bash
git add R/read_sas_dataset.R tests/testthat/test-read_sas_dataset.R DESCRIPTION
git commit -m "feat: .read_sas_dataset() dispatches on sas7bdat and xpt"
```

---

### Task 4: `snapshot_oracle()` — convert and checksum

**Files:**
- Create: `R/snapshot_oracle.R`
- Test: `tests/testthat/test-snapshot_oracle.R`

**Interfaces:**
- Consumes: `.read_sas_dataset()` from Task 3; `hvtiRutilities::update_manifest()`.
- Produces: `snapshot_oracle(sas_path, out_path, expect = NULL, manifest = NULL)` → invisibly, a list with `path`, `n_rows`, `n_cols`, `variables`, `sha256`. Exported.

Recording the snapshot in a manifest is what makes the checksum useful. The spec requires that "an oracle whose recorded checksum does not match the file on disk is an error"; wiring `snapshot_oracle()` to `hvtiRutilities::update_manifest()` means `hvtiRutilities::verify_manifest()` provides that check without new code.

- [ ] **Step 1: Write the failing test**

```r
test_that("snapshot_oracle writes parquet and reports a stable checksum", {
  skip_if_not_installed("arrow")

  out <- withr::local_tempfile(fileext = ".parquet")
  res <- snapshot_oracle(
    .fixture_path(),
    out
  )

  expect_true(file.exists(out))
  expect_equal(res$n_rows, 4L)
  expect_equal(res$n_cols, 5L)
  expect_setequal(res$variables,
                  c("ccfidu", "age", "bmi", "dt_surg", "surgeon"))
  expect_match(res$sha256, "^[0-9a-f]{64}$")

  # Idempotent: same input yields the same checksum.
  out2 <- withr::local_tempfile(fileext = ".parquet")
  res2 <- snapshot_oracle(
    .fixture_path(),
    out2
  )
  expect_equal(res$sha256, res2$sha256)
})

test_that("snapshot_oracle round-trips variable labels", {
  skip_if_not_installed("arrow")

  out <- withr::local_tempfile(fileext = ".parquet")
  snapshot_oracle(
    .fixture_path(),
    out
  )
  back <- as.data.frame(arrow::read_parquet(out))
  expect_equal(attr(back$age, "label"), "Age at surgery")
})

test_that("snapshot_oracle refuses to overwrite silently", {
  skip_if_not_installed("arrow")

  out <- withr::local_tempfile(fileext = ".parquet")
  writeLines("x", out)
  expect_error(
    snapshot_oracle(
      .fixture_path(),
      out
    ),
    "already exists"
  )
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "snapshot_oracle")'`
Expected: FAIL with `could not find function "snapshot_oracle"`

- [ ] **Step 3: Write the implementation**

```r
#' Freeze a SAS-built dataset as a checksummed parquet oracle
#'
#' Reads a SAS dataset once with \pkg{haven}, writes it as parquet, and
#' returns a record of what was written including a SHA-256 checksum of the
#' parquet file.
#'
#' The snapshot exists so that equivalence testing has a fixed reference. A
#' SAS-built dataset on a shared volume can be regenerated at any time; if it
#' changes mid-migration, every previously passing comparison silently becomes
#' meaningless. A checksummed snapshot is a citable fixed point.
#'
#' Note that this does not remove \pkg{haven} from the chain of custody — it
#' confines it to a single audited step. A misread is faithfully preserved in
#' the parquet file. Supply `expect` to validate the conversion against
#' SAS-side `PROC CONTENTS` output.
#'
#' @param sas_path Path to the SAS dataset (`.sas7bdat`).
#' @param out_path Path to write the parquet file. Must not already exist.
#' @param expect Optional named list validating the conversion, with any of
#'   `n_rows`, `n_cols`, and `variables`. Supply values read from SAS-side
#'   `PROC CONTENTS`. A mismatch is an error.
#' @param manifest Optional path to a manifest YAML. When supplied, the
#'   snapshot is recorded with [hvtiRutilities::update_manifest()] so that
#'   [hvtiRutilities::verify_manifest()] can later detect a drifted oracle.
#'
#' @return Invisibly, a list with elements `path`, `n_rows`, `n_cols`,
#'   `variables`, and `sha256`.
#'
#' @seealso [compare_built()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("arrow", quietly = TRUE)) {
#'   src <- system.file("extdata", "oracle_small.sas7bdat",
#'                      package = "hvtiRdatasets")
#'   snapshot_oracle(src, tempfile(fileext = ".parquet"))
#' }
#' }
#'
#' @export
snapshot_oracle <- function(sas_path, out_path, expect = NULL,
                            manifest = NULL) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("Package 'arrow' is required to write oracle snapshots. ",
         "Install it with install.packages('arrow').", call. = FALSE)
  }
  if (file.exists(out_path)) {
    stop("Oracle snapshot already exists: ", out_path,
         ". Refusing to overwrite; delete it explicitly if that is intended.",
         call. = FALSE)
  }

  d <- .read_sas_dataset(sas_path)

  info <- list(
    path      = out_path,
    n_rows    = nrow(d),
    n_cols    = ncol(d),
    variables = names(d)
  )

  .validate_snapshot(info, expect)

  arrow::write_parquet(d, out_path)
  info$sha256 <- digest::digest(out_path, algo = "sha256", file = TRUE)

  if (!is.null(manifest)) {
    # n_rows is passed explicitly: hvtiRutilities:::.auto_count_rows() refuses
    # to guess row counts for a '.parquet', and that refusal is correct.
    hvtiRutilities::update_manifest(
      file          = out_path,
      manifest_path = manifest,
      n_rows        = info$n_rows,
      source        = paste0("Oracle snapshot of ", basename(sas_path))
    )
  }

  invisible(info)
}
```

- [ ] **Step 4: Write the validator in the same file**

```r
#' Validate a snapshot against SAS-side PROC CONTENTS
#'
#' @param info List produced by [snapshot_oracle()].
#' @param expect Optional named list; see [snapshot_oracle()].
#'
#' @return `NULL`, invisibly. Called for the error it raises.
#'
#' @keywords internal
#' @noRd
.validate_snapshot <- function(info, expect) {
  if (is.null(expect)) {
    return(invisible(NULL))
  }
  known <- c("n_rows", "n_cols", "variables")
  unknown <- setdiff(names(expect), known)
  if (length(unknown)) {
    stop("Unknown 'expect' element(s): ", paste(unknown, collapse = ", "),
         ". Expected any of: ", paste(known, collapse = ", "), call. = FALSE)
  }

  for (k in c("n_rows", "n_cols")) {
    if (!is.null(expect[[k]]) && !identical(as.integer(expect[[k]]),
                                            as.integer(info[[k]]))) {
      stop("Snapshot validation failed: ", k, " is ", info[[k]],
           " but SAS reported ", expect[[k]], ".", call. = FALSE)
    }
  }

  if (!is.null(expect$variables)) {
    missing_r  <- setdiff(expect$variables, info$variables)
    missing_sas <- setdiff(info$variables, expect$variables)
    if (length(missing_r) || length(missing_sas)) {
      stop("Snapshot validation failed: variable sets differ. ",
           "In SAS but not snapshot: ",
           if (length(missing_r)) paste(missing_r, collapse = ", ") else "none",
           ". In snapshot but not SAS: ",
           if (length(missing_sas)) paste(missing_sas, collapse = ", ") else "none",
           ".", call. = FALSE)
    }
  }

  invisible(NULL)
}
```

- [ ] **Step 5: Add the validator test**

```r
test_that("snapshot_oracle validates against PROC CONTENTS expectations", {
  skip_if_not_installed("arrow")
  src <- .fixture_path()

  ok <- withr::local_tempfile(fileext = ".parquet")
  expect_silent(
    snapshot_oracle(src, ok, expect = list(n_rows = 4, n_cols = 5))
  )

  bad <- withr::local_tempfile(fileext = ".parquet")
  expect_error(
    snapshot_oracle(src, bad, expect = list(n_rows = 99)),
    "n_rows is 4 but SAS reported 99"
  )
  expect_false(file.exists(bad))

  bad2 <- withr::local_tempfile(fileext = ".parquet")
  expect_error(
    snapshot_oracle(src, bad2, expect = list(variables = c("ccfidu", "nope"))),
    "variable sets differ"
  )

  bad3 <- withr::local_tempfile(fileext = ".parquet")
  expect_error(
    snapshot_oracle(src, bad3, expect = list(n_row = 4)),
    "Unknown 'expect' element"
  )
})
```

- [ ] **Step 6: Add the manifest integration test**

```r
test_that("snapshot_oracle records the snapshot in a manifest", {
  skip_if_not_installed("arrow")

  dir <- withr::local_tempdir()
  out <- file.path(dir, "oracle.parquet")
  man <- file.path(dir, "manifest.yaml")

  res <- snapshot_oracle(.fixture_path(), out, manifest = man)

  expect_true(file.exists(man))
  entries <- yaml::read_yaml(man)
  expect_true(length(entries) >= 1)

  # verify_manifest() re-hashes the file; an untouched oracle verifies clean.
  # It returns a data frame with columns: file, status ("OK"/"FAIL"), message.
  ok <- hvtiRutilities::verify_manifest(
    manifest_path = man, data_dir = dir, stop_on_error = FALSE
  )
  expect_true(all(ok$status == "OK"))

  # A drifted oracle is detected. This is the spec requirement that an oracle
  # whose recorded checksum no longer matches the file is an error.
  #
  # verify_manifest(stop_on_error = FALSE) signals the mismatch with
  # warning(). Capture it explicitly -- a warning left to escape into the
  # suite masks a future unexpected one behind this expected one.
  writeLines("corrupted", out)
  expect_warning(
    drifted <- hvtiRutilities::verify_manifest(
      manifest_path = man, data_dir = dir, stop_on_error = FALSE
    ),
    "SHA-256 mismatch"
  )
  expect_true(any(drifted$status == "FAIL"))
})
```

Add `yaml` to `Suggests` in `DESCRIPTION` for this test.

- [ ] **Step 7: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "snapshot_oracle")'`
Expected: `[ FAIL 0 | PASS 18 ]` for the filtered run — but count the
brief's own assertions rather than trusting this number; the authoritative
check is `FAIL 0` with no loose warnings.

Note that validation runs *before* the parquet is written, so a failed validation leaves no file behind. The `expect_false(file.exists(bad))` assertion pins that ordering.

- [ ] **Step 8: Commit**

```bash
git add R/snapshot_oracle.R tests/testthat/test-snapshot_oracle.R
git commit -m "feat: snapshot_oracle() freezes SAS output as checksummed parquet"
```

---

### Task 5: Comparison primitives

**Files:**
- Create: `R/compare_primitives.R`
- Test: `tests/testthat/test-compare_primitives.R`

**Interfaces:**
- Consumes: nothing.
- Produces: `.cmp_class(x)` → one of `"numeric"`, `"character"`, `"date"`, `"factor"`, `"logical"`; `.as_comparable(x)` → a plain vector with labels and classes stripped; `.compare_vector(a, b, tolerance)` → `list(verdict, n_differ, max_abs_diff, max_rel_diff)`.

Kept in their own file because they carry the semantic decisions — `NA` handling, blank padding, date origin — and every one of them is a place a wrong answer can hide.

- [ ] **Step 1: Write the failing test**

```r
test_that(".cmp_class collapses storage variants to comparison classes", {
  expect_equal(.cmp_class(1.5), "numeric")
  expect_equal(.cmp_class(1L), "numeric")
  expect_equal(.cmp_class(haven::labelled(c(1, 2), c(a = 1))), "numeric")
  expect_equal(.cmp_class("a"), "character")
  expect_equal(.cmp_class(as.Date("2020-01-01")), "date")
  expect_equal(.cmp_class(factor("a")), "factor")
  expect_equal(.cmp_class(TRUE), "logical")
})

test_that(".compare_vector treats matched NA as equal", {
  r <- .compare_vector(c(1, NA), c(1, NA), tolerance = 1e-8)
  expect_equal(r$verdict, "identical")
  expect_equal(r$n_differ, 0L)
})

test_that(".compare_vector treats unmatched NA as a difference", {
  r <- .compare_vector(c(1, NA), c(1, 2), tolerance = 1e-8)
  expect_equal(r$verdict, "differs")
  expect_equal(r$n_differ, 1L)
})

test_that(".compare_vector honours tolerance", {
  within <- .compare_vector(c(1, 2), c(1, 2 + 1e-10), tolerance = 1e-8)
  expect_equal(within$verdict, "within_tolerance")
  expect_true(within$max_abs_diff > 0)

  beyond <- .compare_vector(c(1, 2), c(1, 2.5), tolerance = 1e-8)
  expect_equal(beyond$verdict, "differs")
  expect_equal(beyond$max_abs_diff, 0.5)
})

test_that(".compare_vector ignores trailing blanks, as SAS does", {
  r <- .compare_vector(c("Smith", "Jones "), c("Smith", "Jones"),
                       tolerance = 1e-8)
  expect_equal(r$verdict, "identical")
})

test_that('.compare_vector treats SAS empty-string as character NA', {
  # SAS has no character missing value distinct from "". A missing character
  # in the oracle reads back as ""; the R pipeline produces NA. Reporting that
  # as a difference would be a false positive on every character column that
  # has any missing value.
  sas <- c("Smith", "")
  r   <- c("Smith", NA_character_)
  expect_equal(.compare_vector(sas, r, tolerance = 1e-8)$verdict, "identical")

  # Whitespace-only is also missing, once trimmed.
  expect_equal(
    .compare_vector(c("Smith", "   "), r, tolerance = 1e-8)$verdict,
    "identical"
  )

  # A genuine value difference is still caught.
  differs <- .compare_vector(c("Smith", "Jones"), r, tolerance = 1e-8)
  expect_equal(differs$verdict, "differs")
  expect_equal(differs$n_differ, 1L)
})

test_that(".compare_vector compares dates by value, not representation", {
  a <- as.Date(c("2020-01-15", NA))
  b <- as.Date(c("2020-01-15", NA))
  expect_equal(.compare_vector(a, b, tolerance = 1e-8)$verdict, "identical")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "compare_primitives")'`
Expected: FAIL with `could not find function ".cmp_class"`

- [ ] **Step 3: Write the implementation**

```r
#' Collapse a vector to its comparison class
#'
#' Storage differs between SAS and R for the same logical type: a SAS numeric
#' arrives as `haven_labelled`, a plain double, or an integer depending on how
#' it was written. All three are the same thing for comparison purposes.
#'
#' @param x A vector.
#'
#' @return A length-one character: one of `"date"`, `"factor"`,
#'   `"character"`, `"logical"`, `"numeric"`, or the vector's first class.
#'
#' @keywords internal
#' @noRd
.cmp_class <- function(x) {
  if (inherits(x, "Date") || inherits(x, "POSIXct")) return("date")
  if (is.factor(x))                                  return("factor")
  if (inherits(x, "haven_labelled")) {
    return(if (is.character(unclass(x))) "character" else "numeric")
  }
  if (is.character(x)) return("character")
  if (is.logical(x))   return("logical")
  if (is.numeric(x))   return("numeric")
  class(x)[1]
}

#' Strip a vector to a plain comparable form
#'
#' @param x A vector.
#'
#' @return A plain atomic vector: dates as numeric days, factors as character,
#'   character trimmed of surrounding whitespace with `""` folded to `NA`.
#'
#' @keywords internal
#' @noRd
.as_comparable <- function(x) {
  cls <- .cmp_class(x)
  out <- switch(
    cls,
    date      = as.numeric(as.Date(x)),
    factor    = as.character(x),
    character = .normalise_character(x),
    logical   = as.logical(x),
    numeric   = as.numeric(unclass(x)),
    unclass(x)
  )
  attributes(out) <- NULL
  out
}

#' Normalise a character vector to SAS's notion of a string
#'
#' Two adjustments, both required for a SAS oracle to compare meaningfully
#' against an R rebuild:
#'
#' * **Trailing blanks are stripped.** SAS pads character values to their
#'   declared width, so `'Smith'` and `'Smith   '` are the same value there and
#'   different in R.
#' * **`""` is folded to `NA`.** SAS has no character missing value distinct
#'   from the empty string. A missing character in a SAS dataset reads back as
#'   `""`, while the R pipeline produces `NA`. Treating them as different would
#'   report `differs` for every character column containing any missing value —
#'   false positives in bulk, on every study.
#'
#' The information loss is real but unavoidable: the oracle cannot distinguish
#' `""` from missing, so a difference between them is never evidence of
#' anything.
#'
#' @param x A character or `haven_labelled` character vector.
#'
#' @return A plain character vector, trimmed, with `""` as `NA`.
#'
#' @keywords internal
#' @noRd
.normalise_character <- function(x) {
  v <- trimws(as.character(unclass(x)))
  v[!is.na(v) & v == ""] <- NA_character_
  v
}

#' Compare two vectors elementwise
#'
#' Matched `NA` counts as equal; `NA` on one side only counts as a difference.
#' Character comparison trims whitespace, because SAS pads character values to
#' their declared length and R does not.
#'
#' @param a,b Vectors of equal length.
#' @param tolerance Numeric. Absolute differences at or below this are
#'   `"within_tolerance"` rather than `"differs"`.
#'
#' @return A list with `verdict`, `n_differ`, `max_abs_diff`, `max_rel_diff`.
#'
#' @keywords internal
#' @noRd
.compare_vector <- function(a, b, tolerance) {
  av <- .as_comparable(a)
  bv <- .as_comparable(b)

  both_na <- is.na(av) & is.na(bv)
  one_na  <- xor(is.na(av), is.na(bv))

  if (is.numeric(av) && is.numeric(bv)) {
    d <- abs(av - bv)
    d[both_na] <- 0
    d[one_na]  <- Inf
    denom <- pmax(abs(av), abs(bv))
    rel <- ifelse(is.finite(d) & denom > 0, d / denom, d)
    rel[both_na] <- 0
    n_differ <- sum(d > 0, na.rm = TRUE)
    max_abs  <- if (length(d)) max(d, na.rm = TRUE) else 0
    max_rel  <- if (length(rel)) max(rel, na.rm = TRUE) else 0
  } else {
    unequal <- !both_na & (one_na | (av != bv))
    unequal[is.na(unequal)] <- TRUE
    n_differ <- sum(unequal)
    max_abs  <- if (n_differ > 0) Inf else 0
    max_rel  <- max_abs
  }

  verdict <- if (n_differ == 0) {
    "identical"
  } else if (is.finite(max_abs) && max_abs <= tolerance) {
    "within_tolerance"
  } else {
    "differs"
  }

  list(
    verdict      = verdict,
    n_differ     = as.integer(n_differ),
    max_abs_diff = max_abs,
    max_rel_diff = max_rel
  )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Rscript -e 'devtools::test(filter = "compare_primitives")'`
Expected: `[ FAIL 0 | PASS 12 ]`

- [ ] **Step 5: Commit**

```bash
git add R/compare_primitives.R tests/testthat/test-compare_primitives.R
git commit -m "feat: comparison primitives with SAS-aware NA and blank handling"
```

---

### Task 6: `compare_built()` — schema and row-set layers

**Files:**
- Create: `R/compare_built.R`
- Test: `tests/testthat/test-compare_built-schema.R`

**Interfaces:**
- Consumes: `.cmp_class()` from Task 5.
- Produces: `compare_built(oracle, r, id = "ccfidu", tolerance = 1e-8)` → a `built_comparison` object: a data frame with columns `variable`, `verdict`, `n_differ`, `max_abs_diff`, `max_rel_diff`, `detail`, carrying a `rows` attribute of `list(n_oracle, n_r, n_common, only_oracle, only_r)`.

- [ ] **Step 1: Write the failing test**

```r
test_that("compare_built reports variables present on only one side", {
  o <- data.frame(ccfidu = "A1", age = 65, dropped = 1)
  r <- data.frame(ccfidu = "A1", age = 65, added   = 1)

  res <- compare_built(o, r, id = "ccfidu")

  expect_s3_class(res, "built_comparison")
  expect_equal(res$verdict[res$variable == "dropped"], "absent_in_r")
  expect_equal(res$verdict[res$variable == "added"],   "absent_in_sas")
})

test_that("compare_built flags type mismatches without comparing values", {
  o <- data.frame(ccfidu = "A1", x = 1)
  r <- data.frame(ccfidu = "A1", x = "1", stringsAsFactors = FALSE)

  res <- compare_built(o, r, id = "ccfidu")
  expect_equal(res$verdict[res$variable == "x"], "type_mismatch")
})

test_that("compare_built reports row-set differences separately", {
  o <- data.frame(ccfidu = c("A1", "A2"), age = c(1, 2))
  r <- data.frame(ccfidu = c("A2", "A3"), age = c(2, 3))

  res <- compare_built(o, r, id = "ccfidu")
  rows <- attr(res, "rows")

  expect_equal(rows$n_oracle, 2L)
  expect_equal(rows$n_r, 2L)
  expect_equal(rows$n_common, 1L)
  expect_equal(rows$only_oracle, "A1")
  expect_equal(rows$only_r, "A3")

  # The shared row matches, so age is identical despite the cohort difference.
  expect_equal(res$verdict[res$variable == "age"], "identical")
})

test_that("compare_built errors when the id column is missing", {
  o <- data.frame(ccfidu = "A1", age = 1)
  r <- data.frame(other  = "A1", age = 1)
  expect_error(compare_built(o, r, id = "ccfidu"), "not present")
})

test_that("compare_built errors on duplicate ids", {
  o <- data.frame(ccfidu = c("A1", "A1"), age = c(1, 2))
  r <- data.frame(ccfidu = c("A1", "A1"), age = c(1, 2))
  expect_error(compare_built(o, r, id = "ccfidu"), "duplicated")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "compare_built-schema")'`
Expected: FAIL with `could not find function "compare_built"`

- [ ] **Step 3: Write the implementation**

```r
#' Compare an R-built dataset against a SAS oracle
#'
#' Joins `r` to `oracle` on `id` and classifies every variable. Row-set
#' differences are reported separately from value differences: an identifier
#' present on one side only is a cohort discrepancy, a different class of
#' problem from a miscomputed variable, and conflating the two hides both.
#'
#' This function deliberately returns a table and never a single pass/fail.
#' Collapsing several hundred variables into one boolean launders real
#' differences into a green check. Read the table.
#'
#' A difference does not automatically mean the R code is wrong. SAS orders
#' missing numerics below all values, so `if bmi < 18.5` classifies a missing
#' BMI as underweight where R yields `NA`. Record such cases as
#' `intentional_divergence` in `equivalence_signoff.yaml`.
#'
#' @param oracle Data frame read from the parquet oracle. See
#'   [snapshot_oracle()].
#' @param r Data frame produced by the R pipeline.
#' @param id Name of the identifier column present in both. Must be unique
#'   within each.
#' @param tolerance Numeric. Absolute numeric differences at or below this are
#'   reported as `"within_tolerance"`.
#'
#' @return An object of class `built_comparison`: a data frame with one row per
#'   variable and columns `variable`, `verdict`, `n_differ`, `max_abs_diff`,
#'   `max_rel_diff`, and `detail`. `verdict` is one of `"identical"`,
#'   `"within_tolerance"`, `"differs"`, `"absent_in_r"`, `"absent_in_sas"`, or
#'   `"type_mismatch"`. The `rows` attribute holds a list with `n_oracle`,
#'   `n_r`, `n_common`, `only_oracle`, and `only_r`.
#'
#' @seealso [snapshot_oracle()]
#'
#' @examples
#' o <- data.frame(ccfidu = c("A1", "A2"), age = c(65, 70))
#' r <- data.frame(ccfidu = c("A1", "A2"), age = c(65, 71))
#' compare_built(o, r, id = "ccfidu")
#'
#' @export
compare_built <- function(oracle, r, id = "ccfidu", tolerance = 1e-8) {
  oracle <- as.data.frame(oracle)
  r      <- as.data.frame(r)

  for (nm in c("oracle", "r")) {
    d <- get(nm)
    if (!id %in% names(d)) {
      stop("Identifier column '", id, "' is not present in ", nm, ".",
           call. = FALSE)
    }
    if (anyDuplicated(d[[id]])) {
      stop("Identifier column '", id, "' is duplicated in ", nm,
           ". Comparison requires one row per identifier.", call. = FALSE)
    }
  }

  o_ids <- as.character(oracle[[id]])
  r_ids <- as.character(r[[id]])
  common <- intersect(o_ids, r_ids)

  rows <- list(
    n_oracle    = length(o_ids),
    n_r         = length(r_ids),
    n_common    = length(common),
    only_oracle = setdiff(o_ids, r_ids),
    only_r      = setdiff(r_ids, o_ids)
  )

  o_common <- oracle[match(common, o_ids), , drop = FALSE]
  r_common <- r[match(common, r_ids), , drop = FALSE]

  o_vars <- setdiff(names(oracle), id)
  r_vars <- setdiff(names(r), id)

  out <- do.call(rbind, c(
    lapply(union(o_vars, r_vars), function(v) {
      .compare_one_variable(v, o_common, r_common, o_vars, r_vars, tolerance)
    }),
    list(make.row.names = FALSE)
  ))

  if (is.null(out)) {
    out <- .empty_comparison()
  }
  out <- out[order(match(out$verdict, .verdict_levels()), out$variable), ,
             drop = FALSE]
  rownames(out) <- NULL

  structure(out, class = c("built_comparison", "data.frame"), rows = rows)
}

#' Verdict levels, most serious first
#'
#' @return A character vector of verdict names in report order.
#'
#' @keywords internal
#' @noRd
.verdict_levels <- function() {
  c("differs", "type_mismatch", "absent_in_r", "absent_in_sas",
    "within_tolerance", "identical")
}

#' An empty comparison table with the correct columns
#'
#' @return A zero-row data frame with the `built_comparison` columns.
#'
#' @keywords internal
#' @noRd
.empty_comparison <- function() {
  data.frame(
    variable     = character(0),
    verdict      = character(0),
    n_differ     = integer(0),
    max_abs_diff = numeric(0),
    max_rel_diff = numeric(0),
    detail       = character(0),
    stringsAsFactors = FALSE
  )
}

#' Classify one variable
#'
#' @param v Variable name.
#' @param o_common,r_common Row-aligned data frames restricted to shared ids.
#' @param o_vars,r_vars Variable names on each side, excluding the id.
#' @param tolerance Numeric tolerance passed to [.compare_vector()].
#'
#' @return A one-row data frame with the `built_comparison` columns.
#'
#' @keywords internal
#' @noRd
.compare_one_variable <- function(v, o_common, r_common, o_vars, r_vars,
                                  tolerance) {
  row <- function(verdict, n_differ = NA_integer_, max_abs = NA_real_,
                  max_rel = NA_real_, detail = "") {
    data.frame(variable = v, verdict = verdict, n_differ = n_differ,
               max_abs_diff = max_abs, max_rel_diff = max_rel,
               detail = detail, stringsAsFactors = FALSE)
  }

  if (!v %in% r_vars) {
    return(row("absent_in_r", detail = "Present in oracle, absent in R output."))
  }
  if (!v %in% o_vars) {
    return(row("absent_in_sas", detail = "Present in R output, absent in oracle."))
  }

  o_cls <- .cmp_class(o_common[[v]])
  r_cls <- .cmp_class(r_common[[v]])
  if (!identical(o_cls, r_cls)) {
    return(row("type_mismatch",
               detail = paste0("oracle is ", o_cls, ", R is ", r_cls,
                               "; values not compared.")))
  }

  cmp <- .compare_vector(o_common[[v]], r_common[[v]], tolerance)
  row(cmp$verdict, cmp$n_differ, cmp$max_abs_diff, cmp$max_rel_diff)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "compare_built-schema")'`
Expected: `[ FAIL 0 | PASS 13 ]`

- [ ] **Step 5: Commit**

```bash
git add R/compare_built.R tests/testthat/test-compare_built-schema.R
git commit -m "feat: compare_built() schema and row-set classification"
```

---

### Task 7: `compare_built()` — value verdicts and the renamed-variable guarantee

**Files:**
- Test: `tests/testthat/test-compare_built-values.R`

**Interfaces:**
- Consumes: `compare_built()` from Task 6, `.fixture_frame()` from Task 2.
- Produces: no new code. This task pins behaviour the spec calls out as critical.

No implementation step: Task 6's code should already satisfy these. If a test fails, fix `R/compare_built.R` or `R/compare_primitives.R` and note the fix in the commit message.

- [ ] **Step 1: Write the tests**

```r
test_that("identical frames yield all identical", {
  d <- .fixture_frame()
  res <- compare_built(d, d, id = "ccfidu")
  expect_true(all(res$verdict == "identical"))
  expect_equal(nrow(res), 4L)  # age, bmi, dt_surg, surgeon
})

test_that("a sub-tolerance perturbation is within_tolerance with a real diff", {
  d <- .fixture_frame()
  p <- d
  p$age[1] <- p$age[1] + 1e-10

  res <- compare_built(d, p, id = "ccfidu", tolerance = 1e-8)
  age <- res[res$variable == "age", ]
  expect_equal(age$verdict, "within_tolerance")
  expect_equal(age$n_differ, 1L)
  expect_true(age$max_abs_diff > 0 && age$max_abs_diff <= 1e-8)
})

test_that("a supra-tolerance perturbation differs and reports the magnitude", {
  d <- .fixture_frame()
  p <- d
  p$age[1] <- p$age[1] + 0.5

  res <- compare_built(d, p, id = "ccfidu", tolerance = 1e-8)
  age <- res[res$variable == "age", ]
  expect_equal(age$verdict, "differs")
  expect_equal(age$n_differ, 1L)
  expect_equal(age$max_abs_diff, 0.5)
})

test_that("a renamed variable is never reported as matching", {
  d <- .fixture_frame()
  p <- d
  names(p)[names(p) == "age"] <- "age_at_surgery"

  res <- compare_built(d, p, id = "ccfidu")
  expect_equal(res$verdict[res$variable == "age"], "absent_in_r")
  expect_equal(res$verdict[res$variable == "age_at_surgery"], "absent_in_sas")
  expect_false(any(res$verdict == "identical" &
                     res$variable %in% c("age", "age_at_surgery")))
})

test_that("the SAS missing-sorts-low divergence is visible, not hidden", {
  # SAS: `if bmi < 18.5 then underweight = 1` marks missing BMI as underweight.
  # R excludes it. compare_built must surface this rather than smooth it over.
  d <- .fixture_frame()
  sas <- data.frame(
    ccfidu      = d$ccfidu,
    underweight = as.numeric(!is.na(d$bmi) & d$bmi < 18.5 | is.na(d$bmi)),
    stringsAsFactors = FALSE
  )
  r <- data.frame(
    ccfidu      = d$ccfidu,
    underweight = as.numeric(d$bmi < 18.5),
    stringsAsFactors = FALSE
  )

  res <- compare_built(sas, r, id = "ccfidu")
  expect_equal(res$verdict[res$variable == "underweight"], "differs")
  expect_true(res$n_differ[res$variable == "underweight"] >= 1L)
})
```

- [ ] **Step 2: Run tests**

Run: `Rscript -e 'devtools::test(filter = "compare_built-values")'`
Expected: `[ FAIL 0 | PASS 15 ]`

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/test-compare_built-values.R
git commit -m "test: pin value verdicts, rename safety, and SAS missing-sorts-low divergence"
```

---

### Task 8: `print.built_comparison()` and the no-scalar-verdict guarantee

**Files:**
- Create: `R/print_built_comparison.R`
- Test: `tests/testthat/test-print_built_comparison.R`

**Interfaces:**
- Consumes: `compare_built()` from Task 6.
- Produces: `print.built_comparison(x, ..., show_ids = getOption("hvtiRdatasets.show_ids", FALSE))`, S3 method registered in `NAMESPACE`.

**PHI constraint, and an intentional deviation from the spec.** `ccfidu` is built in `tp.bd.data.master.sas` as `ccf || month || day || year` — an MRN concatenated with a date of surgery. That is PHI, not a de-identified key. Printing identifiers would put PHI into terminals, CI logs, and captured test failures.

Therefore this method prints **counts only** by default. Identifiers remain in the `rows` attribute for programmatic use, since chasing a discrepancy requires them, but reach output only when the caller opts in explicitly. The spec's "reports the first *n* differing `id`s" is deliberately **not** implemented for the same reason; `n_differ` is reported instead.

- [ ] **Step 1: Write the failing test**

```r
test_that("print summarises verdicts and row differences", {
  o <- data.frame(ccfidu = c("A1", "A2"), age = c(65, 70), gone = c(1, 2))
  r <- data.frame(ccfidu = c("A1", "A3"), age = c(65, 99))

  res <- compare_built(o, r, id = "ccfidu")
  out <- paste(capture.output(print(res)), collapse = "\n")

  expect_match(out, "Dataset comparison")
  expect_match(out, "rows: 2 oracle, 2 R, 1 common")
  expect_match(out, "only in oracle: 1")
  expect_match(out, "only in R: 1")
  expect_match(out, "absent_in_r")
})

test_that("print never emits identifiers by default", {
  # ccfidu is MRN + date of surgery. It must not reach output unasked.
  o <- data.frame(ccfidu = c("1234567820200115", "A2"), age = c(65, 70))
  r <- data.frame(ccfidu = c("A2", "9876543220190302"), age = c(70, 55))

  res <- compare_built(o, r, id = "ccfidu")
  out <- paste(capture.output(print(res)), collapse = "\n")

  expect_false(grepl("1234567820200115", out, fixed = TRUE))
  expect_false(grepl("9876543220190302", out, fixed = TRUE))
  expect_match(out, "only in oracle: 1")

  # But they remain reachable for a caller who needs them.
  expect_equal(attr(res, "rows")$only_oracle, "1234567820200115")
})

test_that("print emits identifiers only on explicit opt-in", {
  o <- data.frame(ccfidu = c("1234567820200115", "A2"), age = c(65, 70))
  r <- data.frame(ccfidu = "A2", age = 70)

  res <- compare_built(o, r, id = "ccfidu")
  out <- paste(capture.output(print(res, show_ids = TRUE)), collapse = "\n")

  expect_match(out, "1234567820200115", fixed = TRUE)
})

test_that("print never emits an overall pass or fail", {
  d <- data.frame(ccfidu = "A1", age = 1)
  out <- paste(capture.output(print(compare_built(d, d, id = "ccfidu"))),
               collapse = "\n")
  expect_false(grepl("PASS|FAIL|\\bOK\\b", out))
})

test_that("compare_built returns no scalar verdict field", {
  d <- data.frame(ccfidu = "A1", age = 1)
  res <- compare_built(d, d, id = "ccfidu")
  expect_false(any(c("passed", "ok", "equivalent") %in% names(attributes(res))))
  expect_true(is.data.frame(res))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "print_built_comparison")'`
Expected: FAIL — output does not match `"Dataset comparison"`

- [ ] **Step 3: Write the implementation**

```r
#' Print a dataset comparison
#'
#' Reports row-set differences and a count per verdict, then lists every
#' variable that is not `"identical"`. No overall pass/fail is printed, by
#' design: see [compare_built()].
#'
#' Identifiers are **not** printed by default. In this group's datasets
#' `ccfidu` is a medical record number concatenated with a date of surgery,
#' which is PHI; printing it would place PHI in terminals, logs, and captured
#' test failures. The identifiers remain available in the `rows` attribute for
#' a caller who needs them to chase a discrepancy.
#'
#' @param x An object of class `built_comparison`.
#' @param ... Ignored.
#' @param show_ids Logical. Print the identifiers that appear on only one
#'   side. Defaults to the `hvtiRdatasets.show_ids` option, itself `FALSE`.
#'   **Enabling this may emit PHI.** Only do so in a session whose output is
#'   not being logged or shared.
#'
#' @return `x`, invisibly.
#'
#' @export
print.built_comparison <- function(x, ...,
                                   show_ids = getOption(
                                     "hvtiRdatasets.show_ids", FALSE
                                   )) {
  rows <- attr(x, "rows")

  id_suffix <- function(ids) {
    if (!isTRUE(show_ids)) return("")
    paste0(" (", paste(utils::head(ids, 5), collapse = ", "),
           if (length(ids) > 5) ", ..." else "", ")")
  }

  cat("Dataset comparison\n")
  cat(sprintf("  rows: %d oracle, %d R, %d common\n",
              rows$n_oracle, rows$n_r, rows$n_common))
  if (length(rows$only_oracle)) {
    cat(sprintf("  only in oracle: %d%s\n",
                length(rows$only_oracle), id_suffix(rows$only_oracle)))
  }
  if (length(rows$only_r)) {
    cat(sprintf("  only in R: %d%s\n",
                length(rows$only_r), id_suffix(rows$only_r)))
  }

  cat("\n  variables by verdict:\n")
  counts <- table(factor(x$verdict, levels = .verdict_levels()))
  for (nm in names(counts)) {
    if (counts[[nm]] > 0) {
      cat(sprintf("    %-18s %d\n", nm, counts[[nm]]))
    }
  }

  needs_review <- x[x$verdict != "identical", , drop = FALSE]
  if (nrow(needs_review)) {
    cat("\n  requiring review:\n")
    print.data.frame(needs_review, row.names = FALSE)
  }

  invisible(x)
}
```

Add `@importFrom utils head` to `R/hvtiRdatasets-package.R`, or keep the `utils::` prefix as written and leave `utils` in `Imports`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "print_built_comparison")'`
Expected: `[ FAIL 0 | PASS 8 ]`

- [ ] **Step 5: Run the whole suite and check**

Run:
```bash
Rscript -e 'roxygen2::roxygenise()'
Rscript -e 'devtools::test()'
R CMD build . && R CMD check hvtiRdatasets_0.0.0.9000.tar.gz
```
Expected: all tests pass; `Status: OK` at 0/0/0.

- [ ] **Step 6: Commit**

```bash
git add R/print_built_comparison.R R/hvtiRdatasets-package.R NAMESPACE man/ tests/
git commit -m "feat: print.built_comparison(), with no overall pass/fail by design"
```

---

### Task 9: The `coming-from-sas` migration vignette

**Files:**
- Create: `vignettes/coming-from-sas.qmd`
- Modify: `.Rbuildignore` (no change needed; listed for completeness)

**Interfaces:**
- Consumes: `compare_built()` from Task 6.
- Produces: a vignette that builds with no warehouse, no SAS, and no PHI.

The traps section uses **evaluated** chunks, so the document proves each claim rather than asserting it. The API-mapping section uses `eval = FALSE`, because `dw_pull()` and `derive_vars()` do not exist until S1–S3.

- [ ] **Step 1: Write the vignette**

````markdown
---
title: "Coming from SAS"
vignette: >
  %\VignetteIndexEntry{Coming from SAS}
  %\VignetteEngine{quarto::html}
  %\VignetteEncoding{UTF-8}
format: html
---

```{r}
#| label: setup
#| include: false
knitr::opts_chunk$set(collapse = TRUE, comment = "#>")
library(hvtiRdatasets)
```

## Who this is for

You know the `tp.bd.*` and `tp.vars.*` templates. You now have to read and
write R. This guide will not teach you R. Its job is to make what you already
know transferable, and to warn you about the handful of places where a
reasonable translation from SAS silently produces a *different, plausible*
number rather than an error.

Read the traps section even if you skip everything else.

## The model shift

A SAS program mutates a dataset through a sequence of steps, and the program
itself is the record of what happened. If an analyst commented out a block with
`%macro skip`, that decision lives only in their copy of the script.

R passes values through functions, and the study's `study.yaml` is the record.
Enabling a step is a change to a committed configuration file, not an
uncommented block. This is the whole reason the port is worth doing: what used
to be invisible becomes reviewable.

## Idiom translation

```{r}
#| eval: false
# Functions marked (S1)-(S3) arrive in later slices.
```

| SAS | R |
|---|---|
| `%include "<dbcreds>.sas"` + `CONNECT TO ODBC` | `dw_connect()` (S1) |
| `PROC SQL; SELECT ... FROM connection to ODBC` | `dw_pull(config, conn)` (S1) |
| `libname library "&STUDY/datasets"` | paths in `study.yaml` |
| `%macro skip; ... %mend skip;` | `modules:` / `derive:` toggles in `study.yaml` |
| `%vars(in=built, out=built, transf=1)` | `derive_vars(built, config)` (S3) |
| `data x; set y; ... run;` | a `dplyr` pipeline |
| `PROC CONTENTS` | `hvtiRutilities::data_dictionary()` |
| `label x = 'Age at surgery';` | `labelled` + `hvtiRutilities::label_map()` |
| `first.id` / `last.id` | `group_by()` + `slice_head()` / `slice_tail()` |
| `libname out xport` then `read.xport()` | parquet, or just return the object |

## The traps

Each of these produces a wrong number rather than an error. They are the reason
`compare_built()` exists.

### Missing sorts low

In SAS a missing numeric orders *below every number*. So this marks a patient
with unknown BMI as underweight:

```
if bmi < 18.5 then underweight = 1;
```

R does not:

```{r}
bmi <- c(31.2, NA, 17.0)
bmi < 18.5
```

`NA` propagates instead of comparing as small. R is right and SAS is wrong, so
a faithful port will *fail* equivalence here. That is what the
`intentional_divergence` resolution in `equivalence_signoff.yaml` is for. Do
not reproduce the SAS behaviour to make the comparison green.

### Character comparison is blank-padded in SAS

SAS pads character values to their declared length, so `'Smith'` and
`'Smith   '` compare equal. In R they do not:

```{r}
"Smith" == "Smith   "
trimws("Smith   ") == "Smith"
```

This bites hardest on merges keyed by a character id. `compare_built()` trims
before comparing, for exactly this reason.

### SAS has no missing character value

R distinguishes `NA` from `""`. SAS does not — a missing character **is** the
empty string. Read a SAS dataset and every missing character comes back as
`""`:

```{r}
f <- system.file("extdata", "oracle_small.sas7bdat",
                 package = "hvtiRdatasets")
surgeon <- haven::read_sas(f)$surgeon
surgeon                 # the fourth value was written as NA
is.na(surgeon)          # ... and is not NA any more
```

So a faithful R rebuild holding `NA` disagrees with the oracle holding `""` on
every missing value. `compare_built()` folds `""` to `NA` for character columns
so this does not flood the report with false differences.

The consequence for your own code is sharper: **never test a SAS-sourced
character for `NA`**. `is.na(surgeon)` is `FALSE` even where the value is
missing. Test for `""`, or convert on read.

### `MERGE` is not a join

A SAS data-step `MERGE` on a non-unique BY key does not error. It produces
undefined results. This is not hypothetical — from the revision history of
`tp.bd.data.master.sas`:

> 07/03/23: Changed the join logic for the FUP dataset to correct many-to-1
> join problem when patient has multiple surgeries in the dataset

R makes the same mistake loud:

```{r}
#| warning: true
a <- data.frame(id = c("A", "A"), x = 1:2)
b <- data.frame(id = c("A", "A"), y = 3:4)
nrow(dplyr::left_join(a, b, by = "id", relationship = "many-to-many"))
```

Four rows from two. Without `relationship = "many-to-many"`, `dplyr` warns.
**Never suppress that warning.** It is the check SAS never gave you.

### Dates use different origins

SAS counts days from 1960-01-01; R from 1970-01-01. The gap is 3,653 days.
`haven` converts correctly, so a value read through `snapshot_oracle()` is
already right. A hand-rolled conversion is where this goes wrong.

```{r}
as.Date(0, origin = "1970-01-01")   # R's zero
as.Date(0, origin = "1960-01-01")   # what a raw SAS number means
```

### Automatic variables do not exist in R

`_N_`, `_FREQ_`, and `_TYPE_` are created by SAS. In R you construct them, and
the name is not magic. Phase 0 of this migration found a defect of exactly this
class: `keep _freq_ tau` in one file versus `keep freq tau` in its sibling.
`_FREQ_` is the automatic variable; `freq` is an ordinary one that may not
exist. One of those programs produced wrong counts.

### `length 4` silently truncates

A SAS numeric written with `length 4` loses precision on disk. A value read
back from an old dataset may not equal a freshly computed R value, and **the
SAS side is the lossy one**. This is what `tolerance` in `compare_built()` is
for. If a variable is `within_tolerance` rather than `identical`, storage
precision is the first thing to suspect.

## Verifying your own port

Build the variable in R, then compare against the oracle:

```{r}
oracle <- data.frame(ccfidu = c("A1", "A2", "A3"), age = c(65.5, 70.2, 58.0))
mine   <- data.frame(ccfidu = c("A1", "A2", "A3"), age = c(65.5, 70.2, 58.5))

compare_built(oracle, mine, id = "ccfidu")
```

There is no overall pass or fail, deliberately. Read the table, and record a
resolution for every variable that is not `identical`.
````

- [ ] **Step 2: Build the vignette**

Run:
```bash
Rscript -e 'quarto::quarto_render("vignettes/coming-from-sas.qmd")'
```
Expected: renders with no error. The `MERGE` chunk prints `[1] 4`.

- [ ] **Step 3: Run a full check with vignettes**

Run:
```bash
R CMD build . && R CMD check hvtiRdatasets_0.0.0.9000.tar.gz
```
Expected: `Status: OK`, 0/0/0, vignette built.

- [ ] **Step 4: Commit**

```bash
git add vignettes/ DESCRIPTION
git commit -m "docs: coming-from-sas migration vignette with executable traps"
```

---

### Task 10: README and release gate

**Files:**
- Create: `README.md`
- Create: `.github/workflows/R-CMD-check.yaml`

**Interfaces:**
- Consumes: everything above.
- Produces: a checked, documented package ready for S1.

- [ ] **Step 1: Write `README.md`**

```markdown
# hvtiRdatasets

Builds analysis-ready clinical datasets for the HVTI CORR group, and verifies
them against the legacy SAS datasets they replace.

## Status

Slice S0 (Verify) only. `snapshot_oracle()` and `compare_built()` are
implemented. The pipeline itself — `dw_pull()`, `build_dataset()`,
`derive_vars()` — arrives in S1–S3.

## Installation

```r
# install.packages("remotes")
remotes::install_github("ehrlinger/hvtiRdatasets")
```

`arrow` is an optional dependency, required only for writing oracle snapshots.

## Verifying an R build against SAS

```r
library(hvtiRdatasets)

# Freeze the SAS-built dataset once.
snapshot_oracle(
  "/studies/st1234/datasets/built.sas7bdat",
  "oracle/st1234_built.parquet"
)

# Compare an R rebuild against it.
oracle <- arrow::read_parquet("oracle/st1234_built.parquet")
compare_built(oracle, my_rebuild, id = "ccfidu")
```

There is no overall pass/fail. Read the table, and record a resolution for
every variable that is not `identical`.

## Documentation

- `vignette("coming-from-sas")` — migration guide for SAS users. Start here.

## Design

See `specs/2026-08-04-hvtiRdatasets-design.md`.
```

- [ ] **Step 2: Copy the check workflow**

```bash
mkdir -p .github/workflows
cp ../hvtiRutilities/.github/workflows/*check*.y*ml .github/workflows/
```

Open the copied file and change any occurrence of `hvtiRutilities` to
`hvtiRdatasets`.

- [ ] **Step 3: Run the full gate**

Run:
```bash
Rscript -e 'roxygen2::roxygenise()'
Rscript -e 'devtools::test()'
R CMD build . && R CMD check hvtiRdatasets_0.0.0.9000.tar.gz
```
Expected: `Status: OK`, 0 errors / 0 warnings / 0 notes.

- [ ] **Step 4: Commit**

```bash
git add README.md .github/
git commit -m "docs: README and R CMD check workflow"
```

---

### Task 11: Local integration harness against a real study

**Files:**
- Create: `tests/testthat/test-integration-real-study.R`
- Modify: `.gitignore`
- Modify: `README.md` (add the "Local integration testing" section below)

**Interfaces:**
- Consumes: `snapshot_oracle()`, `compare_built()`.
- Produces: a test file that is **skipped by default** and runs only when `HVTI_ORACLE_DIR` points at a directory of real SAS datasets.

The synthetic fixture proves this package's logic. It cannot prove that `haven` reads what real SAS wrote — real files carry compression, legacy encodings, SAS formats, and hundreds of variables the fixture does not. Only a real study proves that.

**The controlling rule: the data never enters the repository.** It stays where it already lives, on the network volume, under the access controls it already has. `HVTI_ORACLE_DIR` points at it. Data that was never inside the working tree cannot be committed by a careless `git add -A`; the `.gitignore` entries are a backstop against mistakes, not the primary control.

Consequently:
- No path under `HVTI_ORACLE_DIR` is ever copied into the repo.
- The test asserts **shape and verdicts**, never values. A failure message must not carry a patient value.
- `show_ids` is never enabled here.
- The test skips silently when the variable is unset, so CI, `R CMD check`, and every other checkout are unaffected.

- [ ] **Step 1: Confirm `.gitignore` already covers clinical data**

No change should be needed. `.gitignore` was set up at repo creation with
`*.sas7bdat`, `*.parquet`, `*.xpt`, `*.csv`, `*.rds`, `oracle/`, and the
negation `!inst/extdata/oracle_small.sas7bdat` that lets the one synthetic
fixture through.

Verify:

```bash
grep -E 'sas7bdat|parquet|xpt|oracle/' .gitignore
```

Expected: all of the above present, with the negation *after* `*.sas7bdat`.
Order matters — a negation before the pattern it exempts has no effect. Add
anything missing; do not duplicate what is there.

These entries are a backstop against mistakes, not the primary control. The
primary control is that real data lives outside the working tree, under
`HVTI_ORACLE_DIR`.

- [ ] **Step 2: Write the integration test**

```r
# Runs only when HVTI_ORACLE_DIR points at real SAS datasets. That directory
# holds PHI and lives outside this repository; nothing here copies from it.
#
#   HVTI_ORACLE_DIR=/studies/st1234/datasets Rscript -e 'devtools::test()'
#
# Assertions are on shape and verdicts only. No patient value may appear in a
# failure message.

.oracle_dir <- function() Sys.getenv("HVTI_ORACLE_DIR", unset = "")

skip_unless_real_oracle <- function() {
  skip_if_not_installed("arrow")
  d <- .oracle_dir()
  skip_if(!nzchar(d), "HVTI_ORACLE_DIR not set; skipping real-study tests.")
  skip_if(!dir.exists(d), paste0("HVTI_ORACLE_DIR does not exist: ", d))
  invisible(d)
}

test_that("a real SAS dataset reads and snapshots", {
  dir <- skip_unless_real_oracle()
  src <- file.path(dir, "built.sas7bdat")
  skip_if(!file.exists(src), "No built.sas7bdat in HVTI_ORACLE_DIR.")

  out <- withr::local_tempfile(fileext = ".parquet")
  res <- snapshot_oracle(src, out)

  # Shape only. Never print or assert on a value.
  expect_gt(res$n_rows, 0L)
  expect_gt(res$n_cols, 0L)
  expect_match(res$sha256, "^[0-9a-f]{64}$")
  expect_true(file.exists(out))
})

test_that("a real dataset compared against itself is wholly identical", {
  dir <- skip_unless_real_oracle()
  src <- file.path(dir, "built.sas7bdat")
  skip_if(!file.exists(src), "No built.sas7bdat in HVTI_ORACLE_DIR.")

  d <- haven::read_sas(src)
  id <- if ("ccfidu" %in% names(d)) "ccfidu" else names(d)[1]
  skip_if(anyDuplicated(d[[id]]) > 0,
          paste0("Identifier '", id, "' is not unique in this study."))

  res <- compare_built(d, d, id = id)

  # Report counts, never values, so a failure leaks nothing.
  offending <- sum(res$verdict != "identical")
  expect_equal(
    offending, 0L,
    info = paste0(offending, " variable(s) not identical to themselves; ",
                  "this indicates a defect in the comparison primitives, ",
                  "not in the data.")
  )
})

test_that("real-study output carries no identifiers by default", {
  dir <- skip_unless_real_oracle()
  src <- file.path(dir, "built.sas7bdat")
  skip_if(!file.exists(src), "No built.sas7bdat in HVTI_ORACLE_DIR.")

  d <- haven::read_sas(src)
  id <- if ("ccfidu" %in% names(d)) "ccfidu" else names(d)[1]
  skip_if(anyDuplicated(d[[id]]) > 0, "Identifier is not unique.")

  half <- d[seq_len(max(1, floor(nrow(d) / 2))), , drop = FALSE]
  res  <- compare_built(d, half, id = id)
  out  <- paste(capture.output(print(res)), collapse = "\n")

  dropped <- attr(res, "rows")$only_oracle
  skip_if(length(dropped) == 0, "No dropped ids to check.")
  expect_false(grepl(as.character(dropped[1]), out, fixed = TRUE))
})
```

- [ ] **Step 3: Verify the tests skip cleanly with the variable unset**

Run:
```bash
Rscript -e 'devtools::test(filter = "integration-real-study")'
```
Expected: all tests report `SKIP`, none fail. This is the state every other checkout and CI will see.

- [ ] **Step 4: Run against a real study**

Run, substituting a completed study whose `built.sas7bdat` is intact:
```bash
HVTI_ORACLE_DIR=/studies/st1234/datasets Rscript -e 'devtools::test(filter = "integration-real-study")'
```
Expected: all tests PASS. A self-comparison that is not wholly `identical` means a defect in the comparison primitives — investigate `.compare_vector()` before suspecting the data.

- [ ] **Step 5: Confirm nothing real entered the working tree**

Run:
```bash
git status --porcelain
git ls-files | grep -E '\.(sas7bdat|parquet|xpt)$'
```
Expected: `git status` clean; the only listed file is `inst/extdata/oracle_small.sas7bdat`.

- [ ] **Step 6: Document the harness in `README.md`**

```markdown
## Local integration testing

The committed fixtures are synthetic. To exercise the read path against real
SAS output, point `HVTI_ORACLE_DIR` at a study directory:

```bash
HVTI_ORACLE_DIR=/studies/st1234/datasets Rscript -e 'devtools::test()'
```

That directory holds PHI. It must live outside this repository, and nothing in
the test suite copies from it. With the variable unset — the default, and what
CI sees — these tests skip.

`print()` never emits identifiers unless `show_ids = TRUE`, because `ccfidu` is
a medical record number combined with a date of surgery. Do not enable it in a
session whose output is logged or shared.
```

- [ ] **Step 7: Commit**

```bash
git add tests/testthat/test-integration-real-study.R .gitignore README.md
git commit -m "test: gated integration harness against a real study, PHI stays out of the repo"
```

---

## Deferred from this plan

Recorded so nothing is silently dropped:

- `vignette("building-a-study-dataset")` — needs `dw_pull()`, `build_dataset()`,
  and `derive_vars()`. Write it at the end of S3.
- `PROC MEANS` comparison in `.validate_snapshot()`. S0 validates `n_rows`,
  `n_cols`, and variable names from `PROC CONTENTS`. Numeric-summary validation
  is a follow-on once the format SAS emits is settled.
- `equivalence_signoff.yaml` reader and writer. S0 defines the schema in the
  spec and the vignette; the tooling that parses it is only useful once a real
  study is being signed off, in S2.
- `odbc` is not installed on this machine, and S0 does not need it. Installing it
  before S1 is a chore worth doing early on macOS: `brew install unixodbc` plus
  Microsoft's `msodbcsql18` tap, not just `install.packages("odbc")`.
- **Reading a real `library.built`.** Every SAS file in this slice is synthetic.
  Real files carry compression, formats, and legacy encodings the fixture does
  not, which is a class of defect that has already appeared once in this project
  (Latin-1, `hvtiRutilities@183a1cb`). Pointing `snapshot_oracle()` at an actual
  study is a task in S2 and is the first genuine test of the read path.
- **Development stays off the warehouse.** Development happens on macOS,
  execution on the SAS server. Connecting a laptop to `<DW-SERVER>` would land
  clinical data outside the environment SAS was sanctioned to run in, so S1
  develops against mocked connections and real pulls run on the server.
  Credentials are configured by the maintainer and appear in no file here.
