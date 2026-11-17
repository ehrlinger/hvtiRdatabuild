# Propose a batch of corrections from a filled template

Validates every row of a submission made from
[`write_corrections_template()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_corrections_template.md)
and returns a verdict per row:

## Usage

``` r
propose_corrections(config, con, file, dry_run = TRUE, dialect = "mssql")
```

## Arguments

- config:

  A `master_config` from
  [`read_master_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_master_config.md),
  with `sources`.

- con:

  A DBI connection to the warehouse.

- file:

  Character. The filled template, as CSV.

- dry_run:

  If `TRUE`, the default, validate only.

- dialect:

  `"mssql"` or `"duckdb"`.

## Value

Invisibly, a list: `verdicts` (a data frame of `row`, `source`,
`verdict`), `appended` (an integer), `correction_ids` and `file_sha256`.

## Details

- `appendable`: the row passed every check below.

- `rule_not_fact`: a key or the variable holds a pattern, a comparison,
  or "all".

- `unknown_source`: the source is not declared in `master.yml`.

- `invalid_field`: a flag is not 0 or 1 or disagrees with its value, the
  evidence type is unknown, or a required field is blank.

- `no_variable`: the source has no such column, or the column is a key.

- `derived_variable`: the column is the master's, derived from sources;
  correct the sources or change the derivation.

- `unknown_key`: the key is incomplete, carries another source's key
  column, or matches no row.

- `ambiguous_key`: the key matches more than one row.

- `does_not_cast`: a value is not of the column's type, or the
  warehouse's cast to the column's SQL type would round, overflow or
  truncate it. This last check runs after the prior check.

- `prior_mismatch`: the source no longer holds `expected_prior`.

With `dry_run = FALSE`, an all-`appendable` file is appended in one
transaction, and a file with any other verdict is refused whole, with
nothing written. Values are stored in a canonical text form, so `"30.0"`
and `"30"` are the same assertion. A proposed correction applies only
once accepted with
[`decide_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/decide_corrections.md).

Output is verdicts and counts, never a key or a value.

**Interim.** Superseded by the HVTR registry's intake, which takes over
the template and the tables unchanged. Replaces the deprecated
[`propose_correction()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/propose_correction.md).

## See also

[`write_corrections_template()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_corrections_template.md),
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
#> ℹ /tmp/Rtmpt0Skxb/duckdb
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
