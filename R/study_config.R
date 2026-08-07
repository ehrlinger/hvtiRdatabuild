#' Read and validate a study configuration
#'
#' Loads the `study.yaml` that declares which warehouse modules a study pulls
#' and which derivation steps it runs. The SAS templates expressed this as a
#' catalogue of optional blocks, commented in or out; this makes it an explicit,
#' diffable, committed file.
#'
#' Validation is strict by design. An unknown key is an error rather than a
#' warning, because a typo'd module name must not silently disable a module —
#' that failure mode produces a quietly incomplete dataset with no signal.
#'
#' @param path Path to a `study.yaml` file.
#'
#' @return An object of class `study_config`: a list with elements `study`,
#'   `cohort_table`, `warehouse`, `view_schema`, `pull_date` (a `Date`),
#'   `modules`, `varsets`, and `derive` (a named logical vector).
#'
#' @examples
#' path <- tempfile(fileext = ".yaml")
#' yaml::write_yaml(list(
#'   study = "st1234", cohort_table = "db.schema.st1234_cohort",
#'   warehouse = "warehouse", view_schema = "dbo",
#'   pull_date = "2026-08-04", modules = list("base"),
#'   varsets = list("core"), derive = list(missing = TRUE)
#' ), path)
#' read_study_config(path)
#'
#' @export
read_study_config <- function(path) {
  if (!file.exists(path)) {
    stop("Study configuration does not exist: ", path, call. = FALSE)
  }

  raw <- yaml::read_yaml(path)
  if (!is.list(raw) || is.null(names(raw))) {
    stop("Study configuration must be a YAML mapping: ", path, call. = FALSE)
  }

  required <- c("study", "cohort_table", "warehouse", "view_schema",
                "pull_date", "modules")
  optional <- c("varsets", "derive")

  unknown <- setdiff(names(raw), c(required, optional))
  if (length(unknown)) {
    stop("Unknown key(s) in study configuration: ",
         paste(unknown, collapse = ", "),
         ". Known keys are: ", paste(c(required, optional), collapse = ", "),
         ". A typo must not silently disable a step, so this is an error.",
         call. = FALSE)
  }

  missing_keys <- setdiff(required, names(raw))
  if (length(missing_keys)) {
    stop("Study configuration is missing required key(s): ",
         paste(missing_keys, collapse = ", "), ".", call. = FALSE)
  }

  for (k in c("study", "cohort_table", "warehouse", "view_schema")) {
    if (!is.character(raw[[k]]) || length(raw[[k]]) != 1L || !nzchar(raw[[k]])) {
      stop("Study configuration key '", k,
           "' must be a single non-empty string.", call. = FALSE)
    }
  }

  pull_date <- as.Date(as.character(raw$pull_date), format = "%Y-%m-%d")
  if (is.na(pull_date)) {
    stop("Study configuration key 'pull_date' must be YYYY-MM-DD, got: ",
         as.character(raw$pull_date), call. = FALSE)
  }

  cfg <- list(
    study        = raw$study,
    cohort_table = raw$cohort_table,
    warehouse    = raw$warehouse,
    view_schema  = raw$view_schema,
    pull_date    = pull_date,
    modules      = .as_character_vector(raw$modules, "modules"),
    varsets      = .as_character_vector(raw$varsets %||% list(), "varsets"),
    derive       = .as_derive_flags(raw$derive)
  )

  structure(cfg, class = "study_config")
}

#' Null-coalescing helper
#'
#' @param x,y Values; `y` is returned when `x` is `NULL`.
#'
#' @return `x` unless it is `NULL`, otherwise `y`.
#'
#' @keywords internal
#' @noRd
`%||%` <- function(x, y) if (is.null(x)) y else x

#' Coerce a YAML sequence to a character vector
#'
#' @param x Value read from YAML.
#' @param what Key name, used in the error message.
#'
#' @return A character vector, possibly of length zero.
#'
#' @keywords internal
#' @noRd
.as_character_vector <- function(x, what) {
  if (length(x) == 0L) {
    return(character(0))
  }
  if (!is.null(names(x))) {
    stop("Study configuration key '", what,
         "' must be a YAML sequence (a list of strings), not a mapping.",
         call. = FALSE)
  }
  out <- unlist(x, use.names = FALSE)
  if (!is.character(out)) {
    stop("Study configuration key '", what,
         "' must be a list of strings.", call. = FALSE)
  }
  out
}

#' Coerce and validate the derive block
#'
#' @param x Value read from YAML; may be `NULL`.
#'
#' @return A named logical vector, possibly of length zero.
#'
#' @keywords internal
#' @noRd
.as_derive_flags <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(structure(logical(0), names = character(0)))
  }
  if (is.null(names(x)) || any(!nzchar(names(x)))) {
    stop("Study configuration key 'derive' must be a mapping of ",
         "name: true/false.", call. = FALSE)
  }
  for (k in names(x)) {
    if (!is.logical(x[[k]]) || length(x[[k]]) != 1L) {
      stop("Study configuration key 'derive: ", k,
           "' must be logical (true or false).", call. = FALSE)
    }
  }
  vapply(x, isTRUE, logical(1))
}
