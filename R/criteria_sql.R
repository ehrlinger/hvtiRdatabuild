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
