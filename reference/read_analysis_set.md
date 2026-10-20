# Read an analysis set

Reads the analysis set `name` written by
[`write_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_analysis_set.md),
after checking that it is current. A set is stale when the built dataset
has a newer registered version than the one it was cut from, or when its
declaration in `_study.yml` has changed. A stale set is never rebuilt
silently: its exclusions are decisions, and a changed attrition should
be looked at. In a draft render it is read, with a message of class
`hvtiRutilities_stale_analysis_set` giving the
[`write_analysis_set()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/write_analysis_set.md)
call that updates it. In a final render (`HVTI_TEMPLATE_STRICT` set, as
`hvtiRtemplates::render_job(final = TRUE)` sets it) it stops with the
same text. A parquet that no longer matches its manifest entry always
stops.

When the built dataset is registered as a dated parquet, "changed" means
a newer version has been registered with
[`hvtiRutilities::update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.html).
Rebuilding the source alone does not make a set stale, because nothing
reads the rebuild until it is registered.

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
  write_analysis_set("primary", cfg)
  d <- read_analysis_set("primary", cfg)
  print(dim(d))
  print(attr(d, "attrition"))
  unlink(root, recursive = TRUE)
}
#> [1] 5 3
#>   rule   reason n_before n_excluded n_after
#> 1    1 Under 18        6          1       5
# }
```
