# Record chart-review decisions on a pull

Reads a decisions file with one row per entry of
[`review_list()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/review_list.md):
`cohort_unit`, `criterion_id`, `outcome` (`"met"` or `"not_met"`) and
`reason_code`. An outcome that excludes the unit (not met on an include
criterion, or met on an exclude criterion) needs a code from
`reason_codes`. Codes, never free text: chart notes are PHI.

## Usage

``` r
apply_review(pull, path, reason_codes)
```

## Arguments

- pull:

  A `master_pull` awaiting review.

- path:

  Character. The decisions file, as CSV.

- reason_codes:

  Character. The study's declared reason codes.

## Value

The `master_pull`, with the review stages appended and `data` filtered.

## Details

A routed unit is settled at the criterion that routed it, so the stage
counts stay sequential: if review excludes it, the exclusion is recorded
at that criterion and no later stage counts the unit, whether or not a
later criterion also excluded it; if review keeps it, every later
outcome stands. The criterion's provenance records how many were
excluded at review and the decisions file's checksum. Each review
criterion is then its own stage, with source `review`. The file's
SHA-256 is recorded in the pull's metadata, and the pull is then
complete.

Each later criterion's tally of met, not met and undetermined units is
rebuilt from the units that reached it, using the outcomes
[`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md)
keeps in `review$outcomes`. A pull saved before that field existed has
none, so decisions that would change a counted stage are refused with an
error of class `hvtiRdatabuild_review_outcomes_missing`: pull again with
[`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md)
and apply the decisions to the new pull. Decisions that change no
counted stage are applied as usual.

## See also

[`review_list()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/review_list.md),
[`review_criterion()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/review_criterion.md)

## Examples

``` r
# \donttest{
if (requireNamespace("duckdb", quietly = TRUE)) {
  # Synthetic data; no PHI.
  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbWriteTable(con, "master_demo", data.frame(
    mrn = c("SYN101", "SYN102"),
    encounter_date = as.Date(c("2010-03-01", "2012-07-15")),
    proc = c("CABG", "CABG"), age = c(62, 70)
  ))
  DBI::dbWriteTable(con, "master_demo_corrections_applied", data.frame(
    correction_id = character(), mrn = character(), encounter_date = as.Date(character())
  ))
  DBI::dbWriteTable(con, "master_demo_deployment", data.frame(sql_commit = "abc1234"))
  DBI::dbWriteTable(con, "master_demo_parity", data.frame(
    sql_commit = "abc1234", verdict = "pass", verified_at = Sys.time()
  ))
  config <- tempfile(fileext = ".yaml")
  writeLines("study: st0000", config)
  strategy <- review_criterion("strategy", "Planned alternative support", role = "exclude")
  q <- cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")),
                    criteria = list(strategy), index_on = "qualifying")
  pull <- pull_master(con, "master_demo", q, var_cols = "age", path = config,
                      dialect = "duckdb")
  DBI::dbDisconnect(con, shutdown = TRUE)

  # One decision per row of the review list, with a declared code for each exclusion.
  decisions <- review_list(pull)
  decisions$outcome <- c("not_met", "met")
  decisions$reason_code <- c(NA, "PLANNED")
  f <- tempfile(fileext = ".csv")
  utils::write.csv(decisions, f, row.names = FALSE, na = "")
  reviewed <- apply_review(pull, f, reason_codes = "PLANNED")
  reviewed$meta$status
}
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpoKQLwY/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> [1] "complete"
# }
```
