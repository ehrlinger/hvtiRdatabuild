#' Collapse a vector to its comparison class
#'
#' Storage differs between SAS and R for the same logical type: a SAS numeric
#' arrives as `haven_labelled`, a plain double, or an integer depending on how
#' it was written. All three are the same thing for comparison purposes.
#'
#' @param x A vector.
#'
#' @return A length-one character: one of `"date"`, `"datetime"`, `"factor"`,
#'   `"character"`, `"logical"`, `"numeric"`, or the vector's first class.
#'
#' @keywords internal
#' @noRd
.cmp_class <- function(x) {
  if (inherits(x, "POSIXct")) return("datetime")
  if (inherits(x, "Date"))    return("date")
  if (is.factor(x))                                  return("factor")
  if (inherits(x, "haven_labelled")) {
    return(if (is.character(unclass(x))) "character" else "numeric")
  }
  if (is.character(x)) return("character")
  if (is.logical(x))   return("logical")
  if (is.numeric(x))   return("numeric")
  class(x)[1]
}

#' Strip a vector to a plain comparable form
#'
#' @param x A vector.
#'
#' @return A plain atomic vector: dates as numeric days, factors as character,
#'   character trimmed of surrounding whitespace with `""` folded to `NA`.
#'
#' @keywords internal
#' @noRd
.as_comparable <- function(x) {
  cls <- .cmp_class(x)
  out <- switch(
    cls,
    date      = as.numeric(as.Date(x)),
    datetime  = as.numeric(x),
    factor    = as.character(x),
    character = .normalise_character(x),
    logical   = as.logical(x),
    numeric   = as.numeric(unclass(x)),
    unclass(x)
  )
  attributes(out) <- NULL
  out
}

#' Normalise a character vector to SAS's notion of a string
#'
#' Two adjustments, both required for a SAS oracle to compare meaningfully
#' against an R rebuild:
#'
#' * **Trailing blanks are stripped.** SAS pads character values to their
#'   declared width, so `'Smith'` and `'Smith   '` are the same value there and
#'   different in R.
#' * **`""` is folded to `NA`.** SAS has no character missing value distinct
#'   from the empty string. A missing character in a SAS dataset reads back as
#'   `""`, while the R pipeline produces `NA`. Treating them as different would
#'   report `differs` for every character column containing any missing value —
#'   false positives in bulk, on every study.
#'
#' The information loss is real but unavoidable: the oracle cannot distinguish
#' `""` from missing, so a difference between them is never evidence of
#' anything.
#'
#' @param x A character or `haven_labelled` character vector.
#'
#' @return A plain character vector, trimmed, with `""` as `NA`.
#'
#' @keywords internal
#' @noRd
.normalise_character <- function(x) {
  v <- trimws(as.character(unclass(x)))
  v[!is.na(v) & v == ""] <- NA_character_
  v
}

#' Compare two vectors elementwise
#'
#' Matched `NA` counts as equal; `NA` on one side only counts as a difference.
#' Character comparison trims whitespace, because SAS pads character values to
#' their declared length and R does not.
#'
#' `NaN` is folded into "missing" (`is.na(NaN)` is `TRUE` in R), so it
#' compares equal to `NA` and to another `NaN`. This matches the oracle: SAS
#' collapses invalid numeric results (`0/0`, `log()` of a negative, division
#' by zero) into its single missing value, so treating `NaN` as missing here
#' avoids false-positive differences against a SAS-derived `NA`.
#'
#' @param a,b Vectors of equal length.
#' @param tolerance Numeric. Absolute differences at or below this are
#'   `"within_tolerance"` rather than `"differs"`.
#'
#' @return A list with `verdict`, `n_differ`, `max_abs_diff`, `max_rel_diff`.
#'
#' @keywords internal
#' @noRd
.compare_vector <- function(a, b, tolerance) {
  av <- .as_comparable(a)
  bv <- .as_comparable(b)

  both_na <- is.na(av) & is.na(bv)
  one_na  <- xor(is.na(av), is.na(bv))

  if (is.numeric(av) && is.numeric(bv)) {
    d <- abs(av - bv)
    d[both_na] <- 0
    d[one_na]  <- Inf
    # Inf - Inf is NaN, not 0. Without this, a column that is Inf on both
    # sides leaves an all-NaN d, and max(d, na.rm = TRUE) reduces over an
    # empty set: -Inf, plus a warning. Equal values differ by zero.
    d[!is.na(av) & !is.na(bv) & av == bv] <- 0
    denom <- pmax(abs(av), abs(bv))
    rel <- ifelse(is.finite(d) & denom > 0, d / denom, d)
    rel[both_na] <- 0
    n_differ <- sum(d > 0, na.rm = TRUE)
    max_abs  <- if (length(d)) max(d, na.rm = TRUE) else 0
    max_rel  <- if (length(rel)) max(rel, na.rm = TRUE) else 0
  } else {
    unequal <- !both_na & (one_na | (av != bv))
    unequal[is.na(unequal)] <- TRUE
    n_differ <- sum(unequal)
    max_abs  <- if (n_differ > 0) Inf else 0
    max_rel  <- max_abs
  }

  verdict <- if (n_differ == 0) {
    "identical"
  } else if (is.finite(max_abs) && max_abs <= tolerance) {
    "within_tolerance"
  } else {
    "differs"
  }

  list(
    verdict      = verdict,
    n_differ     = as.integer(n_differ),
    max_abs_diff = max_abs,
    max_rel_diff = max_rel
  )
}
