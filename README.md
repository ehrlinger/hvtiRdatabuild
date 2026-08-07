# hvtiRdatasets
<!-- badges: start -->
[![R-CMD-check](https://github.com/ehrlinger/hvtiRdatasets/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/ehrlinger/hvtiRdatasets/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/ehrlinger/hvtiRdatasets/graph/badge.svg)](https://app.codecov.io/gh/ehrlinger/hvtiRdatasets)
[![active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/badges/latest/active.svg)
[![pkgdown](https://github.com/ehrlinger/hvtiRdatasets/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/ehrlinger/hvtiRdatasets/actions/workflows/pkgdown.yaml)

[![R package version](https://img.shields.io/github/r-package/v/ehrlinger/hvtiRdatasets)](https://github.com/ehrlinger/hvtiRdatasets)

[![lint](https://github.com/ehrlinger/hvtiRdatasets/actions/workflows/lint.yaml/badge.svg)](https://github.com/ehrlinger/hvtiRdatasets/actions/workflows/lint.yaml)
<!-- badges: end -->

Builds analysis-ready clinical datasets for the HVTI CORR group, and verifies
them against the legacy SAS datasets they replace.

## Status

Slices S0 (Verify) and S1 (Pull). `snapshot_oracle()` and `compare_built()`
verify an R-built dataset against its SAS oracle. `read_study_config()`,
`dw_connect()`, `dw_modules()`, and `dw_pull()` read a study's warehouse
modules into R. The rest of the pipeline — `build_dataset()`, `derive_vars()`
— arrives in S2–S3.

## Installation

```r
# install.packages("remotes")
remotes::install_github("ehrlinger/hvtiRdatasets")
```

This package imports `hvtiRutilities`, which is **not on CRAN**. The `Remotes:`
field in `DESCRIPTION` points `remotes`/`pak` at `ehrlinger/hvtiRutilities`, so
the command above pulls it in automatically. Installing with plain
`install.packages()` will fail to resolve it.

`arrow` is an optional dependency, required only for writing oracle snapshots.

## Pulling warehouse modules for a study

```r
library(hvtiRdatasets)

# What modules exist, and what each one requires.
dw_modules()

config <- read_study_config("study.yaml")
conn   <- dw_connect(server = "<DW-SERVER>", database = "<DW-DB>", dsn = "HVI_DW")
result <- dw_pull(config, conn)

result$tables    # named list of raw tables, keyed by each module's `output`
result$manifest  # module, output, n_rows, n_cols, pulled_at
```

`dw_pull()` is **read-only**. It never writes to the warehouse — the cohort
write-back the SAS templates perform (`libsql`) is deliberately not ported in
this slice. The re-pull variants (`snapshotpull`, `ccfpull`), which take an
existing built dataset and remap keys because `masterid` stopped being stable
in April 2023, need that write path and arrive in a later slice.

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

## Documentation

- `vignette("coming-from-sas")` — migration guide for SAS users. Start here.

## Design

See `specs/2026-08-04-hvtiRdatasets-design.md`.
