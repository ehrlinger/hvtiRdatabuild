# Pull a study's cohort from a master view

Selects a cohort and reads its rows from a master view in **one
transaction under snapshot isolation**, so the cohort, its data, the
corrections applied to it and the deployment it came from describe one
state of the warehouse even while decisions, loads or deployments
commit.

## Usage

``` r
pull_master(
  con,
  master,
  cohort,
  var_cols,
  path,
  mrn_col = "mrn",
  date_col = "encounter_date",
  dialect = c("mssql", "duckdb"),
  applied_view = paste0(master, "_corrections_applied"),
  deployment_view = paste0(master, "_deployment"),
  parity_view = paste0(master, "_parity"),
  columns,
  study_config
)
```

## Arguments

- con:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  to the warehouse, or to duckdb in tests.

- master:

  Character. The master view, optionally schema-qualified
  (`"dbo.master_cardiac"`).

- cohort:

  A
  [`cohort_query()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/cohort_query.md),
  or a
  [`new_cohort_record()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/new_cohort_record.md)
  built on
  [`cohort_unit_id()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/cohort_unit_id.md)
  units (`patient_id_col = "cohort_unit"`).

- var_cols:

  Character. The study's columns, besides the key.

- path:

  Character. Path to the study configuration file that defines this
  pull. Its checksum is recorded in the provenance.

- mrn_col, date_col:

  Character. The master's key columns.

- dialect:

  `"mssql"` (the warehouse) or `"duckdb"` (tests).

- applied_view, deployment_view, parity_view:

  Character. The master's applied-corrections, deployment and
  parity-verdict views.

- columns:

  Deprecated; use `var_cols`.

- study_config:

  Deprecated; use `path`.

## Value

An object of class `master_pull`: a list with `data` (one row per active
unit: the key columns, `var_cols` and `cohort_unit`), `cohort` (the
cohort record, ending with the `in_master` stage) and `meta`: the
family's provenance record (`package`, `version`, `sha`, `method`,
`seed`, `rng_kind`, `time`), then `master`, `sql_commit`,
`applied_correction_ids`, `corrections_in_effect`, `parity_verified_at`,
`read_at`, `columns`, `cohort_definition`, `study_config_sha256`,
`n_cohort`, `n_matched` and `n_unmatched`. The same pull fields without
the provenance record are also in `provenance`, which is deprecated and
goes in the next release; read `meta`. `corrections_in_effect` holds
every correction id applied anywhere in the master in the same snapshot,
including any that changed who qualified.

## Details

The cohort's keys go into a **session temp table**, which is joined to
the master inside the database. For a
[`cohort_query()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/cohort_query.md)
the epoch, the index and the earlier- encounter flag are computed in
SQL, so no key outside the cohort leaves the database. For a supplied
[`new_cohort_record()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/new_cohort_record.md)
of
[`cohort_unit_id()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/cohort_unit_id.md)
units, its active units are loaded. The temp table is dropped before
commit and never outlives the connection, so no patient list persists in
the warehouse.

The master must have **passed its parity gate at the deployed SQL
commit**: the most recent verdict in `parity_view` for that commit must
be `"pass"`. Otherwise nothing is pulled. The gate is read in the same
snapshot as the data.

The study configuration's SHA-256 is recorded when the pull runs, so
[`freeze_study_pull()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/freeze_study_pull.md)
can refuse a configuration that changed afterwards.

The returned cohort ends with an `in_master` stage that excludes units
with no master row, so the data match the active cohort exactly. A unit
matching more than one master row stops the pull, because the key is
meant to be unique. Nothing in an error or in printed output names a
patient.

## See also

[`cohort_query()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/cohort_query.md),
[`build_from_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/build_from_master.md),
[`freeze_study_pull()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/freeze_study_pull.md)

## Examples

``` r
# \donttest{
if (requireNamespace("duckdb", quietly = TRUE)) {
  # Synthetic data; no PHI.
  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbWriteTable(con, "master_demo", data.frame(
    mrn = c("SYN101", "SYN102"),
    encounter_date = as.Date(c("2010-03-01", "2012-07-15")),
    proc = c("CABG", "AVR"), age = c(62, 70)
  ))
  DBI::dbWriteTable(con, "master_demo_corrections_applied", data.frame(
    correction_id = character(), mrn = character(), encounter_date = as.Date(character())
  ))
  DBI::dbWriteTable(con, "master_demo_deployment", data.frame(sql_commit = "abc1234"))
  DBI::dbWriteTable(con, "master_demo_parity", data.frame(
    sql_commit = "abc1234", verdict = "pass", verified_at = Sys.time()
  ))
  config <- tempfile(fileext = ".yaml")
  writeLines("study: st0000", config)
  q <- cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")))
  pull_master(con, "master_demo", q, var_cols = "age", path = config,
              dialect = "duckdb")
  DBI::dbDisconnect(con, shutdown = TRUE)
}
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp6qemSm/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
# }
```
