# Declare an inclusion or exclusion criterion

A criterion is one stage of the cohort, evaluated in the warehouse
inside the pull's transaction. Its `test` gives met, not met or
undetermined for each unit still in the cohort. `role` turns that into a
verdict: an `"include"` criterion keeps met units, and an `"exclude"`
criterion drops them. `undetermined` says what happens to a unit the
test cannot decide: `"exclude"` it, `"keep"` it, or send it to chart
`"review"` (see
[`apply_review()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/apply_review.md)).

## Usage

``` r
criterion(id, label, role, test, undetermined)
```

## Arguments

- id:

  Character. The stage id: a letter, then letters, digits or
  underscores.

- label:

  Character. The CONSORT label.

- role:

  `"include"` or `"exclude"`.

- test:

  A test from
  [`master_row()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/master_row.md),
  [`view_rows()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/view_rows.md),
  [`any_of()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/any_of.md)
  or
  [`all_of()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/any_of.md).

- undetermined:

  `"exclude"`, `"keep"` or `"review"`.

## Value

An object of class `cohort_criterion`.

## Details

No argument has a default. Which source, which window, which row and
what to do without one are the study's decisions, and the pull records
them.

## See also

[`cohort_query()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/cohort_query.md),
[`local_criterion()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/local_criterion.md),
[`review_criterion()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/review_criterion.md)

## Examples

``` r
criterion("inotrope_72h", "Any inotrope within 72 hours before surgery",
          role = "exclude",
          test = view_rows("med_admin", "given_at", c(-3, 0), "any",
                           "drug_class = 'inotrope'"),
          undetermined = "keep")
#> $id
#> [1] "inotrope_72h"
#> 
#> $label
#> [1] "Any inotrope within 72 hours before surgery"
#> 
#> $role
#> [1] "exclude"
#> 
#> $test
#> $type
#> [1] "view"
#> 
#> $view
#> [1] "med_admin"
#> 
#> $date_col
#> [1] "given_at"
#> 
#> $window
#> [1] -3  0
#> 
#> $pick
#> [1] "any"
#> 
#> $condition
#> [1] "drug_class = 'inotrope'"
#> 
#> $mrn_col
#> [1] "mrn"
#> 
#> attr(,"class")
#> [1] "cohort_test"
#> 
#> $undetermined
#> [1] "keep"
#> 
#> $kind
#> [1] "warehouse"
#> 
#> attr(,"class")
#> [1] "cohort_criterion"
```
