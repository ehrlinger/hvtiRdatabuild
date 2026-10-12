# Create an ordered cohort history

A cohort record stores each patient's outcome at every stage they
entered. Patients excluded at a stage do not appear in later stages.
Summaries are derived from these outcomes, so stage counts cannot drift
from membership.

## Usage

``` r
new_cohort_record(members, stages, patient_id_col)
```

## Arguments

- members:

  A data frame with `patient_id`, `stage_id`, `included`, and `reason`
  columns. Identifiers are runtime data and are never printed.

- stages:

  A data frame with `stage_id`, `order`, `label`, `source`, and
  `provenance` columns, ordered by `order`.

- patient_id_col:

  Name of the patient identifier column in associated patient-level
  data.

## Value

An object of class `cohort_record` with `members`, `stages`, and
`patient_id_col` elements.
