# Declare a criterion evaluated in R on a file the study holds

For a source outside the warehouse. It runs after the pull's
transaction, against the candidates that survived the warehouse
criteria, so the provenance does not claim one snapshot covers it. The
file's SHA-256 is taken when the criterion is declared, and again before
and after `decide()` reads it.
[`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md)
refuses the pull if the file has changed since it was declared, or
changed while it was read.

## Usage

``` r
local_criterion(id, label, role, path, decide, undetermined)
```

## Arguments

- id:

  Character. The stage id: a letter, then letters, digits or
  underscores.

- label:

  Character. The CONSORT label.

- role:

  `"include"` or `"exclude"`.

- path:

  Character. The file the criterion reads.

- decide:

  A function of `(units, path)`. `units` is a data frame with
  `cohort_unit`, `mrn` and `encounter_date`, one row per candidate. It
  must return a logical vector with one value per row: `TRUE` met,
  `FALSE` not met, `NA` undetermined.

- undetermined:

  `"exclude"`, `"keep"` or `"review"`.

## Value

An object of class `cohort_criterion`.

## See also

[`criterion()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/criterion.md),
[`cohort_query()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/cohort_query.md)

## Examples

``` r
f <- tempfile(fileext = ".csv")
writeLines("mrn,covid_date", f)
local_criterion("covid_14d", "COVID-19 within 14 days", role = "exclude", path = f,
                decide = function(units, path) rep(FALSE, nrow(units)),
                undetermined = "review")
#> $id
#> [1] "covid_14d"
#> 
#> $label
#> [1] "COVID-19 within 14 days"
#> 
#> $role
#> [1] "exclude"
#> 
#> $path
#> [1] "/tmp/RtmpVuyOuJ/file1b4c16091e6d.csv"
#> 
#> $sha256
#> [1] "b93be0af3b15ac48e7e3cdcd31e91c3f6a1e91d64d1d830f0e0136081fd8e887"
#> 
#> $decide
#> function (units, path) 
#> rep(FALSE, nrow(units))
#> <environment: 0x57d77178b0f0>
#> 
#> $undetermined
#> [1] "review"
#> 
#> $kind
#> [1] "local"
#> 
#> attr(,"class")
#> [1] "cohort_criterion"
```
