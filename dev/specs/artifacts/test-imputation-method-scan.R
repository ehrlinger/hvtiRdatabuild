#!/usr/bin/env Rscript
# test-imputation-method-scan.R
#
# Checks `imputation-method-scan.R` against a synthetic corpus with a KNOWN
# answer, so the instrument that settles section 2 of
# 2026-09-03-imputation-package-spec.md is itself checked before it is trusted.
#
#   Rscript test-imputation-method-scan.R
#
# WHY THIS FILE EXISTS. The scan lives under `dev/`, which is in
# `.Rbuildignore`, so `devtools::test()` does not see it and a green package
# run says NOTHING about it. Three defects reached the review because of that.
# The corpus below encodes those three, so a regression is a failing run rather
# than a plausible-looking integer in a JSON file.
#
# NO PHI. Every study name, variable and value here is invented.

# Resolve the scan next to this file, so the test runs from any directory.
self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
scan_script <- file.path(here, "imputation-method-scan.R")
stopifnot(file.exists(scan_script))

if (!requireNamespace("hvtiRutilities", quietly = TRUE)) {
  # Same caution as the scan's guard: requireNamespace() cannot distinguish
  # absent from built-by-another-R, so report what is running rather than
  # asserting the package is missing.
  message("SKIP: hvtiRutilities could not be loaded, so the scan cannot run.\n",
          "  This R:   ", R.version.string, "\n",
          "  libPaths: ", paste(.libPaths(), collapse = "\n            "), "\n",
          "It may be absent, or built by a different R than this one.")
  quit(save = "no", status = 0)
}

root <- file.path(tempdir(), paste0("scan-fixture-", Sys.getpid()))
folder <- unique(hvtiRutilities::hvti_taxonomy()$folder)[[1]]

put <- function(study, file, lines) {
  d <- file.path(root, study, folder)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, file.path(d, file))
}

# ---- the corpus, and what each case pins ------------------------------------

# alpha: single and multiple imputation in SEPARATE files, which is how the two
# stems actually divide the work. The file-level AND could never see this, and
# reported studies_both = 0.
put("cardiac/alpha", "imputsub_alpha.sas",
    c("data w; set r.raw;", "run;",
      "proc standard data=w out=x replace;", "  var age bmi;", "run;"))
put("cardiac/alpha", "mult_imput_alpha.sas",
    c("proc mi data=w out=m nimpute=5 seed=1;", "  var age bmi;", "run;"))

# beta: PROC MI used ONLY for missingness diagnostics. NIMPUTE=0 does not
# impute, and counting it inflated studies_multiple.
put("cardiac/beta", "mult_imput_beta.sas",
    c("proc mi data=w nimpute=0;", "  var age bmi;", "run;"))

# gamma: REPLACE together with MEAN=/STD=. This standardises the observed
# values AND fills the missing ones with the MEAN= value. It is imputation, and
# was being excluded from every single-imputation count.
put("vascular/thoracic-aorta/gamma", "imputsub_gamma.sas",
    c("proc standard data=w out=z mean=0 std=1 replace;", "  var age bmi;",
      "run;"))

# delta: a commented-out PROC STANDARD REPLACE, and a PROC STANDARD with no
# REPLACE. Neither imputes; delta must appear in no imputation count.
put("cardiac/delta", "imputsub_delta.sas",
    c("* proc standard data=w out=x replace;",
      "%* an old macro comment mentioning proc standard replace;",
      "proc standard data=w out=x mean=0 std=1;", "  var age;", "run;"))

# epsilon: two PROC MI statements in ONE file, one diagnostic and one real.
# The file imputes; the per-file `m[1]` read reported only the first NIMPUTE=.
put("cardiac/epsilon", "mult_imput_epsilon.sas",
    c("proc mi data=w nimpute=0;", "run;",
      "proc mi data=w out=m nimpute=20;", "run;"))

# ---- run --------------------------------------------------------------------

outfile <- file.path(root, "out.json")
# Spawn the scan with THE R THAT IS RUNNING THIS TEST, not with whatever
# `Rscript` is on PATH. A server may carry a dozen R versions with one default
# symlink, so `system2("Rscript", ...)` can test a different R than the one you
# invoked -- which makes the test's verdict about the wrong interpreter, and
# reports the mismatch as a scan failure rather than an environment one.
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
  studies               = 5L,
  # alpha (separate files), gamma (REPLACE with MEAN=/STD=)
  studies_single        = 2L,
  # alpha, epsilon. NOT beta -- its only PROC MI is NIMPUTE=0.
  studies_multiple      = 2L,
  # alpha, and only alpha
  studies_both          = 1L,
  studies_single_only   = 1L,   # gamma
  studies_multiple_only = 1L,   # epsilon
  # beta only. This is a FILE-level flag meaning every PROC MI in the file is
  # NIMPUTE=0, so epsilon -- one diagnostic call and one real one -- is
  # correctly excluded: that file does impute.
  files_proc_mi_diag_only = 1L,
  # Four PROC MI statements declare NIMPUTE across the corpus: beta's 0,
  # epsilon's 0 and 20, alpha's 5. Reading only the FIRST match per file would
  # give 3 and would hide epsilon's second statement entirely.
  n_statements_declaring = 4L
)

fail <- 0L
for (nm in names(expected)) {
  got <- num(nm)
  ok <- identical(got, expected[[nm]])
  if (!ok) fail <- fail + 1L
  message(sprintf("%-24s expected %2d  got %2d  %s",
                  nm, expected[[nm]], got, if (ok) "ok" else "FAIL"))
}

# The study-level cells must reconcile, or the sets were not built from sets.
if (num("studies_single_only") + num("studies_multiple_only") + num("studies_both") !=
    num("studies_single") + num("studies_multiple") - num("studies_both")) {
  message("FAIL  study-level cells do not reconcile")
  fail <- fail + 1L
}

unlink(root, recursive = TRUE)
if (fail) {
  message("\n", fail, " failure(s)")
  quit(save = "no", status = 1)
}
message("\nall checks passed")
