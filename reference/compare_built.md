# Compare an R-built dataset against a SAS oracle

Joins `r` to `oracle` on `id` and classifies every variable. Row-set
differences are reported separately from value differences: an
identifier present on one side only is a cohort discrepancy, a different
class of problem from a miscomputed variable, and conflating the two
hides both.

## Usage

``` r
compare_built(oracle, r, id = "ccfidu", tolerance = 1e-08)
```

## Arguments

- oracle:

  Data frame read from the parquet oracle. See
  [`snapshot_oracle()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_oracle.md).

- r:

  Data frame produced by the R pipeline.

- id:

  Name of the identifier column present in both. Must be unique within
  each.

- tolerance:

  Numeric. **Absolute** numeric differences at or below this are
  reported as `"within_tolerance"`. A single absolute threshold cannot
  serve columns of very different magnitude; see the "Coming from SAS"
  vignette for how to read `max_rel_diff` alongside it.

## Value

An object of class `built_comparison`: a data frame with one row per
variable and columns `variable`, `n_common`, `verdict`, `n_differ`,
`max_abs_diff`, `max_rel_diff`, and `detail`. `n_common` is the number
of rows compared (constant across all rows, so it survives
[`write.csv()`](https://rdrr.io/r/utils/write.table.html) or
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html), unlike
the `rows` attribute). `verdict` is one of `"identical"`,
`"within_tolerance"`, `"differs"`, `"absent_in_r"`, `"absent_in_sas"`,
or `"type_mismatch"`. The `rows` attribute holds a list with `n_oracle`,
`n_r`, `n_common`, `only_oracle`, and `only_r`.

## Details

This function deliberately returns a table and never a single pass/fail.
Collapsing several hundred variables into one boolean launders real
differences into a green check. Read the table.

A difference does not automatically mean the R code is wrong. SAS orders
missing numerics below all values, so `if bmi < 18.5` classifies a
missing BMI as underweight where R yields `NA`. Record such cases as
`intentional_divergence` in `equivalence_signoff.yaml`.

## See also

[`snapshot_oracle()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_oracle.md)

## Examples

``` r
o <- data.frame(ccfidu = c("A1", "A2"), age = c(65, 70))
r <- data.frame(ccfidu = c("A1", "A2"), age = c(65, 71))
compare_built(o, r, id = "ccfidu")
#> Dataset comparison
#>   rows: 2 oracle, 2 R, 2 common
#> 
#>   variables by verdict:
#>     differs            1
#> 
#>   requiring review:
#>  variable verdict n_differ max_abs_diff max_rel_diff detail
#>       age differs        1            1   0.01408451       
```
