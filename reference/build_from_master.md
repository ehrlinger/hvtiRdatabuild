# Build a study dataset from a master pull

The master-view counterpart of
[`build_dataset()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/build_dataset.md).
A master is already one wide row per encounter, so there are no modules
to join: the pulled rows are the built dataset. `build_from_master()`
checks they match the cohort's active units exactly and records the
build as a cohort stage, returning the same `build_result` shape that
[`derive_vars()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/derive_vars.md)
consumes. A pull awaiting chart review is refused.

## Usage

``` r
build_from_master(pull)
```

## Arguments

- pull:

  A `master_pull` from
  [`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md).

## Value

A `build_result`: a list with `data`, `cohort` (ending with a `build`
stage) and `tables` (empty).

## See also

[`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md),
[`derive_vars()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/derive_vars.md),
[`build_dataset()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/build_dataset.md)

## Examples

``` r
# \donttest{
if (requireNamespace("duckdb", quietly = TRUE)) {
  # Synthetic data; no PHI.
  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbWriteTable(con, "master_demo", data.frame(
    mrn = "SYN101", encounter_date = as.Date("2010-03-01"), proc = "CABG", age = 62
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
  pull <- pull_master(con, "master_demo", q, columns = "age", study_config = config,
                      dialect = "duckdb")
  build_from_master(pull)
  DBI::dbDisconnect(con, shutdown = TRUE)
}
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpt0Skxb/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> Warning: pull_master(): `columns` is renamed `var_cols`. This will be an error in the next release.
#> Warning: pull_master(): `study_config` is renamed `path`. This will be an error in the next release.
# }
```
