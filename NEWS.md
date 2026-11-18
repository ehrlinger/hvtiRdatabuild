# hvtiRdatabuild 0.3.7

* `read_master_config()` refuses a `name`, `snapshots`, `current` or
  `build_program` that yaml did not read as one non-empty string. An unquoted
  `snapshots: .` became `NA`, and `name: .inf` became `"Inf"`; the error says
  to quote the value.

* `propose_corrections()` refuses a row that repeats a correction still
  pending or accepted: same source, key, variable, prior and new value, compared
  in canonical text. The verdict is `duplicate_pending` or `duplicate_accepted`,
  and as with any other refused row the whole file is refused. A proposed
  correction leaves the source unchanged until it is accepted, so the same file
  submitted twice used to be appended twice. An assertion whose correction was
  rejected or superseded may be proposed again. A later row of the same file
  making the same assertion is `duplicate_in_file`. On SQL Server an append locks
  each source's corrections first, so two submissions made at once cannot both
  append the same assertion.

# hvtiRdatabuild 0.3.6

* New interim tools for correcting warehouse source views, superseded by the HVTR
  registry: `generate_corrections_sql()` writes each declared source's corrections tables
  and its corrected, applied, stale and conflicts views, covering every column;
  `write_corrections_template()`, `propose_corrections()` and `decide_corrections()` take
  a whole submission and refuse it whole if any row fails, with a verdict per row and no
  values in any message; `retire_filled_corrections()` retires fill-ins upstream has
  caught up with; and `study_correction_candidates()` turns a study's own fixes into
  candidate corrections against its frozen pull. In these views, accepted corrections to one cell
  that disagree do not resolve to the latest: neither applies until one is superseded.
* `read_master_config()` reads `sources` (correctable source views and their keys) and
  `deciders` from `master.yml`.
* On SQL Server, `table_types()` now carries a decimal column's precision and scale, so the
  master corrections view built by `lift_master()` no longer casts to a bare `decimal`,
  which SQL Server reads as `decimal(18,0)` and rounds.
* `parse_value()` now parses logical columns.

* `propose_corrections()` now checks that each key survives the warehouse's cast to its
  key column unchanged, as it already did for values. Before, an integer key `1.2` loaded
  as `1`, so a correction could name, and after acceptance change, a different row. Such
  a key is now `unknown_key`. A submitted date, timestamp or number must also be the
  whole of its supported form (`YYYY-MM-DD`, that plus `HH:MM[:SS[.fff]]`, or a plain
  decimal): `2020-01-01junk` was read as `2020-01-01` and could name that row, and
  `0x23` was read as 35. Such a key is `unknown_key` and such a value `does_not_cast`.
* `study_correction_candidates()` refuses a missing key in the pull or in `data`
  (`missing_key`); before, a missing key read as the text `"NA"` and could match a real
  key of that value. Its composite keys are now collision-safe, whatever the values
  contain.

* `propose_corrections()`, `decide_corrections()`, `retire_filled_corrections()`,
  `study_correction_candidates()` and `read_pull_provenance()` now have examples that
  run, on synthetic data in DuckDB: a whole propose, decide and retire round trip, and a
  study fix turned into a candidate correction. Their examples were comments only.

* `dw_pull()` now has an example that runs, pulling the `base` module from synthetic
  views in DuckDB, whose in-memory catalog resolves the module SQL's three-part names.
  `dw_connect()`'s example is real code under `\dontrun{}`, since it needs the ODBC driver
  and warehouse credentials, in place of a commented-out call. Both examples were
  comments only.
* DESCRIPTION spells out CORR (Cardiovascular Outcomes, Registries and Research) and HVTI
  (Heart, Vascular and Thoracic Institute), matching hvtiRutilities.

# hvtiRdatabuild 0.3.5

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
* `compare_built()` writes numeric ids losslessly, so two distinct doubles never become one id,
  and it refuses whole-number ids beyond 2^53, which a double cannot hold exactly.
* `read_analysis_set()` holds the study's manifest lock, shared, while it verifies the sidecar,
  the manifest entry and the parquet's hash and reads the parquet, so a writer cannot replace the
  parquet between the check and the read.

* Informational messages go through the hvtiR family's quiet mode: `options(hvti.quiet = TRUE)`
  silences them. Warnings and errors are never silenced.
* Quiet mode cannot hide unfinished work. `snapshot_master()` warns, with class
  `hvtiRdatabuild_snapshot_failed`, when a historical snapshot fails, naming the files.
  `backfill_corrections()` warns, with class `hvtiRdatabuild_incomplete_backfill`, when a legacy
  fact is unresolved or a statement unparsed, giving counts and program line numbers only. Its
  result gains `unparsed`, `unresolved_lines` and `unparsed_lines`.
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
  ISO 8601 local time with its UTC offset, which `as.POSIXct()` reads back.
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
* A failed `dw_connect()` now says what failed, in its message and in the error's `kind` field:
  the driver or DSN would not load, the server could not be reached (DNS or route), the TLS
  handshake failed, or the login was refused. The certificate advice appears only where a
  certificate can be the cause. The driver's own message is still never shown.

* `cohort_query()` takes `criteria`: inclusion and exclusion criteria evaluated in the
  warehouse inside `pull_master()`'s transaction, each a counted cohort stage. A
  criterion (`criterion()`) wraps a test: `master_row()`, `view_rows()` (rows of another
  view in a day window, judged by `pick = "any"`, `"all"` or `"nearest"`), or
  `any_of()` / `all_of()`. Only keys and flags leave the database.
* No clinical defaults: `role`, `undetermined`, `window`, `pick`, `date_col` and, with
  `index = "first"`, `index_on` are required. `index_on = "eligible"` lets a patient's
  later encounter be the index when an earlier one is excluded.
* A unit a criterion cannot decide follows its `undetermined` route: exclude, keep, or
  chart review. `review_criterion()`, `review_list()` and `apply_review()` record review
  decisions from a checksummed file with declared reason codes, as `review` stages.
  `build_from_master()` and `freeze_study_pull()` refuse a pull awaiting review.
* `local_criterion()` decides a criterion in R from a file outside the warehouse, after
  the snapshot, and records the file's SHA-256.
* `review` is a fourth cohort stage source.
* `pull_master()` checks that every candidate unit matches one master row before any
  criterion runs, so a criterion can no longer filter a duplicate key out of sight.

* After chart review moves a unit back to the criterion that routed it, `apply_review()`
  rebuilds each later criterion's met, not met and undetermined tally from the units
  that reached it, so a stage's provenance agrees with its counts. The figures evaluated
  at the pull are kept beside the tally, labelled, where they differ. `pull_master()`
  keeps each unit's outcome at every warehouse and local criterion in `review$outcomes`.
* A pull saved while awaiting review before `review$outcomes` existed cannot have its
  stages recounted. `apply_review()` refuses decisions that would change a counted stage
  on such a pull (`hvtiRdatabuild_review_outcomes_missing`); pull again with
  `pull_master()` and apply the decisions to the new pull. Decisions that change no
  counted stage are applied as before.

* Documentation sweep before 0.3.5. `apply_review()` and `review_list()` gain a runnable
  example on synthetic data. The README's status section lists the stages that ship,
  `build_dataset()` and `derive_vars()` among them, which it still called future work; it
  links `vignette("master-datasets")`, and says a stale analysis set is read with a note in
  a draft and refused in a final render. `vignette("master-datasets")` calls
  `propose_correction(var_col =)`, so it no longer prints a deprecation warning, and points
  to `pull_master()` and `build_from_master()` for reading a master into a study.
  `vignette("coming-from-sas")` says `compare_built()` matches ids exactly, without
  trimming, and that a row whose `exclude` rule is `NA` is kept and counted in `n_na_kept`,
  with the rule to write when the SAS step deleted it.

# hvtiRdatabuild 0.3.4

* `backfill_corrections()`, `propose_correction()` and `decide_correction()` are
  deprecated. Corrections to master datasets move to the HVTR registry, and
  hvtiRdatabuild will read corrected data from it rather than record corrections
  itself. The functions still work and warn on every call with class
  `deprecatedWarning`; set `options(hvtiRdatabuild.warn_deprecated_corrections = FALSE)`
  to silence the warning (#101).

* The `write_analysis_set()` and `read_analysis_set()` examples, and the test
  helper, call `hvtiRutilities::register_data(file =)` rather than the
  deprecated `built =`, so they no longer warn. The `hvtiRutilities` floor
  rises to 1.5.20, the first release with `file =`.

# hvtiRdatabuild 0.3.3

* `write_analysis_set()` builds a set from registered data only, because an analysis set is
  reused by other jobs. It refuses a working read of the study dataset, stops and writes
  nothing.
  - A dataset with no dated version, including one registered before dated versions (a
    manifest entry with no `parquet`), is refused before it is read and the message names
    `hvtiRutilities::update_manifest()`. Run it once to convert a legacy registration; sets
    already written read as before.
  - A registered dataset read as working because `HVTI_DATA=working` is set is refused with a
    message that says to unset `HVTI_DATA`.
  - In a final render or an `Rscript` run, hvtiRutilities' own gate may refuse the read first,
    with its own message.
  - Requires hvtiRutilities 1.5.3, the first release that signals a working read.

* The README points analysts to `vignette("registered-datasets", package = "hvtiRutilities")`,
  which explains dataset registration, version names and which version a job reads. It ships
  with hvtiRutilities 1.5.12 and later.

# hvtiRdatabuild 0.3.2

* The README's Installation section now leads with `hvtiR::install()`, which
  installs the whole HVTI R family in one call, and then gives
  `pak::pak("ehrlinger/hvtiRdatabuild")` for this package alone.

* Tests and examples pass `renv` and `cleanup` to `hvtiRutilities::study_setup()` explicitly, ahead of
  `hvtiRutilities` turning both on by default. A new test fails on any call that leaves them implicit.
* The `hvtiRutilities` floor rises to 1.5.2, the first release whose `study_setup()` takes `renv` and `cleanup`.

# hvtiRdatabuild 0.3.1

* The test of an analysis set over a dataset registered before dated versions
  now writes the set as a datasets job would. hvtiRutilities' stage gate serves
  a dataset with no dated version only to the console and to datasets or
  descriptive jobs, so the test's non-interactive run was refused. Test-only.

# hvtiRdatabuild 0.3.0

* **Now requires R 4.4.0 or newer**, up from 4.1.0, to match the rest of the
  HVTI family. `hvtiR::install()` installs the members together, and several
  already required 4.4.0, so on an older R the install failed whatever this
  package declared. **Now requires hvtiRutilities 1.5.1.**

* **The build layer.** Three pieces sit between `dw_pull()` and the analysis
  sets. `build_dataset()` joins a study's patient-level modules on its cohort
  and keeps repeated-event tables beside the result rather than widening them.
  `derive_vars()` runs the study's own R code, committed with the study, and
  takes back the data with an updated cohort. A `cohort_record`, from
  `new_cohort_record()`, `append_cohort_stage()` and `cohort_summary()`, carries
  inclusion, exclusion and attrition history through both, in order. A missing
  inclusion value is an error, not an implicit pass or exclusion. Duplicate
  source identifier columns are kept for audit, patient identifiers stay stable
  across joins, and the `print()` and `str()` methods and callback diagnostics
  never show a patient value. `vignette("coming-from-sas")` walks the build,
  study code and attrition through a synthetic example. `dplyr` moves from
  `Suggests` to `Imports`.

* **A stale analysis set no longer stops a draft.** `read_analysis_set()`
  reads a set whose parent or declaration has changed, and signals
  `hvtiRutilities_stale_analysis_set` with the `write_analysis_set()` call that
  updates it. A final render (`HVTI_TEMPLATE_STRICT` set, as
  `render_job(final = TRUE)` does) still stops, with the same commands. This
  reverses the earlier rule that every stale read stopped; a damaged set still
  stops in every render.

* An analysis set's parent is now the registered version of the built dataset
  when hvtiRutilities registered it as a dated parquet. Rebuilding
  `built.sas7bdat` without registering it no longer makes every set stale,
  because jobs read nothing new until `hvtiRutilities::update_manifest()`
  registers it. Sets written before this change name the SAS file as their
  parent, so each is stale once after the study's first `update_manifest()`;
  `write_analysis_set()` refreshes it. A dataset still registered the old way
  is identified by its source, as before.

* `write_analysis_set()` and `read_analysis_set()` skip the line of text that
  hvtiRutilities 1.5.1 writes at the head of a `manifest.yaml` holding a
  registered dated version. Without this they stopped with "$ operator is
  invalid for atomic vectors" on every study registered from 1.5.1 on.

* `write_analysis_set()` refuses a set named for a registered dated version,
  such as `built_20261008`, before writing anything. Its parquet would have
  replaced that version, the registered data every job reads.

* `DESCRIPTION` now declares the Quarto command line tool in
  `SystemRequirements`. The vignettes have always needed it to build; the
  field makes that visible to installers and to `R CMD check`.

* Articles on the pkgdown site put the table of contents on the left and use
  the full width of the window, through `pkgdown/extra.css`. The installed
  vignettes are unchanged: the Quarto vignette engine renders them in its own
  minimal format, which has no sidebar layout.

# hvtiRdatabuild 0.2.4

* **Master datasets.** Six new functions snapshot, lift and correct the master
  datasets that study builds read. `read_master_config()` reads a `master.yml`
  declaring a master's key, alternate keys and parent. `snapshot_master()`
  freezes its SAS builds as parquet and records which parent release each was
  built from, read from the run's log first. `lift_master()` loads a snapshot
  into the warehouse behind key and full-parity gates and creates the master's
  view. `backfill_corrections()`, `propose_correction()` and
  `decide_correction()` keep an append-only record of corrections the view
  applies. The bulk functions dry-run by default. See
  `vignette("master-datasets")`. `duckdb` and `tidyselect` join `Suggests`.

* **An analysis set names its own `event` column.** hvtiRutilities 1.4.0 made
  study registration endpoint-neutral: `register_data()` no longer takes
  `event` or `time`, and `study_config()` no longer carries a study-wide
  `cohort`. `write_analysis_set()` had counted `n_events` and `n_censored` from
  that cohort, so under 1.4.0 every write failed. A set now declares `event:`
  (one of its `vars`) to get both counts, and an `expect` on either count
  without one stops with a message naming the missing key. A set with no
  `event` records `n` alone. A set that relied on the study-wide cohort needs
  the one-line `event:` added, which also changes its declaration hash, so
  `read_analysis_set()` asks for one rewrite.
  hvtiRdatabuild now requires hvtiRutilities 1.4.0 or later, since its tests
  and registration fixture use the endpoint-neutral `register_data()`.

* **`snapshot_oracle()` can snapshot a dataset too large for memory.** The new
  `chunk_rows` argument reads the SAS dataset a chunk at a time and writes the
  chunks as row groups of one parquet file. It also records a SHA-256 of the
  SAS source beside the parquet checksum, and writes a `.meta.json` sidecar
  holding each column's label, SAS format and type, so that metadata survives
  into systems that cannot read R attributes. `jsonlite` joins `Suggests`. The
  source checksum now brackets the read, taken before and after; a mismatch
  removes the parquet and stops rather than write a snapshot of a file that
  changed underneath it.

# hvtiRdatabuild 0.2.3

* **New `publish_dataset()`.** A programmer can publish a mutable clinical-data
  draft as an immutable dated release. Publication preserves the draft bytes,
  verifies that the staged copy is readable, records its checksum and shape in
  `dataset-catalog.yml`, and serializes concurrent publishers with a catalog
  lock. Same-day corrections receive revision filenames; retrying identical
  bytes is idempotent, including recovery of a file moved before a failed
  catalog write.

* **New `withdraw_dataset_release()`.** Withdrawal records a reason and an
  optional replacement in the catalog without changing or deleting the
  published file. The package now requires hvtiRutilities 1.3.1, whose study
  workflow discovers, reviews, and explicitly adopts these releases.

# hvtiRdatabuild 0.2.2

* Documentation no longer points `dw_pull()` users at a
  `building-a-study-dataset` vignette that does not exist, and the SAS migration
  guide no longer lists the shipped `dw_connect()` and `dw_pull()` as future
  work. Prose across the README, vignette and reference pages was tightened.

* The SAS migration guide now treats `bd.SAStoR.sas` outputs as general
  downstream data contracts rather than exports owned by their first consumer.
  It shows how the final selection becomes a shared analysis set while variable
  derivation remains in the build layer.

* Analysis-set declarations now reject duplicate variables and require every
  expected row/event count to be one non-negative whole number. This prevents
  duplicate parquet columns from being silently renamed and fractional counts
  from matching after integer truncation.

* Analysis sets resolve their outputs through the study's logical datasets
  directory, preserving numbered new studies and adopted legacy layouts.

# hvtiRdatabuild 0.2.1

* **New `write_analysis_set()` and `read_analysis_set()`.** An analysis set
  is a declared, checkpointed selection of the built dataset: the columns a
  job reads and the rows it excludes, declared under `analysis_sets:` in
  `_study.yml`, written once to `datasets/` as `<name>.parquet` with a sidecar
  recording its parent and per-rule attrition, and read by every job that
  needs it. Reading stops, rather than rebuilding, when the built dataset or
  the declaration has changed.

# hvtiRdatabuild 0.2.0

## Breaking Changes

* Package renamed from `hvtiRdatasets` to `hvtiRdatabuild`. The package exports six
  functions and no data object, so a `...datasets` name promised a payload and delivered a
  pipeline. Update `library()` calls and any `hvtiRdatasets::` prefixes. The repository
  moved to `github.com/ehrlinger/hvtiRdatabuild`; GitHub redirects the old URL, so an
  existing `remotes::install_github("ehrlinger/hvtiRdatasets")` keeps resolving.
* The print option `hvtiRdatasets.show_ids` is now `hvtiRdatabuild.show_ids`. There is no
  fallback to the old name: a stale `options(hvtiRdatasets.show_ids = TRUE)` is ignored and
  identifiers are not printed. That is the conservative direction for a flag whose own
  documentation warns it may emit PHI.

No function changed behaviour, so results are identical to 0.1.2.

# hvtiRdatasets 0.1.2

Adds this changelog. No function changed, so results are identical to 0.1.1.

- `NEWS.md` covers 0.1.0 and 0.1.1 retroactively, reconstructed from the commit
  history. It ships with the package, so `utils::news(package = "hvtiRdatabuild")`
  reads it and the pkgdown site gains a Changelog.
- `AGENTS.md` now says which changes bump the version and which do not. The rule
  was unconditional, but the docs-only commits on `main` had never bumped
  anything, and a rule the repository visibly does not follow teaches the wrong
  lesson. Files excluded by `.Rbuildignore` do not ship, so they do not bump.

# hvtiRdatasets 0.1.1

Slice S1 (Pull). The package can now read a study's configuration, open a
credentialed warehouse connection, and pull the modules the study declares.
Nothing in the S0 verify path changed, so a comparison run against 0.1.0
returns the same verdicts.

## New features

- `read_study_config()` reads a study YAML into a validated configuration. An
  unknown key is an error rather than a silent ignore, and `modules` must be a
  sequence: a YAML mapping there is rejected.
- `dw_connect()` opens the warehouse connection and reports which credential
  source it resolved. The ladder stops at the first one available: Kerberos
  integrated authentication, then a named ODBC DSN, then `HVI_DW_UID` and
  `HVI_DW_PWD` from `~/.Renviron`, then `keyring`. A DSN outranks `.Renviron`
  because the driver reads a DSN password and it never enters R's memory, where
  `Sys.getenv()` prints it and a handler dumping the environment on error
  captures it. A credential file with a loose mode is an error, not a warning,
  and a project-level `.Renviron` shadowing the user-level one warns rather
  than failing somewhere further downstream.
- `dw_modules()` returns the available warehouse modules as a data frame of
  `module`, `output`, `join_key`, and `optional`. The definitions ship as YAML
  under `inst/extdata/modules/`, not as R code, so the SQL can carry
  placeholders and the real warehouse, schema, and cohort names arrive from
  `study.yaml` at run time. That is what keeps site identifiers out of a public
  repository.
- `dw_pull()` pulls the modules a study declares and returns the raw tables
  with a manifest of `module`, `output`, `n_rows`, `n_cols`, and `pulled_at`.
  It is read-only, and a test asserts that no `DBI` write entry point is ever
  called. Colliding module output names error before any query runs, and an
  empty required module is an error.
- `print.pull_result()` prints the manifest shape only, never row-level data,
  so there are no identifiers to redact.

## Scope limits worth knowing

- `compare_built()` measures `bdbase` and `bdstat` only. It requires one row
  per identifier on both sides, and `echo`, `fup`, and `bdevents` are one row
  per event by construction (echocardiogram, follow-up visit, reoperation), so
  a `patid` legitimately repeats and the comparison errors on them.
  Composite-key comparison is the eventual fix, deferred to a later slice.
- The cohort write-back the SAS templates perform (`libsql`) is not ported. The
  re-pull variants that need it, `snapshotpull` and `ccfpull`, arrive with it.

## Documentation and infrastructure

- Roxygen markdown is enabled, so cross-references in the roxygen blocks
  resolve.
- Regenerated with roxygen2 8.1.0, with CI pinned to that version so `man/`
  does not drift against whatever the runner happens to install.
- The repository is on the house CI standard: `R CMD check` across platforms,
  the PDF manual build, `lintr`, the pkgdown site build, and coverage upload.
  `DESCRIPTION` now lists the pkgdown URL.

# hvtiRdatasets 0.1.0

First release. Slice S0 (Verify): freeze a SAS-built dataset as a checksummed
reference, then compare an R rebuild against it.

## New features

- `snapshot_oracle()` reads a SAS dataset once with `haven`, writes parquet,
  and records a SHA-256. A SAS dataset on a shared volume can be regenerated at
  any time, and when it is, every comparison that passed against it silently
  stops meaning anything. Compare against the snapshot, and cite the checksum.
- `compare_built()` joins an R build to its oracle on an identifier and
  classifies every variable as `identical`, `within_tolerance`, `differs`,
  `absent_in_r`, `absent_in_sas`, or `type_mismatch`.
- `print.built_comparison()` and `str.built_comparison()` summarise a
  comparison without printing identifiers, which may be PHI.

## Design notes

- `compare_built()` returns a table and never an overall pass/fail. Several
  hundred variables collapsed into one boolean turns a real difference into a
  green check. Read the table.
- Row-set differences are reported apart from value differences. An identifier
  present on one side only is a cohort discrepancy, a different class of
  problem from a miscomputed variable, and reporting the two together hides
  both.
- A difference is not automatically an R bug. SAS orders missing numerics below
  all values, so `if bmi < 18.5` classifies a missing BMI as underweight where
  R gives `NA`. Record those cases in `equivalence_signoff.yaml` as
  `intentional_divergence`.
- The snapshot does not take `haven` out of the chain of custody, it confines
  it to one audited step. A misread is faithfully preserved in the parquet, so
  supply `expect` to validate the conversion against SAS-side `PROC CONTENTS`
  output rather than treating a clean round-trip as a correct read.

## No PHI in this repository

Test fixtures are invented and say so. `.gitignore` blocks `*.sas7bdat` and
`*.parquet`, with one deliberate exception for the synthetic
`inst/extdata/oracle_small.sas7bdat`. The integration test against a real study
runs only when `HVTI_ORACLE_DIR` points at real SAS datasets, a directory that
lives outside this repository, and its assertions are on shape and verdicts
only, so no patient value can reach a failure message.
