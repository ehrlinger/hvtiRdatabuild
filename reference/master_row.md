# Test a condition on the master row

A test for
[`criterion()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/criterion.md):
the condition is evaluated on the encounter's own master row. It is met
when the condition is true, not met when it is false, and undetermined
when it is unknown (a `NULL` in SQL).

## Usage

``` r
master_row(condition)
```

## Arguments

- condition:

  Character. A SQL boolean expression over the master's columns, written
  by the study programmer. It must never be built from data.

## Value

An object of class `cohort_test`.

## See also

[`criterion()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/criterion.md),
[`view_rows()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/view_rows.md),
[`any_of()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/any_of.md)

## Examples

``` r
master_row("salvage = 1")
#> $type
#> [1] "master"
#> 
#> $condition
#> [1] "salvage = 1"
#> 
#> attr(,"class")
#> [1] "cohort_test"
```
