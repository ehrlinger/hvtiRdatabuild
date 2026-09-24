#' Read a master dataset's configuration
#'
#' A master dataset is a clinical dataset that other builds read, such as the
#' cardiac-surgery master or the mitral master built on top of it. Each is
#' described by a `master.yml` kept outside the package, because it names paths
#' on a shared volume. The file declares the master's view name, its one
#' primary key, any alternate keys, its parent master, and where its SAS
#' snapshots and build program live.
#'
#' The primary key is what corrections match on and what the view joins on.
#' Alternate keys are bridges to other systems: each is checked unique where it
#' is non-null, and its columns are carried on every correction, but nothing
#' matches on them.
#'
#' @param path Path to the `master.yml` file.
#'
#' @return An object of class `master_config`: a list with `name`, `key`,
#'   `alt_keys` (a named list, possibly empty), `parent` (`NULL` or a list with
#'   `master` and `libref`), `parent_release` (`NULL` or a string), `snapshots`,
#'   `current`, `history` (`NULL` or a regular expression), `build_program`,
#'   and `file`.
#'
#' @seealso [snapshot_master()], [lift_master()], [backfill_corrections()]
#'
#' @examples
#' cfg <- read_master_config(system.file("extdata", "master-example.yml",
#'                                       package = "hvtiRdatabuild"))
#' cfg$key
#'
#' @export
read_master_config <- function(path) {
  if (!file.exists(path)) {
    stop("Master configuration does not exist: ", path, call. = FALSE)
  }
  raw <- yaml::read_yaml(path)
  required <- c("name", "key", "snapshots", "current", "build_program")
  missing <- required[!vapply(required, function(f) !is.null(raw[[f]]),
                               logical(1))]
  if (length(missing)) {
    stop("Master configuration is missing required field(s): ",
         paste(missing, collapse = ", "), ".", call. = FALSE)
  }

  key <- raw[["key"]]
  if (length(key) < 1L) {
    stop("'key' must name at least one column.", call. = FALSE)
  }
  if (!is.character(key)) {
    stop("'key' and 'alt_keys' columns must be names, not numbers.",
         call. = FALSE)
  }

  alt_keys <- raw[["alt_keys"]]
  if (is.null(alt_keys)) alt_keys <- list()
  if (length(alt_keys) > 0L) {
    if (is.null(names(alt_keys)) || !all(nzchar(names(alt_keys)))) {
      stop("'alt_keys' must be a mapping of names to columns.",
           call. = FALSE)
    }
    for (i in seq_along(alt_keys)) {
      if (!is.character(alt_keys[[i]])) {
        stop("'key' and 'alt_keys' columns must be names, not numbers.",
             call. = FALSE)
      }
    }
  }
  alt_keys <- lapply(alt_keys, as.character)

  all_cols <- c(as.character(key), unlist(alt_keys, use.names = FALSE))
  twice <- unique(all_cols[duplicated(all_cols)])
  if (length(twice)) {
    stop("Column(s) named more than once across key and alt_keys: ",
         paste(twice, collapse = ", "), ".", call. = FALSE)
  }

  parent <- raw[["parent"]]
  if (!is.null(parent)) {
    if (!is.list(parent)) {
      stop("'parent' must name both master and libref; missing: master, libref.",
           call. = FALSE)
    }
    absent <- c("master", "libref")[!c(!is.null(parent[["master"]]),
                                        !is.null(parent[["libref"]]))]
    if (length(absent)) {
      stop("'parent' must name both master and libref; missing: ",
           paste(absent, collapse = ", "), ".", call. = FALSE)
    }
    parent <- list(master = as.character(parent[["master"]]),
                   libref = as.character(parent[["libref"]]))
  }

  parent_release <- raw[["parent_release"]]
  if (!is.null(parent_release)) {
    if (is.null(parent)) {
      stop("'parent_release' is set but there is no 'parent'.",
           call. = FALSE)
    }
    if (!is.character(parent_release) || length(parent_release) != 1L) {
      stop("'parent_release' must be a single string.", call. = FALSE)
    }
  }

  history <- raw[["history"]]
  if (!is.null(history)) {
    ok <- tryCatch({
      grepl(history, "")
      TRUE
    }, error = function(e) FALSE, warning = function(w) FALSE)
    if (!ok) {
      stop("'history' is not a valid regular expression.", call. = FALSE)
    }
  }

  structure(list(
    name = as.character(raw[["name"]]), key = key, alt_keys = alt_keys,
    parent = parent, parent_release = parent_release,
    snapshots = as.character(raw[["snapshots"]]),
    current = as.character(raw[["current"]]), history = history,
    build_program = as.character(raw[["build_program"]]), file = path
  ), class = "master_config")
}

#' Table names derived from a master's name
#'
#' @param config A `master_config`.
#'
#' @return A list of table and view names.
#'
#' @keywords internal
#' @noRd
.master_tables <- function(config) {
  n <- config$name
  list(corrections = paste0(n, "_corrections"),
       decisions   = paste0(n, "_correction_decisions"),
       stale       = paste0(n, "_corrections_stale"),
       parity      = paste0(n, "_parity"),
       meta        = paste0(n, "_meta"))
}
