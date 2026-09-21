# Withdraw a published dataset release

Withdrawal changes the release's catalog status and records why it
should no longer be adopted. It never changes or deletes the release
file. A study already pinned to that release can therefore reproduce
historical work with the explicit `allow_withdrawn = TRUE` override in
[`hvtiRutilities::read_built()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_built.html),
while normal reads stop and report the withdrawal.

## Usage

``` r
withdraw_dataset_release(
  dataset_id,
  release_id,
  datasets_dir,
  reason,
  replacement_release_id = NULL
)
```

## Arguments

- dataset_id:

  Character. Stable logical dataset identifier.

- release_id:

  Character. Exact release identifier to withdraw.

- datasets_dir:

  Character. Existing directory that owns the published files and
  `dataset-catalog.yml`.

- reason:

  Character. Non-empty reason for withdrawal.

- replacement_release_id:

  Optional character release identifier from the same logical dataset.

## Value

Invisibly, the release record with `status = "withdrawn"`,
`withdrawal_reason`, and `replacement_release_id` when supplied.

## Details

A replacement is optional, but it must name another release under the
same logical dataset. Catalog locking serializes withdrawal with
publication, so neither operation can discard the other's catalog
change.

## Examples

``` r
published <- tempfile("published-")
dir.create(published)
draft <- tempfile(fileext = ".csv")
write.csv(data.frame(synthetic_id = "SYN001", value = 1), draft,
          row.names = FALSE)
release <- publish_dataset(
  draft,
  "example_cohort",
  published,
  extract_date = "2026-09-21"
)
withdrawn <- withdraw_dataset_release(
  "example_cohort",
  release$release_id,
  published,
  reason = "Synthetic example correction"
)
withdrawn$status
#> [1] "withdrawn"
file.exists(file.path(published, release$file))
#> [1] TRUE
unlink(c(draft, published), recursive = TRUE)
```
