# legacy_facts.R
#
# The inline patient-level fixes in a master's SAS build, read at run time and
# recorded as corrections with an unknown prior and a 'bake' decision: present
# in the snapshot, activated by the phase 3 port (spec Section 5.4). Nothing
# here writes a key or a value to a file or to the console.

.lit_pattern <- paste0("('(?:[^']|'')*'d?|\"(?:[^\"]|\"\")*\"d?|",
                       "-?(?:\\d+\\.?\\d*|\\.\\d+)(?:e[+-]?\\d+)?|\\.)")
.var_pattern <- "([a-z_][a-z0-9_]*)"

#' A SAS literal as text, with a missing flag
#'
#' @param lit Character. A single SAS literal token.
#'
#' @return A list with `text` and `missing`, or `NULL` when `lit` cannot be
#'   read.
#'
#' @keywords internal
#' @noRd
.lit_text <- function(lit) {
  if (lit == ".") return(list(text = NA_character_, missing = 1L))
  if (grepl("^['\"].*['\"]d$", lit, ignore.case = TRUE)) {
    m <- regmatches(lit, regexec("^['\"](\\d{1,2})([a-z]{3})(\\d{4})['\"]d$", lit,
                                 ignore.case = TRUE))[[1]]
    if (!length(m)) return(NULL)
    mon <- match(tolower(m[[3]]), tolower(month.abb))
    if (is.na(mon)) return(NULL)
    d <- as.Date(sprintf("%s-%02d-%02d", m[[4]], mon, as.integer(m[[2]])))
    return(list(text = value_text(d), missing = 0L))
  }
  if (grepl("^['\"]", lit)) {
    q <- substr(lit, 1, 1)
    inner <- gsub(paste0(q, q), q, substr(lit, 2, nchar(lit) - 1), fixed = TRUE)
    if (!nzchar(trimws(inner))) return(list(text = NA_character_, missing = 1L))
    return(list(text = inner, missing = 0L))
  }
  list(text = value_text(as.numeric(lit)), missing = 0L)
}

#' Split SAS source lines into statements, quote- and comment-aware
#'
#' @param lines Character. The SAS source lines.
#'
#' @return A data frame of `line` (the statement's starting line) and `stmt`
#'   (its normalised text), comments and blanks dropped.
#'
#' @keywords internal
#' @noRd
.statements <- function(lines) {
  text <- paste(lines, collapse = "\n")
  m <- gregexpr("/\\*[\\s\\S]*?\\*/", text, perl = TRUE)
  regmatches(text, m) <- list(gsub("[^\n]", " ", regmatches(text, m)[[1]]))
  # Quote-aware split: a ';' inside a quoted literal is not a statement end.
  qpat <- "'(?:[^']|'')*'|\"(?:[^\"]|\"\")*\""
  qm <- gregexpr(qpat, text, perl = TRUE)
  regmatches(text, qm) <- list(gsub(";", "\001", regmatches(text, qm)[[1]], fixed = TRUE))
  pieces <- strsplit(text, ";", fixed = TRUE)[[1]]
  nl <- nchar(gsub("[^\n]", "", pieces))
  lead <- sub("^(\\s*)[\\s\\S]*$", "\\1", pieces, perl = TRUE)
  line <- 1L + c(0L, cumsum(nl)[-length(nl)]) + nchar(gsub("[^\n]", "", lead))
  pieces <- gsub("\001", ";", pieces, fixed = TRUE)
  stmt <- trimws(gsub("\\s+", " ", pieces))
  keep <- nzchar(stmt) & !startsWith(stmt, "*")
  data.frame(line = as.integer(line[keep]), stmt = stmt[keep], stringsAsFactors = FALSE)
}

#' Parse a master's inline SAS fixes into legacy facts
#'
#' @param lines Character. The SAS source lines.
#' @param key_var Character. The SAS variable name of the base key used in the
#'   inline `if` conditions.
#'
#' @return A list with `facts` (a data frame of `line`, `key_value`,
#'   `variable`, `value_text`, `value_missing`) and `unparsed` (the line
#'   numbers of statements that mention the key but could not be parsed).
#'
#' @keywords internal
#' @noRd
parse_legacy_facts <- function(lines, key_var = "ccfid") {
  st <- .statements(lines)
  grab <- function(p, s) regmatches(s, regexec(p, s, perl = TRUE, ignore.case = TRUE))[[1]]
  k <- key_var
  p_simple <- paste0("^if\\s*\\(?\\s*", k, "\\s*(?:=|eq)\\s*", .lit_pattern,
                     "\\s*\\)?\\s*then\\s+", .var_pattern, "\\s*=\\s*", .lit_pattern, "$")
  p_in <- paste0("^if\\s*\\(?\\s*", k, "\\s+in\\s*\\(([^)]*)\\)\\s*\\)?\\s*then\\s+",
                 .var_pattern, "\\s*=\\s*", .lit_pattern, "$")
  p_do <- paste0("^if\\s*\\(?\\s*", k, "\\s*(?:=|eq)\\s*", .lit_pattern, "\\s*\\)?\\s*then\\s+do$")
  p_assign <- paste0("^", .var_pattern, "\\s*=\\s*", .lit_pattern, "$")
  p_mentions <- paste0("^if\\b.*\\b", k, "\\b")
  p_else <- "^else\\b"
  p_mentions_key <- paste0("\\b", k, "\\b")

  facts <- list()
  unparsed <- integer()
  last_key_if <- FALSE
  # Returns the fact row, or NULL when it cannot be read; the caller appends
  # it to `facts` itself, so no closure here ever mutates the caller's state.
  add <- function(line, key_lit, var, val_lit) {
    kv <- .lit_text(key_lit)
    vv <- .lit_text(val_lit)
    if (is.null(kv) || is.null(vv) || kv$missing == 1L) return(NULL)
    data.frame(
      line = line, key_value = kv$text, variable = tolower(var),
      value_text = vv$text, value_missing = vv$missing, stringsAsFactors = FALSE
    )
  }

  i <- 1L
  while (i <= nrow(st)) {
    s <- st$stmt[[i]]
    line <- st$line[[i]]
    if (grepl(p_else, s, perl = TRUE, ignore.case = TRUE)) {
      # A rule over every other patient, not a fact: never parsed as one, but
      # only worth flagging when it could be mistaken for a key fact.
      mentions_key <- grepl(p_mentions_key, s, perl = TRUE, ignore.case = TRUE)
      if (mentions_key || last_key_if) unparsed <- c(unparsed, line)
      last_key_if <- FALSE
    } else if (length(m <- grab(p_simple, s))) {
      r <- add(line, m[[2]], m[[3]], m[[4]])
      if (is.null(r)) unparsed <- c(unparsed, line) else facts[[length(facts) + 1L]] <- r
      last_key_if <- TRUE
    } else if (length(m <- grab(p_in, s))) {
      keys <- regmatches(m[[2]], gregexpr(.lit_pattern, m[[2]], perl = TRUE))[[1]]
      rows <- lapply(keys, function(kl) add(line, kl, m[[3]], m[[4]]))
      ok <- !vapply(rows, is.null, logical(1))
      for (r in rows[ok]) facts[[length(facts) + 1L]] <- r
      if (!all(ok)) unparsed <- c(unparsed, line)
      last_key_if <- TRUE
    } else if (length(m <- grab(p_do, s))) {
      block <- list()
      good <- TRUE
      i <- i + 1L
      while (i <= nrow(st) && !grepl("^end$", st$stmt[[i]], ignore.case = TRUE)) {
        a <- grab(p_assign, st$stmt[[i]])
        if (length(a)) block[[length(block) + 1L]] <- a else good <- FALSE
        i <- i + 1L
      }
      if (good && length(block)) {
        rows <- lapply(block, function(a) add(line, m[[2]], a[[2]], a[[3]]))
        ok <- !vapply(rows, is.null, logical(1))
        for (r in rows[ok]) facts[[length(facts) + 1L]] <- r
        if (!all(ok)) unparsed <- c(unparsed, line)
      } else {
        unparsed <- c(unparsed, line)
      }
      last_key_if <- TRUE
    } else if (grepl(p_mentions, s, perl = TRUE, ignore.case = TRUE)) {
      unparsed <- c(unparsed, line)
      last_key_if <- FALSE
    } else {
      last_key_if <- FALSE
    }
    i <- i + 1L
  }
  facts <- if (length(facts)) do.call(rbind, facts) else
    data.frame(line = integer(), key_value = character(), variable = character(),
               value_text = character(), value_missing = integer())
  list(facts = facts, unparsed = unique(unparsed))
}

#' A key value's text form, element by element
#'
#' `format()` on a vector would pad to a common width; this formats each
#' element on its own.
#'
#' @param x A vector of key values.
#'
#' @return A character vector, one text form per element of `x`.
#'
#' @keywords internal
#' @noRd
.key_text <- function(x) {
  if (is.numeric(x)) {
    vapply(x, format, character(1), scientific = FALSE, trim = TRUE, digits = 15)
  } else {
    trimws(as.character(x))
  }
}

#' Turn parsed legacy facts into corrections and decisions rows
#'
#' @param facts A data frame as returned by `parse_legacy_facts()`'s `facts`.
#' @param base_keys A data frame of the base rows' key columns.
#' @param key Character. The base key columns.
#' @param master Character. The master the facts belong to.
#' @param meta A data frame of `variable`, `r_class` for the base's columns.
#' @param source_file Character. The SAS source file's name, for the evidence
#'   reference.
#' @param asserted_on A `POSIXct` timestamp to record as `asserted_on` and
#'   `decided_on`.
#'
#' @return A list with `corrections`, `decisions` (data frames, or `NULL`
#'   when no fact resolved) and `unresolved` (a data frame of `line`,
#'   `reason`).
#'
#' @keywords internal
#' @noRd
legacy_rows <- function(facts, base_keys, key, master, meta, source_file,
                        asserted_on = Sys.time()) {
  kt <- .key_text(base_keys[[key[[1]]]])
  extra_cols <- setdiff(names(base_keys), key)
  out <- list()
  unresolved <- list()
  for (i in seq_len(nrow(facts))) {
    f <- facts[i, ]
    v <- meta$variable[match(tolower(f$variable), tolower(meta$variable))]
    hits <- which(kt == f$key_value)
    r_class <- if (is.na(v)) NA_character_ else meta$r_class[match(v, meta$variable)]
    casts <- !is.na(v) && (f$value_missing == 1L ||
                             !is.na(parse_value(f$value_text, r_class)))
    reason <- if (is.na(v)) "no_variable" else if (v %in% key) "key_variable" else
      if (!length(hits)) "no_record" else if (length(hits) > 1L) "ambiguous" else
        if (!casts) "does_not_cast" else NULL
    if (!is.null(reason)) {
      unresolved[[length(unresolved) + 1L]] <- data.frame(line = f$line, reason = reason)
      next
    }
    id <- paste0("L", substr(digest::digest(list(master, source_file, f$line, i),
                                            algo = "sha1"), 1, 15))
    out[[length(out) + 1L]] <- cbind(
      data.frame(correction_id = id, master = master, stringsAsFactors = FALSE),
      base_keys[hits, c(key, extra_cols), drop = FALSE],
      data.frame(variable = v, expected_prior = NA_character_,
                 expected_prior_missing = NA_integer_, new_value = f$value_text,
                 new_value_missing = f$value_missing, evidence_type = "legacy_sas_inline",
                 evidence_ref = paste0(source_file, ":", f$line),
                 asserted_by = "unknown (legacy)", asserted_on = asserted_on,
                 stringsAsFactors = FALSE)
    )
  }
  corrections <- if (length(out)) do.call(rbind, out) else NULL
  if (!is.null(corrections)) rownames(corrections) <- NULL
  decisions <- if (is.null(corrections)) NULL else data.frame(
    decision_id = paste0("D", substr(vapply(corrections$correction_id, digest::digest,
                                            character(1), algo = "sha1"), 1, 15)),
    correction_id = corrections$correction_id, decision = "bake",
    decided_by = "legacy backfill", decided_on = asserted_on,
    reason = "Present in the snapshot; activated by the phase 3 port.",
    stringsAsFactors = FALSE
  )
  unresolved <- if (length(unresolved)) do.call(rbind, unresolved) else
    data.frame(line = integer(), reason = character())
  list(corrections = corrections, decisions = decisions, unresolved = unresolved)
}

#' Record legacy facts as corrections and decisions, idempotently
#'
#' @param con A DBI connection.
#' @param rows A list as returned by `legacy_rows()`.
#' @param corrections_table Character. The corrections table's name.
#' @param decisions_table Character. The decisions table's name.
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#'
#' @return A list with `appended` and `already_present` counts.
#'
#' @keywords internal
#' @noRd
record_legacy_facts <- function(con, rows, corrections_table, decisions_table,
                                dialect = "mssql") {
  q <- quoter(dialect)
  if (is.null(rows$corrections)) return(list(appended = 0L, already_present = 0L))
  have <- DBI::dbGetQuery(con, sprintf(
    "SELECT correction_id FROM %s WHERE evidence_type = 'legacy_sas_inline'",
    q(corrections_table)
  ))$correction_id
  new <- !rows$corrections$correction_id %in% have
  if (any(new)) {
    DBI::dbWithTransaction(con, {
      DBI::dbAppendTable(con, corrections_table, rows$corrections[new, , drop = FALSE])
      DBI::dbAppendTable(con, decisions_table,
                         rows$decisions[rows$decisions$correction_id %in%
                                          rows$corrections$correction_id[new], ,
                                        drop = FALSE])
    })
  }
  list(appended = sum(new), already_present = sum(!new))
}
