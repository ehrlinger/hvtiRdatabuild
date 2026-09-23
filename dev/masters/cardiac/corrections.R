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
# prior is unknown, either text fails to cast, or the base no longer holds its
# prior. Otherwise it applies.
#
# `as_of`, when non-NULL, freezes the correction state: only decisions with
# decided_on <= as_of and corrections with asserted_on <= as_of count, so the
# same view can be reproduced at a point in time via the freeze record.
resolve_corrections <- function(base, corrections, decisions, key, master, as_of = NULL) {
  if (!is.null(as_of)) decisions <- decisions[decisions$decided_on <= as_of, ]
  dec <- decisions[order(decisions$correction_id, -xtfrm(decisions$decided_on),
                         -xtfrm(decisions$decision_id)), ]
  latest <- dec[!duplicated(dec$correction_id), ]
  accepted <- latest$correction_id[latest$decision == "accept"]
  acc <- corrections[corrections$master == master &
                       corrections$correction_id %in% accepted, ]
  if (!is.null(as_of)) acc <- acc[acc$asserted_on <= as_of, ]
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
      prior_casts <- w$expected_prior_missing == 1L || !is.na(parse_value(w$expected_prior, cls))
      new_casts <- w$new_value_missing == 1L || !is.na(parse_value(w$new_value, cls))
      if (!prior_casts || !new_casts) {
        "does_not_cast"
      } else {
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

.winners_cte <- function(q, corrections_table, decisions_table, master, key, dialect,
                         as_of = NULL) {
  dec_filter <- if (!is.null(as_of)) {
    paste0("\n  WHERE decided_on <= ", sql_timestamp_literal(as_of, dialect))
  } else {
    ""
  }
  acc_filter <- if (!is.null(as_of)) {
    paste0(" AND c.asserted_on <= ", sql_timestamp_literal(as_of, dialect))
  } else {
    ""
  }
  paste0(
    "WITH latest AS (\n",
    "  SELECT correction_id, decision,\n",
    "         ROW_NUMBER() OVER (PARTITION BY correction_id\n",
    "                            ORDER BY decided_on DESC, decision_id DESC) AS rn\n",
    "  FROM ", q(decisions_table), dec_filter, "\n",
    "), accepted AS (\n",
    "  SELECT c.* FROM ", q(corrections_table), " c\n",
    "  JOIN latest l ON l.correction_id = c.correction_id\n",
    "  WHERE l.rn = 1 AND l.decision = 'accept' AND c.master = ", sql_string(master),
    acc_filter, "\n",
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
                                 dialect = "mssql", as_of = NULL) {
  q <- quoter(dialect)
  corrected <- intersect(corrected, setdiff(columns, key))
  stopifnot(all(key %in% columns), all(corrected %in% names(types)))
  alias <- stats::setNames(sprintf("c%d", seq_along(corrected)), corrected)
  select <- vapply(columns, function(v) {
    b <- paste0("b.", q(v))
    if (!v %in% corrected) return(b)
    a <- alias[[v]]
    # TRY_CAST, not CAST: an uncastable stored value must not break the view.
    prior_cast <- sprintf("TRY_CAST(%s.expected_prior AS %s)", a, types[[v]])
    prior_eq <- .string_eq_sql(b, prior_cast, types[[v]], dialect)
    new_cast <- sprintf("TRY_CAST(%s.new_value AS %s)", a, types[[v]])
    cond <- paste0(
      a, ".correction_id IS NOT NULL AND (",
      "(", a, ".expected_prior_missing = 1 AND ", b, " IS NULL) OR ",
      "(", a, ".expected_prior_missing = 0 AND ", prior_cast, " IS NOT NULL AND ",
      prior_eq, "))",
      " AND (", a, ".new_value_missing = 1 OR ", new_cast, " IS NOT NULL)")
    sprintf(paste("CASE WHEN %s THEN CASE WHEN %s.new_value_missing = 1 THEN NULL",
                  "ELSE %s END ELSE %s END AS %s"),
            cond, a, new_cast, b, q(v))
  }, character(1))
  joins <- vapply(corrected, function(v) {
    a <- alias[[v]]
    on <- paste(sprintf("%s.%s = b.%s", a, q(key), q(key)), collapse = " AND ")
    sprintf("LEFT JOIN w %s ON %s AND %s.variable = %s", a, on, a, sql_string(v))
  }, character(1))
  paste0(view_header(dialect), " ", q(view), " AS\n",
         .winners_cte(q, corrections_table, decisions_table, master, key, dialect, as_of),
         "SELECT\n  ", paste(select, collapse = ",\n  "), "\n",
         "FROM ", q(base_table), " b",
         if (length(joins)) paste0("\n", paste(joins, collapse = "\n")) else "",
         ";")
}

stale_view_sql <- function(view, base_table, corrections_table, decisions_table,
                           master, key, columns, corrected, types, dialect = "mssql",
                           as_of = NULL) {
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
      prior_cast <- sprintf("TRY_CAST(w.expected_prior AS %s)", types[[v]])
      new_cast <- sprintf("TRY_CAST(w.new_value AS %s)", types[[v]])
      sprintf(paste("SELECT w.correction_id, w.variable, 'does_not_cast' AS reason FROM w",
                    "JOIN %s b ON %s WHERE w.variable = %s",
                    "AND w.expected_prior_missing IS NOT NULL AND (",
                    "(w.expected_prior_missing = 0 AND %s IS NULL) OR",
                    "(w.new_value_missing = 0 AND %s IS NULL))"),
              q(base_table), on, sql_string(v), prior_cast, new_cast)
    }, character(1)),
    vapply(corrected, function(v) {
      b <- paste0("b.", q(v))
      prior_cast <- sprintf("TRY_CAST(w.expected_prior AS %s)", types[[v]])
      new_cast <- sprintf("TRY_CAST(w.new_value AS %s)", types[[v]])
      prior_eq <- .string_eq_sql(b, prior_cast, types[[v]], dialect)
      sprintf(paste("SELECT w.correction_id, w.variable, 'prior_mismatch' AS reason FROM w",
                    "JOIN %s b ON %s WHERE w.variable = %s",
                    "AND (w.expected_prior_missing = 1 OR %s IS NOT NULL)",
                    "AND (w.new_value_missing = 1 OR %s IS NOT NULL) AND (",
                    "(w.expected_prior_missing = 1 AND %s IS NOT NULL) OR",
                    "(w.expected_prior_missing = 0 AND (%s IS NULL OR NOT (%s))))"),
              q(base_table), on, sql_string(v), prior_cast, new_cast, b, b, prior_eq)
    }, character(1)))
  paste0(view_header(dialect), " ", q(view), " AS\n",
         .winners_cte(q, corrections_table, decisions_table, master, key, dialect, as_of),
         "SELECT correction_id, variable, reason FROM (\n",
         paste(parts, collapse = "\nUNION ALL\n"),
         "\n) s;")
}

corrected_variables <- function(con, corrections_table, master, dialect = "mssql") {
  q <- quoter(dialect)
  DBI::dbGetQuery(con, sprintf("SELECT DISTINCT variable FROM %s WHERE master = ?",
                               q(corrections_table)), params = list(master))$variable
}
