# source_corrections.R
#
# Interim correction intake (spec §3.4, §3.5): generating each source's correction
# objects, the submission template, batch proposal and decision, and retiring fill-ins
# that upstream has caught up with. Superseded by the HVTR registry's intake, which takes
# the template and the tables over unchanged. Output is counts, verdicts, column and
# source names, correction ids and template row numbers; never a key or a value.

# Who records a G7 retirement. Not a person, so it can never be in `deciders`.
FILLED_UPSTREAM_DECIDER <- "filled_upstream" # nolint: object_name_linter.

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
#'   writeLines(c("name: master_demo", "key: [mrn]", "snapshots: .",
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
#' writeLines(c("name: master_demo", "key: [mrn]", "snapshots: .",
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
