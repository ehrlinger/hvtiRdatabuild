# Changelog

## hvtiRdatabuild 0.2.4

- **Master datasets.** Six new functions snapshot, lift and correct the
  master datasets that study builds read.
  [`read_master_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_master_config.md)
  reads a `master.yml` declaring a master’s key, alternate keys and
  parent.
  [`snapshot_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_master.md)
  freezes its SAS builds as parquet and records which parent release
  each was built from, read from the run’s log first.
  [`lift_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/lift_master.md)
  loads a snapshot into the warehouse behind key and full-parity gates
  and creates the master’s view.
  [`backfill_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/backfill_corrections.md),
  [`propose_correction()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/propose_correction.md)
  and
  [`decide_correction()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/decide_correction.md)
  keep an append-only record of corrections the view applies. The bulk
  functions dry-run by default. See
  [`vignette("master-datasets")`](https://ehrlinger.github.io/hvtiRdatabuild/articles/master-datasets.md).
  `duckdb` and `tidyselect` join `Suggests`.

- **An analysis set names its own `event` column.** hvtiRutilities 1.4.0
  made study registration endpoint-neutral: `register_data()` no longer
  takes `event` or `time`, and `study_config()` no longer carries a
  study-wide `cohort`.
  [`write_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_analysis_set.md)
  had counted `n_events` and `n_censored` from that cohort, so under
  1.4.0 every write failed. A set now declares `event:` (one of its
  `vars`) to get both counts, and an `expect` on either count without
  one stops with a message naming the missing key. A set with no `event`
  records `n` alone. A set that relied on the study-wide cohort needs
  the one-line `event:` added, which also changes its declaration hash,
  so
  [`read_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_analysis_set.md)
  asks for one rewrite. hvtiRdatabuild now requires hvtiRutilities 1.4.0
  or later, since its tests and registration fixture use the
  endpoint-neutral `register_data()`.

- **[`snapshot_oracle()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_oracle.md)
  can snapshot a dataset too large for memory.** The new `chunk_rows`
  argument reads the SAS dataset a chunk at a time and writes the chunks
  as row groups of one parquet file. It also records a SHA-256 of the
  SAS source beside the parquet checksum, and writes a `.meta.json`
  sidecar holding each column’s label, SAS format and type, so that
  metadata survives into systems that cannot read R attributes.
  `jsonlite` joins `Suggests`. The source checksum now brackets the
  read, taken before and after; a mismatch removes the parquet and stops
  rather than write a snapshot of a file that changed underneath it.

## hvtiRdatabuild 0.2.3

- **New
  [`publish_dataset()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/publish_dataset.md).**
  A programmer can publish a mutable clinical-data draft as an immutable
  dated release. Publication preserves the draft bytes, verifies that
  the staged copy is readable, records its checksum and shape in
  `dataset-catalog.yml`, and serializes concurrent publishers with a
  catalog lock. Same-day corrections receive revision filenames;
  retrying identical bytes is idempotent, including recovery of a file
  moved before a failed catalog write.

- **New
  [`withdraw_dataset_release()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/withdraw_dataset_release.md).**
  Withdrawal records a reason and an optional replacement in the catalog
  without changing or deleting the published file. The package now
  requires hvtiRutilities 1.3.1, whose study workflow discovers,
  reviews, and explicitly adopts these releases.

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
