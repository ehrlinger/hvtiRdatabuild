# master_lift.R
#
# Lifting a master's parquet snapshot into the warehouse: the key and parity
# gates, the base table's name, the base table behind the latest passing
# parity record, and publishing the master's view.

#' Lift a master's parquet snapshot into the warehouse as a view
#'
#' Checks the primary key, creates a base table named for the snapshot's
#' release, loads it row group by row group, and proves it equal to the
#' snapshot: counts, aggregates and a sampled compare first, then a full
#' comparison of every column joined on the key. Only then is a parity record
#' written and the master's view created. If the master already has a
#' corrections table, the view is regenerated with corrections applied.
#'
#' A dry run, the default, writes the table's DDL next to the snapshot for a
#' hand-off and touches nothing else. Warehouse errors are reported by step,
#' with the driver's message withheld, because it can carry a data value.
#'
#' @param config A `master_config` from [read_master_config()].
#' @param con A DBI connection, such as one from [dw_connect()].
#' @param parquet Path to a snapshot written by [snapshot_master()]; its
#'   `.meta.json` sidecar must sit beside it, and its checksum must match the
#'   sidecar's `parquet_sha256`.
#' @param dry_run If `TRUE`, the default, write the DDL and nothing else.
#' @param dialect `"mssql"` for the warehouse, or `"duckdb"`, used in tests.
#'
#' @return Invisibly, a list with `dry_run`, `base_table`, `ddl_path` and
#'   `verdict` (`"pass"`, or `NA` for a dry run).
#'
#' @seealso [snapshot_master()], [backfill_corrections()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE) &&
#'     requireNamespace("arrow", quietly = TRUE) &&
#'     requireNamespace("jsonlite", quietly = TRUE) &&
#'     requireNamespace("tidyselect", quietly = TRUE)) {
#'   dir <- tempfile("lift")
#'   dir.create(dir)
#'   pq <- file.path(dir, "built_demo.parquet")
#'   arrow::write_parquet(data.frame(id = c("K1", "K2"), x = c(1, 2)), pq)
#'   jsonlite::write_json(
#'     list(parquet_sha256 = digest::digest(pq, algo = "sha256", file = TRUE),
#'          columns = list(list(variable = "id", r_class = "character"),
#'                         list(variable = "x", r_class = "numeric"))),
#'     sub("\\.parquet$", ".meta.json", pq), auto_unbox = TRUE)
#'   cfg_path <- file.path(dir, "master.yml")
#'   writeLines(c("name: master_demo", "key: [id]", paste0("snapshots: ", dir),
#'                "current: built_demo.sas7bdat",
#'                paste0("build_program: ", file.path(dir, "bd.sas"))), cfg_path)
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   lift_master(read_master_config(cfg_path), con, pq, dialect = "duckdb")
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#' }
#' }
#'
#' @export
lift_master <- function(config, con, parquet, dry_run = TRUE, dialect = "mssql") {
  for (p in c("arrow", "tidyselect", "jsonlite")) {
    if (!requireNamespace(p, quietly = TRUE)) {
      stop("Package '", p, "' is required to lift a master. ",
           "Install it with install.packages('", p, "').", call. = FALSE)
    }
  }
  if (!inherits(config, "master_config")) {
    stop("'config' must come from read_master_config().", call. = FALSE)
  }
  meta_path <- .snapshot_meta_path(parquet)
  if (!file.exists(meta_path)) {
    stop("The parquet's metadata sidecar is missing: ", meta_path,
         ". Re-run snapshot_master().", call. = FALSE)
  }
  meta <- jsonlite::read_json(meta_path, simplifyVector = TRUE)
  if (!identical(.file_sha256(parquet), as.character(meta$parquet_sha256))) {
    stop("The parquet does not match its sidecar checksum; re-run snapshot_master().",
         call. = FALSE)
  }
  base <- .base_table_name(config, parquet)

  kv <- key_verdict(parquet, config[["key"]])
  message(format_key_verdict(kv))
  if (kv$verdict != "unique") {
    stop("The primary key is not unique in the snapshot; nothing was created.",
         call. = FALSE)
  }

  ddl <- master_ddl(parquet, base)
  ddl_path <- paste0(parquet, ".ddl.sql")
  if (dry_run) {
    writeLines(ddl$sql, ddl_path)
    message("dry run: DDL for ", base, " written to ", ddl_path)
    return(invisible(list(dry_run = TRUE, base_table = base, ddl_path = ddl_path,
                          verdict = NA_character_)))
  }
  for (p in c("dplyr", "withr")) {
    if (!requireNamespace(p, quietly = TRUE)) {
      stop("Package '", p, "' is required to lift a master. ",
           "Install it with install.packages('", p, "').", call. = FALSE)
    }
  }

  tabs <- .master_tables(config)
  if (!DBI::dbExistsTable(con, base)) {
    run_step("create base table", {
      if (dialect == "mssql") {
        exec_ddl <- master_ddl(parquet, base, schema_name = NULL)
        DBI::dbExecute(con, exec_ddl$sql)
      } else {
        proto <- as.data.frame(arrow::ParquetFileReader$create(parquet)$ReadRowGroup(0L))
        DBI::dbCreateTable(con, base, .zap_all(proto)[0, , drop = FALSE])
      }
    })
  }
  r <- run_step("load", load_parquet(con, parquet, base))
  message("load: ", r$loaded, " row groups loaded, ", r$skipped, " already present")

  res <- run_step("parity check", parity_check(con, base, parquet, config[["key"]],
                                               dialect = dialect))
  message(parity_summary(res))
  full <- if (res$verdict == "pass") {
    run_step("full parity check", parity_full(con, base, parquet, config[["key"]],
                                              dialect = dialect))
  } else {
    NULL
  }
  if (!is.null(full)) message(full_summary(full))
  if (res$verdict != "pass" || any(full$verdict != "match")) {
    stop("Parity failed; the view was not created.", call. = FALSE)
  }

  parity_row <- data.frame(base_table = base, parquet_sha256 = as.character(meta$parquet_sha256),
                           verdict = "pass",
                           checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3", tz = "UTC"))
  # dbWriteTable(append = TRUE) creates the parity table on the first lift.
  run_step("record parity",
           DBI::dbWriteTable(con, tabs$parity, parity_row, append = TRUE))
  run_step("write metadata", DBI::dbWriteTable(con, tabs$meta, as.data.frame(meta$columns),
                                               overwrite = TRUE))
  .publish_views(config, con, base, dialect)
  message("view ", config[["name"]], " -> ", base)
  invisible(list(dry_run = FALSE, base_table = base, ddl_path = NA_character_,
                 verdict = "pass"))
}

#' The base table's name, from the master's name and the snapshot's stem
#'
#' @param config A `master_config`.
#' @param parquet Path to the snapshot.
#'
#' @return A lower-case identifier.
#'
#' @keywords internal
#' @noRd
.base_table_name <- function(config, parquet) {
  stem <- tolower(gsub("[^A-Za-z0-9]+", "_", sub("\\.parquet$", "", basename(parquet))))
  paste0(config[["name"]], "_base_", stem)
}

#' The base table of the latest passing parity record
#'
#' @param con A DBI connection.
#' @param config A `master_config`.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return The base table's name. Stops when no parity has passed.
#'
#' @keywords internal
#' @noRd
.current_base <- function(con, config, dialect) {
  tab <- .master_tables(config)$parity
  if (!DBI::dbExistsTable(con, tab)) {
    stop("Master ", config[["name"]], " has no passing parity record; run lift_master() first.",
         call. = FALSE)
  }
  q <- quoter(dialect)
  sql <- sprintf("SELECT base_table, checked_at FROM %s WHERE verdict = 'pass'", q(tab))
  rec <- DBI::dbGetQuery(con, sql)
  if (!nrow(rec)) {
    stop("Master ", config[["name"]], " has no passing parity record; run lift_master() first.",
         call. = FALSE)
  }
  rec$base_table[order(rec$checked_at, decreasing = TRUE)][[1]]
}

#' Create or regenerate the master's view over a base table
#'
#' @param config A `master_config`.
#' @param con A DBI connection.
#' @param base_table The base table.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
.publish_views <- function(config, con, base_table, dialect) {
  q <- quoter(dialect)
  tabs <- .master_tables(config)
  if (!DBI::dbExistsTable(con, tabs$corrections)) {
    view_sql <- sprintf("%s %s AS SELECT * FROM %s;", view_header(dialect),
                        q(config[["name"]]), q(base_table))
    run_step("create view", DBI::dbExecute(con, view_sql))
    return(invisible(NULL))
  }
  types <- table_types(con, base_table)
  corrected <- corrected_variables(con, tabs$corrections, config[["name"]], dialect)
  corr_sql <- corrections_view_sql(config[["name"]], base_table, tabs$corrections,
                                   tabs$decisions, config[["name"]], config[["key"]],
                                   names(types), corrected, types, dialect)
  run_step("create corrections view", DBI::dbExecute(con, corr_sql))
  stale_sql <- stale_view_sql(tabs$stale, base_table, tabs$corrections, tabs$decisions,
                              config[["name"]], config[["key"]], names(types), corrected,
                              types, dialect)
  run_step("create stale view", DBI::dbExecute(con, stale_sql))
  invisible(NULL)
}
