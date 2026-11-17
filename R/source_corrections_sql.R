# source_corrections_sql.R
#
# Corrections to warehouse source views (spec §3): per-source append-only tables, an R
# reference for the resolution rules, and the generated views that implement the same
# rules. Nothing here prints a key or a value.

#' Object names for one source's corrections
#'
#' @param source Character. The source view's name.
#'
#' @return A list of table and view names.
#'
#' @keywords internal
#' @noRd
.source_tables <- function(source) {
  list(corrections = paste0(source, "_corrections"),
       decisions   = paste0(source, "_correction_decisions"),
       corrected   = paste0(source, "_corrected"),
       applied     = paste0(source, "_corrections_applied"),
       stale       = paste0(source, "_corrections_stale"),
       conflicts   = paste0(source, "_corrections_conflicts"))
}

# Statuses an accepted correction can take, besides "apply" (spec §3.3, G1, G7).
SOURCE_STALE <- c("no_variable", "no_record", "ambiguous_record", "prior_unknown", # nolint
                  "does_not_cast", "prior_mismatch", "filled_upstream_agrees")
SOURCE_CONFLICT <- c("accepted_disagree", "filled_upstream_disagrees") # nolint

#' DDL for one source's corrections and decisions tables
#'
#' @param source Character. The source view's name.
#' @param key_types A named character vector of the source's key columns' SQL types.
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#'
#' @return A named character vector (`corrections`, `decisions`) of `CREATE TABLE`
#'   statements.
#'
#' @keywords internal
#' @noRd
source_corrections_ddl <- function(source, key_types, dialect = "mssql") {
  q <- quoter(dialect)
  ty <- sql_types(dialect)
  tabs <- .source_tables(source)
  col <- function(name, type, null = TRUE) {
    sprintf("  %s %s %s", q(name), type, if (null) "NULL" else "NOT NULL")
  }
  key_cols <- unname(mapply(col, names(key_types), key_types, MoreArgs = list(null = FALSE)))
  corr <- c(col("correction_id", ty$id, FALSE), col("source", ty$id, FALSE), key_cols,
            col("variable", ty$id, FALSE),
            col("expected_prior", ty$text), col("expected_prior_missing", ty$flag),
            col("new_value", ty$text), col("new_value_missing", ty$flag, FALSE),
            col("evidence_type", ty$id, FALSE), col("evidence_ref", ty$text, FALSE),
            col("asserted_by", ty$id, FALSE), col("asserted_on", ty$ts, FALSE),
            sprintf("  PRIMARY KEY (%s)", q("correction_id")))
  dec <- c(col("decision_id", ty$id, FALSE), col("correction_id", ty$id, FALSE),
           col("decision", ty$id, FALSE), col("decided_by", ty$id, FALSE),
           col("decided_on", ty$ts, FALSE), col("reason", ty$text),
           sprintf("  PRIMARY KEY (%s)", q("decision_id")))
  c(corrections = sprintf("CREATE TABLE %s (\n%s\n)", q(tabs$corrections),
                          paste(corr, collapse = ",\n")),
    decisions   = sprintf("CREATE TABLE %s (\n%s\n)", q(tabs$decisions),
                          paste(dec, collapse = ",\n")))
}

#' Resolve one source's corrections in R
#'
#' The reference for the generated views. A correction counts when its latest decision
#' (by `decided_on`, then `decision_id`) is `"accept"`. Each accepted correction then takes
#' the first status that holds, in this order:
#'
#' 1. `no_variable`: its variable is not a non-key column.
#' 2. `no_record`: its key matches no row.
#' 3. `ambiguous_record`: its key matches several rows, so it changes none.
#' 4. `accepted_disagree`: accepted corrections to its cell disagree on the new value (G1).
#' 5. `prior_unknown`.
#' 6. `does_not_cast`.
#' 7. `filled_upstream_agrees` or `filled_upstream_disagrees`: it filled a missing value,
#'    and the source now holds one (G7).
#' 8. `prior_mismatch`.
#' 9. Otherwise, `apply`.
#'
#' @param base A data frame of the source's rows.
#' @param corrections A data frame of the corrections table's rows.
#' @param decisions A data frame of the decisions table's rows.
#' @param key Character. The source's key columns.
#'
#' @return A list: `data`, `applied`, `stale` and `conflicts`.
#'
#' @keywords internal
#' @noRd
resolve_source_corrections <- function(base, corrections, decisions, key) {
  dec <- decisions[order(decisions$correction_id, -xtfrm(decisions$decided_on),
                         -xtfrm(decisions$decision_id)), , drop = FALSE]
  latest <- dec[!duplicated(dec$correction_id), , drop = FALSE]
  acc <- corrections[corrections$correction_id %in%
                       latest$correction_id[latest$decision == "accept"], , drop = FALSE]
  cell_of <- function(d, cols) do.call(paste, c(lapply(d[cols], as.character), sep = "\r"))
  acc_cell <- cell_of(acc, c(key, "variable"))
  marker <- ifelse(acc$new_value_missing == 1L, "\001missing", acc$new_value)
  n_values <- tapply(marker, acc_cell, function(v) length(unique(v)))
  valid <- setdiff(names(base), key)
  base_id <- cell_of(base, key)
  row_of <- match(cell_of(acc, key), base_id)
  # A key that now matches several rows changes none of them (the source lost uniqueness).
  n_rows <- as.integer(table(base_id)[cell_of(acc, key)])
  status <- character(nrow(acc))
  for (i in seq_len(nrow(acc))) {
    a <- acc[i, ]
    v <- a$variable
    status[[i]] <- if (!v %in% valid) {
      "no_variable"
    } else if (is.na(row_of[[i]])) {
      "no_record"
    } else if (n_rows[[i]] > 1L) {
      "ambiguous_record"
    } else if (n_values[[acc_cell[[i]]]] > 1L) {
      "accepted_disagree"
    } else if (is.na(a$expected_prior_missing)) {
      "prior_unknown"
    } else {
      cls <- class(base[[v]])[[1]]
      cur <- base[[v]][[row_of[[i]]]]
      prior <- if (a$expected_prior_missing == 1L) NA else parse_value(a$expected_prior, cls)
      new <- if (a$new_value_missing == 1L) NA else parse_value(a$new_value, cls)
      if ((a$expected_prior_missing == 0L && is.na(prior)) ||
            (a$new_value_missing == 0L && is.na(new))) {
        "does_not_cast"
      } else if (a$expected_prior_missing == 1L && !is.na(cur)) {
        if (a$new_value_missing == 0L && isTRUE(cur == new)) {
          "filled_upstream_agrees"
        } else {
          "filled_upstream_disagrees"
        }
      } else if (a$expected_prior_missing == 0L && (is.na(cur) || !isTRUE(cur == prior))) {
        "prior_mismatch"
      } else {
        "apply"
      }
    }
  }
  data <- base
  for (i in which(status == "apply")) {
    v <- acc$variable[[i]]
    data[[v]][[row_of[[i]]]] <- if (acc$new_value_missing[[i]] == 1L) {
      NA
    } else {
      parse_value(acc$new_value[[i]], class(base[[v]])[[1]])
    }
  }
  pick <- function(keep, cols) {
    out <- acc[keep, c("correction_id", key, "variable"), drop = FALSE]
    out$reason <- status[keep]
    rownames(out) <- NULL
    out[cols]
  }
  list(data = data,
       applied = pick(status == "apply", c("correction_id", key)),
       stale = pick(status %in% SOURCE_STALE, c("correction_id", "variable", "reason")),
       conflicts = pick(status %in% SOURCE_CONFLICT,
                        c("correction_id", "variable", "reason")))
}
