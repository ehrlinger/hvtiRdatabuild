# Snapshot a master dataset to parquet, with its lineage

Freezes a master's current SAS build, or its historical builds, as
parquet with
[`snapshot_oracle()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_oracle.md),
then checks its keys and records which release of its parent master it
was built from.

## Usage

``` r
snapshot_master(
  config,
  out_dir,
  which = c("current", "history"),
  chunk_rows = 1e+05,
  expect = NULL
)
```

## Arguments

- config:

  A `master_config` from
  [`read_master_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_master_config.md).

- out_dir:

  Directory to write the parquet snapshots and their sidecars.

- which:

  `"current"`, `"history"`, or both.

- chunk_rows:

  Rows per chunk, passed to
  [`snapshot_oracle()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_oracle.md).

- expect:

  Optional validation for the current build, passed to
  [`snapshot_oracle()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_oracle.md).
  Historical builds are not validated, because their logs are rarely
  retained.

## Value

Invisibly, a data frame with one row per dataset: `file`, `status`
(`"written"`, `"skipped"` or `"failed"`), `n_rows`, `n_cols`, `sha256`,
`source_sha256`, `parent_release`, `parent_source` (`"log"`,
`"program"`, `"declared"`, `"unknown"` or `"none"`) and `key_verdict`.

## Details

The parent release is read from evidence of what ran, in this order: the
log of the run that produced the dataset (a `.log` whose timestamp falls
within six hours after the dataset's), where SAS records every dataset
it read; then, for the current build only, the build program's `set`
statements; then `parent_release` in the configuration. The log comes
first because a program can be edited after the run. A current build
whose parent cannot be decided stops; a historical one with no detected
parent records `"unknown"`. `parent_release` in the configuration, and
the disagreement check against a detected parent, apply only to the
current build: a declared release describes the build as configured
today, not necessarily what an older historical dataset actually read.

Only `NOTE:` lines naming datasets are read from a log, never data
lines. Nothing printed carries a key or a value.

## See also

[`read_master_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_master_config.md),
[`lift_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/lift_master.md)

## Examples

``` r
# \donttest{
if (requireNamespace("arrow", quietly = TRUE) &&
    requireNamespace("jsonlite", quietly = TRUE) &&
    requireNamespace("tidyselect", quietly = TRUE)) {
  dir <- tempfile("master")
  dir.create(dir)
  file.copy(system.file("extdata", "oracle_small.sas7bdat",
                        package = "hvtiRdatabuild"),
            file.path(dir, "built.sas7bdat"))
  writeLines("data m; run;", file.path(dir, "bd.data.sas"))
  cfg_path <- file.path(dir, "master.yml")
  writeLines(c("name: master_demo", "key: [ccfidu]",
               paste0("snapshots: ", dir), "current: built.sas7bdat",
               paste0("build_program: ", file.path(dir, "bd.data.sas"))),
             cfg_path)
  snapshot_master(read_master_config(cfg_path), tempfile("out"),
                  which = "current")
}
#> built.sas7bdat                           4 rows x 5 columns; key unique; parent NA (none)
# }
```
