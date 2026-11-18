# Pull the enabled warehouse modules for a study

Executes one query per module named in the study configuration and
returns the raw tables alongside a manifest of what was pulled. This is
the R port of `tp.stXXXX_dwpull.sas`.

## Usage

``` r
dw_pull(config, con, conn)
```

## Arguments

- config:

  A `study_config` from
  [`read_study_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_study_config.md).

- con:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html),
  typically from
  [`dw_connect()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/dw_connect.md).

- conn:

  Deprecated; use `con`.

## Value

An object of class `pull_result`: a list with `tables`, a named list of
data frames keyed by each module's `output` name, and `manifest`, a data
frame with columns `module`, `output`, `n_rows`, `n_cols`, and
`pulled_at`.

## Details

The port is **read-only**. The SAS templates also upload a cohort table
to the warehouse; that write is deliberately not carried here and is
deferred to a later slice with its own review.

A module that returns zero rows is an error unless its definition
declares it optional. A silently empty module produces a quietly
incomplete dataset, which is the failure this package exists to prevent.

## See also

[`dw_connect()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/dw_connect.md),
[`dw_modules()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/dw_modules.md),
[`compare_built()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/compare_built.md)

## Examples

``` r
# \donttest{
if (requireNamespace("duckdb", quietly = TRUE)) {
  # Synthetic data; no PHI. DuckDB stands in for the warehouse: its in-memory catalog
  # is `memory` and its default schema `main`, so the module SQL's three-part names
  # resolve without SQL Server.
  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbWriteTable(con, "st1234_cohort", data.frame(masterid = 1:2))
  DBI::dbWriteTable(con, "vw_CardSurg_Base", data.frame(masterid = 1:2, age = c(61, 70)))
  DBI::dbWriteTable(con, "vw_CardSurg_Valve", data.frame(masterid = 1:2, avr = c(1, 0)))
  DBI::dbWriteTable(con, "vw_CardSurg_Cabg", data.frame(masterid = 1:2, cabg = c(0, 1)))
  path <- tempfile(fileext = ".yaml")
  yaml::write_yaml(list(
    study = "st1234", cohort_table = "st1234_cohort",
    warehouse = "memory", view_schema = "main",
    pull_date = "2026-08-04", modules = list("base"),
    varsets = list("core"), derive = list(missing = TRUE)
  ), path)
  res <- dw_pull(read_study_config(path), con)
  res$manifest
  DBI::dbDisconnect(con, shutdown = TRUE)
  unlink(path)
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
