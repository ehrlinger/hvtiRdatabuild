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
# \donttest{
if (requireNamespace("duckdb", quietly = TRUE) &&
      requireNamespace("arrow", quietly = TRUE)) {
  # Synthetic data; no PHI. A master, its lineage to one source, and a frozen pull.
  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbWriteTable(con, "master_demo", data.frame(
    mrn = c("SYN101", "SYN102"), encounter_date = as.Date(c("2010-03-01", "2011-05-02")),
    proc = "CABG", age = c(62, 70)
  ))
  DBI::dbWriteTable(con, "master_demo_corrections_applied", data.frame(
    correction_id = character(), mrn = character(), encounter_date = as.Date(character())
  ))
  DBI::dbWriteTable(con, "master_demo_deployment", data.frame(sql_commit = "abc1234"))
  DBI::dbWriteTable(con, "master_demo_parity", data.frame(
    sql_commit = "abc1234", verdict = "pass", verified_at = Sys.time()
  ))
  DBI::dbWriteTable(con, "master_demo_lineage", data.frame(
    master_column = "age", source = "stg_demo", source_column = "age_years"
  ))
  study_cfg <- tempfile(fileext = ".yaml")
  writeLines("study: st0000", study_cfg)
  q <- cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")))
  pull <- pull_master(con, "master_demo", q, var_cols = c("proc", "age"),
                      path = study_cfg, dialect = "duckdb")
  published <- tempfile("published-")
  dir.create(published)
  frozen <- file.path(published, freeze_study_pull(pull, study_cfg, published,
                                                   "st0000_pull")$file)

  # The study corrects one age; that fix becomes a candidate correction to stg_demo.
  cfg_path <- tempfile(fileext = ".yml")
  writeLines(c("name: master_demo", "key: [mrn, encounter_date]", "snapshots: snaps",
               "current: x.sas7bdat", "build_program: x.sas",
               "sources:", "  stg_demo: {key: [mrn, encounter_date]}"), cfg_path)
  data <- as.data.frame(arrow::read_parquet(frozen))
  data$age[data$mrn == "SYN102"] <- 71
  out <- study_correction_candidates(read_master_config(cfg_path), con, frozen, data,
                                     tempfile(fileext = ".csv"), dialect = "duckdb")
  utils::read.csv(out$path)

  DBI::dbDisconnect(con, shutdown = TRUE)
  unlink(c(study_cfg, cfg_path, published, out$path, out$derived_path), recursive = TRUE)
}
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpEjXK56/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> study_correction_candidates(): 1 candidate correction(s), 0 inconsistent cell(s), 0 derived-column difference(s) in 0 column(s).
# }
```
