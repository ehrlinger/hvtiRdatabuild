# sql_dialect.R
#
# Quoting and dialect details shared by the parity check and the corrections
# SQL. Only two dialects exist: SQL Server in production, duckdb in the tests.

#' An identifier quoter for a SQL dialect
#'
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#'
#' @return A function of one argument that quotes an identifier for `dialect`.
#'
#' @keywords internal
#' @noRd
quoter <- function(dialect) {
  switch(dialect,
         mssql = function(x) paste0("[", gsub("]", "]]", x, fixed = TRUE), "]"),
         duckdb = function(x) paste0("\"", gsub("\"", "\"\"", x, fixed = TRUE), "\""),
         stop("Unknown dialect '", dialect, "'.", call. = FALSE))
}

#' Quote a string literal for SQL
#'
#' @param x Character. The value to quote.
#'
#' @return A length-one character: `x` wrapped in single quotes, with an
#'   embedded quote doubled.
#'
#' @keywords internal
#' @noRd
sql_string <- function(x) paste0("'", gsub("'", "''", x, fixed = TRUE), "'")

#' The column types used by the corrections tables, per dialect
#'
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#'
#' @return A named list with `text`, `id`, `ts` and `flag` type strings.
#'
#' @keywords internal
#' @noRd
sql_types <- function(dialect) {
  switch(dialect,
         mssql = list(text = "nvarchar(4000)", id = "nvarchar(128)",
                      ts = "datetime2", flag = "tinyint"),
         duckdb = list(text = "VARCHAR", id = "VARCHAR", ts = "TIMESTAMP",
                       flag = "TINYINT"),
         stop("Unknown dialect '", dialect, "'.", call. = FALSE))
}

#' The `CREATE VIEW` header for a dialect
#'
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#'
#' @return A length-one character: the dialect's `CREATE ... VIEW` clause.
#'
#' @keywords internal
#' @noRd
view_header <- function(dialect) {
  switch(dialect,
         mssql = "CREATE OR ALTER VIEW",
         duckdb = "CREATE OR REPLACE VIEW",
         stop("Unknown dialect '", dialect, "'.", call. = FALSE))
}

#' A timestamp literal for an as-of filter
#'
#' Rendered in UTC through the dialect's own timestamp type so duckdb and SQL
#' Server parse it the same way.
#'
#' @param ts A `POSIXct` timestamp.
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#'
#' @return A length-one character: a `CAST(...)` SQL literal for `ts`.
#'
#' @keywords internal
#' @noRd
sql_timestamp_literal <- function(ts, dialect) {
  sprintf("CAST('%s' AS %s)", format(ts, "%Y-%m-%d %H:%M:%OS6", tz = "UTC"),
          sql_types(dialect)$ts)
}

#' Run a warehouse step, withholding the driver's own error message
#'
#' A write/DDL/view/load/record step's own error can quote a data value, and
#' PHI must never reach the console or a transcript. Rerun the step
#' interactively to see it.
#'
#' @param name Character. A label for the step, used in the rethrown message.
#' @param expr An expression to evaluate.
#'
#' @return The value of `expr`, or an error naming the step and its class.
#'
#' @keywords internal
#' @noRd
run_step <- function(name, expr) {
  tryCatch(expr, error = function(e) {
    stop("Step '", name, "' failed (", class(e)[[1]],
         "). The driver's message is withheld because ",
         "it can contain a data value; rerun the step ",
         "interactively to see it.", call. = FALSE)
  })
}

#' SQL Server column types of a table, as they would be written in a `CAST`
#'
#' @param con A DBI connection.
#' @param table Character. The table name.
#'
#' @return A named character vector of type strings, named by column.
#'
#' @keywords internal
#' @noRd
table_types <- function(con, table) {
  cols <- DBI::dbGetQuery(con, paste(
                                     "SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH",
                                     "FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = ?",
                                     "ORDER BY ORDINAL_POSITION"), params = list(table))
  names(cols) <- toupper(names(cols))
  len <- cols$CHARACTER_MAXIMUM_LENGTH
  type <- ifelse(is.na(len), cols$DATA_TYPE,
                 sprintf("%s(%s)", cols$DATA_TYPE, ifelse(len == -1, "max", len)))
  stats::setNames(type, cols$COLUMN_NAME)
}
