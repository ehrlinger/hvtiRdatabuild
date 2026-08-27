# Pull the enabled warehouse modules for a study

Executes one query per module named in the study configuration and
returns the raw tables alongside a manifest of what was pulled. This is
the R port of `tp.stXXXX_dwpull.sas`.

## Usage

``` r
dw_pull(config, conn)
```

## Arguments

- config:

  A `study_config` from
  [`read_study_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_study_config.md).

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html),
  typically from
  [`dw_connect()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/dw_connect.md).

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
# Requires a warehouse connection; see vignette("building-a-study-dataset")
# for a runnable version against a mocked connection.
# }
```
