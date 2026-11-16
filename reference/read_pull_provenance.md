# Read the provenance a frozen pull carries

Read the provenance a frozen pull carries

## Usage

``` r
read_pull_provenance(path)
```

## Arguments

- path:

  Character. A parquet file written by
  [`freeze_study_pull()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/freeze_study_pull.md).

## Value

A list: `schema`, `master`, `sql_commit`, `applied_correction_ids`,
`corrections_in_effect`, `parity_verified_at`, `read_at`, `columns`,
`cohort_definition`, `study_config_sha256`, `n_cohort`, `n_matched`,
`n_unmatched` and `cohort_stages`.

## See also

[`freeze_study_pull()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/freeze_study_pull.md)

## Examples

``` r
# See freeze_study_pull().
```
