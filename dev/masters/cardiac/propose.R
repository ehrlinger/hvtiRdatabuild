# propose.R
#
# Append a correction, or a decision on one. Both validate before writing, and
# neither prints a key or a value: messages name the table, the variable and the
# correction id only.

EVIDENCE_TYPES <- c("chart_review", "source_document", "investigator_return",
                    "legacy_sas_inline")
DECISIONS <- c("accept", "reject", "supersede", "bake")

.checked_text <- function(x, r_class, what) {
  if (length(x) != 1L) stop("'", what, "' must be a single value.", call. = FALSE)
  if (is.na(x)) return(NA_character_)
  if (is.factor(x)) {
    stop("'", what, "' does not cast to the variable's type (", r_class, ").",
         call. = FALSE)
  }
  text <- value_text(x)
  back <- parse_value(text, r_class)
  if (is.na(back) || !isTRUE(back == x)) {
    stop("'", what, "' does not cast to the variable's type (", r_class, ").",
         call. = FALSE)
  }
  text
}

propose_correction <- function(con, master, base_table, corrections_table, key_values,
                               variable, expected_prior, new_value, evidence_type,
                               evidence_ref, asserted_by, meta, widths = NULL,
                               dialect = "mssql") {
  q <- quoter(dialect)
  if (!variable %in% meta$variable) {
    stop("Variable is not in the master's metadata: ", variable, call. = FALSE)
  }
  if (variable %in% names(key_values)) {
    stop("A key column cannot be corrected through this path: ", variable, call. = FALSE)
  }
  if (!evidence_type %in% EVIDENCE_TYPES) {
    stop("Unknown evidence type '", evidence_type, "'. Expected one of: ",
         paste(EVIDENCE_TYPES, collapse = ", "), call. = FALSE)
  }
  r_class <- meta$r_class[match(variable, meta$variable)]
  if (!is.null(widths) && identical(r_class, "character") && !is.na(new_value) &&
        variable %in% names(widths) && nchar(new_value) > widths[[variable]]) {
    stop("'new_value' is longer than the column allows (", widths[[variable]],
         " characters).", call. = FALSE)
  }
  prior_text <- .checked_text(expected_prior, r_class, "expected_prior")
  new_text <- .checked_text(new_value, r_class, "new_value")

  where <- paste(sprintf("%s = ?", q(names(key_values))), collapse = " AND ")
  n <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s WHERE %s",
                                    q(base_table), where),
                       params = unname(key_values))$n
  if (!identical(as.integer(n), 1L)) {
    stop("The key matched ", n, " rows in ", base_table, "; expected exactly 1.",
         call. = FALSE)
  }
  seen <- DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS n FROM %s WHERE master = ? AND variable = ?",
    q(corrections_table)), params = list(master, variable))$n

  now <- Sys.time()
  id <- paste0("c", substr(digest::digest(
    list(master, key_values, variable, prior_text, new_text, asserted_by,
         format(now, "%Y-%m-%d %H:%M:%OS6")), algo = "sha1"), 1, 16))
  n_id <- DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS n FROM %s WHERE correction_id = ?",
    q(corrections_table)), params = list(id))$n
  if (as.integer(n_id) > 0L) {
    stop("The generated correction id collides with an existing row; ",
         "retry the proposal.", call. = FALSE)
  }
  row <- data.frame(correction_id = id, master = master, stringsAsFactors = FALSE)
  for (k in names(key_values)) row[[k]] <- key_values[[k]]
  row$variable <- variable
  row$expected_prior <- prior_text
  row$expected_prior_missing <- as.integer(is.na(expected_prior))
  row$new_value <- new_text
  row$new_value_missing <- as.integer(is.na(new_value))
  row$evidence_type <- evidence_type
  row$evidence_ref <- evidence_ref
  row$asserted_by <- asserted_by
  row$asserted_on <- now
  DBI::dbAppendTable(con, corrections_table, row)

  new_variable <- as.integer(seen) == 0L
  message("Correction ", id, " appended.",
          if (new_variable) " First correction to this variable: regenerate the view.")
  invisible(list(verdict = "appended", correction_id = id, new_variable = new_variable))
}

decide_correction <- function(con, decisions_table, corrections_table, correction_id,
                              decision, decided_by, reason = NA_character_,
                              dialect = "mssql") {
  q <- quoter(dialect)
  if (!decision %in% DECISIONS) {
    stop("Unknown decision '", decision, "'. Expected one of: ",
         paste(DECISIONS, collapse = ", "), call. = FALSE)
  }
  n <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s WHERE correction_id = ?",
                                    q(corrections_table)), params = list(correction_id))$n
  if (as.integer(n) != 1L) {
    stop("There is no correction ", correction_id, ".", call. = FALSE)
  }
  now <- Sys.time()
  did <- paste0("d", substr(digest::digest(
    list(correction_id, decision, decided_by, format(now, "%Y-%m-%d %H:%M:%OS6")),
    algo = "sha1"), 1, 16))
  n_did <- DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS n FROM %s WHERE decision_id = ?",
    q(decisions_table)), params = list(did))$n
  if (as.integer(n_did) > 0L) {
    stop("The generated decision id collides with an existing row; ",
         "retry the decision.", call. = FALSE)
  }
  DBI::dbAppendTable(con, decisions_table, data.frame(
    decision_id = did, correction_id = correction_id, decision = decision,
    decided_by = decided_by, decided_on = now, reason = reason,
    stringsAsFactors = FALSE))
  message("Decision ", did, " (", decision, ") recorded on ", correction_id, ".")
  invisible(list(verdict = "recorded", decision_id = did))
}
