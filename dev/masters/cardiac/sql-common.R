# sql-common.R
#
# Quoting and dialect details shared by the parity check and the corrections
# SQL. Only two dialects exist: SQL Server in production, duckdb in the tests.

quoter <- function(dialect) {
  switch(dialect,
         mssql  = function(x) paste0("[", gsub("]", "]]", x, fixed = TRUE), "]"),
         duckdb = function(x) paste0("\"", gsub("\"", "\"\"", x, fixed = TRUE), "\""),
         stop("Unknown dialect '", dialect, "'.", call. = FALSE))
}

sql_string <- function(x) paste0("'", gsub("'", "''", x, fixed = TRUE), "'")

sql_types <- function(dialect) {
  switch(dialect,
         mssql  = list(text = "nvarchar(4000)", id = "nvarchar(128)",
                       ts = "datetime2", flag = "tinyint"),
         duckdb = list(text = "VARCHAR", id = "VARCHAR", ts = "TIMESTAMP",
                       flag = "TINYINT"),
         stop("Unknown dialect '", dialect, "'.", call. = FALSE))
}

view_header <- function(dialect) {
  switch(dialect,
         mssql  = "CREATE OR ALTER VIEW",
         duckdb = "CREATE OR REPLACE VIEW",
         stop("Unknown dialect '", dialect, "'.", call. = FALSE))
}

# SQL Server column types of a table, as they would be written in a CAST.
table_types <- function(con, table) {
  cols <- DBI::dbGetQuery(con, paste(
    "SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH",
    "FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = ?",
    "ORDER BY ORDINAL_POSITION"), params = list(table))
  len <- cols$CHARACTER_MAXIMUM_LENGTH
  type <- ifelse(is.na(len), cols$DATA_TYPE,
                 sprintf("%s(%s)", cols$DATA_TYPE, ifelse(len == -1, "max", len)))
  stats::setNames(type, cols$COLUMN_NAME)
}
