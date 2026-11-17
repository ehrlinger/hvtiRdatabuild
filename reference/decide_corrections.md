# Decide a batch of corrections

Records `accept`, `reject`, `supersede` or `bake` for each row of
`decisions`. A correction applies while its latest decision is `accept`.
When two accepted corrections to a cell disagree, neither applies (G1):
supersede the wrong one to settle the cell.

## Usage

``` r
decide_corrections(config, con, decisions, dry_run = TRUE, dialect = "mssql")
```

## Arguments

- config:

  A `master_config` from
  [`read_master_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_master_config.md),
  with `sources` and `deciders`.

- con:

  A DBI connection to the warehouse.

- decisions:

  A data frame with `source`, `correction_id`, `decision`, `decided_by`
  and optionally `reason`.

- dry_run:

  If `TRUE`, the default, validate only.

- dialect:

  `"mssql"` or `"duckdb"`.

## Value

Invisibly, a list: `verdicts` (a data frame of `row`, `verdict`) and
`recorded` (an integer).

## Details

Each row gets one of these verdicts:

- `recordable`: the row passed every check below.

- `unknown_source`: the source is not declared in `master.yml`.

- `repeated_correction`: the batch decides the same correction more than
  once. Every row of a batch shares one `decided_on`, so their order
  would be arbitrary; decide it again in a later batch instead.

- `unknown_correction`: the source has no correction with that id.

- `invalid_decision`: the decision is not one of the four.

- `not_decider`: the decider is not listed in `master.yml`'s `deciders`.

- `self_accepted`: the decider asserted the correction (G2).

With `dry_run = FALSE`, an all-`recordable` batch is recorded in one
transaction, and a batch with any other verdict is refused whole.

**Interim.** Superseded by the HVTR registry. Replaces the deprecated
[`decide_correction()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/decide_correction.md).

## See also

[`propose_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/propose_corrections.md),
[`retire_filled_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/retire_filled_corrections.md)

## Examples

``` r
# See propose_corrections().
```
