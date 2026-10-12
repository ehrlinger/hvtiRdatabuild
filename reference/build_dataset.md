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
