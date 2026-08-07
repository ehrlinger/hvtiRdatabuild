#' Compare an R-built dataset against a SAS oracle
#'
#' Joins `r` to `oracle` on `id` and classifies every variable. Row-set
#' differences are reported separately from value differences: an identifier
#' present on one side only is a cohort discrepancy, a different class of
#' problem from a miscomputed variable, and conflating the two hides both.
#'
#' This function deliberately returns a table and never a single pass/fail.
#' Collapsing several hundred variables into one boolean launders real
#' differences into a green check. Read the table.
#'
#' A difference does not automatically mean the R code is wrong. SAS orders
#' missing numerics below all values, so `if bmi < 18.5` classifies a missing
#' BMI as underweight where R yields `NA`. Record such cases as
#' `intentional_divergence` in `equivalence_signoff.yaml`.
#'
#' @param oracle Data frame read from the parquet oracle. See
#'   [snapshot_oracle()].
#' @param r Data frame produced by the R pipeline.
#' @param id Name of the identifier column present in both. Must be unique
#'   within each.
#' @param tolerance Numeric. **Absolute** numeric differences at or below
#'   this are reported as `"within_tolerance"`. A single absolute threshold
#'   cannot serve columns of very different magnitude; see the "Coming from
#'   SAS" vignette for how to read `max_rel_diff` alongside it.
#'
#' @return An object of class `built_comparison`: a data frame with one row per
#'   variable and columns `variable`, `n_common`, `verdict`, `n_differ`,
#'   `max_abs_diff`, `max_rel_diff`, and `detail`. `n_common` is the number of
#'   rows compared (constant across all rows, so it survives `write.csv()` or
#'   `as.data.frame()`, unlike the `rows` attribute). `verdict` is one of
#'   `"identical"`, `"within_tolerance"`, `"differs"`, `"absent_in_r"`,
#'   `"absent_in_sas"`, or `"type_mismatch"`. The `rows` attribute holds a
#'   list with `n_oracle`, `n_r`, `n_common`, `only_oracle`, and `only_r`.
#'
#' @seealso [snapshot_oracle()]
#'
#' @examples
#' o <- data.frame(ccfidu = c("A1", "A2"), age = c(65, 70))
#' r <- data.frame(ccfidu = c("A1", "A2"), age = c(65, 71))
#' compare_built(o, r, id = "ccfidu")
#'
#' @export
compare_built <- function(oracle, r, id = "ccfidu", tolerance = 1e-8) {
  oracle <- as.data.frame(oracle)
  r      <- as.data.frame(r)

  for (nm in c("oracle", "r")) {
    d <- get(nm)
    if (!id %in% names(d)) {
      stop("Identifier column '", id, "' is not present in ", nm, ".",
           call. = FALSE)
    }
    if (anyDuplicated(d[[id]])) {
      stop("Identifier column '", id, "' is duplicated in ", nm,
           ". Comparison requires one row per identifier.", call. = FALSE)
    }
    if (anyNA(d[[id]])) {
      stop("Identifier column '", id, "' contains ", sum(is.na(d[[id]])),
           " missing value(s) in ", nm,
           ". Comparison requires a usable identifier for every row.",
           call. = FALSE)
    }
  }

  o_ids <- as.character(oracle[[id]])
  r_ids <- as.character(r[[id]])
  common <- intersect(o_ids, r_ids)

  rows <- list(
    n_oracle    = length(o_ids),
    n_r         = length(r_ids),
    n_common    = length(common),
    only_oracle = setdiff(o_ids, r_ids),
    only_r      = setdiff(r_ids, o_ids)
  )

  if (length(common) == 0L) {
    stop("No shared values of identifier '", id, "': ",
         rows$n_oracle, " row(s) in oracle, ", rows$n_r, " in R, 0 in common. ",
         "Check that both datasets are the same study and that '", id,
         "' is the right identifier.", call. = FALSE)
  }

  o_common <- oracle[match(common, o_ids), , drop = FALSE]
  r_common <- r[match(common, r_ids), , drop = FALSE]

  o_vars <- setdiff(names(oracle), id)
  r_vars <- setdiff(names(r), id)

  all_vars <- union(o_vars, r_vars)

  # Handle "no variables to compare" before rbind rather than after. With an
  # empty list, do.call(rbind, list(make.row.names = FALSE)) does not return
  # NULL -- it returns an atomic -- so an is.null() guard downstream never
  # fires and the failure surfaces later as "$ operator is invalid for
  # atomic vectors".
  out <- if (length(all_vars) == 0L) {
    .empty_comparison()
  } else {
    do.call(rbind, c(
      lapply(all_vars, function(v) {
        .compare_one_variable(v, o_common, r_common, o_vars, r_vars, tolerance,
                              rows$n_common)
      }),
      list(make.row.names = FALSE)
    ))
  }
  out <- out[order(match(out$verdict, .verdict_levels()), out$variable), ,
             drop = FALSE]
  rownames(out) <- NULL

  structure(out, class = c("built_comparison", "data.frame"), rows = rows)
}

#' Verdict levels, most serious first
#'
#' @return A character vector of verdict names in report order.
#'
#' @keywords internal
#' @noRd
.verdict_levels <- function() {
  c("differs", "type_mismatch", "absent_in_r", "absent_in_sas",
    "within_tolerance", "identical")
}

#' An empty comparison table with the correct columns
#'
#' @return A zero-row data frame with the `built_comparison` columns.
#'
#' @keywords internal
#' @noRd
.empty_comparison <- function() {
  data.frame(
    variable     = character(0),
    n_common     = integer(0),
    verdict      = character(0),
    n_differ     = integer(0),
    max_abs_diff = numeric(0),
    max_rel_diff = numeric(0),
    detail       = character(0),
    stringsAsFactors = FALSE
  )
}

#' Classify one variable
#'
#' @param v Variable name.
#' @param o_common,r_common Row-aligned data frames restricted to shared ids.
#' @param o_vars,r_vars Variable names on each side, excluding the id.
#' @param tolerance Numeric tolerance passed to `.compare_vector()`.
#' @param n_common Integer. Number of rows compared, constant across the
#'   whole comparison. Recorded on every row so it survives `write.csv()`.
#'
#' @return A one-row data frame with the `built_comparison` columns.
#'
#' @keywords internal
#' @noRd
.compare_one_variable <- function(v, o_common, r_common, o_vars, r_vars,
                                  tolerance, n_common) {
  row <- function(verdict, n_differ = NA_integer_, max_abs = NA_real_,
                  max_rel = NA_real_, detail = "") {
    data.frame(variable = v, n_common = n_common, verdict = verdict,
               n_differ = n_differ, max_abs_diff = max_abs,
               max_rel_diff = max_rel, detail = detail,
               stringsAsFactors = FALSE)
  }

  if (!v %in% r_vars) {
    return(row("absent_in_r", detail = "Present in oracle, absent in R output."))
  }
  if (!v %in% o_vars) {
    return(row("absent_in_sas", detail = "Present in R output, absent in oracle."))
  }

  o_cls <- .cmp_class(o_common[[v]])
  r_cls <- .cmp_class(r_common[[v]])
  if (!identical(o_cls, r_cls)) {
    return(row("type_mismatch",
               detail = paste0("oracle is ", o_cls, ", R is ", r_cls,
                               "; values not compared.")))
  }

  cmp <- .compare_vector(o_common[[v]], r_common[[v]], tolerance)
  row(cmp$verdict, cmp$n_differ, cmp$max_abs_diff, cmp$max_rel_diff)
}
