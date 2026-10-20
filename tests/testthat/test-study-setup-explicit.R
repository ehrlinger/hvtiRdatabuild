# Every study_setup() call in this suite names renv, and names cleanup when it
# names adopt. hvtiRutilities makes renv = TRUE and cleanup = adopt the
# defaults: a call that relied on the old ones would start a real renv
# environment for every temporary study, or stop for want of the template
# corpus, which exists only on the analysis server.
# An empty argument, as in x[, 1], is the missing symbol; binding it to a name errors.
is_empty_arg <- function(a) is.symbol(a) && !nzchar(as.character(a))

calls_to <- function(e, fn) {
  found <- list()
  walk <- function(x) {
    if (is.call(x)) {
      head <- x[[1L]]
      name <- if (is.symbol(head)) {
        as.character(head)
      } else if (is.call(head) && identical(head[[1L]], as.symbol("::"))) {
        as.character(head[[3L]])
      } else {
        ""
      }
      if (identical(name, fn)) found[[length(found) + 1L]] <<- x
      for (i in seq_along(x)[-1L]) if (!is_empty_arg(x[[i]])) walk(x[[i]])
    } else if (is.expression(x) || is.pairlist(x)) {
      for (i in seq_along(x)) if (!is_empty_arg(x[[i]])) walk(x[[i]])
    }
  }
  walk(e)
  found
}

test_that("every study_setup() call in the tests is explicit about renv and cleanup", {
  files <- list.files(test_path(), pattern = "[.]R$", full.names = TRUE)
  bad <- character(0)
  for (file in files) {
    for (call in calls_to(parse(file, keep.source = FALSE), "study_setup")) {
      args <- names(as.list(call))[-1L]
      if (!"renv" %in% args || ("adopt" %in% args && !"cleanup" %in% args)) {
        bad <- c(bad, paste0(basename(file), ": ", paste(deparse(call), collapse = " ")))
      }
    }
  }
  expect(length(bad) == 0L, paste(c("implicit study_setup() calls:", bad), collapse = "\n"))
})
