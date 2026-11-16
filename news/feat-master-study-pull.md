* New `pull_master()` selects a cohort and reads its rows from a master view in one
  snapshot-isolation transaction, joined through a session temp table, and records the
  SQL commit, the ids of the corrections applied and the study configuration's checksum.
  It refuses a master that has not passed its parity gate at the deployed SQL commit.
  `cohort_query()` defines a cohort by query, epoch and index (`"first"` or `"all"`), computed in the database, with a
  qualifying encounter before the epoch recorded as a counted stage.
  `build_from_master()` turns the pull into the `build_result` that `derive_vars()`
  consumes. `freeze_study_pull()` publishes the pull as a parquet release carrying its
  provenance in the file, read back with `read_pull_provenance()`, and refuses a study
  configuration changed since the pull.
* New `cohort_unit_id()` and `split_cohort_unit()` key a cohort by MRN and encounter date,
  so a patient with two operations is two units.
* `publish_dataset()` accepts `.parquet` drafts.
