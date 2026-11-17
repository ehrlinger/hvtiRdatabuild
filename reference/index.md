# Package index

## Package Overview

Package-level documentation: what the package builds, who it’s for, and
how the verify workflow fits together.

- [`hvtiRdatabuild`](https://ehrlinger.github.io/hvtiRdatabuild/reference/hvtiRdatabuild-package.md)
  [`hvtiRdatabuild-package`](https://ehrlinger.github.io/hvtiRdatabuild/reference/hvtiRdatabuild-package.md)
  : hvtiRdatabuild: Build and Verify Analytic Datasets for the HVTI CORR
  Group

## Verify: R Build vs. SAS Oracle

Freeze a SAS-built dataset as a checksummed parquet oracle, then compare
an R-built dataset against it. Use
[`snapshot_oracle()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_oracle.md)
once per legacy SAS dataset to create the frozen reference; use
[`compare_built()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/compare_built.md)
for every R rebuild you want to verify against it.

- [`snapshot_oracle()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_oracle.md)
  : Freeze a SAS-built dataset as a checksummed parquet oracle
- [`compare_built()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/compare_built.md)
  : Compare an R-built dataset against a SAS oracle
- [`print(`*`<built_comparison>`*`)`](https://ehrlinger.github.io/hvtiRdatabuild/reference/print.built_comparison.md)
  : Print a dataset comparison
- [`str(`*`<built_comparison>`*`)`](https://ehrlinger.github.io/hvtiRdatabuild/reference/str.built_comparison.md)
  : Structure of a dataset comparison, without identifiers

## Pull: Warehouse to R

Read a study’s configuration, open a credentialed warehouse connection,
and pull the modules the study declares. The pull is read-only.

- [`read_study_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_study_config.md)
  : Read and validate a study configuration
- [`dw_connect()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/dw_connect.md)
  : Open a connection to the data warehouse
- [`dw_modules()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/dw_modules.md)
  : List the available warehouse modules
- [`dw_pull()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/dw_pull.md)
  : Pull the enabled warehouse modules for a study
- [`print(`*`<pull_result>`*`)`](https://ehrlinger.github.io/hvtiRdatabuild/reference/print.pull_result.md)
  : Print a pull result

## Pull: Master views to a study

Define a cohort of encounters, select and pull it from a master view in
one consistent read, build from the pull, and freeze it with its
provenance.

- [`cohort_unit_id()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/cohort_unit_id.md)
  : Identify a cohort unit by MRN and encounter date
- [`split_cohort_unit()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/split_cohort_unit.md)
  : Split cohort unit identifiers into MRN and encounter date
- [`cohort_query()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/cohort_query.md)
  : Define a cohort by a query on a master view
- [`print(`*`<cohort_query>`*`)`](https://ehrlinger.github.io/hvtiRdatabuild/reference/print.cohort_query.md)
  : Print a cohort query
- [`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md)
  : Pull a study's cohort from a master view
- [`print(`*`<master_pull>`*`)`](https://ehrlinger.github.io/hvtiRdatabuild/reference/print.master_pull.md)
  [`str(`*`<master_pull>`*`)`](https://ehrlinger.github.io/hvtiRdatabuild/reference/print.master_pull.md)
  : Print a master pull
- [`build_from_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/build_from_master.md)
  : Build a study dataset from a master pull
- [`freeze_study_pull()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/freeze_study_pull.md)
  : Freeze a study's pull from a master view
- [`read_pull_provenance()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_pull_provenance.md)
  : Read the provenance a frozen pull carries

## Pull: Cohort criteria

Declare inclusion and exclusion criteria for a cohort query. Each is
evaluated in the warehouse inside the pull, counted as its own stage,
and states every clinical choice itself.

- [`criterion()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/criterion.md)
  : Declare an inclusion or exclusion criterion
- [`master_row()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/master_row.md)
  : Test a condition on the master row
- [`view_rows()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/view_rows.md)
  : Test rows of another view in a window around the encounter
- [`any_of()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/any_of.md)
  [`all_of()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/any_of.md)
  : Combine tests
- [`local_criterion()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/local_criterion.md)
  : Declare a criterion evaluated in R on a file the study holds
- [`review_criterion()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/review_criterion.md)
  : Declare a criterion decided at chart review
- [`review_list()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/review_list.md)
  : List what a pull needs decided at chart review
- [`apply_review()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/apply_review.md)
  : Record chart-review decisions on a pull

## Build: Assemble and Derive

Join the pulled modules into a study’s built dataset, run its
study-specific derivation code, and carry the cohort’s inclusion and
exclusion history through both in order.

- [`build_dataset()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/build_dataset.md)
  : Assemble the patient-level dataset
- [`derive_vars()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/derive_vars.md)
  : Apply study-specific variable derivations
- [`new_cohort_record()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/new_cohort_record.md)
  : Create an ordered cohort history
- [`append_cohort_stage()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/append_cohort_stage.md)
  : Append an outcome stage to a cohort history
- [`cohort_summary()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/cohort_summary.md)
  : Summarize cohort attrition without patient identifiers
- [`print(`*`<build_result>`*`)`](https://ehrlinger.github.io/hvtiRdatabuild/reference/print.build_result.md)
  : Print a built dataset result without patient values
- [`str(`*`<build_result>`*`)`](https://ehrlinger.github.io/hvtiRdatabuild/reference/str.build_result.md)
  : Safely inspect a built dataset result
- [`print(`*`<derive_result>`*`)`](https://ehrlinger.github.io/hvtiRdatabuild/reference/print.derive_result.md)
  : Print a derived dataset result without patient values
- [`str(`*`<derive_result>`*`)`](https://ehrlinger.github.io/hvtiRdatabuild/reference/str.derive_result.md)
  : Safely inspect a derived dataset result
- [`str(`*`<cohort_record>`*`)`](https://ehrlinger.github.io/hvtiRdatabuild/reference/str.cohort_record.md)
  : Safely inspect a cohort record

## Analysis sets

Write and read declared, checkpointed selections of a study’s built
dataset.

- [`write_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_analysis_set.md)
  : Write an analysis set
- [`read_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_analysis_set.md)
  : Read an analysis set

## Dataset publication

Turn a mutable draft into an immutable dated release, or withdraw a
release without changing its bytes.

- [`publish_dataset()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/publish_dataset.md)
  : Publish an immutable dataset release
- [`withdraw_dataset_release()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/withdraw_dataset_release.md)
  : Withdraw a published dataset release

## Master datasets

Snapshot and lift the master datasets studies read.

- [`read_master_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_master_config.md)
  : Read a master dataset's configuration
- [`snapshot_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_master.md)
  : Snapshot a master dataset to parquet, with its lineage
- [`lift_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/lift_master.md)
  : Lift a master's parquet snapshot into the warehouse as a view

## Corrections to source views (interim)

Interim intake for corrections to warehouse source views, superseded by
the HVTR registry, which takes over the template and the tables
unchanged.

- [`generate_corrections_sql()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/generate_corrections_sql.md)
  : Generate the correction tables and views for a master's sources
- [`write_corrections_template()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_corrections_template.md)
  : Write an empty correction submission template
- [`propose_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/propose_corrections.md)
  : Propose a batch of corrections from a filled template
- [`decide_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/decide_corrections.md)
  : Decide a batch of corrections
- [`retire_filled_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/retire_filled_corrections.md)
  : Retire fill-ins that upstream has caught up with
- [`study_correction_candidates()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/study_correction_candidates.md)
  : Turn a study's own data fixes into candidate corrections

## Deprecated

Corrections to master datasets move to the HVTR registry; this package
will read corrected data from it. These still work and warn on every
call.

- [`backfill_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/backfill_corrections.md)
  : Backfill a master's corrections from its SAS build, and regenerate
  its view
- [`propose_correction()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/propose_correction.md)
  : Propose a correction to a single cell of a master
- [`decide_correction()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/decide_correction.md)
  : Decide a correction: accept, reject, supersede or bake it
