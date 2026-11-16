# Split cohort unit identifiers into MRN and encounter date

The inverse of
[`cohort_unit_id()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/cohort_unit_id.md).

## Usage

``` r
split_cohort_unit(unit)
```

## Arguments

- unit:

  Character. Identifiers made by
  [`cohort_unit_id()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/cohort_unit_id.md).

## Value

A data frame with columns `mrn` (character) and `encounter_date`
(`Date`), one row per element of `unit`.

## See also

[`cohort_unit_id()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/cohort_unit_id.md)

## Examples

``` r
# Synthetic identifiers; no PHI.
split_cohort_unit(cohort_unit_id("SYN101", as.Date("2010-03-01")))
#>      mrn encounter_date
#> 1 SYN101     2010-03-01
```
