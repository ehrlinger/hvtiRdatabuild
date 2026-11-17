# Combine tests

`any_of()` is met when any part is met, not met when every part is not
met, and undetermined otherwise. `all_of()` is met when every part is
met, not met when any part is not met, and undetermined otherwise.
Combinations nest.

## Usage

``` r
any_of(...)

all_of(...)
```

## Arguments

- ...:

  Two or more tests from
  [`master_row()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/master_row.md),
  [`view_rows()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/view_rows.md),
  `any_of()` or `all_of()`.

## Value

An object of class `cohort_test`.

## See also

[`criterion()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/criterion.md)

## Examples

``` r
any_of(
  view_rows("echo_measure", "measured_on", c(-30, 0), "nearest", "lvef <= 25"),
  all_of(
    view_rows("echo_measure", "measured_on", c(-30, 0), "nearest", "lvef <= 35"),
    master_row("mitral_surgery = 1")
  )
)
#> $type
#> [1] "any"
#> 
#> $parts
#> $parts[[1]]
#> $type
#> [1] "view"
#> 
#> $view
#> [1] "echo_measure"
#> 
#> $date_col
#> [1] "measured_on"
#> 
#> $window
#> [1] -30   0
#> 
#> $pick
#> [1] "nearest"
#> 
#> $condition
#> [1] "lvef <= 25"
#> 
#> $mrn_col
#> [1] "mrn"
#> 
#> attr(,"class")
#> [1] "cohort_test"
#> 
#> $parts[[2]]
#> $type
#> [1] "all"
#> 
#> $parts
#> $parts[[1]]
#> $type
#> [1] "view"
#> 
#> $view
#> [1] "echo_measure"
#> 
#> $date_col
#> [1] "measured_on"
#> 
#> $window
#> [1] -30   0
#> 
#> $pick
#> [1] "nearest"
#> 
#> $condition
#> [1] "lvef <= 35"
#> 
#> $mrn_col
#> [1] "mrn"
#> 
#> attr(,"class")
#> [1] "cohort_test"
#> 
#> $parts[[2]]
#> $type
#> [1] "master"
#> 
#> $condition
#> [1] "mitral_surgery = 1"
#> 
#> attr(,"class")
#> [1] "cohort_test"
#> 
#> 
#> attr(,"class")
#> [1] "cohort_test"
#> 
#> 
#> attr(,"class")
#> [1] "cohort_test"
```
