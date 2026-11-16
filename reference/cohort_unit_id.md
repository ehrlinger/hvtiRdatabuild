# Identify a cohort unit by MRN and encounter date

A cohort row is one encounter, not one patient: a patient with two
operations is two units. `cohort_unit_id()` joins the medical record
number and the encounter date into the single identifier a
[`new_cohort_record()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/new_cohort_record.md)
carries as `patient_id`, so the cohort history works unchanged while its
unit becomes the encounter. A cohort built this way uses
`patient_id_col = "cohort_unit"`, the column
[`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md)
adds to the data it returns.

## Usage

``` r
cohort_unit_id(mrn, encounter_date)
```

## Arguments

- mrn:

  Character. Medical record numbers, none missing or empty, none
  containing `|`.

- encounter_date:

  A `Date` vector the same length as `mrn`, none missing.

## Value

A character vector of unit identifiers, `"<mrn>|<YYYY-MM-DD>"`.

## Details

Values are never echoed in an error.

## See also

[`split_cohort_unit()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/split_cohort_unit.md),
[`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md),
[`cohort_query()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/cohort_query.md)

## Examples

``` r
# Synthetic identifiers; no PHI.
cohort_unit_id(c("SYN101", "SYN101"), as.Date(c("2010-03-01", "2015-06-30")))
#> [1] "SYN101|2010-03-01" "SYN101|2015-06-30"
```
