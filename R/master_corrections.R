# master_corrections.R
#
# The corrections API: backfilling a master's inline SAS fixes, and proposing
# and deciding corrections by hand. No message here ever carries a key or a
# value: output is counts, verdicts, column names, correction ids and line
# numbers.

EVIDENCE_TYPES <- c( # nolint: object_name_linter. Legacy constant name, preserved deliberately.
  "chart_review", "source_document", "investigator_return",
  "legacy_sas_inline"
)
DECISIONS <- c("accept", "reject", "supersede", "bake") # nolint: object_name_linter.

#' A value's checked text form for a corrections column
#'
#' Refuses a factor outright, then round-trips the value through
#' `value_text()` and `parse_value()` and refuses anything that does not come
#' back equal to itself.
#'
#' @param x A length-one value, or `NA`.
#' @param r_class Character. The target R class from the master's metadata.
#' @param what Character. The argument's name, for the error message.
#'
#' @return A length-one character, or `NA_character_` when `x` is missing.
#'
#' @keywords internal
#' @noRd
.checked_text <- function(x, r_class, what) {
  if (length(x) != 1L) stop("'", what, "' must be a single value.", call. = FALSE)
  if (is.na(x)) {
    return(NA_character_)
  }
  if (is.factor(x)) {
    stop("'", what, "' does not cast to the variable's type (", r_class, ").",
      call. = FALSE
    )
  }
  text <- value_text(x)
  back <- parse_value(text, r_class)
  if (is.na(back) || !isTRUE(back == x)) {
    stop("'", what, "' does not cast to the variable's type (", r_class, ").",
      call. = FALSE
    )
  }
  text
}

#' Backfill a master's corrections from its SAS build, and regenerate its view
#'
#' Creates the master's corrections and decisions tables if absent, reads the
#' inline patient-level fixes from the SAS build program, records each one that
#' resolves to exactly one record as a correction with an unknown prior and a
#' `bake` decision (present in the snapshot, not applied), and regenerates the
#' view and its stale view. Fixes that change a key column, match no record,
#' match several, or cannot be read are reported by reason and line number and
#' never recorded.
#'
#' Requires a passing parity record from [lift_master()]. A dry run, the
#' default, parses and resolves and writes nothing.
#'
#' @param config A `master_config` from [read_master_config()].
#' @param con A DBI connection.
#' @param dry_run If `TRUE`, the default, report what would be recorded.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return Invisibly, a list of counts: `dry_run`, `facts`, `resolved`,
#'   `unresolved`, `appended` and `stale`.
#'
#' @seealso [propose_correction()], [decide_correction()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE) &&
#'     requireNamespace("arrow", quietly = TRUE) &&
#'     requireNamespace("jsonlite", quietly = TRUE) &&
#'     requireNamespace("tidyselect", quietly = TRUE) &&
#'     requireNamespace("dplyr", quietly = TRUE) &&
#'     requireNamespace("withr", quietly = TRUE) &&
#'     requireNamespace("digest", quietly = TRUE)) {
#'   dir <- tempfile("backfill")
#'   dir.create(dir)
#'   pq <- file.path(dir, "built_demo.parquet")
#'   arrow::write_parquet(data.frame(id = c("K1", "K2"), age = c(60, 61)), pq)
#'   jsonlite::write_json(
#'     list(parquet_sha256 = digest::digest(pq, algo = "sha256", file = TRUE),
#'          columns = list(list(variable = "id", r_class = "character"),
#'                         list(variable = "age", r_class = "numeric"))),
#'     sub("\\.parquet$", ".meta.json", pq), auto_unbox = TRUE)
#'   writeLines(c("data m; set base;", "if id = 'K1' then age = 60;", "run;"),
#'              file.path(dir, "bd.sas"))
#'   cfg_path <- file.path(dir, "master.yml")
#'   writeLines(c("name: master_demo", "key: [id]", paste0("snapshots: ", dir),
#'                "current: built_demo.sas7bdat",
#'                paste0("build_program: ", file.path(dir, "bd.sas"))), cfg_path)
#'   cfg <- read_master_config(cfg_path)
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   lift_master(cfg, con, pq, dry_run = FALSE, dialect = "duckdb")
#'   backfill_corrections(cfg, con, dry_run = FALSE, dialect = "duckdb")
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#' }
#' }
#'
#' @export
backfill_corrections <- function(config, con, dry_run = TRUE, dialect = "mssql") {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required.", call. = FALSE)
  }
  tabs <- .master_tables(config)
  base <- .current_base(con, config, dialect)
  q <- quoter(dialect)
  meta <- DBI::dbReadTable(con, tabs$meta)
  types <- table_types(con, base)

  parsed <- parse_legacy_facts(readLines(config[["build_program"]], warn = FALSE),
    key_var = config[["key"]][[1]]
  )
  alt_cols <- intersect(unique(unlist(config[["alt_keys"]], use.names = FALSE)), names(types))
  base_keys <- DBI::dbGetQuery(con, sprintf(
    "SELECT %s FROM %s",
    paste(q(c(config[["key"]], alt_cols)), collapse = ", "), q(base)
  ))
  rows <- legacy_rows(
    parsed$facts, base_keys, config[["key"]], config[["name"]], meta,
    basename(config[["build_program"]])
  )
  n_res <- NROW(rows$corrections)
  message(
    "legacy: ", nrow(parsed$facts), " facts parsed; ", n_res, " resolved; ",
    nrow(rows$unresolved), " unresolved"
  )
  if (nrow(rows$unresolved)) {
    tab <- table(rows$unresolved$reason)
    message("  unresolved by reason: ", paste(names(tab), tab, sep = " ", collapse = ", "))
    message("  at lines: ", paste(sort(unique(rows$unresolved$line)), collapse = ", "))
  }
  if (length(parsed$unparsed)) {
    message("  unparsed statements at lines: ", paste(parsed$unparsed, collapse = ", "))
  }
  out <- list(
    dry_run = dry_run, facts = nrow(parsed$facts), resolved = n_res,
    unresolved = nrow(rows$unresolved), appended = 0L, stale = NA_integer_
  )
  if (dry_run) {
    message("dry run: nothing written")
    return(invisible(out))
  }

  if (!DBI::dbExistsTable(con, tabs$corrections)) {
    alt_cols <- intersect(unique(unlist(config[["alt_keys"]], use.names = FALSE)), names(types))
    ddl <- corrections_ddl(tabs$corrections, tabs$decisions,
      key_types = types[config[["key"]]],
      alt_key_types = if (length(alt_cols)) types[alt_cols] else NULL,
      dialect = dialect
    )
    run_step("create corrections table", DBI::dbExecute(con, ddl[["corrections"]]))
    run_step("create decisions table", DBI::dbExecute(con, ddl[["decisions"]]))
  }
  r <- run_step(
    "record legacy facts",
    record_legacy_facts(con, rows, tabs$corrections, tabs$decisions, dialect)
  )
  .publish_views(config, con, base, dialect)
  out$appended <- as.integer(r$appended)
  out$stale <- as.integer(DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS n FROM %s",
    q(tabs$stale)
  ))$n)
  message("recorded ", out$appended, "; ", out$stale, " stale corrections")
  invisible(out)
}

#' Propose a correction to a single cell of a master
#'
#' Validates the proposal, then appends it to the master's corrections table
#' with no decision, so it is not applied until [decide_correction()] accepts
#' it. `dry_run = TRUE` validates and returns the row that would be written,
#' without writing it. A single correction is written by default because
#' proposing one is a deliberate act. No message ever carries a key or a
#' value: an unmatched or ambiguous key is reported by count only, and an
#' over-width or uncastable value is reported by column and limit only.
#'
#' By default, `key_values` must name exactly the master's primary key
#' columns, each a single non-missing value. When `alt_key` is given instead,
#' `key_values` must name exactly that alternate key's columns, none may be
#' missing, and it must match exactly one row in the master's current base
#' table; the correction is then stored against that row's primary key.
#' Either way, every alternate-key column present in the base table is filled
#' from that row and carried on the correction for reference; `variable` may
#' not be the primary key or any alternate key's column. A failing warehouse
#' call is reported by step, with the driver's message withheld, because it
#' can quote a data value.
#'
#' @details Requires the master's corrections tables, which
#'   [backfill_corrections()] creates.
#'
#' @param config A `master_config` from [read_master_config()].
#' @param con A DBI connection.
#' @param key_values A named list of key values identifying the record: the
#'   primary key by default, or `alt_key`'s columns when `alt_key` is given.
#' @param variable Character. The column to correct; must not be a key or
#'   alternate-key column.
#' @param expected_prior The value the record is expected to currently hold,
#'   or `NA` when it is expected to be missing.
#' @param new_value The corrected value, or `NA` to correct to missing.
#' @param evidence_type Character. One of `EVIDENCE_TYPES`.
#' @param evidence_ref Character. A reference to the evidence, such as a
#'   document id; never a data value.
#' @param asserted_by Character. Who is asserting the correction.
#' @param alt_key Character, or `NULL`, the default. The name of an alternate
#'   key in `config$alt_keys` that `key_values` matches instead of the
#'   primary key.
#' @param dry_run If `TRUE`, validate and return the row without writing it.
#'   The default, `FALSE`, writes it.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return Invisibly, a list with `verdict` (`"appended"`, or `"validated"` on
#'   a dry run), `correction_id`, `new_variable` (whether this is the first
#'   correction to `variable`, meaning the view should be regenerated), and
#'   `row` (the one-row data frame that was or would be appended).
#'
#' @seealso [backfill_corrections()], [decide_correction()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE) &&
#'     requireNamespace("arrow", quietly = TRUE) &&
#'     requireNamespace("jsonlite", quietly = TRUE) &&
#'     requireNamespace("tidyselect", quietly = TRUE) &&
#'     requireNamespace("dplyr", quietly = TRUE) &&
#'     requireNamespace("withr", quietly = TRUE) &&
#'     requireNamespace("digest", quietly = TRUE)) {
#'   dir <- tempfile("propose")
#'   dir.create(dir)
#'   pq <- file.path(dir, "built_demo.parquet")
#'   arrow::write_parquet(data.frame(id = c("K1", "K2"), age = c(60, 61)), pq)
#'   jsonlite::write_json(
#'     list(parquet_sha256 = digest::digest(pq, algo = "sha256", file = TRUE),
#'          columns = list(list(variable = "id", r_class = "character"),
#'                         list(variable = "age", r_class = "numeric"))),
#'     sub("\\.parquet$", ".meta.json", pq), auto_unbox = TRUE)
#'   writeLines("data m; run;", file.path(dir, "bd.sas"))
#'   cfg_path <- file.path(dir, "master.yml")
#'   writeLines(c("name: master_demo", "key: [id]", paste0("snapshots: ", dir),
#'                "current: built_demo.sas7bdat",
#'                paste0("build_program: ", file.path(dir, "bd.sas"))), cfg_path)
#'   cfg <- read_master_config(cfg_path)
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   lift_master(cfg, con, pq, dry_run = FALSE, dialect = "duckdb")
#'   backfill_corrections(cfg, con, dry_run = FALSE, dialect = "duckdb")
#'   propose_correction(cfg, con, key_values = list(id = "K1"), variable = "age",
#'                      expected_prior = 60, new_value = 61, evidence_type = "chart_review",
#'                      evidence_ref = "invented", asserted_by = "tester", dialect = "duckdb")
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#' }
#' }
#'
#' @export
propose_correction <- function(config, con, key_values, variable, expected_prior, new_value,
                               evidence_type, evidence_ref, asserted_by, alt_key = NULL,
                               dry_run = FALSE, dialect = "mssql") {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required.", call. = FALSE)
  }
  q <- quoter(dialect)
  tabs <- .master_tables(config)
  base <- .current_base(con, config, dialect)
  meta <- run_step("read metadata", DBI::dbReadTable(con, tabs$meta))
  types <- run_step("read column types", table_types(con, base))
  widths <- .char_widths(types)
  alt_cols <- intersect(unique(unlist(config[["alt_keys"]], use.names = FALSE)), names(types))

  if (!is.null(alt_key)) {
    cols <- config[["alt_keys"]][[alt_key]]
    if (is.null(cols)) stop("Unknown alternate key '", alt_key, "'.", call. = FALSE)
    if (!setequal(names(key_values), cols)) {
      stop("'key_values' must name exactly the columns of alternate key '", alt_key, "'.",
        call. = FALSE
      )
    }
    if (any(vapply(key_values, function(v) length(v) != 1L || is.na(v), logical(1)))) {
      stop("Alternate key '", alt_key, "' has a null part, which never matches.",
        call. = FALSE
      )
    }
    where <- paste(sprintf("%s = ?", q(cols)), collapse = " AND ")
    hits <- run_step("alternate key lookup", DBI::dbGetQuery(con, sprintf(
      "SELECT %s FROM %s WHERE %s",
      paste(q(config[["key"]]), collapse = ", "), q(base),
      where
    ),
    params = unname(key_values[cols])
    ))
    if (nrow(hits) != 1L) {
      stop("Alternate key '", alt_key, "' matched ", nrow(hits), " rows in ", base,
        "; expected exactly 1.",
        call. = FALSE
      )
    }
    key_values <- as.list(hits[1, config[["key"]], drop = FALSE])
  } else {
    if (!setequal(names(key_values), config[["key"]])) {
      stop("'key_values' must name exactly the primary key columns: ",
        paste(config[["key"]], collapse = ", "), ".",
        call. = FALSE
      )
    }
    if (any(vapply(key_values, function(v) length(v) != 1L || is.na(v), logical(1)))) {
      stop("'key_values' must name exactly the primary key columns: ",
        paste(config[["key"]], collapse = ", "), ".",
        call. = FALSE
      )
    }
  }

  if (!variable %in% meta$variable) {
    stop("Variable is not in the master's metadata: ", variable, call. = FALSE)
  }
  if (variable %in% config[["key"]] || variable %in% alt_cols) {
    stop("A key or alternate-key column cannot be corrected through this path: ", variable,
      call. = FALSE
    )
  }
  if (!evidence_type %in% EVIDENCE_TYPES) {
    stop("Unknown evidence type '", evidence_type, "'. Expected one of: ",
      paste(EVIDENCE_TYPES, collapse = ", "),
      call. = FALSE
    )
  }
  r_class <- meta$r_class[match(variable, meta$variable)]
  prior_text <- .checked_text(expected_prior, r_class, "expected_prior")
  new_text <- .checked_text(new_value, r_class, "new_value")
  if (!is.null(widths) && identical(r_class, "character") && !is.na(new_text) &&
        variable %in% names(widths) && nchar(new_text) > widths[[variable]]) {
    stop("'new_value' is longer than the column allows (", widths[[variable]],
      " characters).",
      call. = FALSE
    )
  }

  where <- paste(sprintf("%s = ?", q(names(key_values))), collapse = " AND ")
  n <- run_step("key lookup", DBI::dbGetQuery(
    con, sprintf("SELECT COUNT(*) AS n FROM %s WHERE %s", q(base), where),
    params = unname(key_values)
  ))$n
  if (!identical(as.integer(n), 1L)) {
    stop("The key matched ", n, " rows in ", base, "; expected exactly 1.", call. = FALSE)
  }
  alt_values <- if (length(alt_cols)) {
    hit <- run_step("alternate-key column lookup", DBI::dbGetQuery(
      con, sprintf("SELECT %s FROM %s WHERE %s", paste(q(alt_cols), collapse = ", "),
                   q(base), where),
      params = unname(key_values)
    ))
    as.list(hit[1, alt_cols, drop = FALSE])
  } else {
    list()
  }
  seen <- run_step("check existing corrections", DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS n FROM %s WHERE master = ? AND variable = ?",
    q(tabs$corrections)
  ), params = list(config[["name"]], variable)))$n

  now <- Sys.time()
  id <- paste0("c", substr(digest::digest(
    list(
      config[["name"]], key_values, variable, prior_text, new_text, asserted_by,
      format(now, "%Y-%m-%d %H:%M:%OS6")
    ),
    algo = "sha1"
  ), 1, 16))
  n_id <- run_step("check correction id", DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS n FROM %s WHERE correction_id = ?",
    q(tabs$corrections)
  ), params = list(id)))$n
  if (as.integer(n_id) > 0L) {
    stop("The generated correction id collides with an existing row; ",
      "retry the proposal.",
      call. = FALSE
    )
  }
  row <- data.frame(correction_id = id, master = config[["name"]], stringsAsFactors = FALSE)
  for (k in names(key_values)) row[[k]] <- key_values[[k]]
  for (k in names(alt_values)) row[[k]] <- alt_values[[k]]
  row$variable <- variable
  row$expected_prior <- prior_text
  row$expected_prior_missing <- as.integer(is.na(expected_prior))
  row$new_value <- new_text
  row$new_value_missing <- as.integer(is.na(new_value))
  row$evidence_type <- evidence_type
  row$evidence_ref <- evidence_ref
  row$asserted_by <- asserted_by
  row$asserted_on <- now

  new_variable <- as.integer(seen) == 0L
  if (dry_run) {
    message("Correction ", id, " validated; nothing written.")
    return(invisible(list(
      verdict = "validated", correction_id = id,
      new_variable = new_variable, row = row
    )))
  }
  run_step("append correction", DBI::dbAppendTable(con, tabs$corrections, row))
  message(
    "Correction ", id, " appended.",
    if (new_variable) " First correction to this variable: regenerate the view."
  )
  invisible(list(
    verdict = "appended", correction_id = id, new_variable = new_variable,
    row = row
  ))
}

#' Decide a correction: accept, reject, supersede or bake it
#'
#' Records the decision in the master's decisions table; the correction
#' applies only when its latest decision is `"accept"`. `dry_run = TRUE`
#' validates and returns the row that would be written, without writing it.
#'
#' @details Requires the master's corrections tables, which
#'   [backfill_corrections()] creates.
#'
#' @param config A `master_config` from [read_master_config()].
#' @param con A DBI connection.
#' @param correction_id Character. The correction being decided.
#' @param decision Character. One of `DECISIONS`.
#' @param decided_by Character. Who is deciding.
#' @param reason Character, or `NA_character_`, the default. A note on the
#'   decision.
#' @param dry_run If `TRUE`, validate and return the row without writing it.
#'   The default, `FALSE`, writes it.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return Invisibly, a list with `verdict` (`"recorded"`, or `"validated"`
#'   on a dry run), `decision_id`, and `row` (the one-row data frame that was
#'   or would be appended).
#'
#' @seealso [backfill_corrections()], [propose_correction()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE) &&
#'     requireNamespace("arrow", quietly = TRUE) &&
#'     requireNamespace("jsonlite", quietly = TRUE) &&
#'     requireNamespace("tidyselect", quietly = TRUE) &&
#'     requireNamespace("dplyr", quietly = TRUE) &&
#'     requireNamespace("withr", quietly = TRUE) &&
#'     requireNamespace("digest", quietly = TRUE)) {
#'   dir <- tempfile("decide")
#'   dir.create(dir)
#'   pq <- file.path(dir, "built_demo.parquet")
#'   arrow::write_parquet(data.frame(id = c("K1", "K2"), age = c(60, 61)), pq)
#'   jsonlite::write_json(
#'     list(parquet_sha256 = digest::digest(pq, algo = "sha256", file = TRUE),
#'          columns = list(list(variable = "id", r_class = "character"),
#'                         list(variable = "age", r_class = "numeric"))),
#'     sub("\\.parquet$", ".meta.json", pq), auto_unbox = TRUE)
#'   writeLines("data m; run;", file.path(dir, "bd.sas"))
#'   cfg_path <- file.path(dir, "master.yml")
#'   writeLines(c("name: master_demo", "key: [id]", paste0("snapshots: ", dir),
#'                "current: built_demo.sas7bdat",
#'                paste0("build_program: ", file.path(dir, "bd.sas"))), cfg_path)
#'   cfg <- read_master_config(cfg_path)
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   lift_master(cfg, con, pq, dry_run = FALSE, dialect = "duckdb")
#'   backfill_corrections(cfg, con, dry_run = FALSE, dialect = "duckdb")
#'   prop <- propose_correction(cfg, con, key_values = list(id = "K1"), variable = "age",
#'                              expected_prior = 60, new_value = 61,
#'                              evidence_type = "chart_review", evidence_ref = "invented",
#'                              asserted_by = "tester", dialect = "duckdb")
#'   decide_correction(cfg, con, prop$correction_id, "accept", "tester", dialect = "duckdb")
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#' }
#' }
#'
#' @export
decide_correction <- function(config, con, correction_id, decision, decided_by,
                              reason = NA_character_, dry_run = FALSE, dialect = "mssql") {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required.", call. = FALSE)
  }
  q <- quoter(dialect)
  tabs <- .master_tables(config)
  if (!decision %in% DECISIONS) {
    stop("Unknown decision '", decision, "'. Expected one of: ",
      paste(DECISIONS, collapse = ", "),
      call. = FALSE
    )
  }
  n <- run_step("check correction exists", DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS n FROM %s WHERE correction_id = ?",
    q(tabs$corrections)
  ), params = list(correction_id)))$n
  if (as.integer(n) != 1L) {
    stop("There is no correction ", correction_id, ".", call. = FALSE)
  }
  now <- Sys.time()
  did <- paste0("d", substr(digest::digest(
    list(correction_id, decision, decided_by, format(now, "%Y-%m-%d %H:%M:%OS6")),
    algo = "sha1"
  ), 1, 16))
  n_did <- run_step("check decision id", DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS n FROM %s WHERE decision_id = ?",
    q(tabs$decisions)
  ), params = list(did)))$n
  if (as.integer(n_did) > 0L) {
    stop("The generated decision id collides with an existing row; ",
      "retry the decision.",
      call. = FALSE
    )
  }
  row <- data.frame(
    decision_id = did, correction_id = correction_id, decision = decision,
    decided_by = decided_by, decided_on = now, reason = reason,
    stringsAsFactors = FALSE
  )
  if (dry_run) {
    message("Decision ", did, " (", decision, ") validated; nothing written.")
    return(invisible(list(verdict = "validated", decision_id = did, row = row)))
  }
  run_step("append decision", DBI::dbAppendTable(con, tabs$decisions, row))
  message("Decision ", did, " (", decision, ") recorded on ", correction_id, ".")
  invisible(list(verdict = "recorded", decision_id = did, row = row))
}

#' Character-column widths from a table's SQL types
#'
#' @param types A named character vector of SQL types, as from `table_types()`.
#'
#' @return A named integer vector of widths for `nvarchar(n)`/`varchar(n)`
#'   columns, or `NULL` when none have a fixed width.
#'
#' @keywords internal
#' @noRd
.char_widths <- function(types) {
  m <- regmatches(types, regexec("^n?varchar\\((\\d+)\\)$", types, ignore.case = TRUE))
  n <- vapply(m, length, integer(1))
  if (!any(n > 1L)) {
    return(NULL)
  }
  widths <- as.integer(vapply(m[n > 1L], `[[`, character(1), 2))
  stats::setNames(widths, names(types)[n > 1L])
}
