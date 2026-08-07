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
