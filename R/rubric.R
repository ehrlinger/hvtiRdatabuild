# rubric.R
#
# The hvtiR family conventions this package implements in a few lines of its
# own (the hvtiR API rubric): quiet mode, classed errors, the provenance
# record, and one-release deprecations for renamed arguments.

#' Send an informational message unless the family is in quiet mode
#'
#' Every informational `message()` goes through here. Setting
#' `options(hvti.quiet = TRUE)` silences them; warnings and errors are never
#' silenced by it.
#'
#' @param ... Passed to [message()].
#'
#' @return `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
.hvti_inform <- function(...) {
  if (!isTRUE(getOption("hvti.quiet"))) message(...)
  invisible()
}

#' Stop with an `hvtiRdatabuild_<condition>` class
#'
#' For an error a caller is expected to catch. The condition carries
#' `hvtiRdatabuild_<condition>`, then `hvtiRdatabuild_error`, then the base
#' error classes, and no call, as `stop(call. = FALSE)` gives.
#'
#' @param condition The condition's name, without the package prefix.
#' @param ... Pasted together, with no separator, as the message.
#'
#' @return Does not return.
#'
#' @keywords internal
#' @noRd
.abort <- function(condition, ...) {
  stop(errorCondition(
    paste0(...),
    class = c(paste0("hvtiRdatabuild_", condition), "hvtiRdatabuild_error"),
    call = NULL
  ))
}

#' Warn with an `hvtiRdatabuild_<condition>` class
#'
#' For work that finished but is incomplete. Unlike `.hvti_inform()`, it is
#' not silenced by `hvti.quiet`: quiet mode hides progress, never an
#' unsuccessful outcome.
#'
#' @param condition The condition's name, without the package prefix.
#' @param ... Pasted together, with no separator, as the message.
#'
#' @return `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
.warn <- function(condition, ...) {
  warning(warningCondition(
    paste0(...),
    class = c(paste0("hvtiRdatabuild_", condition), "hvtiRdatabuild_warning"),
    call = NULL
  ))
  invisible()
}

#' The family's seven-field provenance record
#'
#' A named list with every field present; a value that does not apply is `NA`
#' of the stated type. Package-specific fields may follow.
#'
#' @param method What was run.
#' @param seed The seed used, or `NA` when none.
#' @param time When it ran.
#'
#' @return A list with `package`, `version`, `sha`, `method`, `seed`,
#'   `rng_kind` and `time`.
#'
#' @keywords internal
#' @noRd
.provenance_record <- function(method, seed = NA_integer_, time = Sys.time()) {
  desc <- utils::packageDescription("hvtiRdatabuild")
  sha <- desc[["RemoteSha"]]
  list(
    package = "hvtiRdatabuild",
    version = as.character(utils::packageVersion("hvtiRdatabuild")),
    sha = if (is.null(sha) || !nzchar(sha)) NA_character_ else as.character(sha),
    method = as.character(method),
    seed = as.integer(seed),
    rng_kind = RNGkind(),
    time = as.POSIXct(time)
  )
}

#' A time as ISO 8601 local text with its UTC offset, which `as.POSIXct()` reads back
#'
#' Local time keeps the date a reader takes from the first ten characters the
#' date the job ran on; the offset keeps the instant exact.
#'
#' @param time A `POSIXct`.
#'
#' @return Character, such as `"2026-11-16T14:40:00-0500"`.
#'
#' @keywords internal
#' @noRd
.iso_time <- function(time) {
  format(time, "%Y-%m-%dT%H:%M:%S%z")
}

# Deprecations already announced this session, keyed "fn:what".
.deprecation_seen <- new.env(parent = emptyenv())

#' Warn once per session about a deprecated usage
#'
#' A renamed argument, or a removed study-specific default, keeps working for
#' one release and warns once per session, with class
#' `hvtiRdatabuild_deprecated`, then becomes an error in the next release.
#'
#' @param fn The exported function, for the message.
#' @param what A short key for the deprecated usage.
#' @param message What changed and what to do instead.
#'
#' @return `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
.deprecate <- function(fn, what, message) {
  key <- paste(fn, what, sep = ":")
  if (!isTRUE(.deprecation_seen[[key]])) {
    assign(key, TRUE, envir = .deprecation_seen)
    warning(warningCondition(
      paste0(fn, "(): ", message, " This will be an error in the next release."),
      class = c("hvtiRdatabuild_deprecated", "deprecatedWarning"),
      call = NULL
    ))
  }
  invisible(NULL)
}

#' Accept a renamed argument for one release
#'
#' Supplying both names is an error that names both: neither silently wins.
#'
#' @param fn The exported function, for the message.
#' @param old,new The old and new argument names.
#' @param value The value passed under the old name.
#' @param new_supplied Whether the new name was supplied too.
#'
#' @return `value`.
#'
#' @keywords internal
#' @noRd
.renamed_arg <- function(fn, old, new, value, new_supplied) {
  if (new_supplied) {
    .abort("both_names",
           fn, "(): give `", new, "` only; `", old, "` is its old name.")
  }
  .deprecate(fn, old, paste0("`", old, "` is renamed `", new, "`."))
  value
}

#' The study-specific default an argument used to have, with a deprecation
#'
#' A study-specific value is never a default in the hvtiR family, so the
#' argument is now required; for one release an omitted value still means the
#' old default, and warns.
#'
#' @param fn The exported function, for the message.
#' @param arg The argument's name.
#' @param value The old default.
#'
#' @return `value`.
#'
#' @keywords internal
#' @noRd
.deprecated_default <- function(fn, arg, value) {
  .deprecate(fn, paste0(arg, "-default"), paste0(
    "`", arg, "` has no default now; `\"", value, "\"` was one study's column name. ",
    "Name the column, for example `", arg, " = \"", value, "\"`."
  ))
  value
}
