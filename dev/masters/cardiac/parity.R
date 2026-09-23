# parity.R
#
# Is the loaded table the parquet snapshot? Row count; per column, non-null
# count, distinct count and numeric sum on both sides; and a full value compare
# on a random sample of rows joined on the key. Aggregates alone pass with
# compensating errors: a sum cannot see two cells swap. Verdicts only.

parity_sql <- function(table, column, is_numeric, is_character, dialect) {
  q <- quoter(dialect)
  col <- q(column)
  # SQL Server's default collation ignores case and trailing spaces in DISTINCT;
  # hashing compares the stored characters exactly, as R does.
  distinct_expr <- if (is_character && dialect == "mssql") {
    sprintf("HASHBYTES('SHA2_256', %s)", col)
  } else {
    col
  }
  total <- if (is_numeric) sprintf(", SUM(CAST(%s AS DOUBLE PRECISION)) AS total", col) else ""
  sprintf("SELECT COUNT(%s) AS n_nonnull, COUNT(DISTINCT %s) AS n_distinct%s FROM %s",
          col, distinct_expr, total, q(table))
}

.zap_all <- function(d) {
  haven::zap_widths(haven::zap_formats(haven::zap_labels(haven::zap_label(d))))
}

parity_check <- function(con, table, parquet, key, sample_n = 1000L, seed = 1L,
                         dialect = "mssql") {
  q <- quoter(dialect)
  reader <- arrow::ParquetFileReader$create(parquet)
  cols <- names(reader$GetSchema())

  db_n <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s", q(table)))$n
  row_count <- if (as.numeric(db_n) == as.numeric(reader$num_rows)) "match" else "mismatch"

  columns <- do.call(rbind, lapply(cols, function(v) {
    x <- arrow::read_parquet(parquet, col_select = tidyselect::all_of(v))[[1]]
    is_num <- is.numeric(unclass(x)) && !inherits(x, c("Date", "POSIXt"))
    is_chr <- is.character(x)
    db <- DBI::dbGetQuery(con, parity_sql(table, v, is_num, is_chr, dialect))
    ok <- as.numeric(db$n_nonnull) == sum(!is.na(x)) &&
      as.numeric(db$n_distinct) == length(unique(x[!is.na(x)]))
    if (is_num) {
      db_total <- if (is.na(db$total)) 0 else as.numeric(db$total)
      ok <- ok && isTRUE(all.equal(sum(as.numeric(x), na.rm = TRUE), db_total,
                                   tolerance = 1e-9))
    }
    data.frame(variable = v, verdict = if (ok) "match" else "mismatch",
               stringsAsFactors = FALSE)
  }))

  keys <- as.data.frame(arrow::read_parquet(parquet, col_select = tidyselect::all_of(key)))
  idx <- withr::with_seed(seed, sample.int(nrow(keys), min(sample_n, nrow(keys))))
  picked <- keys[idx, , drop = FALSE]
  tmp <- if (dialect == "mssql") "#parity_sample_keys" else "parity_sample_keys"
  DBI::dbWriteTable(con, tmp, picked, temporary = TRUE, overwrite = TRUE)
  on.exit(DBI::dbRemoveTable(con, tmp), add = TRUE)
  on <- paste(sprintf("t.%s = s.%s", q(key), q(key)), collapse = " AND ")
  db_rows <- DBI::dbGetQuery(con, sprintf("SELECT t.* FROM %s t JOIN %s s ON %s",
                                          q(table), q(tmp), on))
  pq_rows <- .zap_all(as.data.frame(dplyr::collect(
    dplyr::semi_join(arrow::open_dataset(parquet), picked, by = key))))

  make_id <- function(d) do.call(paste, c(lapply(d[key], as.character), sep = "\r"))
  pq_rows$.parity_key <- make_id(pq_rows)
  db_rows$.parity_key <- make_id(db_rows)
  cmp <- hvtiRdatabuild::compare_built(pq_rows, db_rows, id = ".parity_key")
  rows <- attr(cmp, "rows")
  rows_complete <- length(rows$only_oracle) == 0L && length(rows$only_r) == 0L
  sample_ok <- cmp$verdict %in% c("identical", "within_tolerance") & rows_complete
  sample <- data.frame(variable = cmp$variable,
                       verdict = ifelse(sample_ok, "match", "mismatch"),
                       stringsAsFactors = FALSE)

  pass <- row_count == "match" && all(columns$verdict == "match") &&
    all(sample$verdict == "match")
  list(verdict = if (pass) "pass" else "fail", row_count = row_count,
       columns = columns, sample = sample)
}

parity_summary <- function(res) {
  sprintf("parity %s: row count %s; %d of %d columns mismatch; %d of %d sampled columns mismatch",
          res$verdict, res$row_count,
          sum(res$columns$verdict == "mismatch"), nrow(res$columns),
          sum(res$sample$verdict == "mismatch"), nrow(res$sample))
}

# The full gate: every non-key column, every row, compared by key. parity_check
# is aggregates plus a sample, which a compensating swap of two cells can pass;
# this cannot, because every row is in the comparison.
parity_full <- function(con, table, parquet, key, dialect = "mssql") {
  q <- quoter(dialect)
  reader <- arrow::ParquetFileReader$create(parquet)
  cols <- setdiff(names(reader$GetSchema()), key)
  make_id <- function(d) do.call(paste, c(lapply(d[key], as.character), sep = "\r"))
  rows <- lapply(cols, function(v) {
    pq <- .zap_all(as.data.frame(
      arrow::read_parquet(parquet, col_select = tidyselect::all_of(c(key, v)))))
    db <- DBI::dbGetQuery(con, sprintf("SELECT %s FROM %s",
                                       paste(q(c(key, v)), collapse = ", "), q(table)))
    pq_v <- data.frame(.parity_key = make_id(pq), value = pq[[v]], stringsAsFactors = FALSE)
    db_v <- data.frame(.parity_key = make_id(db), value = db[[v]], stringsAsFactors = FALSE)
    cmp <- hvtiRdatabuild::compare_built(pq_v, db_v, id = ".parity_key")
    keyed <- attr(cmp, "rows")
    rows_complete <- length(keyed$only_oracle) == 0L && length(keyed$only_r) == 0L
    ok <- isTRUE(cmp$verdict %in% c("identical", "within_tolerance")) && rows_complete
    data.frame(variable = v, verdict = if (ok) "match" else "mismatch", stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

full_summary <- function(df) {
  sprintf("parity_full: %d of %d columns mismatch", sum(df$verdict == "mismatch"), nrow(df))
}
