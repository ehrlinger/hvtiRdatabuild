# Read a master dataset's configuration

A master dataset is a clinical dataset that other builds read, such as
the cardiac-surgery master or the mitral master built on top of it. Each
is described by a `master.yml` kept outside the package, because it
names paths on a shared volume. The file declares the master's view
name, its one primary key, any alternate keys, its parent master, and
where its SAS snapshots and build program live.

## Usage

``` r
read_master_config(path)
```

## Arguments

- path:

  Path to the `master.yml` file.

## Value

An object of class `master_config`: a list with `name`, `key`,
`alt_keys` (a named list, possibly empty), `parent` (`NULL` or a list
with `master` and `libref`), `parent_release` (`NULL` or a string),
`snapshots`, `current`, `history` (`NULL` or a regular expression),
`build_program`, and `file`.

## Details

The primary key is what corrections match on and what the view joins on.
Alternate keys are bridges to other systems: each is checked unique
where it is non-null, and its columns are carried on every correction,
but nothing matches on them.

## See also

[`snapshot_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_master.md),
[`lift_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/lift_master.md),
[`backfill_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/backfill_corrections.md)

## Examples

``` r
cfg <- read_master_config(system.file("extdata", "master-example.yml",
                                      package = "hvtiRdatabuild"))
cfg$key
#> [1] "ccfid"   "dt_surg"
```
