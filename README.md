# hvtiRdatasets

Builds analysis-ready clinical datasets for the HVTI CORR group, and verifies
them against the legacy SAS datasets they replace.

## Status

Slice S0 (Verify) only. `snapshot_oracle()` and `compare_built()` are
implemented. The pipeline itself — `dw_pull()`, `build_dataset()`,
`derive_vars()` — arrives in S1–S3.

## Installation

This repository is local-only for now (no GitHub remote yet). Once it is
pushed to `ehrlinger/hvtiRdatasets`, install with:

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
