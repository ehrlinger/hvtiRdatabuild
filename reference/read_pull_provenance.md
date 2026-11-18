# Read the provenance a frozen pull carries

Read the provenance a frozen pull carries

## Usage

``` r
read_pull_provenance(path)
```

## Arguments

- path:

  Character. A parquet file written by
  [`freeze_study_pull()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/freeze_study_pull.md).

## Value

A list: `schema`; for a pull frozen with the provenance record, that
record (`package`, `version`, `sha`, `method`, `seed`, `rng_kind`, and
`time` as ISO 8601 text); then `master`, `sql_commit`,
`applied_correction_ids`, `corrections_in_effect`, `parity_verified_at`,
`read_at`, `columns`, `cohort_definition`, `study_config_sha256`,
`n_cohort`, `n_matched`, `n_unmatched` and `cohort_stages`.

## See also

[`freeze_study_pull()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/freeze_study_pull.md)

## Examples

``` r
# \donttest{
if (requireNamespace("duckdb", quietly = TRUE) &&
      requireNamespace("arrow", quietly = TRUE)) {
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
  pull <- pull_master(con, "master_demo", q, var_cols = "age", path = config,
                      dialect = "duckdb")
  published <- tempfile("published-")
  dir.create(published)
  release <- freeze_study_pull(pull, config, published, "st0000_pull")
  read_pull_provenance(file.path(published, release$file))$sql_commit
  DBI::dbDisconnect(con, shutdown = TRUE)
  unlink(c(config, published), recursive = TRUE)
}
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpg9Eg5v/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
# }
```
