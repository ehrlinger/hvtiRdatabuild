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

Slice S0 (Verify) only. `snapshot_oracle()` and `compare_built()` are
implemented. The pipeline itself — `dw_pull()`, `build_dataset()`,
`derive_vars()` — arrives in S1–S3.

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
