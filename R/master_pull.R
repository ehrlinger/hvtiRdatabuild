# master_pull.R
#
# Study pulls from a master view. Selection and read run in one transaction, joined
# through a session temp table of cohort keys. Spec: dev/specs/
# 2026-11-16-master-views-design.md §5, §6.1.

# Run `code` in one transaction. On SQL Server the transaction uses SNAPSHOT
# isolation, so every read sees one state of the warehouse; a duckdb transaction is
# a snapshot already. Rolls back on error.
.with_snapshot_txn <- function(con, dialect, code) {
  if (identical(dialect, "mssql")) {
    run_step("set snapshot isolation",
             DBI::dbExecute(con, "SET TRANSACTION ISOLATION LEVEL SNAPSHOT"))
  }
  run_step("begin transaction", DBI::dbBegin(con))
  committed <- FALSE
  on.exit(if (!committed) try(DBI::dbRollback(con), silent = TRUE), add = TRUE)
  out <- force(code)
  run_step("commit transaction", DBI::dbCommit(con))
  committed <- TRUE
  out
}

.qualified_name <- function(name, dialect) {
  q <- quoter(dialect)
  paste(vapply(strsplit(name, ".", fixed = TRUE)[[1]], q, character(1)), collapse = ".")
}

.cohort_temp <- function(dialect) {
  switch(dialect,
         mssql = list(
           name = "#study_cohort",
           create = paste("CREATE TABLE #study_cohort (mrn nvarchar(128) NOT NULL,",
                          "encounter_date date NOT NULL, prior_qualifying tinyint NOT NULL)")
         ),
         duckdb = list(
           name = "study_cohort",
           create = paste("CREATE TEMP TABLE study_cohort (mrn VARCHAR NOT NULL,",
                          "encounter_date DATE NOT NULL, prior_qualifying TINYINT NOT NULL)")
         ))
}

.read_now_sql <- function(dialect) {
  switch(dialect,
         mssql = "SELECT SYSUTCDATETIME() AS read_at",
         duckdb = "SELECT CAST(timezone('UTC', CURRENT_TIMESTAMP) AS TIMESTAMP) AS read_at")
}

.read_deployment <- function(con, deployment_view, dialect) {
  dep <- run_step("read deployment", DBI::dbGetQuery(
    con, paste("SELECT sql_commit FROM", .qualified_name(deployment_view, dialect))
  ))
  commit <- as.character(dep$sql_commit)
  if (length(commit) != 1L || is.na(commit) || !nzchar(commit)) {
    stop("The deployment view must hold exactly one non-empty sql_commit; it holds ",
         length(commit), " row(s). Nothing was pulled.", call. = FALSE)
  }
  commit
}

.unit_cohort_active <- function(cohort) {
  if (!identical(cohort$patient_id_col, "cohort_unit")) {
    stop("A supplied cohort must be built on cohort_unit_id() units ",
         "(patient_id_col = \"cohort_unit\").", call. = FALSE)
  }
  last <- utils::tail(cohort$stages$stage_id[order(cohort$stages$order)], 1L)
  units <- cohort$members$patient_id[cohort$members$stage_id == last &
                                       cohort$members$included]
  if (!length(units)) {
    stop("The cohort's latest stage has no included units. Nothing was pulled.",
         call. = FALSE)
  }
  units
}

# INSERT ... SELECT that puts a query's units into the temp table. Bound parameters,
# in text order: epoch start (the EXISTS), epoch start, epoch end (the BETWEEN).
.select_units_sql <- function(query, master_q, tmp, mrn_q, date_q) {
  paste(
    "INSERT INTO", tmp, "(mrn, encounter_date, prior_qualifying)",
    "SELECT q.mrn, q.encounter_date,",
    sprintf("CASE WHEN EXISTS (SELECT 1 FROM %s p WHERE (%s) AND p.%s = q.mrn AND p.%s < ?)",
            master_q, query$qualifying, mrn_q, date_q),
    "THEN 1 ELSE 0 END",
    "FROM (",
    sprintf("SELECT m.%s AS mrn, m.%s AS encounter_date,", mrn_q, date_q),
    sprintf("ROW_NUMBER() OVER (PARTITION BY m.%s ORDER BY m.%s) AS rn", mrn_q, date_q),
    sprintf("FROM %s m WHERE (%s) AND m.%s IS NOT NULL AND m.%s BETWEEN ? AND ?",
            master_q, query$qualifying, mrn_q, date_q),
    ") q",
    if (identical(query$index, "first")) "WHERE q.rn = 1" else ""
  )
}

.query_cohort <- function(query, selected, master, commit) {
  units <- cohort_unit_id(as.character(selected$mrn), as.Date(selected$encounter_date))
  has_prior <- selected$prior_qualifying == 1L
  exclude <- identical(query$prior, "exclude") & has_prior
  query_prov <- sprintf("%s where %s; epoch %s to %s; index %s; SQL commit %s",
                        master, query$qualifying, format(query$epoch[[1]]),
                        format(query$epoch[[2]]), query$index, commit)
  verdict <- if (identical(query$prior, "keep")) "kept" else "excluded"
  prior_prov <- sprintf("%d unit(s) with a qualifying encounter before the epoch; %s",
                        sum(has_prior), verdict)
  members <- rbind(
    data.frame(patient_id = units, stage_id = "qualifying", included = TRUE,
               reason = NA_character_, stringsAsFactors = FALSE),
    data.frame(patient_id = units, stage_id = "prior_qualifying", included = !exclude,
               reason = ifelse(exclude, "qualifying encounter before the epoch",
                               NA_character_),
               stringsAsFactors = FALSE)
  )
  stages <- data.frame(
    stage_id = c("qualifying", "prior_qualifying"),
    order = c(1L, 2L),
    label = c("Qualifying encounters in the epoch",
              "Qualifying encounter before the epoch"),
    source = "upstream",
    provenance = c(query_prov, prior_prov),
    stringsAsFactors = FALSE
  )
  new_cohort_record(members, stages, patient_id_col = "cohort_unit")
}

#' Pull a study's cohort from a master view
#'
#' Selects a cohort and reads its rows from a master view in **one transaction under
#' snapshot isolation**, so the cohort, its data, the corrections applied to it and the
#' deployment it came from describe one state of the warehouse even while decisions,
#' loads or deployments commit.
#'
#' The cohort's keys go into a **session temp table**, which is joined to the master
#' inside the database. For a [cohort_query()] the epoch, the index and the earlier-
#' encounter flag are computed in SQL, so no key outside the cohort leaves the database.
#' For a supplied [new_cohort_record()] of [cohort_unit_id()] units, its active units are
#' loaded. The temp table is dropped before commit and never outlives the connection, so
#' no patient list persists in the warehouse.
#'
#' The returned cohort ends with an `in_master` stage that excludes units with no master
#' row, so the data match the active cohort exactly. A unit matching more than one
#' master row stops the pull, because the key is meant to be unique. Nothing in an error
#' or in printed output names a patient.
#'
#' @param con A [DBI::DBIConnection-class] to the warehouse, or to duckdb in tests.
#' @param master Character. The master view, optionally schema-qualified
#'   (`"dbo.master_cardiac"`).
#' @param cohort A [cohort_query()], or a [new_cohort_record()] built on
#'   [cohort_unit_id()] units (`patient_id_col = "cohort_unit"`).
#' @param columns Character. The study's columns, besides the key.
#' @param mrn_col,date_col Character. The master's key columns.
#' @param dialect `"mssql"` (the warehouse) or `"duckdb"` (tests).
#' @param applied_view,deployment_view Character. The master's applied-corrections and
#'   deployment views.
#'
#' @return An object of class `master_pull`: a list with `data` (one row per active
#'   unit: the key columns, `columns` and `cohort_unit`), `cohort` (the cohort record,
#'   ending with the `in_master` stage) and `provenance` (`master`, `sql_commit`,
#'   `applied_correction_ids`, `corrections_in_effect`, `read_at`, `columns`,
#'   `cohort_definition`, `n_cohort`, `n_matched`, `n_unmatched`).
#'   `corrections_in_effect` holds every correction id applied anywhere in the master in
#'   the same snapshot, including any that changed who qualified.
#'
#' @seealso [cohort_query()], [build_from_master()], [freeze_study_pull()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   # Synthetic data; no PHI.
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   DBI::dbWriteTable(con, "master_demo", data.frame(
#'     mrn = c("SYN101", "SYN102"),
#'     encounter_date = as.Date(c("2010-03-01", "2012-07-15")),
#'     proc = c("CABG", "AVR"), age = c(62, 70)
#'   ))
#'   DBI::dbWriteTable(con, "master_demo_corrections_applied", data.frame(
#'     correction_id = character(), mrn = character(), encounter_date = as.Date(character())
#'   ))
#'   DBI::dbWriteTable(con, "master_demo_deployment", data.frame(sql_commit = "abc1234"))
#'   q <- cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")))
#'   pull_master(con, "master_demo", q, columns = "age", dialect = "duckdb")
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#' }
#' }
#'
#' @export
pull_master <- function(con, master, cohort, columns, mrn_col = "mrn",
                        date_col = "encounter_date", dialect = c("mssql", "duckdb"),
                        applied_view = paste0(master, "_corrections_applied"),
                        deployment_view = paste0(master, "_deployment")) {
  dialect <- match.arg(dialect)
  if (!is.character(columns) || !length(columns) || anyNA(columns) ||
        any(!nzchar(columns))) {
    stop("'columns' must name at least one column.", call. = FALSE)
  }
  if (anyDuplicated(columns)) {
    stop("'columns' contains a duplicate name.", call. = FALSE)
  }
  is_query <- inherits(cohort, "cohort_query")
  if (!is_query && !inherits(cohort, "cohort_record")) {
    stop("'cohort' must be a cohort_query or a cohort_record.", call. = FALSE)
  }
  supplied <- if (is_query) NULL else split_cohort_unit(.unit_cohort_active(cohort))

  q <- quoter(dialect)
  tmp <- .cohort_temp(dialect)
  master_q <- .qualified_name(master, dialect)
  cols <- unique(c(mrn_col, date_col, columns))
  select_sql <- paste0("m.", vapply(cols, q, character(1)), collapse = ", ")
  join_sql <- sprintf("m.%s = c.mrn AND m.%s = c.encounter_date", q(mrn_col), q(date_col))
  if (is_query && identical(cohort$prior, "exclude")) {
    join_sql <- paste(join_sql, "AND c.prior_qualifying = 0")
  }

  read <- .with_snapshot_txn(con, dialect, {
    read_at <- run_step("read time", DBI::dbGetQuery(con, .read_now_sql(dialect)))$read_at
    commit <- .read_deployment(con, deployment_view, dialect)
    run_step("create cohort temp table", DBI::dbExecute(con, tmp$create))
    if (is_query) {
      run_step("select cohort", DBI::dbExecute(
        con, .select_units_sql(cohort, master_q, tmp$name, q(mrn_col), q(date_col)),
        params = list(cohort$epoch[[1]], cohort$epoch[[1]], cohort$epoch[[2]])
      ))
      selected <- run_step("read cohort keys", DBI::dbGetQuery(
        con, paste("SELECT mrn, encounter_date, prior_qualifying FROM", tmp$name)
      ))
      if (!nrow(selected)) {
        stop("No qualifying encounters fall in the epoch. Check the cohort query.",
             call. = FALSE)
      }
    } else {
      run_step("load cohort keys", DBI::dbExecute(
        con,
        paste("INSERT INTO", tmp$name,
              "(mrn, encounter_date, prior_qualifying) VALUES (?, ?, 0)"),
        params = list(supplied$mrn, supplied$encounter_date)
      ))
      selected <- NULL
    }
    data <- run_step("read master", DBI::dbGetQuery(con, sprintf(
      "SELECT %s FROM %s m INNER JOIN %s c ON %s", select_sql, master_q, tmp$name, join_sql
    )))
    applied <- run_step("read applied corrections", DBI::dbGetQuery(con, sprintf(
      paste("SELECT DISTINCT a.correction_id FROM %s a INNER JOIN %s c",
            "ON a.mrn = c.mrn AND a.encounter_date = c.encounter_date"),
      .qualified_name(applied_view, dialect), tmp$name
    )))
    in_effect <- run_step("read corrections in effect", DBI::dbGetQuery(con, paste(
      "SELECT DISTINCT correction_id FROM", .qualified_name(applied_view, dialect)
    )))
    run_step("drop cohort temp table", DBI::dbExecute(con, paste("DROP TABLE", tmp$name)))

    data$cohort_unit <- cohort_unit_id(as.character(data[[mrn_col]]),
                                       as.Date(data[[date_col]]))
    n_dup <- sum(duplicated(data$cohort_unit))
    if (n_dup) {
      stop(n_dup, " cohort unit(s) matched more than one master row; the key is meant ",
           "to be unique. Nothing was pulled.", call. = FALSE)
    }
    list(data = data, selected = selected, read_at = read_at, commit = commit,
         applied = sort(unique(as.character(applied$correction_id))),
         in_effect = sort(unique(as.character(in_effect$correction_id))))
  })

  base <- if (is_query) .query_cohort(cohort, read$selected, master, read$commit) else cohort
  last <- utils::tail(base$stages$stage_id[order(base$stages$order)], 1L)
  active <- base$members$patient_id[base$members$stage_id == last & base$members$included]
  found <- active %in% read$data$cohort_unit
  read_at <- format(as.POSIXct(read$read_at, tz = "UTC"), "%Y-%m-%dT%H:%M:%OS6Z",
                    tz = "UTC")
  final <- append_cohort_stage(
    base,
    data.frame(stage_id = "in_master", order = max(base$stages$order) + 1L,
               label = "Has a row in the master view", source = "upstream",
               provenance = sprintf("%s at SQL commit %s, read %s", master, read$commit,
                                    read_at),
               stringsAsFactors = FALSE),
    data.frame(patient_id = active, included = found,
               reason = ifelse(found, NA_character_, "no row in the master view"),
               stringsAsFactors = FALSE)
  )
  data <- read$data[read$data$cohort_unit %in% active[found], , drop = FALSE]
  row.names(data) <- NULL

  structure(list(
    data = data,
    cohort = final,
    provenance = list(
      master = master,
      sql_commit = read$commit,
      applied_correction_ids = read$applied,
      corrections_in_effect = read$in_effect,
      read_at = read_at,
      columns = columns,
      cohort_definition = if (is_query) {
        list(qualifying = cohort$qualifying, epoch = format(cohort$epoch),
             index = cohort$index, prior = cohort$prior)
      } else {
        "supplied cohort_record"
      },
      n_cohort = length(active),
      n_matched = sum(found),
      n_unmatched = sum(!found)
    )
  ), class = "master_pull")
}

#' Print a master pull
#'
#' Shows counts and provenance, never a patient value or identifier.
#'
#' @param x A `master_pull` from [pull_master()].
#' @param ... Ignored.
#'
#' @return `x`, invisibly.
#'
#' @export
print.master_pull <- function(x, ...) {
  p <- x$provenance
  cat("Master pull from ", p$master, " at SQL commit ", p$sql_commit, "\n", sep = "")
  cat("  cohort units: ", p$n_cohort, "; matched: ", p$n_matched,
      "; unmatched: ", p$n_unmatched, "\n", sep = "")
  cat("  columns: ", length(p$columns), "; corrections applied: ",
      length(p$applied_correction_ids), "; read at ", p$read_at, "\n", sep = "")
  invisible(x)
}

#' @rdname print.master_pull
#' @param object A `master_pull` from [pull_master()].
#' @export
str.master_pull <- function(object, ...) {
  cat("Structure of master_pull\n")
  print.master_pull(object, ...)
  invisible(NULL)
}
