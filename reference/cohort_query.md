# Define a cohort by a query on a master view

A definition only: nothing is read until
[`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md)
runs it, inside the same transaction as the pull, so the cohort and its
data describe one state of the warehouse.

## Usage

``` r
cohort_query(
  qualifying,
  epoch,
  index = c("first", "all"),
  prior = c("keep", "exclude")
)
```

## Arguments

- qualifying:

  Character. A SQL boolean expression over the master's columns, for
  example `"proc = 'CABG'"`.

- epoch:

  A `Date` vector of length two: first and last encounter date,
  inclusive.

- index:

  `"first"` or `"all"`.

- prior:

  `"keep"` or `"exclude"`, for units with a qualifying encounter before
  the epoch.

## Value

An object of class `cohort_query`.

## Details

The cohort is every encounter in the master that meets `qualifying` and
falls inside `epoch`. `index` sets the study's unit: `"first"` keeps
each patient's earliest qualifying encounter in the epoch (one row per
patient; later encounters remain follow-up events), and `"all"` keeps
every qualifying encounter in the epoch.

A patient whose qualifying encounter in the epoch was preceded by one
**before** the epoch is a redo, not a first. Those units are always
recorded as a cohort stage, `prior_qualifying`: `prior = "keep"` keeps
them, `prior = "exclude"` drops them with a reason. Nothing is dropped
silently. The earlier encounter is detected in the database; its date
never leaves it.

`qualifying` is SQL written by the study programmer and run as a `WHERE`
condition on the master. It must never be built from data.

## See also

[`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md)

## Examples

``` r
cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")))
#> Cohort query: proc = 'CABG'
#>   epoch 2000-01-01 to 2024-07-31; index first; earlier qualifying encounter: keep
```
