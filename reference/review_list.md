# List what a pull needs decided at chart review

Every unit a criterion routed to review (`undetermined = "review"`), and
every unit still in the cohort for each
[`review_criterion()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/review_criterion.md).
The list holds unit identifiers. Keep it with the study's other
restricted files, and never print it to a shared log.

## Usage

``` r
review_list(pull)
```

## Arguments

- pull:

  A `master_pull` from
  [`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md).

## Value

A data frame with `cohort_unit` and `criterion_id`.

## See also

[`apply_review()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/apply_review.md)
