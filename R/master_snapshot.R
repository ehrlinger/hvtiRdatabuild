#' Snapshot a master dataset to parquet, with its lineage
#'
#' Freezes a master's current SAS build, or its historical builds, as parquet
#' with [snapshot_oracle()], then checks its keys and records which release of
#' its parent master it was built from.
#'
#' The parent release is read from evidence of what ran, in this order: the log
#' of the run that produced the dataset (a `.log` whose timestamp falls within
#' six hours after the dataset's), where SAS records every dataset it read;
#' then, for the current build only, the build program's `set` statements; then
#' `parent_release` in the configuration. The log comes first because a
#' program can be edited after the run. A current build whose parent cannot be
#' decided stops; a historical one records `"unknown"`.
#'
#' Only `NOTE:` lines naming datasets are read from a log, never data lines.
#' Nothing printed carries a key or a value.
#'
#' @param config A `master_config` from [read_master_config()].
#' @param out_dir Directory to write the parquet snapshots and their sidecars.
#' @param which `"current"`, `"history"`, or both.
#' @param chunk_rows Rows per chunk, passed to [snapshot_oracle()].
#' @param expect Optional validation for the current build, passed to
#'   [snapshot_oracle()]. Historical builds are not validated, because their
#'   logs are rarely retained.
#'
#' @return Invisibly, a data frame with one row per dataset: `file`, `status`
#'   (`"written"`, `"skipped"` or `"failed"`), `n_rows`, `n_cols`, `sha256`,
#'   `source_sha256`, `parent_release`, `parent_source` (`"log"`, `"program"`,
#'   `"declared"`, `"unknown"` or `"none"`) and `key_verdict`.
#'
#' @seealso [read_master_config()], [lift_master()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("arrow", quietly = TRUE) &&
#'     requireNamespace("jsonlite", quietly = TRUE) &&
#'     requireNamespace("tidyselect", quietly = TRUE)) {
#'   dir <- tempfile("master")
#'   dir.create(dir)
#'   file.copy(system.file("extdata", "oracle_small.sas7bdat",
#'                         package = "hvtiRdatabuild"),
#'             file.path(dir, "built.sas7bdat"))
#'   writeLines("data m; run;", file.path(dir, "bd.data.sas"))
#'   cfg_path <- file.path(dir, "master.yml")
#'   writeLines(c("name: master_demo", "key: [ccfidu]",
#'                paste0("snapshots: ", dir), "current: built.sas7bdat",
#'                paste0("build_program: ", file.path(dir, "bd.data.sas"))),
#'              cfg_path)
#'   snapshot_master(read_master_config(cfg_path), tempfile("out"),
#'                   which = "current")
#' }
#' }
#'
#' @export
snapshot_master <- function(config, out_dir, which = c("current", "history"),
                            chunk_rows = 1e5, expect = NULL) {
  for (p in c("arrow", "jsonlite", "tidyselect")) {
    if (!requireNamespace(p, quietly = TRUE)) {
      stop("Package '", p, "' is required to snapshot a master. ",
           "Install it with install.packages('", p, "').", call. = FALSE)
    }
  }
  if (!inherits(config, "master_config")) {
    stop("'config' must come from read_master_config().", call. = FALSE)
  }
  which <- match.arg(which, several.ok = TRUE)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  targets <- character()
  if ("current" %in% which) targets <- file.path(config[["snapshots"]], config[["current"]])
  if ("history" %in% which) targets <- c(targets, .find_history(config))

  rows <- lapply(targets, function(sas) {
    is_current <- identical(
      normalizePath(sas, mustWork = FALSE),
      normalizePath(file.path(config[["snapshots"]], config[["current"]]), mustWork = FALSE)
    )
    out <- file.path(out_dir, sub("\\.sas7bdat$", ".parquet", basename(sas)))
    row <- data.frame(file = basename(sas), status = "skipped", n_rows = NA_real_,
                      n_cols = NA_real_, sha256 = NA_character_,
                      source_sha256 = NA_character_, parent_release = NA_character_,
                      parent_source = NA_character_, key_verdict = NA_character_,
                      stringsAsFactors = FALSE)
    if (file.exists(out)) return(row)

    if (is_current) return(.snapshot_one(sas, config, out, is_current, chunk_rows, expect, row))
    tryCatch(
      .snapshot_one(sas, config, out, is_current, chunk_rows, expect, row),
      error = function(e) {
        .clean_partial(out)
        message(sprintf("FAILED  %s: %s", basename(sas), class(e)[[1]]))
        row$status <- "failed"
        row
      }
    )
  })
  invisible(do.call(rbind, rows))
}

#' Snapshot one dataset and record its lineage and key verdicts
#'
#' @param sas Path to the SAS dataset.
#' @param config A `master_config`.
#' @param out Path to write the parquet snapshot.
#' @param is_current Whether this is the current build.
#' @param chunk_rows Rows per chunk, passed to [snapshot_oracle()].
#' @param expect Optional validation, passed to [snapshot_oracle()] for the
#'   current build only.
#' @param row The dataset's starting result row, to be filled in.
#'
#' @return The result row, with `status` `"written"`.
#'
#' @keywords internal
#' @noRd
.snapshot_one <- function(sas, config, out, is_current, chunk_rows, expect, row) {
  lineage <- .resolve_parent(sas, config, is_current)
  info <- snapshot_oracle(sas, out, expect = if (is_current) expect else NULL,
                          chunk_rows = chunk_rows)
  verdicts <- c(key = key_verdict(out, config[["key"]])$verdict,
                vapply(config[["alt_keys"]], function(cols) {
                  key_verdict(out, cols, nonnull_only = TRUE)$verdict
                }, character(1)))
  meta <- jsonlite::read_json(info$meta_path)
  meta$lineage <- list(parent_master = if (is.null(config[["parent"]])) NULL else
                         config[["parent"]][["master"]],
                       parent_release = if (is.na(lineage$release)) NULL else
                         lineage$release,
                       parent_source = lineage$source)
  meta$keys <- as.list(verdicts)
  jsonlite::write_json(meta, info$meta_path, auto_unbox = TRUE, null = "null",
                       pretty = TRUE)

  row$status <- "written"
  row$n_rows <- info$n_rows
  row$n_cols <- info$n_cols
  row$sha256 <- info$sha256
  row$source_sha256 <- info$source_sha256
  row$parent_release <- lineage$release
  row$parent_source <- lineage$source
  row$key_verdict <- verdicts[["key"]]
  message(sprintf("%-40s %s rows x %s columns; key %s; parent %s (%s)",
                  basename(sas), info$n_rows, info$n_cols, verdicts[["key"]],
                  lineage$release, lineage$source))
  row
}

#' Remove a snapshot's parquet and sidecar, if either was partially written
#'
#' @param out Path to the parquet file.
#'
#' @return `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
.clean_partial <- function(out) {
  unlink(out)
  unlink(.snapshot_meta_path(out))
  invisible(NULL)
}

#' Historical builds matching the configuration's pattern
#'
#' @param config A `master_config`.
#'
#' @return Paths in `snapshots/` and its immediate subfolders whose file name
#'   matches `history`, excluding the current build.
#'
#' @keywords internal
#' @noRd
.find_history <- function(config) {
  if (is.null(config[["history"]])) return(character())
  dirs <- c(config[["snapshots"]], list.dirs(config[["snapshots"]], recursive = FALSE))
  files <- unlist(lapply(dirs, list.files, pattern = config[["history"]], full.names = TRUE))
  files <- files[basename(files) != config[["current"]]]
  sort(unique(files))
}

#' The log whose timestamp brackets a dataset's
#'
#' @param dataset Path to the dataset.
#' @param dirs Directories to search for `.log` files.
#' @param window_hours Hours after the dataset's modification time within which
#'   the log must have been written.
#'
#' @return The closest qualifying log's path, or `NA`.
#'
#' @keywords internal
#' @noRd
.bracketing_log <- function(dataset, dirs, window_hours = 6) {
  logs <- unique(unlist(lapply(unique(dirs), list.files, pattern = "\\.log$",
                               full.names = TRUE, ignore.case = TRUE)))
  if (!length(logs)) return(NA_character_)
  t0 <- file.mtime(dataset)
  dt <- as.numeric(difftime(file.mtime(logs), t0, units = "hours"))
  ok <- !is.na(dt) & dt >= 0 & dt <= window_hours
  if (!any(ok)) return(NA_character_)
  logs[ok][which.min(dt[ok])]
}

#' Parent members named in a log's dataset-read NOTEs
#'
#' @param log Path to a SAS log.
#' @param libref The libref the parent is read through.
#'
#' @return Distinct members, lower case.
#'
#' @keywords internal
#' @noRd
.parent_from_log <- function(log, libref) {
  lines <- readLines(log, warn = FALSE)
  notes <- grep("^NOTE:", lines, value = TRUE)
  pat <- paste0("read from the data set ", libref, "\\.([A-Za-z0-9_]+)")
  m <- regmatches(notes, regexec(pat, notes, ignore.case = TRUE))
  unique(tolower(vapply(Filter(length, m), `[[`, character(1), 2)))
}

#' Parent members named in a build program's reads
#'
#' @param program Path to the SAS build program.
#' @param libref The libref the parent is read through.
#'
#' @return Distinct members, lower case.
#'
#' @keywords internal
#' @noRd
.parent_from_program <- function(program, libref) {
  if (!file.exists(program)) return(character())
  text <- readLines(program, warn = FALSE)
  pat <- paste0("\\b(set|merge|from|join)\\s+", libref, "\\.([A-Za-z0-9_]+)")
  m <- regmatches(text, regexec(pat, text, ignore.case = TRUE))
  unique(tolower(vapply(Filter(length, m), `[[`, character(1), 3)))
}

#' Decide a dataset's parent release, and how it was decided
#'
#' @param sas Path to the dataset.
#' @param config A `master_config`.
#' @param is_current Whether this is the current build.
#'
#' @return A list with `release` (a string or `NA`) and `source`.
#'
#' @keywords internal
#' @noRd
.resolve_parent <- function(sas, config, is_current) {
  if (is.null(config[["parent"]])) return(list(release = NA_character_, source = "none"))
  libref <- config[["parent"]][["libref"]]
  log_dirs <- if (is_current) c(dirname(sas), dirname(config[["build_program"]])) else dirname(sas)
  log <- .bracketing_log(sas, log_dirs)
  found <- if (!is.na(log)) .parent_from_log(log, libref) else character()
  source <- "log"
  if (!length(found) && is_current) {
    found <- .parent_from_program(config[["build_program"]], libref)
    source <- "program"
  }
  declared <- config[["parent_release"]]
  if (length(found) == 1L) {
    if (!is.null(declared) && !identical(tolower(declared), found)) {
      stop("The declared parent_release disagrees with the ", source,
           ", which names ", found, ".", call. = FALSE)
    }
    return(list(release = found, source = source))
  }
  if (!is.null(declared)) return(list(release = tolower(declared), source = "declared"))
  if (is_current) {
    stop("Could not decide which release of ", config[["parent"]][["master"]], " ",
         basename(sas), " was built from (", length(found), " candidates). ",
         "Set 'parent_release' in ", basename(config[["file"]]), ".", call. = FALSE)
  }
  list(release = NA_character_, source = "unknown")
}
