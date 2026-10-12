# Append an outcome stage to a cohort history

Append an outcome stage to a cohort history

## Usage

``` r
append_cohort_stage(cohort, stage, outcomes)
```

## Arguments

- cohort:

  A `cohort_record` created by
  [`new_cohort_record()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/new_cohort_record.md).

- stage:

  A one-row data frame with the `stages` schema.

- outcomes:

  A data frame with one `patient_id`, `included`, and `reason` outcome
  for every patient active at the preceding stage.

## Value

An updated object of class `cohort_record`.
