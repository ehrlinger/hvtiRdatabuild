# Summarize cohort attrition without patient identifiers

Summarize cohort attrition without patient identifiers

## Usage

``` r
cohort_summary(cohort)
```

## Arguments

- cohort:

  A `cohort_record`.

## Value

A list with `stages` (stage counts) and `reasons` (exclusion counts)
data frames. Neither table contains patient identifiers.
