# List what a pull needs decided at chart review

Every unit a criterion routed to review (`undetermined = "review"`), and
every unit still in the cohort for each
[`review_criterion()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/review_criterion.md).
The list holds unit identifiers. Keep it with the study's other
restricted files, and never print it to a shared log.

## Usage

``` r
review_list(pull)
```

## Arguments

- pull:

  A `master_pull` from
  [`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md).

## Value

A data frame with `cohort_unit` and `criterion_id`.

## See also

[`apply_review()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/apply_review.md)

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
#> ℹ /tmp/Rtmpg9Eg5v/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> [1] "complete"
# }
```
