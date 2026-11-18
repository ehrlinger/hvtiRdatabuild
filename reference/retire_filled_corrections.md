# Retire fill-ins that upstream has caught up with

A correction that filled a missing source value goes stale as
`filled_upstream_agrees` once the source holds that same value (G7).
This records a `bake` decision for each such correction, by the reserved
decider `"filled_upstream"`, so it leaves the stale view. Schedule it
beside the data load. A fill-in where upstream holds a different value
is a conflict and is never retired here.

## Usage

``` r
retire_filled_corrections(
  config,
  con,
  source,
  dry_run = TRUE,
  dialect = "mssql"
)
```

## Arguments

- config:

  A `master_config` from
  [`read_master_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_master_config.md),
  with `sources`.

- con:

  A DBI connection to the warehouse.

- source:

  Character. A declared source.

- dry_run:

  If `TRUE`, the default, list what would be retired.

- dialect:

  `"mssql"` or `"duckdb"`.

## Value

Invisibly, a list: `correction_ids` and `recorded` (an integer).

## Details

**Interim.** Superseded by the HVTR registry.

## See also

[`decide_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/decide_corrections.md)

## Examples

``` r
# \donttest{
if (requireNamespace("duckdb", quietly = TRUE)) {
  # Synthetic data; no PHI. One source view, its master, and a deployed corrections layer.
  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbWriteTable(con, "stg_demo", data.frame(mrn = c("SYN1", "SYN2"), lvef = c(30, NA)))
  DBI::dbWriteTable(con, "master_demo", data.frame(mrn = c("SYN1", "SYN2"), lvef = c(30, NA)))
  cfg_path <- tempfile(fileext = ".yml")
  writeLines(c("name: master_demo", "key: [mrn]", "snapshots: snaps",
               "current: x.sas7bdat", "build_program: x.sas",
               "sources:", "  stg_demo: {key: [mrn]}", "deciders: [dm_one]"), cfg_path)
  cfg <- read_master_config(cfg_path)
  sql_dir <- tempfile("sql-")
  dir.create(sql_dir)
  for (p in generate_corrections_sql(cfg, con, sql_dir, dialect = "duckdb")) {
    for (s in strsplit(paste(readLines(p), collapse = "\n"), "\nGO\n?")[[1]]) {
      DBI::dbExecute(con, s)
    }
  }

  # A correction to SYN1 and a fill-in for SYN2's missing value.
  sub <- tempfile(fileext = ".csv")
  utils::write.csv(data.frame(
    source = "stg_demo", mrn = c("SYN1", "SYN2"), variable = "lvef",
    expected_prior = c("30", ""), expected_prior_missing = c("0", "1"),
    new_value = c("35", "40"), new_value_missing = "0", evidence_type = "chart_review",
    evidence_ref = "invented note", asserted_by = "reviewer_a"
  ), sub, row.names = FALSE)
  propose_corrections(cfg, con, sub, dialect = "duckdb")$verdicts   # a dry run
  ids <- propose_corrections(cfg, con, sub, dry_run = FALSE,
                             dialect = "duckdb")$correction_ids

  # A named decider, not the asserter, accepts both; they apply on the next query.
  decide_corrections(cfg, con, data.frame(
    source = "stg_demo", correction_id = ids, decision = "accept", decided_by = "dm_one",
    reason = "chart confirms"
  ), dry_run = FALSE, dialect = "duckdb")
  DBI::dbGetQuery(con, "SELECT * FROM stg_demo_corrected ORDER BY mrn")

  # Upstream fills SYN2 with the same value: the fill-in is retired.
  DBI::dbExecute(con, "UPDATE stg_demo SET lvef = 40 WHERE mrn = 'SYN2'")
  retire_filled_corrections(cfg, con, "stg_demo", dry_run = FALSE, dialect = "duckdb")

  DBI::dbDisconnect(con, shutdown = TRUE)
  unlink(c(cfg_path, sub, sql_dir), recursive = TRUE)
}
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp8deRAi/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> Wrote correction SQL for 1 source(s).
#> propose_corrections(): appendable 2.
#> propose_corrections(): appendable 2.
#> decide_corrections(): recordable 2.
#> retire_filled_corrections(): 1 fill-in(s) retired.
# }
```
