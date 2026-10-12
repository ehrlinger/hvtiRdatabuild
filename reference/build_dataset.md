# Assemble the patient-level dataset

Joins the patient-level base and vital-status modules while retaining
repeated-event modules as supporting tables. The supplied cohort history
is carried forward and receives a build stage after membership is
verified.

## Usage

``` r
build_dataset(raw, config, cohort)
```

## Arguments

- raw:

  A `pull_result` from
  [`dw_pull()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/dw_pull.md).

- config:

  A `study_config` from
  [`read_study_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_study_config.md).

- cohort:

  A `cohort_record` whose latest stage identifies the selected build
  membership.

## Value

An object of class `build_result` with `data`, `cohort`, and `tables`
elements. `tables` contains unjoined repeated-event module data.

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
built
#> Built dataset: 3 row(s), 4 column(s)
#> Supporting module tables: 0 
#>  stage_id               label n_in n_excluded n_remaining
#>  selected            Selected    3          0           3
#>     build Patient-level build    3          0           3
```
