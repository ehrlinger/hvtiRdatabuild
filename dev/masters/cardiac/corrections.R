# corrections.R
#
# The corrections contract (spec §5): two append-only tables, an R reference
# resolver, and the generated SQL that implements the same rules as a view. The
# SQL uses CTEs, CASE, JOIN, LEFT JOIN, UNION ALL and ROW_NUMBER() only, so the
# duckdb test proves the logic SQL Server will run.

corrections_ddl <- function(corrections_table, decisions_table, key_types,
                            alt_key_types = NULL, dialect = "mssql") {
  q <- quoter(dialect)
  ty <- sql_types(dialect)
  col <- function(name, type, null = TRUE) {
    sprintf("  %s %s %s", q(name), type, if (null) "NULL" else "NOT NULL")
  }
  key_cols <- unname(mapply(col, names(key_types), key_types, MoreArgs = list(null = FALSE)))
  alt_cols <- if (length(alt_key_types)) {
    unname(mapply(col, names(alt_key_types), alt_key_types))
  } else {
    character()
  }
  corr <- c(col("correction_id", ty$id, FALSE), col("master", ty$id, FALSE),
            key_cols, alt_cols,
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
  c(corrections = sprintf("CREATE TABLE %s (\n%s\n);", q(corrections_table),
                          paste(corr, collapse = ",\n")),
    decisions   = sprintf("CREATE TABLE %s (\n%s\n);", q(decisions_table),
                          paste(dec, collapse = ",\n")))
}

# The R reference. Rules, in order: a correction's latest decision (by
# decided_on, then decision_id) must be 'accept'; among accepted corrections to
# one cell the latest (by asserted_on, then correction_id) wins; the winner is
# stale if its variable is not a correctable column, its key matches no row, its
# prior is unknown, or the base no longer holds its prior. Otherwise it applies.
resolve_corrections <- function(base, corrections, decisions, key, master) {
  dec <- decisions[order(decisions$correction_id, -xtfrm(decisions$decided_on),
                         -xtfrm(decisions$decision_id)), ]
  latest <- dec[!duplicated(dec$correction_id), ]
  accepted <- latest$correction_id[latest$decision == "accept"]
  acc <- corrections[corrections$master == master &
                       corrections$correction_id %in% accepted, ]
  acc <- acc[order(-xtfrm(acc$asserted_on), -xtfrm(acc$correction_id)), ]
  cell <- function(d, cols) do.call(paste, c(lapply(d[cols], as.character), sep = "\r"))
  winners <- acc[!duplicated(cell(acc, c(key, "variable"))), ]

  out <- base
  valid <- setdiff(names(base), key)
  base_id <- cell(base, key)
  stale <- list()
  for (i in seq_len(nrow(winners))) {
    w <- winners[i, ]
    row <- match(cell(w, key), base_id)
    reason <- if (!w$variable %in% valid) {
      "no_variable"
    } else if (is.na(row)) {
      "no_record"
    } else if (is.na(w$expected_prior_missing)) {
      "prior_unknown"
    } else {
      cls <- class(base[[w$variable]])[[1]]
      cur <- base[[w$variable]][row]
      prior_ok <- if (w$expected_prior_missing == 1L) {
        is.na(cur)
      } else {
        !is.na(cur) && isTRUE(cur == parse_value(w$expected_prior, cls))
      }
      if (prior_ok) {
        out[[w$variable]][row] <- if (w$new_value_missing == 1L) NA else
          parse_value(w$new_value, cls)
        NULL
      } else {
        "prior_mismatch"
      }
    }
    if (!is.null(reason)) {
      stale[[length(stale) + 1L]] <- data.frame(correction_id = w$correction_id,
                                                variable = w$variable, reason = reason,
                                                stringsAsFactors = FALSE)
    }
  }
  stale <- if (length(stale)) do.call(rbind, stale) else
    data.frame(correction_id = character(), variable = character(), reason = character())
  list(data = out, stale = stale)
}

# SQL Server's default collation compares strings case- and trailing-space-
# insensitively; a binary collation with an explicit length check compares the
# stored characters exactly, as R and the other dialects do.
.string_eq_sql <- function(a, b, type, dialect) {
  is_string <- dialect == "mssql" && grepl("^n?(var)?char\\b", type, ignore.case = TRUE)
  if (is_string) {
    sprintf(paste0("(%1$s COLLATE Latin1_General_BIN2 = %2$s COLLATE Latin1_General_BIN2 ",
                   "AND DATALENGTH(%1$s) = DATALENGTH(%2$s))"), a, b)
  } else {
    sprintf("%s = %s", a, b)
  }
}

.winners_cte <- function(q, corrections_table, decisions_table, master, key) {
  paste0(
    "WITH latest AS (\n",
    "  SELECT correction_id, decision,\n",
    "         ROW_NUMBER() OVER (PARTITION BY correction_id\n",
    "                            ORDER BY decided_on DESC, decision_id DESC) AS rn\n",
    "  FROM ", q(decisions_table), "\n",
    "), accepted AS (\n",
    "  SELECT c.* FROM ", q(corrections_table), " c\n",
    "  JOIN latest l ON l.correction_id = c.correction_id\n",
    "  WHERE l.rn = 1 AND l.decision = 'accept' AND c.master = ", sql_string(master), "\n",
    "), ranked AS (\n",
    "  SELECT a.*, ROW_NUMBER() OVER (PARTITION BY ",
    paste0("a.", q(key), collapse = ", "), ", a.variable\n",
    "                     ORDER BY a.asserted_on DESC, a.correction_id DESC) AS rn\n",
    "  FROM accepted a\n",
    "), w AS (\n",
    "  SELECT * FROM ranked WHERE rn = 1\n",
    ")\n")
}

# Only variables in `corrected` get a join and a CASE; the rest pass through.
# Regenerate the view when a variable receives its first correction.
corrections_view_sql <- function(view, base_table, corrections_table, decisions_table,
                                 master, key, columns, corrected, types,
                                 dialect = "mssql") {
  q <- quoter(dialect)
  corrected <- intersect(corrected, setdiff(columns, key))
  stopifnot(all(key %in% columns), all(corrected %in% names(types)))
  alias <- stats::setNames(sprintf("c%d", seq_along(corrected)), corrected)
  select <- vapply(columns, function(v) {
    b <- paste0("b.", q(v))
    if (!v %in% corrected) return(b)
    a <- alias[[v]]
    prior_eq <- .string_eq_sql(b, sprintf("CAST(%s.expected_prior AS %s)", a, types[[v]]),
                               types[[v]], dialect)
    sprintf(paste0("CASE WHEN %1$s.correction_id IS NOT NULL AND (",
                   "(%1$s.expected_prior_missing = 1 AND %2$s IS NULL) OR ",
                   "(%1$s.expected_prior_missing = 0 AND %5$s))",
                   " THEN CASE WHEN %1$s.new_value_missing = 1 THEN NULL",
                   " ELSE CAST(%1$s.new_value AS %3$s) END",
                   " ELSE %2$s END AS %4$s"),
            a, b, types[[v]], q(v), prior_eq)
  }, character(1))
  joins <- vapply(corrected, function(v) {
    a <- alias[[v]]
    on <- paste(sprintf("%s.%s = b.%s", a, q(key), q(key)), collapse = " AND ")
    sprintf("LEFT JOIN w %s ON %s AND %s.variable = %s", a, on, a, sql_string(v))
  }, character(1))
  paste0(view_header(dialect), " ", q(view), " AS\n",
         .winners_cte(q, corrections_table, decisions_table, master, key),
         "SELECT\n  ", paste(select, collapse = ",\n  "), "\n",
         "FROM ", q(base_table), " b",
         if (length(joins)) paste0("\n", paste(joins, collapse = "\n")) else "",
         ";")
}

stale_view_sql <- function(view, base_table, corrections_table, decisions_table,
                           master, key, columns, corrected, types, dialect = "mssql") {
  q <- quoter(dialect)
  valid <- setdiff(columns, key)
  corrected <- intersect(corrected, valid)
  stopifnot(all(corrected %in% names(types)))
  in_valid <- paste(sql_string(valid), collapse = ", ")
  on <- paste(sprintf("b.%s = w.%s", q(key), q(key)), collapse = " AND ")
  parts <- c(
    sprintf(paste("SELECT w.correction_id, w.variable, 'no_variable' AS reason FROM w",
                  "WHERE w.variable NOT IN (%s)"), in_valid),
    sprintf(paste("SELECT w.correction_id, w.variable, 'no_record' AS reason FROM w",
                  "LEFT JOIN %s b ON %s WHERE w.variable IN (%s) AND b.%s IS NULL"),
            q(base_table), on, in_valid, q(key[[1]])),
    sprintf(paste("SELECT w.correction_id, w.variable, 'prior_unknown' AS reason FROM w",
                  "JOIN %s b ON %s WHERE w.variable IN (%s)",
                  "AND w.expected_prior_missing IS NULL"),
            q(base_table), on, in_valid),
    vapply(corrected, function(v) {
      b <- paste0("b.", q(v))
      prior_eq <- .string_eq_sql(b, sprintf("CAST(w.expected_prior AS %s)", types[[v]]),
                                 types[[v]], dialect)
      sprintf(paste("SELECT w.correction_id, w.variable, 'prior_mismatch' AS reason FROM w",
                    "JOIN %s b ON %s WHERE w.variable = %s AND (",
                    "(w.expected_prior_missing = 1 AND %s IS NOT NULL) OR",
                    "(w.expected_prior_missing = 0 AND (%s IS NULL OR NOT (%s))))"),
              q(base_table), on, sql_string(v), b, b, prior_eq)
    }, character(1)))
  paste0(view_header(dialect), " ", q(view), " AS\n",
         .winners_cte(q, corrections_table, decisions_table, master, key),
         "SELECT correction_id, variable, reason FROM (\n",
         paste(parts, collapse = "\nUNION ALL\n"),
         "\n) s;")
}

corrected_variables <- function(con, corrections_table, master, dialect = "mssql") {
  q <- quoter(dialect)
  DBI::dbGetQuery(con, sprintf("SELECT DISTINCT variable FROM %s WHERE master = ?",
                               q(corrections_table)), params = list(master))$variable
}
