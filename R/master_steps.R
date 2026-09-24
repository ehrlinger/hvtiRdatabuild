# master_steps.R
#
# The build steps for a master: is a candidate key unique in a parquet
# snapshot; the DDL for it, with SQL Server's row and column limits preflighted;
# loading it a row group at a time; and parity between the snapshot and the
# loaded table.

#' Is a candidate key unique in a parquet snapshot?
#'
#' Reads only the key columns and reports counts and a verdict, never a key
#' value.
#'
#' @param parquet Character. Path to the parquet snapshot.
#' @param key Character. The candidate key columns.
#' @param nonnull_only Logical. When `TRUE`, uniqueness is judged only among
#'   rows with no missing key part.
#'
#' @return A list with `key` (the key label), `n_rows`, `n_null_key`,
#'   `n_duplicates` and `verdict` (`"unique"`, `"not unique"` or `"absent"`).
#'
#' @keywords internal
#' @noRd
key_verdict <- function(parquet, key, nonnull_only = FALSE) {
  label <- paste(key, collapse = " + ")
  present <- names(arrow::ParquetFileReader$create(parquet)$GetSchema())
  if (!all(key %in% present)) {
    return(list(key = label, n_rows = NA_integer_, n_null_key = NA_integer_,
                n_duplicates = NA_integer_, verdict = "absent"))
  }
  k <- as.data.frame(arrow::read_parquet(parquet,
                                         col_select = tidyselect::all_of(key)))
  has_null <- !stats::complete.cases(k)
  n_null <- sum(has_null)
  if (nonnull_only) k <- k[!has_null, , drop = FALSE]
  n_dup <- sum(duplicated(k))
  unique_ok <- n_dup == 0L && (nonnull_only || n_null == 0L)
  list(key = label, n_rows = nrow(k), n_null_key = n_null,
       n_duplicates = n_dup, verdict = if (unique_ok) "unique" else "not unique")
}

#' Format a key verdict for a report, without ever printing a key value
#'
#' @param v A list as returned by `key_verdict()`.
#'
#' @return A length-one character summary line.
#'
#' @keywords internal
#' @noRd
format_key_verdict <- function(v) {
  sprintf("key %-32s %-10s rows %s, null key parts %s, duplicates %s",
          v$key, v$verdict, v$n_rows, v$n_null_key, v$n_duplicates)
}

#' The SQL Server type for an arrow type
#'
#' @param arrow_type Character. An arrow type's `ToString()` form.
#' @param max_nchar Integer. The widest observed character count, for a
#'   character arrow type; ignored otherwise.
#'
#' @return A list with `sql` (the SQL Server type string), `bytes` (its
#'   fixed-width row contribution) and `variable` (whether it is
#'   variable-width).
#'
#' @keywords internal
#' @noRd
mssql_type <- function(arrow_type, max_nchar = NA_integer_) {
  fixed <- function(sql, bytes) list(sql = sql, bytes = bytes, variable = FALSE)
  if (arrow_type == "double") return(fixed("float", 8L))
  if (arrow_type == "int32") return(fixed("int", 4L))
  if (arrow_type == "bool") return(fixed("bit", 1L))
  if (startsWith(arrow_type, "date32")) return(fixed("date", 3L))
  if (startsWith(arrow_type, "timestamp")) {
    return(fixed("datetime2", 8L))
  }
  if (startsWith(arrow_type, "time")) return(fixed("time", 5L))
  if (arrow_type %in% c("string", "large_string", "utf8")) {
    n <- if (is.na(max_nchar)) 1L else max(1L, as.integer(max_nchar))
    sql <- if (n > 4000L) "nvarchar(max)" else sprintf("nvarchar(%d)", n)
    return(list(sql = sql, bytes = 0L, variable = TRUE))
  }
  stop("No SQL Server type for arrow type '", arrow_type, "'.", call. = FALSE)
}

#' Preflight a table's row size and column count against SQL Server's limits
#'
#' In-row size: 4-byte header, fixed-width data, 2-byte column count, the
#' null bitmap, and 2 bytes per variable-width column plus 2 for their count.
#' Variable-width data can overflow off-row, so only its offsets count here.
#'
#' @param types A list of type descriptors as returned by `mssql_type()`.
#' @param max_row Integer. SQL Server's in-row byte limit.
#' @param max_cols Integer. SQL Server's column-count limit.
#'
#' @return A list with `ok`, `row_bytes` and a `message`.
#'
#' @keywords internal
#' @noRd
ddl_preflight <- function(types, max_row = 8060L, max_cols = 1024L) {
  n <- length(types)
  fixed <- sum(vapply(types, `[[`, integer(1), "bytes"))
  n_var <- sum(vapply(types, `[[`, logical(1), "variable"))
  row_bytes <- 4L + fixed + 2L + ceiling(n / 8) +
    if (n_var) 2L + 2L * n_var else 0L
  if (n > max_cols) {
    return(list(ok = FALSE, row_bytes = row_bytes,
                message = sprintf(
                  "%d columns exceed SQL Server's limit of %d.",
                  n, max_cols
                )))
  }
  if (row_bytes > max_row) {
    return(list(
      ok = FALSE, row_bytes = row_bytes,
      message = sprintf(
        paste0("The fixed-width row is %d bytes, over ",
               "SQL Server's %d. Split the table in two ",
               "and join the halves in the view."),
        row_bytes, max_row
      )
    ))
  }
  list(ok = TRUE, row_bytes = row_bytes, message = "ok")
}

#' The `CREATE TABLE` DDL for a parquet snapshot
#'
#' Arrow schema of a parquet snapshot to SQL Server DDL, with a preflight
#' against SQL Server's 8,060-byte in-row limit and its 1,024-column limit.
#' Character widths are measured from the data, one column at a time.
#'
#' @param parquet Character. Path to the parquet snapshot.
#' @param table Character. The target table's name.
#' @param schema_name Character, or `NULL`. The target schema's name; `NULL`
#'   leaves the table unqualified, so it lands in the connection's default
#'   schema.
#'
#' @return A list with `sql` (the `CREATE TABLE` statement), `types` (a named
#'   character vector of SQL types), `row_bytes` and `n_cols`.
#'
#' @keywords internal
#' @noRd
master_ddl <- function(parquet, table, schema_name = "dbo") {
  sch <- arrow::ParquetFileReader$create(parquet)$GetSchema()
  cols <- names(sch)
  arrow_types <- vapply(cols, function(v) sch[[v]]$type$ToString(),
                        character(1))
  types <- lapply(cols, function(v) {
    at <- arrow_types[[v]]
    if (!at %in% c("string", "large_string", "utf8")) {
      return(mssql_type(at))
    }
    x <- arrow::read_parquet(parquet, col_select = tidyselect::all_of(v))[[1]]
    observed <- if (all(is.na(x))) NA_integer_ else max(nchar(x, type = "chars"), na.rm = TRUE)
    fmt <- attr(x, "format.sas", exact = TRUE)
    declared <- if (!is.null(fmt) && length(fmt) == 1L && !is.na(fmt) &&
                      grepl("^\\$(\\d+)\\.?$", fmt)) {
      as.integer(sub("^\\$(\\d+)\\.?$", "\\1", fmt))
    } else {
      NA_integer_
    }
    # Width is the wider of the observed data and the SAS-declared width; with
    # neither available (all-missing, no format) fall back to 255.
    candidates <- c(observed, declared)
    candidates <- candidates[!is.na(candidates)]
    width <- if (length(candidates)) max(candidates) else 255L
    mssql_type(at, width)
  })
  pre <- ddl_preflight(types)
  if (!pre$ok) stop(pre$message, call. = FALSE)
  q <- function(x) paste0("[", gsub("]", "]]", x, fixed = TRUE), "]")
  sql_types <- vapply(types, `[[`, character(1), "sql")
  body <- paste(sprintf("  %s %s NULL", q(cols), sql_types), collapse = ",\n")
  table_ref <- if (is.null(schema_name)) q(table) else paste0(q(schema_name), ".", q(table))
  list(sql = sprintf("CREATE TABLE %s (\n%s\n);", table_ref, body),
       types = stats::setNames(sql_types, cols),
       row_bytes = pre$row_bytes, n_cols = length(cols))
}

#' Load a parquet snapshot into an existing table, one row group at a time
#'
#' Each group and its log row commit in one transaction, so a failure resumes
#' from the last committed group rather than restarting.
#'
#' @param con A DBI connection.
#' @param parquet Character. Path to the parquet snapshot.
#' @param table Character. The target table's name.
#' @param log_table Character. The name of the load log table.
#'
#' @return A list with `row_groups`, `loaded` and `skipped` counts.
#'
#' @keywords internal
#' @noRd
load_parquet <- function(con, parquet, table, log_table = paste0(table, "__load_log")) {
  if (!DBI::dbExistsTable(con, table)) {
    stop("Target table does not exist: ", table, ". Run the DDL first.", call. = FALSE)
  }
  if (!DBI::dbExistsTable(con, log_table)) {
    n_existing <- DBI::dbGetQuery(con, paste("SELECT COUNT(*) AS n FROM",
                                             DBI::dbQuoteIdentifier(con, table)))$n
    if (as.numeric(n_existing) > 0) {
      stop("Target table ", table, " has rows but no load log; drop it or ",
           "reconcile it before loading.", call. = FALSE)
    }
    DBI::dbCreateTable(con, log_table,
                       data.frame(row_group = integer(), n_rows = integer(),
                                  loaded_at = character()))
  }
  done <- DBI::dbGetQuery(con, paste("SELECT row_group FROM",
                                     DBI::dbQuoteIdentifier(con, log_table)))$row_group

  reader <- arrow::ParquetFileReader$create(parquet)
  n_groups <- reader$num_row_groups
  loaded <- 0L
  skipped <- 0L
  for (g in seq_len(n_groups) - 1L) {
    if (g %in% done) {
      skipped <- skipped + 1L
      next
    }
    d <- as.data.frame(reader$ReadRowGroup(g))
    # SQL Server has no labels or formats; the sidecar carries them instead.
    d <- haven::zap_widths(haven::zap_formats(haven::zap_labels(haven::zap_label(d))))
    DBI::dbWithTransaction(con, {
      DBI::dbAppendTable(con, table, d)
      DBI::dbAppendTable(con, log_table, data.frame(
        row_group = g, n_rows = nrow(d),
        loaded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
      ))
    })
    loaded <- loaded + 1L
  }
  list(row_groups = n_groups, loaded = loaded, skipped = skipped)
}

#' The SQL for one column's parity aggregates
#'
#' SQL Server's default collation ignores case and trailing spaces in
#' `DISTINCT`; hashing compares the stored characters exactly, as R does.
#'
#' @param table Character. The table's name.
#' @param column Character. The column's name.
#' @param is_numeric Logical. Whether the column is numeric.
#' @param is_character Logical. Whether the column is character.
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#'
#' @return A length-one character: a `SELECT` statement.
#'
#' @keywords internal
#' @noRd
parity_sql <- function(table, column, is_numeric, is_character, dialect) {
  q <- quoter(dialect)
  col <- q(column)
  distinct_expr <- if (is_character && dialect == "mssql") {
    sprintf("HASHBYTES('SHA2_256', %s)", col)
  } else {
    col
  }
  total <- if (is_numeric) sprintf(", SUM(CAST(%s AS DOUBLE PRECISION)) AS total", col) else ""
  sprintf("SELECT COUNT(%s) AS n_nonnull, COUNT(DISTINCT %s) AS n_distinct%s FROM %s",
          col, distinct_expr, total, q(table))
}

#' Strip `haven` labels, formats and widths from a data frame
#'
#' @param d A data frame, possibly with `haven`-labelled columns.
#'
#' @return `d` with every column's `haven` label, format and width dropped.
#'
#' @keywords internal
#' @noRd
.zap_all <- function(d) {
  haven::zap_widths(haven::zap_formats(haven::zap_labels(haven::zap_label(d))))
}

#' The ON clause for a key join, collation-aware for `mssql` character keys
#'
#' @param q A quoting function from `quoter()`.
#' @param key Character. The key columns.
#' @param types A named character vector of the key columns' SQL types, as
#'   from `table_types()`.
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#'
#' @return A length-one character: the join's `ON` predicate.
#'
#' @keywords internal
#' @noRd
.parity_join_on <- function(q, key, types, dialect) {
  paste(vapply(key, function(k) {
    .string_eq_sql(paste0("t.", q(k)), paste0("s.", q(k)), types[[k]], dialect)
  }, character(1)), collapse = " AND ")
}

#' Is the loaded table the parquet snapshot?
#'
#' Row count; per column, non-null count, distinct count and numeric sum on
#' both sides; and a full value compare on a random sample of rows joined on
#' the key. Aggregates alone pass with compensating errors: a sum cannot see
#' two cells swap. Verdicts only.
#'
#' @param con A DBI connection.
#' @param table Character. The loaded table's name.
#' @param parquet Character. Path to the parquet snapshot.
#' @param key Character. The base key columns.
#' @param sample_n Integer. The number of rows to sample for the full compare.
#' @param seed Integer. The sampling seed.
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#'
#' @return A list with `verdict` (`"pass"` or `"fail"`), `row_count`,
#'   `columns` and `sample` (data frames of per-column verdicts).
#'
#' @keywords internal
#' @noRd
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
  key_types <- table_types(con, table)[key]
  on <- .parity_join_on(q, key, key_types, dialect)
  db_rows <- DBI::dbGetQuery(con, sprintf("SELECT t.* FROM %s t JOIN %s s ON %s",
                                          q(table), q(tmp), on))
  pq_rows <- .zap_all(as.data.frame(dplyr::collect(
    dplyr::semi_join(arrow::open_dataset(parquet), picked, by = key)
  )))

  make_id <- function(d) do.call(paste, c(lapply(d[key], as.character), sep = "\r"))
  pq_rows$.parity_key <- make_id(pq_rows)
  db_rows$.parity_key <- make_id(db_rows)
  cmp <- compare_built(pq_rows, db_rows, id = ".parity_key")
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

#' Format a `parity_check()` result for a report
#'
#' @param res A list as returned by `parity_check()`.
#'
#' @return A length-one character summary line.
#'
#' @keywords internal
#' @noRd
parity_summary <- function(res) {
  sprintf("parity %s: row count %s; %d of %d columns mismatch; %d of %d sampled columns mismatch",
          res$verdict, res$row_count,
          sum(res$columns$verdict == "mismatch"), nrow(res$columns),
          sum(res$sample$verdict == "mismatch"), nrow(res$sample))
}

#' The full parity gate: every non-key column, every row
#'
#' `parity_check()` is aggregates plus a sample, which a compensating swap of
#' two cells can pass; this cannot, because every row is in the comparison.
#'
#' @param con A DBI connection.
#' @param table Character. The loaded table's name.
#' @param parquet Character. Path to the parquet snapshot.
#' @param key Character. The base key columns.
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#'
#' @return A data frame of `variable`, `verdict` (`"match"` or `"mismatch"`).
#'
#' @keywords internal
#' @noRd
parity_full <- function(con, table, parquet, key, dialect = "mssql") {
  q <- quoter(dialect)
  reader <- arrow::ParquetFileReader$create(parquet)
  cols <- setdiff(names(reader$GetSchema()), key)
  make_id <- function(d) do.call(paste, c(lapply(d[key], as.character), sep = "\r"))
  rows <- lapply(cols, function(v) {
    pq <- .zap_all(as.data.frame(
      arrow::read_parquet(parquet, col_select = tidyselect::all_of(c(key, v)))
    ))
    db <- DBI::dbGetQuery(con, sprintf("SELECT %s FROM %s",
                                       paste(q(c(key, v)), collapse = ", "), q(table)))
    pq_v <- data.frame(.parity_key = make_id(pq), value = pq[[v]], stringsAsFactors = FALSE)
    db_v <- data.frame(.parity_key = make_id(db), value = db[[v]], stringsAsFactors = FALSE)
    cmp <- compare_built(pq_v, db_v, id = ".parity_key")
    keyed <- attr(cmp, "rows")
    rows_complete <- length(keyed$only_oracle) == 0L && length(keyed$only_r) == 0L
    ok <- isTRUE(cmp$verdict %in% c("identical", "within_tolerance")) && rows_complete
    data.frame(variable = v, verdict = if (ok) "match" else "mismatch", stringsAsFactors = FALSE)
  })
  pq_keys <- as.data.frame(arrow::read_parquet(parquet, col_select = tidyselect::all_of(key)))
  db_keys <- DBI::dbGetQuery(con, sprintf("SELECT %s FROM %s",
                                          paste(q(key), collapse = ", "), q(table)))
  keys_match <- identical(sort(make_id(pq_keys)), sort(make_id(db_keys)))
  key_row <- data.frame(variable = paste(key, collapse = "+"),
                        verdict = if (keys_match) "match" else "mismatch",
                        stringsAsFactors = FALSE)
  do.call(rbind, c(rows, list(key_row)))
}

#' Format a `parity_full()` result for a report
#'
#' @param df A data frame as returned by `parity_full()`.
#'
#' @return A length-one character summary line.
#'
#' @keywords internal
#' @noRd
full_summary <- function(df) {
  sprintf("parity_full: %d of %d columns mismatch", sum(df$verdict == "mismatch"), nrow(df))
}
