# Decide a correction: accept, reject, supersede or bake it

Records the decision in the master's decisions table; the correction
applies only when its latest decision is `"accept"`. `dry_run = TRUE`
validates and returns the row that would be written, without writing it.

## Usage

``` r
decide_correction(
  config,
  con,
  correction_id,
  decision,
  decided_by,
  reason = NA_character_,
  dry_run = FALSE,
  dialect = "mssql"
)
```

## Arguments

- config:

  A `master_config` from
  [`read_master_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_master_config.md).

- con:

  A DBI connection.

- correction_id:

  Character. The correction being decided.

- decision:

  Character. One of `DECISIONS`.

- decided_by:

  Character. Who is deciding.

- reason:

  Character, or `NA_character_`, the default. A note on the decision.

- dry_run:

  If `TRUE`, validate and return the row without writing it. The
  default, `FALSE`, writes it.

- dialect:

  `"mssql"` or `"duckdb"`.

## Value

Invisibly, a list with `verdict` (`"recorded"`, or `"validated"` on a
dry run), `decision_id`, and `row` (the one-row data frame that was or
would be appended).

## Details

Requires the master's corrections tables, which
[`backfill_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/backfill_corrections.md)
creates.

## See also

[`backfill_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/backfill_corrections.md),
[`propose_correction()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/propose_correction.md)

## Examples

``` r
# \donttest{
if (requireNamespace("duckdb", quietly = TRUE) &&
    requireNamespace("arrow", quietly = TRUE) &&
    requireNamespace("jsonlite", quietly = TRUE) &&
    requireNamespace("tidyselect", quietly = TRUE) &&
    requireNamespace("dplyr", quietly = TRUE) &&
    requireNamespace("withr", quietly = TRUE) &&
    requireNamespace("digest", quietly = TRUE)) {
  dir <- tempfile("decide")
  dir.create(dir)
  pq <- file.path(dir, "built_demo.parquet")
  arrow::write_parquet(data.frame(id = c("K1", "K2"), age = c(60, 61)), pq)
  jsonlite::write_json(
    list(parquet_sha256 = digest::digest(pq, algo = "sha256", file = TRUE),
         columns = list(list(variable = "id", r_class = "character"),
                        list(variable = "age", r_class = "numeric"))),
    sub("\\.parquet$", ".meta.json", pq), auto_unbox = TRUE)
  writeLines("data m; run;", file.path(dir, "bd.sas"))
  cfg_path <- file.path(dir, "master.yml")
  writeLines(c("name: master_demo", "key: [id]", paste0("snapshots: ", dir),
               "current: built_demo.sas7bdat",
               paste0("build_program: ", file.path(dir, "bd.sas"))), cfg_path)
  cfg <- read_master_config(cfg_path)
  con <- DBI::dbConnect(duckdb::duckdb())
  lift_master(cfg, con, pq, dry_run = FALSE, dialect = "duckdb")
  backfill_corrections(cfg, con, dry_run = FALSE, dialect = "duckdb")
  prop <- propose_correction(cfg, con, key_values = list(id = "K1"), variable = "age",
                             expected_prior = 60, new_value = 61,
                             evidence_type = "chart_review", evidence_ref = "invented",
                             asserted_by = "tester", dialect = "duckdb")
  decide_correction(cfg, con, prop$correction_id, "accept", "tester", dialect = "duckdb")
  DBI::dbDisconnect(con, shutdown = TRUE)
}
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpjL3Uzs/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
#> key id                               unique     rows 2, null key parts 0, duplicates 0
#> load: 1 row groups loaded, 0 already present
#> parity pass: row count match; 0 of 2 columns mismatch; 0 of 2 sampled columns mismatch
#> parity_full: 0 of 2 columns mismatch
#> view master_demo -> master_demo_base_built_demo
#> legacy: 0 facts parsed; 0 resolved; 0 unresolved
#> recorded 0; 0 stale corrections
#> Correction cf3351fb9e65b18f4 appended. First correction to this variable: regenerate the view.
#> Decision d5aeb20f8579c2701 (accept) recorded on cf3351fb9e65b18f4.
# }
```
