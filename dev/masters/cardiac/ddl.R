# ddl.R
#
# Arrow schema of a parquet snapshot to SQL Server DDL, with a preflight against
# SQL Server's 8,060-byte in-row limit and its 1,024-column limit. Character
# widths are measured from the data, one column at a time.

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

# In-row size: 4-byte header, fixed-width data, 2-byte column count, the null
# bitmap, and 2 bytes per variable-width column plus 2 for their count.
# Variable-width data can overflow off-row, so only its offsets count here.
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
                  n, max_cols)))
  }
  if (row_bytes > max_row) {
    return(list(
      ok = FALSE, row_bytes = row_bytes,
      message = sprintf(
        paste0("The fixed-width row is %d bytes, over ",
               "SQL Server's %d. Split the table in two ",
               "and join the halves in the view."),
        row_bytes, max_row)))
  }
  list(ok = TRUE, row_bytes = row_bytes, message = "ok")
}

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
    width <- if (all(is.na(x))) {
      NA_integer_
    } else {
      max(nchar(x, type = "chars"), na.rm = TRUE)
    }
    mssql_type(at, width)
  })
  pre <- ddl_preflight(types)
  if (!pre$ok) stop(pre$message, call. = FALSE)
  q <- function(x) paste0("[", gsub("]", "]]", x, fixed = TRUE), "]")
  sql_types <- vapply(types, `[[`, character(1), "sql")
  body <- paste(sprintf("  %s %s NULL", q(cols), sql_types), collapse = ",\n")
  list(sql = sprintf("CREATE TABLE %s.%s (\n%s\n);",
                     q(schema_name), q(table), body),
       types = stats::setNames(sql_types, cols),
       row_bytes = pre$row_bytes, n_cols = length(cols))
}
