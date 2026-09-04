#!/usr/bin/env Rscript
# test-imputation-callsite-scan.R
#
# Checks `imputation-callsite-scan.R` against a synthetic corpus with a known
# answer. Same reasoning as the sibling test: `dev/` is `.Rbuildignore`d, so the
# package suite never exercises this script and a green package run says nothing
# about it.
#
# The cases below encode the two things the first scan could NOT see: a study
# that holds a macro definition and never calls it, and a NIMPUTE that is not a
# literal on the PROC MI statement.
#
#   Rscript test-imputation-callsite-scan.R
#
# NO PHI. Every study name, variable and value here is invented.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
scan_script <- file.path(here, "imputation-callsite-scan.R")
stopifnot(file.exists(scan_script))

if (!requireNamespace("hvtiRutilities", quietly = TRUE)) {
  message("SKIP: hvtiRutilities could not be loaded, so the scan cannot run.\n",
          "  This R:   ", R.version.string, "\n",
          "  libPaths: ", paste(.libPaths(), collapse = "\n            "), "\n",
          "It may be absent, or built by a different R than this one.")
  quit(save = "no", status = 0)
}

root <- file.path(tempdir(), paste0("callsite-fixture-", Sys.getpid()))
folder <- unique(hvtiRutilities::hvti_taxonomy()$folder)[[1]]

put <- function(study, file, lines) {
  d <- file.path(root, study, folder)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, file.path(d, file))
}

# ---- the corpus, and what each case pins ------------------------------------

# alpha: holds BOTH definitions and calls NEITHER. This is the case the first
# scan counted as "ran single and multiple imputation" and is the whole reason
# this scan exists.
put("cardiac/alpha", "imputsub_alpha.sas",
    c("%macro imputsub(data=, var=);",
      "proc standard data=&data out=&data replace;", "  var &var;", "run;",
      "%mend;"))
put("cardiac/alpha", "mult_imput_alpha.sas",
    c("%macro mult_imput(data=, nimpute=);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))

# beta: holds a definition AND calls it. NIMPUTE resolved from the macro-call
# argument -- 25, so genuine multiple imputation.
put("cardiac/beta", "mult_imput_beta.sas",
    c("%macro mult_imput(data=, nimpute=);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;",
      "%mult_imput(data=w, nimpute=25);"))

# gamma: NIMPUTE resolved from a %let, and the value is 1 -- SINGLE imputation
# under a macro named for multiple imputation. The finding this scan is hunting.
put("vascular/thoracic-aorta/gamma", "mult_imput_gamma.sas",
    c("%let nimp = 1;",
      "proc mi data=w out=m nimpute=&nimp;", "run;"))

# delta: PROC MI with NIMPUTE set somewhere this file cannot see. Must count as
# UNRESOLVED, never as absent -- a number exists and we failed to read it.
put("cardiac/delta", "mult_imput_delta.sas",
    c("proc mi data=w out=m nimpute=&outside;", "run;"))

# epsilon: PROC MI with no NIMPUTE written at all. ABSENT, i.e. the SAS default.
put("cardiac/epsilon", "mult_imput_epsilon.sas",
    c("proc mi data=w out=m;", "run;"))

# zeta: imputes INLINE with no macro anywhere. Invisible to a stem-matched
# scan, and it must not be lost here. Its file name carries no stem, so it is
# only reached because zeta also holds a stem-matched file.
put("cardiac/zeta", "imputsub_zeta.sas",
    c("%macro imputsub(data=);", "%mend;"))
put("cardiac/zeta", "vars.sas",
    c("proc standard data=w out=x replace;", "  var age;", "run;"))

# ---- run --------------------------------------------------------------------

outfile <- file.path(root, "out.json")
rscript <- file.path(R.home("bin"), "Rscript")
res <- system2(rscript, c(shQuote(normalizePath(scan_script)),
                          "--root", shQuote(root), "--out", shQuote(outfile)),
               stdout = TRUE, stderr = TRUE)
if (!file.exists(outfile)) {
  cat(res, sep = "\n")
  stop("scan produced no output")
}
j <- paste(readLines(outfile), collapse = " ")
num <- function(field) {
  m <- regmatches(j, regexpr(paste0("\"", field, "\": *-?[0-9]+"), j))
  if (!length(m)) stop("field not found in output: ", field)
  as.integer(sub(".*: *", "", m))
}

# ---- expectations -----------------------------------------------------------

expected <- list(
  studies_with_definition = 6L,
  # beta calls %mult_imput; gamma, delta, epsilon have a bare PROC MI but no
  # macro call. alpha and zeta call nothing.
  studies_calling_mult_imput = 1L,
  studies_calling_imputsub   = 0L,
  # alpha, gamma, delta, epsilon, zeta -- every study but beta
  studies_with_definition_but_no_call = 5L,
  # zeta imputes inline without going through a macro
  studies_inline_replace_no_macro = 1L,
  # alpha, beta, gamma, delta, epsilon -- one PROC MI statement each
  statements_total      = 5L,
  # beta's 25 and gamma's 1. alpha's is inside a definition with no %let, so it
  # is unresolved rather than resolved.
  statements_resolved   = 2L,
  statements_nimpute_1  = 1L,
  statements_nimpute_gt1 = 1L,
  # alpha (parameter, never bound) and delta (set outside the file)
  statements_unresolved = 2L,
  # epsilon only
  statements_absent     = 1L
)

fail <- 0L
for (nm in names(expected)) {
  got <- num(nm)
  ok <- identical(got, expected[[nm]])
  if (!ok) fail <- fail + 1L
  message(sprintf("%-36s expected %2d  got %2d  %s",
                  nm, expected[[nm]], got, if (ok) "ok" else "FAIL"))
}

# The three NIMPUTE states are disjoint and must account for every statement.
if (num("statements_resolved") + num("statements_unresolved") +
    num("statements_absent") != num("statements_total")) {
  message("FAIL  NIMPUTE states do not partition the statements")
  fail <- fail + 1L
}

unlink(root, recursive = TRUE)
if (fail) {
  message("\n", fail, " failure(s)")
  quit(save = "no", status = 1)
}
message("\nall checks passed")
