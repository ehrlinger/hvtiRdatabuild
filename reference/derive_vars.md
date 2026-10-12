# Apply study-specific variable derivations

Runs committed study-specific R code after dataset assembly. The
callback may add analysis variables and append local exclusion stages to
the cohort record; it may not rewrite earlier membership decisions.

## Usage

``` r
derive_vars(build, config, study_derive)
```

## Arguments

- build:

  A `build_result` from
  [`build_dataset()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/build_dataset.md).

- config:

  A `study_config` from
  [`read_study_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_study_config.md).

- study_derive:

  A function with arguments `data`, `cohort`, and `config`. It returns a
  named list with updated `data` and `cohort` elements.

## Value

An object of class `derive_result` with `data`, `cohort`, and unchanged
supporting `tables` elements.

## Examples

``` r
# Synthetic identifiers and values; no PHI, no warehouse connection.
ids <- c("SYN201", "SYN202", "SYN203")
cohort <- new_cohort_record(
  members = data.frame(
    patient_id = ids, stage_id = "selected", included = TRUE,
    reason = NA_character_
  ),
  stages = data.frame(
    stage_id = "selected", order = 1L, label = "Selected",
    source = "upstream", provenance = "synthetic selection"
  ),
  patient_id_col = "masterid"
)
path <- tempfile(fileext = ".yaml")
yaml::write_yaml(list(
  study = "synthetic", cohort_table = "synthetic.cohort",
  warehouse = "synthetic_warehouse", view_schema = "dbo",
  pull_date = "2026-10-01", modules = list("base", "vitalstatus"),
  derive = list(scale_value = TRUE)
), path)
config <- read_study_config(path)
unlink(path)
raw <- structure(list(
  tables = list(
    bdbase = data.frame(masterid = ids, base_value = c(3, 5, 8),
                        keep = c(TRUE, FALSE, TRUE)),
    bdstat = data.frame(masterid = ids,
                        status_value = c("alive", "alive", "deceased"))
  ),
  manifest = data.frame(
    module = c("base", "vitalstatus"), output = c("bdbase", "bdstat"),
    n_rows = c(3L, 3L), n_cols = c(3L, 2L),
    pulled_at = as.POSIXct(rep("2026-10-01", 2L), tz = "UTC")
  )
), class = "pull_result")
built <- build_dataset(raw, config, cohort)
study_derive <- function(data, cohort, config) {
  keep <- data$keep
  if (isTRUE(config$derive[["scale_value"]])) {
    data$analysis_value <- data$base_value * 2
  }
  reason <- ifelse(keep, NA_character_, "synthetic study exclusion")
  stage <- data.frame(
    stage_id = "study_eligibility", order = max(cohort$stages$order) + 1L,
    label = "Study eligibility", source = "derive",
    provenance = "synthetic study rule"
  )
  outcomes <- data.frame(patient_id = data$masterid, included = keep,
                         reason = reason)
  list(data = data[keep, , drop = FALSE],
       cohort = append_cohort_stage(cohort, stage, outcomes))
}
derived <- derive_vars(built, config, study_derive)
derived
#> Derived dataset: 2 row(s), 5 column(s)
#> Supporting module tables: 0 
#>           stage_id               label n_in n_excluded n_remaining
#>           selected            Selected    3          0           3
#>              build Patient-level build    3          0           3
#>  study_eligibility   Study eligibility    3          1           2
```
