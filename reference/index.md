# Package index

## Package Overview

Package-level documentation: what the package builds, who it’s for, and
how the verify workflow fits together.

- [`hvtiRdatasets`](https://ehrlinger.github.io/hvtiRdatasets/reference/hvtiRdatasets-package.md)
  [`hvtiRdatasets-package`](https://ehrlinger.github.io/hvtiRdatasets/reference/hvtiRdatasets-package.md)
  : hvtiRdatasets: Build and Verify Analytic Datasets for the HVTI CORR
  Group

## Verify: R Build vs. SAS Oracle

Freeze a SAS-built dataset as a checksummed parquet oracle, then compare
an R-built dataset against it. Use
[`snapshot_oracle()`](https://ehrlinger.github.io/hvtiRdatasets/reference/snapshot_oracle.md)
once per legacy SAS dataset to create the frozen reference; use
[`compare_built()`](https://ehrlinger.github.io/hvtiRdatasets/reference/compare_built.md)
for every R rebuild you want to verify against it.

- [`snapshot_oracle()`](https://ehrlinger.github.io/hvtiRdatasets/reference/snapshot_oracle.md)
  : Freeze a SAS-built dataset as a checksummed parquet oracle
- [`compare_built()`](https://ehrlinger.github.io/hvtiRdatasets/reference/compare_built.md)
  : Compare an R-built dataset against a SAS oracle
- [`print(`*`<built_comparison>`*`)`](https://ehrlinger.github.io/hvtiRdatasets/reference/print.built_comparison.md)
  : Print a dataset comparison
- [`str(`*`<built_comparison>`*`)`](https://ehrlinger.github.io/hvtiRdatasets/reference/str.built_comparison.md)
  : Structure of a dataset comparison, without identifiers

## Pull: Warehouse to R

Read a study’s configuration, open a credentialed warehouse connection,
and pull the modules the study declares. The pull is read-only.

- [`read_study_config()`](https://ehrlinger.github.io/hvtiRdatasets/reference/read_study_config.md)
  : Read and validate a study configuration
- [`dw_connect()`](https://ehrlinger.github.io/hvtiRdatasets/reference/dw_connect.md)
  : Open a connection to the data warehouse
- [`dw_modules()`](https://ehrlinger.github.io/hvtiRdatasets/reference/dw_modules.md)
  : List the available warehouse modules
- [`dw_pull()`](https://ehrlinger.github.io/hvtiRdatasets/reference/dw_pull.md)
  : Pull the enabled warehouse modules for a study
- [`print(`*`<pull_result>`*`)`](https://ehrlinger.github.io/hvtiRdatasets/reference/print.pull_result.md)
  : Print a pull result
