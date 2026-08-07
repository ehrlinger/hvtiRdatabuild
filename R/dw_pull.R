#' Pull the enabled warehouse modules for a study
#'
#' Executes one query per module named in the study configuration and returns
#' the raw tables alongside a manifest of what was pulled. This is the R port
#' of `tp.stXXXX_dwpull.sas`.
#'
#' The port is **read-only**. The SAS templates also upload a cohort table to
#' the warehouse; that write is deliberately not carried here and is deferred
#' to a later slice with its own review.
#'
#' A module that returns zero rows is an error unless its definition declares
#' it optional. A silently empty module produces a quietly incomplete dataset,
#' which is the failure this package exists to prevent.
#'
#' @param config A `study_config` from [read_study_config()].
#' @param conn A [DBI::DBIConnection-class], typically from [dw_connect()].
#'
#' @return An object of class `pull_result`: a list with `tables`, a named
#'   list of data frames keyed by each module's `output` name, and `manifest`,
#'   a data frame with columns `module`, `output`, `n_rows`, `n_cols`, and
#'   `pulled_at`.
#'
#' @seealso [dw_connect()], [dw_modules()], [compare_built()]
#'
#' @examples
#' \donttest{
#' # Requires a warehouse connection; see vignette("building-a-study-dataset")
#' # for a runnable version against a mocked connection.
#' }
#'
#' @export
dw_pull <- function(config, conn) {
  if (!inherits(config, "study_config")) {
    stop("'config' must be a study_config from read_study_config().",
         call. = FALSE)
  }

  specs <- .read_module_specs()
  unknown <- setdiff(config$modules, names(specs))
  if (length(unknown)) {
    stop("Study configuration names unknown module(s): ",
         paste(unknown, collapse = ", "), ". Known modules are: ",
         paste(names(specs), collapse = ", "),
         ". Nothing was pulled.", call. = FALSE)
  }

  pulled_at <- Sys.time()
  tables <- list()
  rows   <- list()

  for (m in config$modules) {
    spec <- specs[[m]]
    sql  <- .module_sql(m, config)

    d <- tryCatch(
      DBI::dbGetQuery(conn, sql),
      error = function(e) {
        # The SQL is withheld: it names warehouse objects, and an error
        # message is exactly the artefact that ends up pasted into a ticket.
        stop("Pull failed for module '", m,
             "'. The query was not echoed. Check warehouse access and the ",
             "cohort table named in study.yaml.", call. = FALSE)
      }
    )

    if (nrow(d) == 0L && !isTRUE(spec$optional)) {
      stop("Module '", m, "' returned zero rows and is not declared ",
           "optional. An empty required module yields a quietly incomplete ",
           "dataset. If emptiness is expected, mark the module optional.",
           call. = FALSE)
    }

    tables[[spec$output]] <- d
    rows[[length(rows) + 1L]] <- data.frame(
      module    = m,
      output    = spec$output,
      n_rows    = nrow(d),
      n_cols    = ncol(d),
      pulled_at = pulled_at,
      stringsAsFactors = FALSE
    )
  }

  man <- do.call(rbind, rows)

  structure(list(tables = tables, manifest = man), class = "pull_result")
}

#' Print a pull result
#'
#' @param x A `pull_result` from [dw_pull()].
#' @param ... Ignored.
#'
#' @return `x`, invisibly.
#'
#' @export
print.pull_result <- function(x, ...) {
  cat("Warehouse pull:", nrow(x$manifest), "module(s)\n\n")
  print(x$manifest, row.names = FALSE)
  invisible(x)
}
