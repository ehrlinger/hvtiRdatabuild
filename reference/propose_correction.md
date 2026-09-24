# Propose a correction to a single cell of a master

Validates the proposal, then appends it to the master's corrections
table with no decision, so it is not applied until
[`decide_correction()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/decide_correction.md)
accepts it. `dry_run = TRUE` validates and returns the row that would be
written, without writing it. A single correction is written by default
because proposing one is a deliberate act. No message ever carries a key
or a value: an unmatched or ambiguous key is reported by count only, and
an over-width or uncastable value is reported by column and limit only.

## Usage

``` r
propose_correction(
  config,
  con,
  key_values,
  variable,
  expected_prior,
  new_value,
  evidence_type,
  evidence_ref,
  asserted_by,
  alt_key = NULL,
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

- key_values:

  A named list of key values identifying the record: the primary key by
  default, or `alt_key`'s columns when `alt_key` is given.

- variable:

  Character. The column to correct; must not be a key or alternate-key
  column.

- expected_prior:

  The value the record is expected to currently hold, or `NA` when it is
  expected to be missing.

- new_value:

  The corrected value, or `NA` to correct to missing.

- evidence_type:

  Character. One of `EVIDENCE_TYPES`.

- evidence_ref:

  Character. A reference to the evidence, such as a document id; never a
  data value.

- asserted_by:

  Character. Who is asserting the correction.

- alt_key:

  Character, or `NULL`, the default. The name of an alternate key in
  `config$alt_keys` that `key_values` matches instead of the primary
  key.

- dry_run:

  If `TRUE`, validate and return the row without writing it. The
  default, `FALSE`, writes it.

- dialect:

  `"mssql"` or `"duckdb"`.

## Value

Invisibly, a list with `verdict` (`"appended"`, or `"validated"` on a
dry run), `correction_id`, `new_variable` (whether this is the first
correction to `variable`, meaning the view should be regenerated), and
`row` (the one-row data frame that was or would be appended).

## Details

By default, `key_values` must name exactly the master's primary key
columns, each a single non-missing value. When `alt_key` is given
instead, `key_values` must name exactly that alternate key's columns,
none may be missing, and it must match exactly one row in the master's
current base table; the correction is then stored against that row's
primary key. Either way, every alternate-key column present in the base
table is filled from that row and carried on the correction for
reference; `variable` may not be the primary key or any alternate key's
column. A failing warehouse call is reported by step, with the driver's
message withheld, because it can quote a data value.

Requires the master's corrections tables, which
[`backfill_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/backfill_corrections.md)
creates.

## See also

[`backfill_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/backfill_corrections.md),
[`decide_correction()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/decide_correction.md)

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
  dir <- tempfile("propose")
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
  propose_correction(cfg, con, key_values = list(id = "K1"), variable = "age",
                     expected_prior = 60, new_value = 61, evidence_type = "chart_review",
                     evidence_ref = "invented", asserted_by = "tester", dialect = "duckdb")
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
#> Correction c2250525e1b07fddd appended. First correction to this variable: regenerate the view.
# }
```
