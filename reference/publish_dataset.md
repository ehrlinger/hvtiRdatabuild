# Publish an immutable dataset release

A draft is the file a programmer is still allowed to rebuild.
Publication copies those bytes to a dated release file and adds the
release to `dataset-catalog.yml`. Consuming studies can then discover
the release, but they keep reading the release they already pinned until
someone explicitly adopts the new one with
[`hvtiRutilities::adopt_data_update()`](https://ehrlinger.github.io/hvtiRutilities/reference/adopt_data_update.html).

## Usage

``` r
publish_dataset(
  draft,
  dataset_id,
  datasets_dir,
  extract_date = Sys.Date(),
  source = NULL,
  file_stem = dataset_id
)
```

## Arguments

- draft:

  Character. Path to a mutable draft dataset.

- dataset_id:

  Character. Stable logical dataset identifier, using lower-case
  letters, digits, and underscores.

- datasets_dir:

  Character. Existing directory that owns the published files and
  `dataset-catalog.yml`.

- extract_date:

  A `Date` or `YYYY-MM-DD` string. Defaults to today.

- source:

  Optional character string recording publisher provenance.

- file_stem:

  Character. Safe basename stem for dated release files. Defaults to
  `dataset_id`.

## Value

Invisibly, a named list containing `release_id`, `sequence`, `file`,
`extract_date`, `revision`, `published_at`, `sha256`, `n_rows`,
`n_cols`, `status`, and `source` when supplied.

## Details

`publish_dataset()` reads the draft, stages a byte-for-byte copy in
`datasets_dir`, and reads the staged copy again before recording its
SHA-256, row count, and column count. It supports the clinical-data
formats read by
[`hvtiRutilities::read_clinical_data()`](https://ehrlinger.github.io/hvtiRutilities/reference/read_clinical_data.html):
`.sas7bdat`, `.csv`, `.xlsx`, `.xls`, and `.rds`. This verifies that the
release is readable and records its shape. It does not decide whether
the cohort or its values are clinically correct.

The first release on a date is named `<file_stem>_YYYYMMDD.<ext>`. A
different release published for the same extract date adds `_r2`, `_r3`,
and so on. The catalog lock protects that sequence when two processes
publish at once. Publishing the same bytes again for the same dataset
and date is idempotent: it returns the existing release rather than
creating a revision. If that release was withdrawn, it remains
withdrawn; publication does not reactivate the bytes under a new release
identity.

The release file moves into place before the catalog is replaced. If the
catalog write fails, the file remains as an unregistered orphan. No
study can discover it. Retry the same call and publication registers the
matching orphan without rewriting its bytes. Different bytes at an
expected release filename are an integrity error and are never
overwritten.

## Examples

``` r
published <- tempfile("published-")
dir.create(published)
draft <- tempfile(fileext = ".csv")
write.csv(
  data.frame(synthetic_id = c("SYN001", "SYN002"), value = c(1, 2)),
  draft,
  row.names = FALSE
)
release <- publish_dataset(
  draft,
  dataset_id = "example_cohort",
  datasets_dir = published,
  extract_date = "2026-09-21",
  source = "Synthetic documentation example"
)
release$release_id
#> [1] "example_cohort-20260921-r1"
unlink(c(draft, published), recursive = TRUE)
```
