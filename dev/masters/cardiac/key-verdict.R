# key-verdict.R
#
# Is a candidate key unique in a parquet snapshot? Reads only the key columns and
# reports counts and a verdict, never a key value.

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

format_key_verdict <- function(v) {
  sprintf("key %-32s %-10s rows %s, null key parts %s, duplicates %s",
          v$key, v$verdict, v$n_rows, v$n_null_key, v$n_duplicates)
}
