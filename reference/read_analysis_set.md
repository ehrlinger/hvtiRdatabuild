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
