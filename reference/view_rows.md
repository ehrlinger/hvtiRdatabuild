# Test rows of another view in a window around the encounter

A test for
[`criterion()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/criterion.md):
rows of `view` for the same patient whose `date_col` falls within
`window` days of the encounter date are judged by `condition`. Which
rows are judged is `pick`:

## Usage

``` r
view_rows(view, date_col, window, pick, condition, mrn_col = "mrn")
```

## Arguments

- view:

  Character. A view in the same database, optionally schema-qualified.

- date_col:

  Character. The view's date or timestamp column. Timestamps are cast to
  dates.

- window:

  Integer vector of length two: first and last day relative to the
  encounter date, inclusive. `c(-30, 0)` is the 30 days before, and the
  day of, surgery.

- pick:

  `"any"`, `"all"` or `"nearest"`.

- condition:

  Character. A SQL boolean expression over the view's columns, written
  by the study programmer. Every column it names must exist in the view.

- mrn_col:

  Character. The view's patient identifier column.

## Value

An object of class `cohort_test`.

## Details

- `"any"`: met if any row meets the condition.

- `"all"`: met if every row meets it.

- `"nearest"`: the row or rows nearest the encounter date must agree,
  and their verdict is the test's.

The test is **undetermined** when there is no row in the window, when a
row's condition is unknown and the verdict depends on it, or when rows
tied for nearest disagree. None of `date_col`, `window` or `pick` has a
default: they are the study's choices.

Windows are whole days on dates. "Within 72 hours before surgery"
written as `c(-3, 0)` is wider than 72 hours, and the provenance records
the day window used.

## See also

[`criterion()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/criterion.md),
[`master_row()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/master_row.md),
[`any_of()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/any_of.md)

## Examples

``` r
view_rows("echo_measure", date_col = "measured_on", window = c(-30, 0),
          pick = "nearest", condition = "lvef <= 25")
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
```
