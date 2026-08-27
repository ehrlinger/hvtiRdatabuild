#' List the available warehouse modules
#'
#' Module definitions ship as data under `inst/extdata/modules/`, one YAML
#' file per module, rather than as R code. They change independently of the
#' code that executes them, they carry a description of the SAS block each one
#' ports, and holding them outside R source is what keeps site-specific
#' identifiers out of this repository — the SQL ships with placeholders and
#' the real warehouse, schema, and cohort names arrive from `study.yaml` at
#' run time.
#'
#' @return A data frame with one row per module and columns `module`,
#'   `output`, `join_key`, and `optional`.
#'
#' @examples
#' dw_modules()
#'
#' @export
dw_modules <- function() {
  specs <- .read_module_specs()
  data.frame(
    module   = vapply(specs, function(s) s$module,   character(1)),
    output   = vapply(specs, function(s) s$output,   character(1)),
    join_key = vapply(specs, function(s) s$join_key, character(1)),
    optional = vapply(specs, function(s) isTRUE(s$optional), logical(1)),
    stringsAsFactors = FALSE
  )
}

#' Read every shipped module specification
#'
#' @return A named list of module specifications.
#'
#' @keywords internal
#' @noRd
.read_module_specs <- function() {
  dir <- system.file("extdata", "modules", package = "hvtiRdatabuild")
  files <- list.files(dir, pattern = "\\.yaml$", full.names = TRUE)
  if (length(files) == 0L) {
    stop("No module definitions found in ", dir,
         ". The package installation is incomplete.", call. = FALSE)
  }
  specs <- lapply(files, yaml::read_yaml)
  required <- c("module", "output", "join_key", "sql")
  for (i in seq_along(specs)) {
    missing_fields <- setdiff(required, names(specs[[i]]))
    if (length(missing_fields)) {
      stop("Module definition ", basename(files[i]),
           " is missing field(s): ",
           paste(missing_fields, collapse = ", "), ".", call. = FALSE)
    }
  }
  stats::setNames(specs, vapply(specs, function(s) s$module, character(1)))
}

#' Build the SQL for one module
#'
#' @param module Module name, one of `dw_modules()$module`.
#' @param config A `study_config` from [read_study_config()].
#'
#' @return A single SQL string with every placeholder interpolated.
#'
#' @keywords internal
#' @noRd
.module_sql <- function(module, config) {
  specs <- .read_module_specs()
  if (!module %in% names(specs)) {
    stop("Unknown module '", module, "'. Known modules are: ",
         paste(names(specs), collapse = ", "), ".", call. = FALSE)
  }
  sql <- specs[[module]]$sql

  replacements <- c(
    "{cohort}"      = config$cohort_table,
    "{warehouse}"   = config$warehouse,
    "{view_schema}" = config$view_schema
  )
  for (token in names(replacements)) {
    sql <- gsub(token, replacements[[token]], sql, fixed = TRUE)
  }

  leftover <- regmatches(sql, gregexpr("\\{[^}]*\\}", sql))[[1]]
  if (length(leftover)) {
    stop("Module '", module, "' has uninterpolated placeholder(s): ",
         paste(unique(leftover), collapse = ", "), ".", call. = FALSE)
  }

  trimws(sql)
}
