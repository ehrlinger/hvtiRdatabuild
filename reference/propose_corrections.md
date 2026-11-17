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
# See the generate_corrections_sql() example and the reference group "Corrections to
# source views (interim)"; the round trip needs a warehouse connection with the source
# views.
```
