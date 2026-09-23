# hvtiRdatabuild (unreleased)

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
