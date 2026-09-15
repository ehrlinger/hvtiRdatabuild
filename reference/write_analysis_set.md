# Write an analysis set

Cuts the analysis set `name`, declared under `analysis_sets:` in the
study's `_study.yml`, from the built dataset: keeps its `vars`, applies
its `exclude` rules in order (first match wins), checks any `expect`
counts, and writes `<name>.parquet` and a `<name>.set.yml` sidecar in
the study's logical datasets directory, plus a `manifest.yaml` entry.
The sidecar records the parent dataset and the attrition.

## Usage

``` r
write_analysis_set(name, cfg = hvtiRutilities::study_config())
```

## Arguments

- name:

  Character(1). The set's name in `_study.yml`.

- cfg:

  List. A study manifest from
  [`hvtiRutilities::study_config()`](https://ehrlinger.github.io/hvtiRutilities/reference/study_config.html).

## Value

The sidecar contents, invisibly: a list with `set`, `parent`,
`declaration_sha256`, `written`, `counts`, `n_cols`, `attrition` and
`packages`.

## Details

Nothing is written unless every check passes. Each `when` is R code
evaluated against the data with only base R visible; a missing value
counts as not excluded, as SAS `if <missing> then delete` does. The
identifier column named by `id` is used to track exclusions and is never
written to the sidecar or the manifest.
