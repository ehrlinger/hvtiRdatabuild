# Turn a study's own data fixes into candidate corrections

A fix made in study code leaves the study out of step with the master
and every other study (G5). This compares the study's corrected data
with **the study's own frozen pull**, never the live view: sources are
not time-travelable, so a later read would mistake upstream change for a
study fix (spec §3.5).

## Usage

``` r
study_correction_candidates(
  config,
  con,
  pull,
  data,
  path,
  key = c("mrn", "encounter_date"),
  dialect = "mssql"
)
```

## Arguments

- config:

  A `master_config` from
  [`read_master_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_master_config.md),
  with `sources`.

- con:

  A DBI connection to the warehouse, to read the master's lineage.

- pull:

  Character. The study's frozen pull, from
  [`freeze_study_pull()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/freeze_study_pull.md).

- data:

  A data frame: the study's corrected data, keyed as the pull is.

- path:

  Character. The candidate template to write, ending `.csv`. Never
  overwritten.

- key:

  Character. The cohort unit's key columns in the pull and in `data`.

- dialect:

  `"mssql"` or `"duckdb"`.

## Value

Invisibly, a list: `candidates`, `inconsistent`, `derived` (a data frame
of `column`, `n_cells`), `path` and `derived_path`.

## Details

- **Pass-through columns.** A differing cell in a column that
  `<master>_lineage` lists becomes a row of the correction template at
  `path`. The row is keyed by the source's declared key, and
  `expected_prior` comes from the pull. `evidence_type` and
  `asserted_by` are left blank, so
  [`propose_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/propose_corrections.md)
  refuses the file until a person has reviewed it and filled them in.

- **Derived columns.** A differing cell in any other column is a
  candidate derivation, not a correction. It is counted per column in
  the `-derived.csv` file beside `path`.

- **Patient-level sources.** When encounters of one patient disagree on
  such a source's cell, the candidates are dropped and counted as
  inconsistent. Agreement is checked over the encounters present in
  `data`; an encounter dropped from `data` carries no study value, so it
  cannot contradict a candidate, and intake rechecks `expected_prior`
  against the source.

- **Undeclared sources.** A lineage source not declared in `master.yml`
  is counted as derived, because this intake cannot correct it.

If the source has changed since the pull, intake refuses the row as
`prior_mismatch`. Nothing is appended here, and only counts are printed.
The files hold identifiers and belong in the study's data folder.

**Interim.** Superseded by the HVTR registry.

## See also

[`propose_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/propose_corrections.md),
[`freeze_study_pull()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/freeze_study_pull.md)

## Examples

``` r
# Needs a frozen pull and the warehouse; see freeze_study_pull().
```
