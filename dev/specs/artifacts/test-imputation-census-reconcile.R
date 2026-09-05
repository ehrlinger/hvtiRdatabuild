#!/usr/bin/env Rscript
# test-imputation-census-reconcile.R
#
# Checks `imputation-census-reconcile.R` against a synthetic corpus whose
# exact/variant/extension split is known by construction.
#
#   Rscript test-imputation-census-reconcile.R
#
# NO PHI. Every study name and file name here is invented.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
scan_script <- file.path(here, "imputation-census-reconcile.R")
stopifnot(file.exists(scan_script))

if (!requireNamespace("hvtiRutilities", quietly = TRUE)) {
  message("SKIP: hvtiRutilities could not be loaded, so the scan cannot run.\n",
          "  This R:   ", R.version.string, "\n",
          "  libPaths: ", paste(.libPaths(), collapse = "\n            "))
  quit(save = "no", status = 0)
}

root <- file.path(tempdir(), paste0("census-fixture-", Sys.getpid()))
folder <- unique(hvtiRutilities::hvti_taxonomy()$folder)[[1]]
put <- function(study, file) {
  d <- file.path(root, study, folder)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines("x", file.path(d, file))
}

# imputsub: the exact stem only, across two studies and three extensions.
# Models the observed case where studies match the census exactly and only the
# FILE count differs, because the census counts .log and .lst too.
put("cardiac/alpha", "imputsub.sas")
put("cardiac/alpha", "imputsub.log")
put("cardiac/alpha", "imputsub.lst")
put("cardiac/beta",  "imputsub.sas")

# mult_imput: the exact stem in one study, plus VARIANT stems in two others.
# Models the case that inflates a prefix match above the census.
put("cardiac/gamma", "mult_imput.sas")
put("cardiac/gamma", "mult_imput.log")
put("vascular/thoracic-aorta/delta", "mult_imputation.sas")
put("cardiac/epsilon", "mult_imput2.sas")
put("cardiac/epsilon", "mult_imput_old.sas")

outfile <- file.path(root, "out.json")
rscript <- file.path(R.home("bin"), "Rscript")
res <- system2(rscript, c(shQuote(normalizePath(scan_script)),
                          "--root", shQuote(root), "--out", shQuote(outfile)),
               stdout = TRUE, stderr = TRUE)
if (!file.exists(outfile)) { cat(res, sep = "\n"); stop("scan produced no output") }
j <- readLines(outfile)

# Read a field from inside a named top-level block, so `files` under imputsub is
# not confused with `files` under mult_imput.
block <- function(name) {
  i <- grep(paste0("^  \"", name, "\""), j)
  if (!length(i)) stop("block not found: ", name)
  k <- grep("^  \"", j)
  e <- k[k > i[1]]
  j[i[1]:(if (length(e)) e[1] - 1L else length(j))]
}
num_in <- function(name, field, sub = NULL) {
  b <- block(name)
  if (!is.null(sub)) {
    i <- grep(paste0("^    \"", sub, "\""), b)
    if (!length(i)) stop("sub-block not found: ", sub)
    k <- grep("^    \"", b); e <- k[k > i[1]]
    b <- b[i[1]:(if (length(e)) e[1] - 1L else length(b))]
  }
  m <- regmatches(b, regexpr(paste0("\"", field, "\": *-?[0-9]+"), b))
  m <- unlist(m)
  if (!length(m)) stop("field not found: ", name, "/", field)
  as.integer(sub(".*: *", "", m[1]))
}

checks <- list(
  # exact stem, all extensions: 4 files (3 + 1), 2 studies
  list("imputsub exact files",        num_in("imputsub", "files", "exact"), 4L),
  list("imputsub exact studies",      num_in("imputsub", "studies", "exact"), 2L),
  # .sas only drops the .log and .lst: 2 files, still 2 studies
  list("imputsub .sas files",         num_in("imputsub", "files", "exact_sas_only"), 2L),
  list("imputsub .sas studies",       num_in("imputsub", "studies", "exact_sas_only"), 2L),
  # no variants, so a prefix match adds nothing
  list("imputsub variant stems",      num_in("imputsub", "distinct_stems", "prefix_only"), 0L),
  list("imputsub variant studies",    num_in("imputsub", "studies", "prefix_only"), 0L),
  # mult_imput exact: 2 files, 1 study
  list("mult_imput exact files",      num_in("mult_imput", "files", "exact"), 2L),
  list("mult_imput exact studies",    num_in("mult_imput", "studies", "exact"), 1L),
  # three variant stems across two studies -- the inflation being explained
  list("mult_imput variant stems",    num_in("mult_imput", "distinct_stems", "prefix_only"), 3L),
  list("mult_imput variant files",    num_in("mult_imput", "files", "prefix_only"), 3L),
  list("mult_imput variant studies",  num_in("mult_imput", "studies", "prefix_only"), 2L),
  # ⭐ the shape the real corpus shows: a prefix, .sas-only match returns MORE
  # studies (3) than the exact-stem census (1), despite the extension filter.
  list("mult_imput prefix studies",   num_in("mult_imput", "studies", "prefix_sas_only"), 3L)
)

fail <- 0L
for (c in checks) {
  ok <- identical(c[[2]], c[[3]])
  if (!ok) fail <- fail + 1L
  message(sprintf("%-28s expected %2d  got %2d  %s", c[[1]], c[[3]], c[[2]],
                  if (ok) "ok" else "FAIL"))
}

unlink(root, recursive = TRUE)
if (fail) { message("\n", fail, " failure(s)"); quit(save = "no", status = 1) }
message("\nall checks passed")
