# Backfill a master's corrections from its SAS build, and regenerate its view

Creates the master's corrections and decisions tables if absent, reads
the inline patient-level fixes from the SAS build program, records each
one that resolves to exactly one record as a correction with an unknown
prior and a `bake` decision (present in the snapshot, not applied), and
regenerates the view and its stale view. Fixes that change a key column,
match no record, match several, or cannot be read are reported by reason
and line number and never recorded.

## Usage

``` r
backfill_corrections(config, con, dry_run = TRUE, dialect = "mssql")
```

## Arguments

- config:

  A `master_config` from
  [`read_master_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_master_config.md).

- con:

  A DBI connection.

- dry_run:

  If `TRUE`, the default, report what would be recorded.

- dialect:

  `"mssql"` or `"duckdb"`.

## Value

Invisibly, a list of counts: `dry_run`, `facts`, `resolved`,
`unresolved`, `appended` and `stale`.

## Details

Requires a passing parity record from
[`lift_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/lift_master.md).
A dry run, the default, parses and resolves and writes nothing.

## See also

[`propose_correction()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/propose_correction.md),
[`decide_correction()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/decide_correction.md)

## Examples

``` r
# \donttest{
if (requireNamespace("duckdb", quietly = TRUE) &&
    requireNamespace("arrow", quietly = TRUE) &&
    requireNamespace("jsonlite", quietly = TRUE) &&
    requireNamespace("tidyselect", quietly = TRUE) &&
    requireNamespace("dplyr", quietly = TRUE) &&
    requireNamespace("withr", quietly = TRUE) &&
    requireNamespace("digest", quietly = TRUE)) {
  dir <- tempfile("backfill")
  dir.create(dir)
  pq <- file.path(dir, "built_demo.parquet")
  arrow::write_parquet(data.frame(id = c("K1", "K2"), age = c(60, 61)), pq)
  jsonlite::write_json(
    list(parquet_sha256 = digest::digest(pq, algo = "sha256", file = TRUE),
         columns = list(list(variable = "id", r_class = "character"),
                        list(variable = "age", r_class = "numeric"))),
    sub("\\.parquet$", ".meta.json", pq), auto_unbox = TRUE)
  writeLines(c("data m; set base;", "if id = 'K1' then age = 60;", "run;"),
             file.path(dir, "bd.sas"))
  cfg_path <- file.path(dir, "master.yml")
  writeLines(c("name: master_demo", "key: [id]", paste0("snapshots: ", dir),
               "current: built_demo.sas7bdat",
               paste0("build_program: ", file.path(dir, "bd.sas"))), cfg_path)
  cfg <- read_master_config(cfg_path)
  con <- DBI::dbConnect(duckdb::duckdb())
  lift_master(cfg, con, pq, dry_run = FALSE, dialect = "duckdb")
  backfill_corrections(cfg, con, dry_run = FALSE, dialect = "duckdb")
  DBI::dbDisconnect(con, shutdown = TRUE)
}
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpjL3Uzs/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> key id                               unique     rows 2, null key parts 0, duplicates 0
#> load: 1 row groups loaded, 0 already present
#> parity pass: row count match; 0 of 2 columns mismatch; 0 of 2 sampled columns mismatch
#> parity_full: 0 of 2 columns mismatch
#> view master_demo -> master_demo_base_built_demo
#> legacy: 1 facts parsed; 1 resolved; 0 unresolved
#> recorded 1; 0 stale corrections
# }
```
