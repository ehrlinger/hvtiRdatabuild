# Changelog

## hvtiRdatabuild 0.3.3

- [`write_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_analysis_set.md)
  builds a set from registered data only, because an analysis set is
  reused by other jobs. It refuses a working read of the study dataset,
  stops and writes nothing.
  - A dataset with no dated version, including one registered before
    dated versions (a manifest entry with no `parquet`), is refused
    before it is read and the message names
    [`hvtiRutilities::update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.html).
    Run it once to convert a legacy registration; sets already written
    read as before.
  - A registered dataset read as working because `HVTI_DATA=working` is
    set is refused with a message that says to unset `HVTI_DATA`.
  - In a final render or an `Rscript` run, hvtiRutilities’ own gate may
    refuse the read first, with its own message.
  - Requires hvtiRutilities 1.5.3, the first release that signals a
    working read.
- The README points analysts to
  [`vignette("registered-datasets", package = "hvtiRutilities")`](https://ehrlinger.github.io/hvtiRutilities/articles/registered-datasets.html),
  which explains dataset registration, version names and which version a
  job reads. It ships with hvtiRutilities 1.5.12 and later.

## hvtiRdatabuild 0.3.2

- The README’s Installation section now leads with `hvtiR::install()`,
  which installs the whole HVTI R family in one call, and then gives
  `pak::pak("ehrlinger/hvtiRdatabuild")` for this package alone.

- Tests and examples pass `renv` and `cleanup` to
  [`hvtiRutilities::study_setup()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_setup.html)
  explicitly, ahead of `hvtiRutilities` turning both on by default. A
  new test fails on any call that leaves them implicit.

- The `hvtiRutilities` floor rises to 1.5.2, the first release whose
  `study_setup()` takes `renv` and `cleanup`.

## hvtiRdatabuild 0.3.1

- The test of an analysis set over a dataset registered before dated
  versions now writes the set as a datasets job would. hvtiRutilities’
  stage gate serves a dataset with no dated version only to the console
  and to datasets or descriptive jobs, so the test’s non-interactive run
  was refused. Test-only.

## hvtiRdatabuild 0.3.0

- **Now requires R 4.4.0 or newer**, up from 4.1.0, to match the rest of
  the HVTI family. `hvtiR::install()` installs the members together, and
  several already required 4.4.0, so on an older R the install failed
  whatever this package declared. **Now requires hvtiRutilities 1.5.1.**

- **The build layer.** Three pieces sit between
  [`dw_pull()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/dw_pull.md)
  and the analysis sets.
  [`build_dataset()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/build_dataset.md)
  joins a study’s patient-level modules on its cohort and keeps
  repeated-event tables beside the result rather than widening them.
  [`derive_vars()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/derive_vars.md)
  runs the study’s own R code, committed with the study, and takes back
  the data with an updated cohort. A `cohort_record`, from
  [`new_cohort_record()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/new_cohort_record.md),
  [`append_cohort_stage()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/append_cohort_stage.md)
  and
  [`cohort_summary()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/cohort_summary.md),
  carries inclusion, exclusion and attrition history through both, in
  order. A missing inclusion value is an error, not an implicit pass or
  exclusion. Duplicate source identifier columns are kept for audit,
  patient identifiers stay stable across joins, and the
  [`print()`](https://rdrr.io/r/base/print.html) and
  [`str()`](https://rdrr.io/r/utils/str.html) methods and callback
  diagnostics never show a patient value.
  [`vignette("coming-from-sas")`](https://ehrlinger.github.io/hvtiRdatabuild/articles/coming-from-sas.md)
  walks the build, study code and attrition through a synthetic example.
  `dplyr` moves from `Suggests` to `Imports`.

- **A stale analysis set no longer stops a draft.**
  [`read_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_analysis_set.md)
  reads a set whose parent or declaration has changed, and signals
  `hvtiRutilities_stale_analysis_set` with the
  [`write_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_analysis_set.md)
  call that updates it. A final render (`HVTI_TEMPLATE_STRICT` set, as
  `render_job(final = TRUE)` does) still stops, with the same commands.
  This reverses the earlier rule that every stale read stopped; a
  damaged set still stops in every render.

- An analysis set’s parent is now the registered version of the built
  dataset when hvtiRutilities registered it as a dated parquet.
  Rebuilding `built.sas7bdat` without registering it no longer makes
  every set stale, because jobs read nothing new until
  [`hvtiRutilities::update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.html)
  registers it. Sets written before this change name the SAS file as
  their parent, so each is stale once after the study’s first
  `update_manifest()`;
  [`write_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_analysis_set.md)
  refreshes it. A dataset still registered the old way is identified by
  its source, as before.

- [`write_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_analysis_set.md)
  and
  [`read_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_analysis_set.md)
  skip the line of text that hvtiRutilities 1.5.1 writes at the head of
  a `manifest.yaml` holding a registered dated version. Without this
  they stopped with “\$ operator is invalid for atomic vectors” on every
  study registered from 1.5.1 on.

- [`write_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_analysis_set.md)
  refuses a set named for a registered dated version, such as
  `built_20261008`, before writing anything. Its parquet would have
  replaced that version, the registered data every job reads.

- `DESCRIPTION` now declares the Quarto command line tool in
  `SystemRequirements`. The vignettes have always needed it to build;
  the field makes that visible to installers and to `R CMD check`.

- Articles on the pkgdown site put the table of contents on the left and
  use the full width of the window, through `pkgdown/extra.css`. The
  installed vignettes are unchanged: the Quarto vignette engine renders
  them in its own minimal format, which has no sidebar layout.

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
