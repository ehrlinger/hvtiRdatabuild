# List the available warehouse modules

Module definitions ship as data under `inst/extdata/modules/`, one YAML
file per module, rather than as R code. They change independently of the
code that executes them, they carry a description of the SAS block each
one ports, and holding them outside R source is what keeps site-specific
identifiers out of this repository — the SQL ships with placeholders and
the real warehouse, schema, and cohort names arrive from `study.yaml` at
run time.

## Usage

``` r
dw_modules()
```

## Value

A data frame with one row per module and columns `module`, `output`,
`join_key`, and `optional`.

## Examples

``` r
dw_modules()
#>                  module   output join_key optional
#> base               base   bdbase masterid    FALSE
#> echo               echo     echo    patid     TRUE
#> events           events bdevents    patid     TRUE
#> fup                 fup      fup    patid    FALSE
#> vitalstatus vitalstatus   bdstat masterid    FALSE
```
