#' Print a dataset comparison
#'
#' Reports row-set differences and a count per verdict, then lists every
#' variable that is not `"identical"`. No overall pass/fail is printed, by
#' design: see [compare_built()].
#'
#' Identifiers are **not** printed by default. In this group's datasets
#' `ccfidu` is a medical record number concatenated with a date of surgery,
#' which is PHI; printing it would place PHI in terminals, logs, and captured
#' test failures. The identifiers remain available in the `rows` attribute for
#' a caller who needs them to chase a discrepancy.
#'
#' @param x An object of class `built_comparison`.
#' @param ... Ignored.
#' @param show_ids Logical. Print the identifiers that appear on only one
#'   side. Defaults to the `hvtiRdatasets.show_ids` option, itself `FALSE`.
#'   **Enabling this may emit PHI.** Only do so in a session whose output is
#'   not being logged or shared.
#'
#' @return `x`, invisibly.
#'
#' @export
print.built_comparison <- function(x, ...,
                                   show_ids = getOption(
                                     "hvtiRdatasets.show_ids", FALSE
                                   )) {
  rows <- attr(x, "rows")

  id_suffix <- function(ids) {
    if (!isTRUE(show_ids)) return("")
    paste0(" (", paste(utils::head(ids, 5), collapse = ", "),
           if (length(ids) > 5) ", ..." else "", ")")
  }

  cat("Dataset comparison\n")
  cat(sprintf("  rows: %d oracle, %d R, %d common\n",
              rows$n_oracle, rows$n_r, rows$n_common))
  if (length(rows$only_oracle)) {
    cat(sprintf("  only in oracle: %d%s\n",
                length(rows$only_oracle), id_suffix(rows$only_oracle)))
  }
  if (length(rows$only_r)) {
    cat(sprintf("  only in R: %d%s\n",
                length(rows$only_r), id_suffix(rows$only_r)))
  }

  cat("\n  variables by verdict:\n")
  counts <- table(factor(x$verdict, levels = .verdict_levels()))
  for (nm in names(counts)) {
    if (counts[[nm]] > 0) {
      cat(sprintf("    %-18s %d\n", nm, counts[[nm]]))
    }
  }

  needs_review <- x[x$verdict != "identical", , drop = FALSE]
  if (nrow(needs_review)) {
    cat("\n  requiring review:\n")
    print.data.frame(needs_review, row.names = FALSE)
  }

  invisible(x)
}
