# Apply study-specific variable derivations

Runs committed study-specific R code after dataset assembly. The
callback may add analysis variables and append local exclusion stages to
the cohort record; it may not rewrite earlier membership decisions.

## Usage

``` r
derive_vars(build, config, study_derive)
```

## Arguments

- build:

  A `build_result` from
  [`build_dataset()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/build_dataset.md).

- config:

  A `study_config` from
  [`read_study_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_study_config.md).

- study_derive:

  A function with arguments `data`, `cohort`, and `config`. It returns a
  named list with updated `data` and `cohort` elements.

## Value

An object of class `derive_result` with `data`, `cohort`, and unchanged
supporting `tables` elements.
