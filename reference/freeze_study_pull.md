# Freeze a study's pull from a master view

Sources are not time-travelable, so the release, not the warehouse, is
the record of what a study read. `freeze_study_pull()` publishes the
pull as an immutable parquet release with
[`publish_dataset()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/publish_dataset.md),
with its provenance written **into the file's own metadata**: the SQL
model commit, the ids of the corrections applied, when the pull read,
the parity verdict it passed, the cohort definition and stage counts,
and the study configuration's checksum as recorded when the pull ran.
Because the provenance is part of the bytes, the release's SHA-256
covers it, and a release can never exist without it. Read it back with
[`read_pull_provenance()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_pull_provenance.md).

## Usage

``` r
freeze_study_pull(
  pull,
  path,
  dir,
  dataset_id,
  extract_date = Sys.Date(),
  study_config,
  datasets_dir
)
```

## Arguments

- pull:

  A `master_pull` from
  [`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md).

- path:

  Character. Path to the study configuration file given to
  [`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md);
  it must be unchanged since the pull.

- dir, dataset_id, extract_date:

  As for
  [`publish_dataset()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/publish_dataset.md).

- study_config:

  Deprecated; use `path`.

- datasets_dir:

  Deprecated; use `dir`.

## Value

Invisibly, the release, as returned by
[`publish_dataset()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/publish_dataset.md).

## Details

The configuration must be unchanged since the pull: if its checksum no
longer matches the one
[`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md)
recorded, nothing is published. A pull awaiting chart review is refused.

Retrying the same pull returns the same release. A distinct pull with
identical data carries different provenance, so it becomes its own
release.

The retained pull holds patient values. It belongs in the study's data
folder under the same rules as the built dataset, never in a repository.

## See also

[`read_pull_provenance()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_pull_provenance.md),
[`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md),
[`publish_dataset()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/publish_dataset.md)

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
#> ℹ /tmp/RtmpeZtUmy/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
# }
```
