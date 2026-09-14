# Read an analysis set

Reads the analysis set `name` written by
[`write_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_analysis_set.md),
after checking that it is current. It stops, naming the
[`write_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_analysis_set.md)
call that fixes it, when the built dataset has changed since the set was
written, when the set's declaration in `_study.yml` has changed, or when
the parquet no longer matches its manifest entry. A stale set is never
rebuilt silently: its exclusions are decisions, and a changed attrition
should be looked at.

## Usage

``` r
read_analysis_set(name, cfg = hvtiRutilities::study_config())
```

## Arguments

- name:

  Character(1). The set's name in `_study.yml`.

- cfg:

  List. A study manifest from
  [`hvtiRutilities::study_config()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.html).

## Value

A data frame of the set's columns and rows, with the per-rule attrition
table attached as `attr(x, "attrition")`.

## See also

[`write_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_analysis_set.md)
