* `snapshot_master()` compares the source SAS file's sha256 with the one its sidecar records, and
  snapshots a rebuilt current master again instead of skipping it. `lift_master()` refuses a
  snapshot whose current build has changed since it was taken.
* `lift_master()` names the base table for the snapshot's release and the first 12 hex digits of
  its sha256, and the load log records the parquet's sha256 with each row group. Re-lifting a
  rebuilt master loads a new base table and moves the view to it, where it used to skip the row
  groups already logged. A load log written for a different parquet now stops the load.
* `publish_dataset()` on bytes identical to a withdrawn release is an error that names the
  withdrawn release and says how to reinstate it. It used to return the withdrawn record as if publication had worked.
* `write_analysis_set()` counts each event code explicitly: `n_censored` (0), `n_events` (1),
  `n_other_events` (any other code) and `n_event_missing` (`NA`). `n_censored` was `n` minus the
  events, which counted competing risks and missing codes as censored. `expect:` accepts the two
  new counts.
* A patient whose value is `NA` on an exclusion rule is still kept, for SAS parity, and is now
  counted at each rule they reach in a new attrition column, `n_na_kept`.
* `write_analysis_set()` holds the study's manifest lock while it writes, and the sidecar records
  the parquet's sha256. `read_analysis_set()` stops when the sidecar does not describe the parquet
  beside it. A sidecar written before this change is not checked until the set is rewritten.
* `compare_built()` matches numeric ids by value: a double `100000` in a SAS oracle and an integer
  `100000L` in R no longer show up as row drift.
* `dw_connect()` defaults to `trust_certificate = FALSE`, so the warehouse server's TLS certificate
  is checked. A failed connection that checked it says how to install the CA chain, and that
  `trust_certificate = TRUE` is a stop-gap only.
* The analysis-set examples call `hvtiRutilities::register_data(file = , root = )`, and
  exclusions pass `patient_id_col` to `hvtiPlotR::hv_consort_start()`.
