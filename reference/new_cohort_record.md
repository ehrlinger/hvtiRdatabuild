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

## Examples

``` r
# Synthetic identifiers; no PHI.
cohort <- new_cohort_record(
  members = data.frame(
    patient_id = c("SYN101", "SYN102", "SYN103"), stage_id = "selected",
    included = TRUE, reason = NA_character_
  ),
  stages = data.frame(
    stage_id = "selected", order = 1L, label = "Selected",
    source = "upstream", provenance = "synthetic selection"
  ),
  patient_id_col = "masterid"
)
cohort
#> Cohort record: 1 stage(s), 3 patient-stage outcome(s)
#>     label n_in n_excluded n_remaining
#>  Selected    3          0           3
```
