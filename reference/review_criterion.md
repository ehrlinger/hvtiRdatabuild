# Declare a criterion decided at chart review

For a criterion no data can decide. Every unit still in the cohort after
the pull needs a decision for it, recorded with
[`apply_review()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/apply_review.md).

## Usage

``` r
review_criterion(id, label, role)
```

## Arguments

- id:

  Character. The stage id: a letter, then letters, digits or
  underscores.

- label:

  Character. The CONSORT label.

- role:

  `"include"` or `"exclude"`.

## Value

An object of class `cohort_criterion`.

## See also

[`apply_review()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/apply_review.md),
[`review_list()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/review_list.md)

## Examples

``` r
review_criterion("planned_mcs", "Planned alternative temporary support strategy",
                 role = "exclude")
#> $id
#> [1] "planned_mcs"
#> 
#> $label
#> [1] "Planned alternative temporary support strategy"
#> 
#> $role
#> [1] "exclude"
#> 
#> $kind
#> [1] "review"
#> 
#> attr(,"class")
#> [1] "cohort_criterion"
```
