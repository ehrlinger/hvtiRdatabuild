# Read and validate a study configuration

Loads the `study.yaml` that declares which warehouse modules a study
pulls and which derivation steps it runs. The SAS templates expressed
this as a catalogue of optional blocks, commented in or out; this makes
it an explicit, diffable, committed file.

## Usage

``` r
read_study_config(path)
```

## Arguments

- path:

  Path to a `study.yaml` file.

## Value

An object of class `study_config`: a list with elements `study`,
`cohort_table`, `warehouse`, `view_schema`, `pull_date` (a `Date`),
`modules` (a non-empty character vector), `varsets`, and `derive` (a
named logical vector).

## Details

Validation is strict by design. An unknown key is an error rather than a
warning, because a typo'd module name must not silently disable a module
— that failure mode produces a quietly incomplete dataset with no
signal. For the same reason, `modules` must name at least one module: an
empty or bare `modules` key would otherwise pull zero data with no
error, the same failure mode the SAS-era workflow of commenting out the
last enabled block produces.

## Examples

``` r
path <- tempfile(fileext = ".yaml")
yaml::write_yaml(list(
  study = "st1234", cohort_table = "db.schema.st1234_cohort",
  warehouse = "warehouse", view_schema = "dbo",
  pull_date = "2026-08-04", modules = list("base"),
  varsets = list("core"), derive = list(missing = TRUE)
), path)
read_study_config(path)
#> $study
#> [1] "st1234"
#> 
#> $cohort_table
#> [1] "db.schema.st1234_cohort"
#> 
#> $warehouse
#> [1] "warehouse"
#> 
#> $view_schema
#> [1] "dbo"
#> 
#> $pull_date
#> [1] "2026-08-04"
#> 
#> $modules
#> [1] "base"
#> 
#> $varsets
#> [1] "core"
#> 
#> $derive
#> missing 
#>    TRUE 
#> 
#> attr(,"class")
#> [1] "study_config"
```
