# Lift a master's parquet snapshot into the warehouse as a view

Checks the primary key, creates a base table named for the snapshot's
release, loads it row group by row group, and proves it equal to the
snapshot: counts, aggregates and a sampled compare first, then a full
comparison of every column joined on the key. Only then is a parity
record written and the master's view created. If the master already has
a corrections table, the view is regenerated with corrections applied.

## Usage

``` r
lift_master(config, con, parquet, dry_run = TRUE, dialect = "mssql")
```

## Arguments

- config:

  A `master_config` from
  [`read_master_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_master_config.md).

- con:

  A DBI connection, such as one from
  [`dw_connect()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/dw_connect.md).

- parquet:

  Path to a snapshot written by
  [`snapshot_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_master.md);
  its `.meta.json` sidecar must sit beside it, and its checksum must
  match the sidecar's `parquet_sha256`.

- dry_run:

  If `TRUE`, the default, write the DDL and nothing else.

- dialect:

  `"mssql"` for the warehouse, or `"duckdb"`, used in tests.

## Value

Invisibly, a list with `dry_run`, `base_table`, `ddl_path` and `verdict`
(`"pass"`, or `NA` for a dry run).

## Details

A dry run, the default, writes the table's DDL next to the snapshot for
a hand-off and touches nothing else. Warehouse errors are reported by
step, with the driver's message withheld, because it can carry a data
value.

## See also

[`snapshot_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_master.md),
[`backfill_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/backfill_corrections.md)

## Examples

``` r
# \donttest{
if (requireNamespace("duckdb", quietly = TRUE) &&
    requireNamespace("arrow", quietly = TRUE) &&
    requireNamespace("jsonlite", quietly = TRUE) &&
    requireNamespace("tidyselect", quietly = TRUE)) {
  dir <- tempfile("lift")
  dir.create(dir)
  pq <- file.path(dir, "built_demo.parquet")
  arrow::write_parquet(data.frame(id = c("K1", "K2"), x = c(1, 2)), pq)
  jsonlite::write_json(
    list(parquet_sha256 = digest::digest(pq, algo = "sha256", file = TRUE),
         columns = list(list(variable = "id", r_class = "character"),
                        list(variable = "x", r_class = "numeric"))),
    sub("\\.parquet$", ".meta.json", pq), auto_unbox = TRUE)
  cfg_path <- file.path(dir, "master.yml")
  writeLines(c("name: master_demo", "key: [id]", paste0("snapshots: ", dir),
               "current: built_demo.sas7bdat",
               paste0("build_program: ", file.path(dir, "bd.sas"))), cfg_path)
  con <- DBI::dbConnect(duckdb::duckdb())
  lift_master(read_master_config(cfg_path), con, pq, dialect = "duckdb")
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
#> dry run: DDL for master_demo_base_built_demo written to /tmp/RtmpjL3Uzs/lift1c1c197477a1/built_demo.parquet.ddl.sql
# }
```
