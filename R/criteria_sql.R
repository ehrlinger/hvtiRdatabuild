# criteria_sql.R
#
# SQL for cohort criteria, run inside pull_master()'s transaction against the session
# cohort table. Flags are 1 met, 0 not met, NULL undetermined. Spec:
# dev/specs/2026-11-16-cohort-criteria-addendum.md §4.

# A node as a SQL expression over the flag columns, with the same three-valued logic
# as .eval_node().
.node_sql <- function(node) {
  if (identical(node$type, "leaf")) return(node$col)
  parts <- vapply(node$parts, .node_sql, character(1))
  win <- if (identical(node$type, "any")) 1L else 0L
  lose <- 1L - win
  sprintf("CASE WHEN %s THEN %d WHEN %s THEN %d END",
          paste0("(", parts, ") = ", win, collapse = " OR "), win,
          paste0("(", parts, ") = ", lose, collapse = " AND "), lose)
}

# Deactivate the active units a stage does not keep (see .stage_outcome()).
.deactivate_sql <- function(tmp, stage) {
  s <- .node_sql(stage$node)
  target <- if (identical(stage$role, "include")) 1L else 0L
  und_keeps <- if (identical(stage$undetermined, "exclude")) 0L else 1L
  sprintf(paste("UPDATE %s SET active = 0 WHERE active = 1 AND",
                "(CASE WHEN (%s) = %d THEN 1 WHEN (%s) IS NULL THEN %d ELSE 0 END) = 0"),
          tmp, s, target, s, und_keeps)
}

.date_shift_sql <- function(dialect, x, days) {
  switch(dialect,
         mssql = sprintf("DATEADD(day, %d, %s)", as.integer(days), x),
         duckdb = sprintf("CAST(%s + %d AS DATE)", x, as.integer(days)))
}

.day_diff_sql <- function(dialect, from, to) {
  switch(dialect,
         mssql = sprintf("DATEDIFF(day, %s, %s)", from, to),
         duckdb = sprintf("date_diff('day', %s, %s)", from, to))
}

# 1 when the condition is true, 0 when false, NULL when unknown.
.met_sql <- function(condition) {
  sprintf("CASE WHEN (%s) THEN 1 WHEN NOT (%s) THEN 0 END", condition, condition)
}

# Over the judged rows: their common verdict, or NULL when there are none, any is
# unknown, or they disagree.
.agree_sql <- function(met) {
  sprintf(paste("CASE WHEN COUNT(*) > 0 AND COUNT(%1$s) = COUNT(*) AND",
                "MIN(%1$s) = MAX(%1$s) THEN MIN(%1$s) END"), met)
}

# One leaf's value for the cohort row `tmp`, as a correlated scalar subquery. Aggregates
# take inner columns only: SQL Server refuses an aggregate over an outer reference.
.leaf_value_sql <- function(test, tmp, master_q, mrn_q, date_q, dialect) {
  met <- .met_sql(test$condition)
  enc <- paste0(tmp, ".encounter_date")
  if (identical(test$type, "master")) {
    return(sprintf("(SELECT %s FROM %s m WHERE m.%s = %s.mrn AND m.%s = %s)",
                   .agree_sql(met), master_q, mrn_q, tmp, date_q, enc))
  }
  q <- quoter(dialect)
  view_q <- .qualified_name(test$view, dialect)
  day <- function(alias) sprintf("CAST(%s.%s AS DATE)", alias, q(test$date_col))
  in_window <- function(alias) {
    sprintf("%s.%s = %s.mrn AND %s BETWEEN %s AND %s", alias, q(test$mrn_col), tmp,
            day(alias), .date_shift_sql(dialect, enc, test$window[[1]]),
            .date_shift_sql(dialect, enc, test$window[[2]]))
  }
  where <- in_window("v")
  if (identical(test$pick, "nearest")) {
    before <- sprintf("(SELECT MAX(%s) FROM %s v2 WHERE %s AND %s <= %s)", day("v2"),
                      view_q, in_window("v2"), day("v2"), enc)
    after <- sprintf("(SELECT MIN(%s) FROM %s v3 WHERE %s AND %s >= %s)", day("v3"),
                     view_q, in_window("v3"), day("v3"), enc)
    gap <- function(x) sprintf("ABS(%s)", .day_diff_sql(dialect, enc, x))
    nearest_gap <- sprintf(paste("CASE WHEN %1$s IS NULL THEN %4$s WHEN %2$s IS NULL",
                                 "THEN %3$s WHEN %3$s <= %4$s THEN %3$s ELSE %4$s END"),
                           before, after, gap(before), gap(after))
    where <- sprintf("%s AND %s = %s", where, gap(day("v")), nearest_gap)
  }
  agg <- switch(
    test$pick,
    any = sprintf(paste("CASE WHEN MAX(%1$s) = 1 THEN 1 WHEN COUNT(*) > 0 AND",
                        "COUNT(%1$s) = COUNT(*) THEN 0 END"), met),
    all = sprintf(paste("CASE WHEN MIN(%1$s) = 0 THEN 0 WHEN COUNT(*) > 0 AND",
                        "COUNT(%1$s) = COUNT(*) THEN 1 END"), met),
    nearest = .agree_sql(met)
  )
  sprintf("(SELECT %s FROM %s v WHERE %s)", agg, view_q, where)
}

.leaf_update_sql <- function(leaf, tmp, master_q, mrn_q, date_q, dialect) {
  sprintf("UPDATE %s SET %s = %s WHERE active = 1", tmp, leaf$col,
          .leaf_value_sql(leaf$test, tmp, master_q, mrn_q, date_q, dialect))
}
