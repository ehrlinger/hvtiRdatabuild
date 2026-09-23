# test-harness.R
#
# A minimal check harness for the standalone tests in this folder, in the style
# of dev/specs/artifacts/test-*.R. NO PHI.

fail <- 0L

check <- function(label, ok) {
  ok <- isTRUE(ok)
  if (!ok) fail <<- fail + 1L
  message(sprintf("%-68s %s", label, if (ok) "ok" else "FAIL"))
  invisible(ok)
}

check_error <- function(label, expr, pattern = NULL) {
  msg <- tryCatch({
    force(expr)
    NULL
  }, error = function(e) conditionMessage(e))
  check(label, !is.null(msg) && (is.null(pattern) || grepl(pattern, msg)))
  invisible(msg)
}

skip_unless <- function(pkgs) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    message("SKIP: missing ", paste(missing, collapse = ", "))
    quit(save = "no", status = 0)
  }
}

finish <- function() {
  if (fail) {
    message("\n", fail, " failure(s)")
    quit(save = "no", status = 1)
  }
  message("\nall checks passed")
}
