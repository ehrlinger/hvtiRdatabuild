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
cohort <- append_cohort_stage(
  cohort,
  stage = data.frame(
    stage_id = "adults", order = 2L, label = "Adults only",
    source = "derive", provenance = "synthetic rule"
  ),
  outcomes = data.frame(
    patient_id = c("SYN101", "SYN102", "SYN103"),
    included = c(TRUE, FALSE, TRUE),
    reason = c(NA, "synthetic exclusion", NA)
  )
)
cohort
#> Cohort record: 2 stage(s), 6 patient-stage outcome(s)
#>        label n_in n_excluded n_remaining
#>     Selected    3          0           3
#>  Adults only    3          1           2
```
