# value-text.R
#
# A value's text form in the corrections table, and back. Doubles are written
# with 17 significant digits, which is enough for CAST(text AS float) in SQL, or
# as.numeric() in R, to return exactly the same double.

value_text <- function(x) {
  stopifnot(length(x) == 1L)
  if (is.na(x)) return(NA_character_)
  if (inherits(x, "Date")) return(format(x, "%Y-%m-%d"))
  if (inherits(x, "POSIXct")) return(format(x, "%Y-%m-%d %H:%M:%OS6", tz = "UTC"))
  if (is.numeric(unclass(x))) return(sprintf("%.17g", as.numeric(x)))
  as.character(x)
}

parse_value <- function(text, r_class) {
  if (is.na(text)) {
    return(switch(r_class, Date = as.Date(NA), POSIXct = as.POSIXct(NA),
                  character = NA_character_, NA_real_))
  }
  switch(r_class,
         numeric = , integer = , haven_labelled = suppressWarnings(as.numeric(text)),
         Date = as.Date(text, format = "%Y-%m-%d"),
         POSIXct = as.POSIXct(text, tz = "UTC"),
         character = text,
         stop("No text form for class '", r_class, "'.", call. = FALSE))
}
