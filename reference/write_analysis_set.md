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
written to the sidecar or the manifest. A set that names an `event`
column, one of its `vars`, also counts `n_events` (rows where it
equals 1) and `n_censored`; an `expect` on either count needs that
`event` key.

The parent is read with
[`hvtiRutilities::read_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.html),
and a working read is refused: an analysis set is built from registered
data only. Under `HVTI_DATA=working`, or for a dataset with no dated
version, it stops and names `update_manifest()`.

## Examples

``` r
# \donttest{
if (requireNamespace("arrow", quietly = TRUE)) {
  # A throwaway study in a temporary directory. Values are invented; no PHI.
  root <- tempfile("study")
  dir.create(root)
  suppressMessages(hvtiRutilities::study_setup(
    root, study = "Synthetic", study_tracker_id = 1L, adopt = TRUE,
    cleanup = FALSE, renv = FALSE
  ))
  built <- data.frame(
    ccfid = 1:6, age = c(15, 42, 55, 61, 70, 48),
    dead = c(0L, 1L, 0L, 1L, 0L, 0L)
  )
  utils::write.csv(
    built,
    file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"),
    row.names = FALSE
  )
  suppressMessages(hvtiRutilities::register_data(root, built = "built.csv"))
  yml <- file.path(root, "_study.yml")
  y <- yaml::read_yaml(yml)
  y$analysis_sets <- list(primary = list(
    id = "ccfid", vars = c("ccfid", "age", "dead"), event = "dead",
    exclude = list(list(reason = "Under 18", when = "age < 18"))
  ))
  yaml::write_yaml(y, yml)
  cfg <- hvtiRutilities::study_config(root)
  side <- write_analysis_set("primary", cfg)
  print(side$counts)
  unlink(root, recursive = TRUE)
}
#> $n
#> [1] 5
#> 
#> $n_events
#> [1] 2
#> 
#> $n_censored
#> [1] 3
#> 
# }
```
