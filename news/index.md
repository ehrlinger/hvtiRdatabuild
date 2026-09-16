# Changelog

## hvtiRdatabuild 0.2.2

- Documentation no longer points
  [`dw_pull()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/dw_pull.md)
  users at a `building-a-study-dataset` vignette that does not exist,
  and the SAS migration guide no longer lists the shipped
  [`dw_connect()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/dw_connect.md)
  and
  [`dw_pull()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/dw_pull.md)
  as future work. Prose across the README, vignette and reference pages
  was tightened.

- The SAS migration guide now treats `bd.SAStoR.sas` outputs as general
  downstream data contracts rather than exports owned by their first
  consumer. It shows how the final selection becomes a shared analysis
  set while variable derivation remains in the build layer.

- Analysis-set declarations now reject duplicate variables and require
  every expected row/event count to be one non-negative whole number.
  This prevents duplicate parquet columns from being silently renamed
  and fractional counts from matching after integer truncation.

- Analysis sets resolve their outputs through the study’s logical
  datasets directory, preserving numbered new studies and adopted legacy
  layouts.

## hvtiRdatabuild 0.2.1

- **New
  [`write_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_analysis_set.md)
  and
  [`read_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_analysis_set.md).**
  An analysis set is a declared, checkpointed selection of the built
  dataset: the columns a job reads and the rows it excludes, declared
  under `analysis_sets:` in `_study.yml`, written once to `datasets/` as
  `<name>.parquet` with a sidecar recording its parent and per-rule
  attrition, and read by every job that needs it. Reading stops, rather
  than rebuilding, when the built dataset or the declaration has
  changed.

## hvtiRdatabuild 0.2.0

### Breaking Changes

- Package renamed from `hvtiRdatasets` to `hvtiRdatabuild`. The package
  exports six functions and no data object, so a `...datasets` name
  promised a payload and delivered a pipeline. Update
  [`library()`](https://rdrr.io/r/base/library.html) calls and any
  `hvtiRdatasets::` prefixes. The repository moved to
  `github.com/ehrlinger/hvtiRdatabuild`; GitHub redirects the old URL,
  so an existing `remotes::install_github("ehrlinger/hvtiRdatasets")`
  keeps resolving.
- The print option `hvtiRdatasets.show_ids` is now
  `hvtiRdatabuild.show_ids`. There is no fallback to the old name: a
  stale `options(hvtiRdatasets.show_ids = TRUE)` is ignored and
  identifiers are not printed. That is the conservative direction for a
  flag whose own documentation warns it may emit PHI.

No function changed behaviour, so results are identical to 0.1.2.
