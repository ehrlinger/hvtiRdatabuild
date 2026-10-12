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
cohort_summary(cohort)$stages
#>   stage_id       label n_in n_excluded n_remaining
#> 1 selected    Selected    3          0           3
#> 2   adults Adults only    3          1           2
```
