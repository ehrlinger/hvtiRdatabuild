# Generate the correction tables and views for a master's sources

Writes, for each source declared in `master.yml`, a
`<source>.tables.sql` file that creates its corrections and decisions
tables once, and a `<source>.views.sql` file that creates or replaces
its four views:

## Usage

``` r
generate_corrections_sql(config, con, dir, dialect = "mssql")
```

## Arguments

- config:

  A `master_config` from
  [`read_master_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_master_config.md),
  with `sources`.

- con:

  A DBI connection that can see the source views.

- dir:

  Character. An existing directory to write the files into.

- dialect:

  `"mssql"` or `"duckdb"`.

## Value

The written paths, invisibly.

## Details

- `<source>_corrected`: the source with accepted corrections applied,
  covering every column, so a first correction to a column is live with
  no redeployment.

- `<source>_corrections_applied`: which correction applied to which row.

- `<source>_corrections_stale` and `<source>_corrections_conflicts`: for
  data management.

Statements are separated by `GO` lines, as `sqlcmd` expects. Regenerate
the views whenever the source view's columns change. Data engineering
deploys the files.

**Interim.** Superseded by the HVTR registry, which takes over the
tables unchanged.

## See also

[`propose_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/propose_corrections.md),
[`decide_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/decide_corrections.md)

## Examples

``` r
# \donttest{
if (requireNamespace("duckdb", quietly = TRUE)) {
  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbWriteTable(con, "stg_demo", data.frame(mrn = "SYN1", lvef = 30))
  cfg_path <- tempfile(fileext = ".yml")
  writeLines(c("name: master_demo", "key: [mrn]", "snapshots: snaps",
               "current: x.sas7bdat", "build_program: x.sas",
               "sources:", "  stg_demo: {key: [mrn]}"), cfg_path)
  generate_corrections_sql(read_master_config(cfg_path), con, tempdir(),
                           dialect = "duckdb")
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
#> Wrote correction SQL for 1 source(s).
# }
```
