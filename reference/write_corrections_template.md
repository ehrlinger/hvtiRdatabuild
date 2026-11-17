# Write an empty correction submission template

One row per cell. `source` is a source view declared in `master.yml`.
The key columns are the union of every source's declared key. A row
fills exactly its own source's key and leaves the others blank: a
patient-level source's rows carry no encounter date.
`expected_prior_missing` and `new_value_missing` are `0` or `1`, and a
value column is blank exactly when its flag is `1`.

## Usage

``` r
write_corrections_template(config, path)
```

## Arguments

- config:

  A `master_config` from
  [`read_master_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_master_config.md),
  with `sources`.

- path:

  Character. Where to write the CSV. An existing file is never
  overwritten.

## Value

`path`, invisibly.

## Details

The filled template holds identifiers. Keep it under the same rules as
study data, and never commit it to a repository.

**Interim.** Superseded by the HVTR registry, which takes over the
template.

## See also

[`propose_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/propose_corrections.md)

## Examples

``` r
cfg_path <- tempfile(fileext = ".yml")
writeLines(c("name: master_demo", "key: [mrn]", "snapshots: snaps",
             "current: x.sas7bdat", "build_program: x.sas",
             "sources:", "  stg_demo: {key: [mrn]}"), cfg_path)
write_corrections_template(read_master_config(cfg_path), tempfile(fileext = ".csv"))
```
