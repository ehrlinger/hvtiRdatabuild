* Informational messages go through the hvtiR family's quiet mode: `options(hvti.quiet = TRUE)`
  silences them. Warnings and errors are never silenced.
* Errors a caller is expected to catch carry an `hvtiRdatabuild_<condition>` class and
  `hvtiRdatabuild_error`: `withdrawn_release`, `stale_snapshot`, `parity_failed`,
  `key_not_unique`, `load_log_mismatch`, `parity_gate`, `connection_failed`, `lock_timeout`,
  `unregistered_parent`, `expect_failed`, `analysis_set_not_written`, `analysis_set_integrity`,
  `stale_analysis_set` and `both_names`. Their messages start with the function's name.
* The stale-analysis-set message carries `hvtiRdatabuild_stale_analysis_set` first and
  `hvtiRutilities_stale_analysis_set` second. The old class goes in the next release.
* `pull_master()` returns `$meta`, which leads with the hvtiR provenance record (`package`,
  `version`, `sha`, `method`, `seed`, `rng_kind`, `time`). `$provenance` is deprecated and goes in
  the next release. The analysis-set sidecar carries the same record, and its `written` time is
  ISO 8601 UTC text that `as.POSIXct()` reads back.
* Renamed arguments, each deprecated for one release with a once-per-session warning of class
  `hvtiRdatabuild_deprecated`. Giving both the old and the new name is an error that names both.
  - `compare_built(id)` is `id_col`, with no default (`"ccfidu"` was one study's column).
  - `parse_legacy_facts(key_var)` is `key_col`, with no default.
  - `pull_master(columns, study_config)` are `var_cols` and `path`.
  - `propose_correction(variable)` is `var_col`.
  - `snapshot_master(out_dir)` is `dir`, and so is `datasets_dir` in `publish_dataset()`,
    `withdraw_dataset_release()` and `freeze_study_pull()`.
  - `freeze_study_pull(study_config)` is `path`.
  - `snapshot_oracle(sas_path, out_path)` are `path` and `file`.
  - `dw_pull(conn)` is `con`.
