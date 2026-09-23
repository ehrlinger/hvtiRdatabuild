# load.R
#
# Load a parquet snapshot into an existing table one row group at a time. Each
# group and its log row commit in one transaction, so a failure resumes from the
# last committed group rather than restarting.

load_parquet <- function(con, parquet, table, log_table = paste0(table, "__load_log")) {
  if (!DBI::dbExistsTable(con, table)) {
    stop("Target table does not exist: ", table, ". Run the DDL first.", call. = FALSE)
  }
  if (!DBI::dbExistsTable(con, log_table)) {
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
        loaded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")))
    })
    loaded <- loaded + 1L
  }
  list(row_groups = n_groups, loaded = loaded, skipped = skipped)
}
