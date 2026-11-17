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
# See propose_corrections().
```
