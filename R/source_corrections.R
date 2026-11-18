# source_corrections.R
#
# Interim correction intake (spec §3.4, §3.5): generating each source's correction
# objects, the submission template, batch proposal and decision, and retiring fill-ins
# that upstream has caught up with. Superseded by the HVTR registry's intake, which takes
# the template and the tables over unchanged. Output is counts, verdicts, column and
# source names, correction ids and template row numbers; never a key or a value.

# Who records a G7 retirement. Not a person, so it can never be in `deciders`.
FILLED_UPSTREAM_DECIDER <- "filled_upstream" # nolint: object_name_linter.

#' A short id: a prefix and the first 20 hex digits of the SHA-1 of `parts`
#'
#' @param prefix Character. One letter.
#' @param parts A list to hash.
#'
#' @return A length-one character.
#'
#' @keywords internal
#' @noRd
.short_id <- function(prefix, parts) {
  paste0(prefix, substr(digest::digest(parts, algo = "sha1"), 1, 20))
}

#' Each declared source's correction statements
#'
#' @param config A `master_config`.
#' @param con A DBI connection that can see the source views.
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#'
#' @return A named list, one element per source: `list(tables = , views = )`.
#'
#' @keywords internal
#' @noRd
.corrections_statements <- function(config, con, dialect) {
  if (!length(config$sources)) {
    .abort("no_sources", "generate_corrections_sql(): master.yml declares no sources.")
  }
  stats::setNames(lapply(names(config$sources), function(s) {
    types <- run_step("read source columns", table_types(con, s))
    if (!length(types)) {
      .abort("unknown_source", "generate_corrections_sql(): source ", s,
             " is not in the warehouse.")
    }
    key <- config$sources[[s]]$key
    if (!all(key %in% names(types))) {
      .abort("unknown_key_column", "generate_corrections_sql(): source ", s,
             " has no column(s) ", paste(setdiff(key, names(types)), collapse = ", "), ".")
    }
    list(tables = unname(source_corrections_ddl(s, types[key], dialect)),
         views = unname(source_views_sql(s, key, types, dialect)))
  }), names(config$sources))
}

#' Generate the correction tables and views for a master's sources
#'
#' Writes, for each source declared in `master.yml`, a `<source>.tables.sql` file that
#' creates its corrections and decisions tables once, and a `<source>.views.sql` file that
#' creates or replaces its four views:
#'
#' - `<source>_corrected`: the source with accepted corrections applied, covering every
#'   column, so a first correction to a column is live with no redeployment.
#' - `<source>_corrections_applied`: which correction applied to which row.
#' - `<source>_corrections_stale` and `<source>_corrections_conflicts`: for data
#'   management.
#'
#' Statements are separated by `GO` lines, as `sqlcmd` expects. Regenerate the views
#' whenever the source view's columns change. Data engineering deploys the files.
#'
#' **Interim.** Superseded by the HVTR registry, which takes over the tables unchanged.
#'
#' @param config A `master_config` from [read_master_config()], with `sources`.
#' @param con A DBI connection that can see the source views.
#' @param dir Character. An existing directory to write the files into.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return The written paths, invisibly.
#'
#' @seealso [propose_corrections()], [decide_corrections()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   DBI::dbWriteTable(con, "stg_demo", data.frame(mrn = "SYN1", lvef = 30))
#'   cfg_path <- tempfile(fileext = ".yml")
#'   writeLines(c("name: master_demo", "key: [mrn]", "snapshots: snaps",
#'                "current: x.sas7bdat", "build_program: x.sas",
#'                "sources:", "  stg_demo: {key: [mrn]}"), cfg_path)
#'   generate_corrections_sql(read_master_config(cfg_path), con, tempdir(),
#'                            dialect = "duckdb")
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#' }
#' }
#'
#' @export
generate_corrections_sql <- function(config, con, dir, dialect = "mssql") {
  if (!dir.exists(dir)) {
    .abort("no_directory", "generate_corrections_sql(): `dir` does not exist.")
  }
  st <- .corrections_statements(config, con, dialect)
  paths <- unlist(lapply(names(st), function(s) {
    p <- file.path(dir, paste0(s, c(".tables.sql", ".views.sql")))
    writeLines(paste(st[[s]]$tables, collapse = "\nGO\n"), p[[1]])
    writeLines(paste(st[[s]]$views, collapse = "\nGO\n"), p[[2]])
    p
  }))
  .hvti_inform("Wrote correction SQL for ", length(st), " source(s).")
  invisible(paths)
}

#' The submission template's columns
#'
#' @param config A `master_config` with `sources`.
#'
#' @return A character vector.
#'
#' @keywords internal
#' @noRd
.template_columns <- function(config) {
  keys <- unique(unlist(lapply(config$sources, `[[`, "key"), use.names = FALSE))
  c("source", keys, "variable", "expected_prior", "expected_prior_missing", "new_value",
    "new_value_missing", "evidence_type", "evidence_ref", "asserted_by")
}

#' Write an empty correction submission template
#'
#' One row per cell. `source` is a source view declared in `master.yml`. The key columns
#' are the union of every source's declared key. A row fills exactly its own source's key
#' and leaves the others blank: a patient-level source's rows carry no encounter date.
#' `expected_prior_missing` and `new_value_missing` are `0` or `1`, and a value column is
#' blank exactly when its flag is `1`.
#'
#' The filled template holds identifiers. Keep it under the same rules as study data, and
#' never commit it to a repository.
#'
#' **Interim.** Superseded by the HVTR registry, which takes over the template.
#'
#' @param config A `master_config` from [read_master_config()], with `sources`.
#' @param path Character. Where to write the CSV. An existing file is never overwritten.
#'
#' @return `path`, invisibly.
#'
#' @seealso [propose_corrections()]
#'
#' @examples
#' cfg_path <- tempfile(fileext = ".yml")
#' writeLines(c("name: master_demo", "key: [mrn]", "snapshots: snaps",
#'              "current: x.sas7bdat", "build_program: x.sas",
#'              "sources:", "  stg_demo: {key: [mrn]}"), cfg_path)
#' write_corrections_template(read_master_config(cfg_path), tempfile(fileext = ".csv"))
#'
#' @export
write_corrections_template <- function(config, path) {
  if (file.exists(path)) {
    .abort("file_exists", "write_corrections_template(): the file already exists.")
  }
  cols <- .template_columns(config)
  empty <- as.data.frame(stats::setNames(rep(list(character()), length(cols)), cols),
                         check.names = FALSE)
  utils::write.csv(empty, path, row.names = FALSE)
  invisible(path)
}

#' Read a submission file once: its rows and the SHA-256 of the same bytes
#'
#' @param config A `master_config` with `sources`.
#' @param file Character. The filled template.
#'
#' @return A list: `rows` (a character data frame, blanks as `NA`) and `sha256`.
#'
#' @keywords internal
#' @noRd
.read_template <- function(config, file) {
  if (!file.exists(file)) .abort("no_file", "propose_corrections(): `file` does not exist.")
  bytes <- readBin(file, "raw", file.size(file))
  sha <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
  # Nothing becomes NA on reading: the two value columns are kept exactly as written, and
  # their flags, not an empty cell, say whether a value is missing.
  rows <- utils::read.csv(text = rawToChar(bytes), colClasses = "character",
                          na.strings = character(), check.names = FALSE)
  if (!identical(names(rows), .template_columns(config))) {
    .abort("template_columns", "propose_corrections(): the file's columns are not the ",
           "template's. Start from write_corrections_template().")
  }
  # Trim only the structural fields. Keys and values stay verbatim: a prior of " A" is not
  # "A", and parse_value()/value_text() preserve character text. Outside the two value
  # columns an empty cell is missing; inside them an empty cell is an empty string unless
  # its flag says missing, so "" and "   " are both representable.
  structural <- c("source", "variable", "expected_prior_missing", "new_value_missing",
                  "evidence_type", "asserted_by")
  rows[structural] <- lapply(rows[structural], trimws)
  other <- setdiff(names(rows), c("expected_prior", "new_value"))
  rows[other] <- lapply(rows[other], function(x) {
    x[!nzchar(x)] <- NA_character_
    x
  })
  list(rows = rows, sha256 = sha)
}

#' The intake key temp table for one source
#'
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#' @param key_types A named character vector of the source's key columns' SQL types.
#'
#' @return A list: `name` and `create`.
#'
#' @keywords internal
#' @noRd
.intake_temp <- function(dialect, key_types) {
  q <- quoter(dialect)
  cols <- paste0(", ", q(names(key_types)), " ", key_types, collapse = "")
  switch(dialect,
         mssql = list(name = "#correction_intake",
                      create = paste0("CREATE TABLE #correction_intake (row_id int NOT NULL",
                                      cols, ")")),
         duckdb = list(name = "correction_intake",
                       create = paste0("CREATE TEMP TABLE correction_intake (row_id INTEGER",
                                       " NOT NULL", cols, ")")))
}

#' The intake lookup: the source rows whose keys match the intake table
#'
#' Character keys join exactly on SQL Server, as the generated views do (see
#' `.key_join_sql()`), so a row judged appendable here is a row the views will apply to.
#' The intake row id is aliased `intake_row_` so it cannot collide with a source column.
#'
#' @param intake Character. The intake temp table's name.
#' @param source Character. The source's name.
#' @param key Character. The source's key columns.
#' @param types A named character vector of the source's SQL types.
#' @param wanted Character. The variables to read.
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#'
#' @return A length-one character: the `SELECT`.
#'
#' @keywords internal
#' @noRd
.intake_lookup_sql <- function(intake, source, key, types, wanted, dialect) {
  q <- quoter(dialect)
  sprintf("SELECT t.row_id AS intake_row_, %s FROM %s t JOIN %s b ON %s",
          paste0("b.", q(wanted), collapse = ", "), intake, q(source),
          .key_join_sql("b", "t", key, types, dialect))
}

#' One text per correction: its source key, variable, prior and new value
#'
#' Two corrections with the same signature make the same assertion about the same cell.
#' Keys and values are compared in their canonical text form, so `"30.0"` and `"30"` agree.
#'
#' @param d A data frame of corrections, with the key columns, `variable`,
#'   `expected_prior`, `expected_prior_missing`, `new_value` and `new_value_missing`.
#' @param key Character. The source's key columns.
#'
#' @return A character vector, one element per row of `d`.
#'
#' @keywords internal
#' @noRd
.correction_signature <- function(d, key) {
  texts <- lapply(key, function(k) {
    vapply(seq_len(nrow(d)), function(j) value_text(d[[k]][j]), character(1))
  })
  .composite_key(c(texts, list(
    as.character(d$variable), as.character(d$expected_prior),
    as.character(d$expected_prior_missing), as.character(d$new_value),
    as.character(d$new_value_missing)
  )))
}

#' The corrections that block a resubmission, by signature
#'
#' A correction holds its assertion while its latest decision (by `decided_on`, then
#' `decision_id`, as the views order them) is `"accept"`, or while it has none. A rejected
#' or superseded correction holds nothing, so the same assertion may be proposed again.
#'
#' @param con A DBI connection.
#' @param source Character. The source view.
#' @param key Character. The source's key columns.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return A named character vector: `"duplicate_pending"` or `"duplicate_accepted"`,
#'   named by `.correction_signature()`.
#'
#' @keywords internal
#' @noRd
.held_corrections <- function(con, source, key, dialect) {
  q <- quoter(dialect)
  tabs <- .source_tables(source)
  # A source whose corrections layer is not deployed holds nothing; appending to it fails
  # on its own, as before.
  if (!DBI::dbExistsTable(con, tabs$corrections)) {
    return(stats::setNames(character(), character()))
  }
  cols <- c("correction_id", key, "variable", "expected_prior", "expected_prior_missing",
            "new_value", "new_value_missing")
  corr <- DBI::dbGetQuery(con, paste("SELECT", paste(q(cols), collapse = ", "), "FROM",
                                     q(tabs$corrections)))
  dec <- DBI::dbGetQuery(con, paste(
    "SELECT", paste(q(c("correction_id", "decision", "decided_on", "decision_id")),
                    collapse = ", "),
    "FROM", q(tabs$decisions)
  ))
  dec <- dec[order(dec$correction_id, -xtfrm(dec$decided_on), -xtfrm(dec$decision_id)), ,
             drop = FALSE]
  latest <- dec$decision[!duplicated(dec$correction_id)]
  names(latest) <- dec$correction_id[!duplicated(dec$correction_id)]
  state <- unname(latest[corr$correction_id])
  verdict <- ifelse(is.na(state), "duplicate_pending",
                    ifelse(state == "accept", "duplicate_accepted", NA_character_))
  keep <- !is.na(verdict)
  stats::setNames(verdict[keep], .correction_signature(corr[keep, , drop = FALSE], key))
}

#' Propose a batch of corrections from a filled template
#'
#' Validates every row of a submission made from [write_corrections_template()] and returns
#' a verdict per row:
#'
#' - `appendable`: the row passed every check below.
#' - `rule_not_fact`: a key or the variable holds a pattern, a comparison, or "all".
#' - `unknown_source`: the source is not declared in `master.yml`.
#' - `invalid_field`: a flag is not 0 or 1 or disagrees with its value, the evidence type
#'   is unknown, or a required field is blank.
#' - `no_variable`: the source has no such column, or the column is a key.
#' - `derived_variable`: the column is the master's, derived from sources; correct the
#'   sources or change the derivation.
#' - `unknown_key`: the key is incomplete, carries another source's key column, or matches
#'   no row.
#' - `ambiguous_key`: the key matches more than one row.
#' - `does_not_cast`: a value is not of the column's type, or the warehouse's cast to the
#'   column's SQL type would round, overflow or truncate it. This last check runs after
#'   the prior check.
#' - `prior_mismatch`: the source no longer holds `expected_prior`.
#' - `duplicate_pending` or `duplicate_accepted`: a correction already makes the same
#'   assertion (same source, key, variable, prior and new value) and is undecided, or its
#'   latest decision is to accept it. A proposed correction leaves the source unchanged
#'   until it is accepted, so without this check the same file submitted twice would be
#'   appended twice. An assertion whose correction was rejected or superseded may be
#'   proposed again.
#'
#' With `dry_run = FALSE`, an all-`appendable` file is appended in one transaction, and a
#' file with any other verdict is refused whole, with nothing written. Values are stored in
#' a canonical text form, so `"30.0"` and `"30"` are the same assertion. A proposed
#' correction applies only once accepted with [decide_corrections()].
#'
#' Output is verdicts and counts, never a key or a value.
#'
#' **Interim.** Superseded by the HVTR registry's intake, which takes over the template
#' and the tables unchanged. Replaces the deprecated [propose_correction()].
#'
#' @param config A `master_config` from [read_master_config()], with `sources`.
#' @param con A DBI connection to the warehouse.
#' @param file Character. The filled template, as CSV.
#' @param dry_run If `TRUE`, the default, validate only.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return Invisibly, a list: `verdicts` (a data frame of `row`, `source`, `verdict`),
#'   `appended` (an integer), `correction_ids` and `file_sha256`.
#'
#' @seealso [write_corrections_template()], [decide_corrections()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   # Synthetic data; no PHI. One source view, its master, and a deployed corrections layer.
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   DBI::dbWriteTable(con, "stg_demo", data.frame(mrn = c("SYN1", "SYN2"), lvef = c(30, NA)))
#'   DBI::dbWriteTable(con, "master_demo", data.frame(mrn = c("SYN1", "SYN2"), lvef = c(30, NA)))
#'   cfg_path <- tempfile(fileext = ".yml")
#'   writeLines(c("name: master_demo", "key: [mrn]", "snapshots: snaps",
#'                "current: x.sas7bdat", "build_program: x.sas",
#'                "sources:", "  stg_demo: {key: [mrn]}", "deciders: [dm_one]"), cfg_path)
#'   cfg <- read_master_config(cfg_path)
#'   sql_dir <- tempfile("sql-")
#'   dir.create(sql_dir)
#'   for (p in generate_corrections_sql(cfg, con, sql_dir, dialect = "duckdb")) {
#'     for (s in strsplit(paste(readLines(p), collapse = "\n"), "\nGO\n?")[[1]]) {
#'       DBI::dbExecute(con, s)
#'     }
#'   }
#'
#'   # A correction to SYN1 and a fill-in for SYN2's missing value.
#'   sub <- tempfile(fileext = ".csv")
#'   utils::write.csv(data.frame(
#'     source = "stg_demo", mrn = c("SYN1", "SYN2"), variable = "lvef",
#'     expected_prior = c("30", ""), expected_prior_missing = c("0", "1"),
#'     new_value = c("35", "40"), new_value_missing = "0", evidence_type = "chart_review",
#'     evidence_ref = "invented note", asserted_by = "reviewer_a"
#'   ), sub, row.names = FALSE)
#'   propose_corrections(cfg, con, sub, dialect = "duckdb")$verdicts   # a dry run
#'   ids <- propose_corrections(cfg, con, sub, dry_run = FALSE,
#'                              dialect = "duckdb")$correction_ids
#'
#'   # A named decider, not the asserter, accepts both; they apply on the next query.
#'   decide_corrections(cfg, con, data.frame(
#'     source = "stg_demo", correction_id = ids, decision = "accept", decided_by = "dm_one",
#'     reason = "chart confirms"
#'   ), dry_run = FALSE, dialect = "duckdb")
#'   DBI::dbGetQuery(con, "SELECT * FROM stg_demo_corrected ORDER BY mrn")
#'
#'   # Upstream fills SYN2 with the same value: the fill-in is retired.
#'   DBI::dbExecute(con, "UPDATE stg_demo SET lvef = 40 WHERE mrn = 'SYN2'")
#'   retire_filled_corrections(cfg, con, "stg_demo", dry_run = FALSE, dialect = "duckdb")
#'
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#'   unlink(c(cfg_path, sub, sql_dir), recursive = TRUE)
#' }
#' }
#'
#' @export
propose_corrections <- function(config, con, file, dry_run = TRUE, dialect = "mssql") {
  tpl <- .read_template(config, file)
  rows <- tpl$rows
  n <- nrow(rows)
  st <- new.env(parent = emptyenv())
  st$verdict <- rep(NA_character_, n)
  # Give rows `i` (logical, or integer positions) verdict `v` unless they already have one,
  # so each row keeps the first verdict it earns.
  set <- function(i, v) {
    if (!is.logical(i)) i <- seq_len(n) %in% i
    st$verdict[i & is.na(st$verdict)] <- v
  }
  keys_all <- unique(unlist(lapply(config$sources, `[[`, "key"), use.names = FALSE))

  # Checks that need no database.
  pattern <- "[*%?<>=,;]|^(all|any)$"
  ruled <- Reduce(`|`, lapply(c(keys_all, "variable"), function(k) {
    !is.na(rows[[k]]) & grepl(pattern, rows[[k]], ignore.case = TRUE)
  }))
  set(ruled, "rule_not_fact")
  set(!rows$source %in% names(config$sources), "unknown_source")
  # A flag is 0 or 1, and a missing value (flag 1) leaves its cell empty. With flag 0 any
  # text is the value, the empty string included.
  flag_ok <- function(f, value) {
    f %in% c("0", "1") & (f %in% "0" | !nzchar(value))
  }
  bad <- is.na(rows$variable) | is.na(rows$evidence_ref) | is.na(rows$asserted_by) |
    !rows$evidence_type %in% setdiff(EVIDENCE_TYPES, "legacy_sas_inline") |
    !flag_ok(rows$expected_prior_missing, rows$expected_prior) |
    !flag_ok(rows$new_value_missing, rows$new_value)
  set(bad, "invalid_field")
  rows$expected_prior[rows$expected_prior_missing %in% "1"] <- NA_character_
  rows$new_value[rows$new_value_missing %in% "1"] <- NA_character_

  master_cols <- names(run_step("read master columns", table_types(con, config$name)))
  st$out_rows <- list()
  now <- Sys.time()
  write_all <- function() {
    for (s in intersect(names(config$sources), rows$source[is.na(st$verdict)])) {
      idx <- which(rows$source == s & is.na(st$verdict))
      key <- config$sources[[s]]$key
      types <- run_step("read source columns", table_types(con, s))
      proto <- run_step("read source types", DBI::dbGetQuery(
        con, paste("SELECT * FROM", quoter(dialect)(s), "WHERE 1 = 0")
      ))
      var <- rows$variable[idx]
      in_source <- var %in% setdiff(names(types), key)
      set(idx[!in_source & var %in% setdiff(master_cols, names(types))], "derived_variable")
      set(idx[!in_source], "no_variable")

      # The key: exactly this source's columns, each parsing to its column's type.
      other <- setdiff(keys_all, key)
      typed <- lapply(key, function(k) {
        cls <- class(proto[[k]])[[1]]
        vapply(rows[[k]][idx], function(x) {
          if (is.na(x)) return(NA_character_)
          value_text(.parse_submitted(x, cls))
        }, character(1), USE.NAMES = FALSE)
      })
      names(typed) <- key
      # The key must survive the warehouse's cast to the key column unchanged, as values
      # must: an integer key `1.2` would load as `1` and name another row.
      for (k in key) {
        j <- which(!is.na(typed[[k]]))
        typed[[k]][j[!.casts_losslessly(con, typed[[k]][j], types[[k]])]] <- NA_character_
      }
      incomplete <- Reduce(`|`, lapply(typed, is.na)) |
        (if (length(other)) Reduce(`|`, lapply(other, function(k) !is.na(rows[[k]][idx])))
         else FALSE)
      set(idx[incomplete], "unknown_key")
      live <- idx[is.na(st$verdict[idx])]
      if (!length(live)) next

      tmp <- .intake_temp(dialect, types[key])
      run_step("create intake table", DBI::dbExecute(con, tmp$create))
      run_step("load intake keys", DBI::dbExecute(
        con, sprintf("INSERT INTO %s VALUES (%s)", tmp$name,
                     paste(rep("?", length(key) + 1L), collapse = ", ")),
        params = c(list(live), lapply(key, function(k) {
          parse_value_vec(typed[[k]][match(live, idx)], class(proto[[k]])[[1]])
        }))
      ))
      wanted <- unique(rows$variable[live])
      found <- run_step("look up source rows", DBI::dbGetQuery(
        con, .intake_lookup_sql(tmp$name, s, key, types, wanted, dialect)
      ))
      run_step("drop intake table", DBI::dbExecute(con, paste("DROP TABLE", tmp$name)))
      hits <- tabulate(match(found$intake_row_, live), nbins = length(live))
      set(live[hits == 0L], "unknown_key")
      set(live[hits > 1L], "ambiguous_key")
      held <- run_step("read held corrections", .held_corrections(con, s, key, dialect))

      for (i in live[hits == 1L]) {
        v <- rows$variable[[i]]
        cls <- class(proto[[v]])[[1]]
        cur <- found[[v]][[match(i, found$intake_row_)]]
        parsed <- function(x) .parse_submitted(x, cls)
        prior <- if (rows$expected_prior_missing[[i]] == "1") NA else
          parsed(rows$expected_prior[[i]])
        new <- if (rows$new_value_missing[[i]] == "1") NA else parsed(rows$new_value[[i]])
        if ((rows$expected_prior_missing[[i]] == "0" && is.na(prior)) ||
              (rows$new_value_missing[[i]] == "0" && is.na(new))) {
          set(i, "does_not_cast")
          next
        }
        same <- if (is.na(prior)) is.na(cur) else
          !is.na(cur) && identical(value_text(cur), value_text(prior))
        if (!same) {
          set(i, "prior_mismatch")
          next
        }
        r <- data.frame(correction_id = NA_character_, source = s,
                        stringsAsFactors = FALSE)
        for (k in key) r[[k]] <- parse_value(typed[[k]][[match(i, idx)]],
                                             class(proto[[k]])[[1]])
        r$variable <- v
        r$expected_prior <- if (is.na(prior)) NA_character_ else value_text(prior)
        r$expected_prior_missing <- as.integer(rows$expected_prior_missing[[i]])
        r$new_value <- if (is.na(new)) NA_character_ else value_text(new)
        r$new_value_missing <- as.integer(rows$new_value_missing[[i]])
        r$evidence_type <- rows$evidence_type[[i]]
        r$evidence_ref <- rows$evidence_ref[[i]]
        r$asserted_by <- rows$asserted_by[[i]]
        r$asserted_on <- now
        r$correction_id <- .short_id("c", list(tpl$sha256, i, format(now, "%Y-%m-%d %H:%M:%OS6")))
        # A pending correction leaves the source unchanged, so a resubmitted row passes the
        # prior check again; it is refused here instead of being appended a second time.
        dup <- held[.correction_signature(r, key)]
        if (!is.na(dup)) {
          set(i, dup)
          next
        }
        r$.row <- i
        st$out_rows[[length(st$out_rows) + 1L]] <- r
      }

      # The warehouse's own cast decides, through the column's SQL type, so a value R
      # accepts but the column would round, overflow or truncate is refused here, not
      # discovered as a silently different value in the corrected view.
      mine <- st$out_rows[vapply(st$out_rows, `[[`, character(1), "source") == s]
      for (v in unique(vapply(mine, `[[`, character(1), "variable"))) {
        rv <- mine[vapply(mine, `[[`, character(1), "variable") == v]
        texts <- c(vapply(rv, `[[`, character(1), "expected_prior"),
                   vapply(rv, `[[`, character(1), "new_value"))
        rid <- rep(vapply(rv, `[[`, integer(1), ".row"), 2L)
        keep <- !is.na(texts)  # a missing-to-missing row has nothing to cast
        ok <- .casts_losslessly(con, texts[keep], types[[v]])
        set(unique(rid[keep][!ok]), "does_not_cast")
      }
      set(vapply(mine, `[[`, integer(1), ".row"), "appendable")
    }
    row_of <- vapply(st$out_rows, `[[`, integer(1), ".row")
    st$out_rows <- st$out_rows[st$verdict[row_of] == "appendable"]
    st$out_rows <- lapply(st$out_rows, function(r) r[setdiff(names(r), ".row")])
    stopifnot(!anyNA(st$verdict))
    if (dry_run || any(st$verdict != "appendable")) return(invisible(NULL))
    for (s in unique(vapply(st$out_rows, `[[`, character(1), "source"))) {
      from_s <- vapply(st$out_rows, `[[`, character(1), "source") == s
      batch <- do.call(rbind, st$out_rows[from_s])
      run_step("append corrections",
               DBI::dbAppendTable(con, .source_tables(s)$corrections, batch))
    }
    invisible(NULL)
  }
  .with_snapshot_txn(con, dialect, write_all())

  verdicts <- data.frame(row = seq_len(n), source = rows$source, verdict = st$verdict,
                         stringsAsFactors = FALSE)
  counts <- table(st$verdict)
  .hvti_inform("propose_corrections(): ",
               paste(sprintf("%s %d", names(counts), counts), collapse = ", "), ".")
  if (!dry_run && any(st$verdict != "appendable")) {
    .abort("corrections_refused", "propose_corrections(): the file was refused whole and ",
           "nothing was written: ", sum(st$verdict != "appendable"), " of ", n,
           " row(s) are not appendable. See the dry run's verdicts.")
  }
  ids <- vapply(st$out_rows, `[[`, character(1), "correction_id")
  invisible(list(verdicts = verdicts,
                 appended = if (dry_run) 0L else length(ids),
                 correction_ids = if (dry_run) character() else ids,
                 file_sha256 = tpl$sha256))
}

#' Which canonical texts the warehouse casts to a SQL type without loss
#'
#' Each text goes through `TRY_CAST(... AS type)` in the warehouse, the cast the generated
#' views use. A text passes when the cast succeeds and the result's canonical text is the
#' text itself: `1.239` into `decimal(10,2)` comes back `1.24` and fails, as does an
#' overflow (`NULL`) or a truncation. Batches of 500 keep under SQL Server's 2,100
#' parameters.
#'
#' @param con A DBI connection.
#' @param texts Character. Canonical texts, none missing.
#' @param type Character. The column's SQL type, from `table_types()`.
#'
#' @return A logical vector the length of `texts`.
#'
#' @keywords internal
#' @noRd
.casts_losslessly <- function(con, texts, type) {
  ok <- rep(FALSE, length(texts))
  if (!length(texts)) return(ok)  # seq(1, 0, by = 500) would error
  for (start in seq(1L, length(texts), by = 500L)) {
    i <- start:min(start + 499L, length(texts))
    params <- vector("list", 2L * length(i))
    params[c(TRUE, FALSE)] <- as.list(i)
    params[c(FALSE, TRUE)] <- as.list(texts[i])
    got <- run_step("check casts", DBI::dbGetQuery(con, sprintf(
      "SELECT i, TRY_CAST(txt AS %s) AS x FROM (VALUES %s) AS t(i, txt)", type,
      paste(rep("(?, ?)", length(i)), collapse = ", ")
    ), params = params))
    x <- got$x[match(i, got$i)]
    ok[i] <- vapply(seq_along(i), function(j) {
      !is.na(x[[j]]) && identical(value_text(x[[j]]), texts[i][[j]])
    }, logical(1))
  }
  ok
}

#' Parse a submitted key or value, accepting only the whole of a supported form
#'
#' `parse_value()` is lenient: `as.Date()` and `as.POSIXct()` keep a valid prefix and drop
#' the rest, and `as.numeric()` reads hexadecimal. At intake that would let
#' `2020-01-01junk` name the row keyed `2020-01-01`, so the raw text must first match its
#' class's form in full: `YYYY-MM-DD` for a date, the same with `HH:MM`, optional seconds
#' and fraction for a timestamp, and a plain decimal (optionally with an exponent) for a
#' number. Character and logical text go to `parse_value()` unchanged.
#'
#' @param text Character. One submitted text, not `NA`.
#' @param r_class Character. The column's R class.
#'
#' @return The parsed value, or `NA` when the text is not a whole supported form or does
#'   not parse.
#'
#' @keywords internal
#' @noRd
.parse_submitted <- function(text, r_class) {
  form <- switch(r_class,
                 Date = "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
                 POSIXct = paste0("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}",
                                  "(:[0-9]{2}([.][0-9]+)?)?$"),
                 numeric = , integer = , haven_labelled =
                   "^[+-]?([0-9]+[.]?[0-9]*|[.][0-9]+)([eE][+-]?[0-9]+)?$",
                 NULL)
  if (!is.null(form) && !grepl(form, text)) return(NA)
  tryCatch(parse_value(text, r_class), error = function(e) NA)
}

#' Parse a vector of canonical texts to one class
#'
#' @param x Character. Canonical texts, possibly `NA`.
#' @param r_class Character. The target class.
#'
#' @return A vector of class `r_class`.
#'
#' @keywords internal
#' @noRd
parse_value_vec <- function(x, r_class) {
  out <- lapply(x, parse_value, r_class = r_class)
  do.call(c, out)
}

#' Decide a batch of corrections
#'
#' Records `accept`, `reject`, `supersede` or `bake` for each row of `decisions`. A
#' correction applies while its latest decision is `accept`. When two accepted corrections
#' to a cell disagree, neither applies (G1): supersede the wrong one to settle the cell.
#'
#' Each row gets one of these verdicts:
#'
#' - `recordable`: the row passed every check below.
#' - `unknown_source`: the source is not declared in `master.yml`.
#' - `repeated_correction`: the batch decides the same correction more than once. Every row
#'   of a batch shares one `decided_on`, so their order would be arbitrary; decide it again
#'   in a later batch instead.
#' - `unknown_correction`: the source has no correction with that id.
#' - `invalid_decision`: the decision is not one of the four.
#' - `not_decider`: the decider is not listed in `master.yml`'s `deciders`.
#' - `self_accepted`: the decider asserted the correction (G2).
#'
#' With `dry_run = FALSE`, an all-`recordable` batch is recorded in one transaction, and a
#' batch with any other verdict is refused whole.
#'
#' **Interim.** Superseded by the HVTR registry. Replaces the deprecated
#' [decide_correction()].
#'
#' @param config A `master_config` from [read_master_config()], with `sources` and
#'   `deciders`.
#' @param con A DBI connection to the warehouse.
#' @param decisions A data frame with `source`, `correction_id`, `decision`, `decided_by`
#'   and optionally `reason`.
#' @param dry_run If `TRUE`, the default, validate only.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return Invisibly, a list: `verdicts` (a data frame of `row`, `verdict`) and
#'   `recorded` (an integer).
#'
#' @seealso [propose_corrections()], [retire_filled_corrections()]
#'
#' @inherit propose_corrections examples
#'
#' @export
decide_corrections <- function(config, con, decisions, dry_run = TRUE, dialect = "mssql") {
  if (!length(config$deciders)) {
    .abort("no_deciders", "decide_corrections(): master.yml names no deciders.")
  }
  need <- c("source", "correction_id", "decision", "decided_by")
  if (!is.data.frame(decisions) || !all(need %in% names(decisions))) {
    .abort("decisions_columns", "decide_corrections(): `decisions` needs ",
           paste(need, collapse = ", "), ".")
  }
  if (!"reason" %in% names(decisions)) decisions$reason <- NA_character_
  n <- nrow(decisions)
  st <- new.env(parent = emptyenv())
  st$verdict <- rep(NA_character_, n)
  set <- function(i, v) {
    if (!is.logical(i)) i <- seq_len(n) %in% i
    st$verdict[i & is.na(st$verdict)] <- v
  }
  set(!decisions$source %in% names(config$sources), "unknown_source")
  # One correction, one decision per batch: rows sharing a decided_on would be ordered by
  # their hash-derived decision_id, not by intent.
  dup <- paste(decisions$source, decisions$correction_id, sep = "\r")
  set(dup %in% dup[duplicated(dup)], "repeated_correction")
  q <- quoter(dialect)
  now <- Sys.time()
  record <- function() {
    for (s in intersect(names(config$sources), decisions$source)) {
      idx <- which(decisions$source == s)
      ids <- unique(decisions$correction_id[idx])
      # The R match() below makes the comparison exact; a very large batch can hit SQL
      # Server's 2100-parameter limit, which fails loud and rolls back.
      known <- run_step("look up corrections", DBI::dbGetQuery(con, sprintf(
        "SELECT correction_id, asserted_by FROM %s WHERE correction_id IN (%s)",
        q(.source_tables(s)$corrections), paste(rep("?", length(ids)), collapse = ", ")
      ), params = as.list(ids)))
      asserter <- known$asserted_by[match(decisions$correction_id[idx], known$correction_id)]
      set(idx[is.na(asserter)], "unknown_correction")
      set(idx[!decisions$decision[idx] %in% DECISIONS], "invalid_decision")
      who <- function(x) tolower(trimws(x))
      set(idx[!who(decisions$decided_by[idx]) %in% who(config$deciders)], "not_decider")
      set(idx[!is.na(asserter) & who(asserter) == who(decisions$decided_by[idx])],
          "self_accepted")
      set(idx, "recordable")
    }
    if (dry_run || any(st$verdict != "recordable")) return(invisible(NULL))
    for (s in unique(decisions$source)) {
      idx <- which(decisions$source == s)
      rows <- data.frame(
        decision_id = vapply(idx, function(i) {
          .short_id("d", list(decisions$correction_id[[i]], decisions$decision[[i]],
                              decisions$decided_by[[i]], i,
                              format(now, "%Y-%m-%d %H:%M:%OS6")))
        }, character(1)),
        correction_id = decisions$correction_id[idx], decision = decisions$decision[idx],
        decided_by = decisions$decided_by[idx], decided_on = now,
        reason = as.character(decisions$reason[idx]), stringsAsFactors = FALSE
      )
      run_step("append decisions",
               DBI::dbAppendTable(con, .source_tables(s)$decisions, rows))
    }
    invisible(NULL)
  }
  .with_snapshot_txn(con, dialect, record())
  counts <- table(st$verdict)
  .hvti_inform("decide_corrections(): ",
               paste(sprintf("%s %d", names(counts), counts), collapse = ", "), ".")
  if (!dry_run && any(st$verdict != "recordable")) {
    .abort("decisions_refused", "decide_corrections(): the batch was refused whole and ",
           "nothing was written: ", sum(st$verdict != "recordable"), " of ", n,
           " row(s) are not recordable.")
  }
  invisible(list(verdicts = data.frame(row = seq_len(n), verdict = st$verdict,
                                       stringsAsFactors = FALSE),
                 recorded = if (dry_run) 0L else n))
}

#' Retire fill-ins that upstream has caught up with
#'
#' A correction that filled a missing source value goes stale as `filled_upstream_agrees`
#' once the source holds that same value (G7). This records a `bake` decision for each
#' such correction, by the reserved decider `"filled_upstream"`, so it leaves the stale
#' view. Schedule it beside the data load. A fill-in where upstream holds a different
#' value is a conflict and is never retired here.
#'
#' **Interim.** Superseded by the HVTR registry.
#'
#' @param config A `master_config` from [read_master_config()], with `sources`.
#' @param con A DBI connection to the warehouse.
#' @param source Character. A declared source.
#' @param dry_run If `TRUE`, the default, list what would be retired.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return Invisibly, a list: `correction_ids` and `recorded` (an integer).
#'
#' @seealso [decide_corrections()]
#'
#' @inherit propose_corrections examples
#'
#' @export
retire_filled_corrections <- function(config, con, source, dry_run = TRUE,
                                      dialect = "mssql") {
  if (!source %in% names(config$sources)) {
    .abort("unknown_source", "retire_filled_corrections(): ", source,
           " is not declared in master.yml.")
  }
  tabs <- .source_tables(source)
  q <- quoter(dialect)
  now <- Sys.time()
  retire <- function() {
    ids <- run_step("read stale fill-ins", DBI::dbGetQuery(con, paste(
      "SELECT correction_id FROM", q(tabs$stale),
      "WHERE reason = 'filled_upstream_agrees'"
    )))$correction_id
    if (!dry_run && length(ids)) {
      rows <- data.frame(
        decision_id = vapply(ids, function(id) {
          .short_id("d", list(id, "bake", FILLED_UPSTREAM_DECIDER,
                              format(now, "%Y-%m-%d %H:%M:%OS6")))
        }, character(1)),
        correction_id = ids, decision = "bake", decided_by = FILLED_UPSTREAM_DECIDER,
        decided_on = now, reason = "The source now holds the corrected value.",
        stringsAsFactors = FALSE
      )
      run_step("append bake decisions", DBI::dbAppendTable(con, tabs$decisions, rows))
    }
    ids
  }
  ids <- .with_snapshot_txn(con, dialect, retire())
  .hvti_inform("retire_filled_corrections(): ", length(ids), " fill-in(s) ",
               if (dry_run) "would be retired." else "retired.")
  invisible(list(correction_ids = ids, recorded = if (dry_run) 0L else length(ids)))
}
