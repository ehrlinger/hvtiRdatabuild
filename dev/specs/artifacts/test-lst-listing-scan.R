#!/usr/bin/env Rscript
# test-lst-listing-scan.R
#
# Checks `lst-listing-scan.R` against synthetic listings whose content is known
# by construction.
#
#   Rscript test-lst-listing-scan.R
#
# ⚠️ NO PHI, AND NOTHING RESEMBLING IT. These are invented SAS listing fragments.
# A real `.lst` IS printed output and a `PROC PRINT` one is patient data by
# design, which is why that scan's contract is stricter than most. A fixture must
# not smuggle a realistic-looking listing into the repository, so the "print
# output" case below carries invented column headers and no values at all.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
scan_script <- file.path(here, "lst-listing-scan.R")
stopifnot(file.exists(scan_script))

if (!requireNamespace("hvtiRutilities", quietly = TRUE)) {
  message("SKIP: hvtiRutilities could not be loaded, so the scan cannot run.\n",
          "  This R:   ", R.version.string, "\n",
          "  libPaths: ", paste(.libPaths(), collapse = "\n            "))
  quit(save = "no", status = 0)
}

root <- file.path(tempdir(), paste0("lst-fixture-", Sys.getpid()))
folder <- unique(hvtiRutilities::hvti_taxonomy()$folder)[[1]]
put <- function(study, file, lines) {
  d <- file.path(root, study, folder)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, file.path(d, file))
}

# alpha: a model listing. Could check a port's values at rung 3.
put("cardiac/alpha", "model.lst",
    c("The PHREG Procedure", "Analysis of Maximum Likelihood Estimates",
      "(invented fixture, no values)"))

# beta: a different model heading, so the pattern is not one string.
put("cardiac/beta", "fit.lst",
    c("The GLM Procedure", "Parameter Estimates", "(invented fixture)"))

# ⚠️ gamma: patient-level print output. Counted, never read. Invented headers
# only, and deliberately no rows.
put("thoracic/gamma", "listing.lst",
    c("The PRINT Procedure", "Obs    InventedColumn    AnotherInvented"))

# delta: a procedure ran but printed nothing a port can use.
put("cardiac/delta", "freq.lst", c("The FREQ Procedure", "(invented fixture)"))

# eps: nothing recognised at all.
put("cardiac/eps", "notes.lst", c("invented text with no procedure heading"))

# zeta: a second model listing in the SAME study as another file, so the study
# is counted once.
put("cardiac/alpha", "model2.lst",
    c("The LOGISTIC Procedure", "Analysis of Maximum Likelihood Estimates"))

outfile <- file.path(root, "out.json")
rscript <- file.path(R.home("bin"), "Rscript")
res <- system2(rscript, c(shQuote(normalizePath(scan_script)),
                          "--root", shQuote(root), "--out", shQuote(outfile)),
               stdout = TRUE, stderr = TRUE)
if (!file.exists(outfile)) { cat(res, sep = "\n"); stop("scan produced no output") }
raw <- readLines(outfile)
j <- paste(raw, collapse = " ")
num <- function(field) {
  m <- regmatches(j, regexpr(paste0("\"", field, "\": *-?[0-9]+"), j))
  if (!length(m)) stop("field not found: ", field)
  as.integer(sub(".*: *", "", m))
}

expected <- list(
  listings_considered = 6L,
  read = 6L,
  # alpha's two, beta's one
  with_model_listing = 3L,
  with_print_output = 1L,          # gamma
  with_any_procedure = 5L,         # all but eps
  with_nothing_recognised = 1L,    # eps
  with_any_listing = 5L,
  # ⭐ alpha counted once despite two model listings, plus beta
  with_a_model_listing = 2L
)

fail <- 0L
for (nm in names(expected)) {
  got <- num(nm)
  ok <- identical(got, expected[[nm]])
  if (!ok) fail <- fail + 1L
  message(sprintf("%-26s expected %2d  got %2d  %s", nm, expected[[nm]], got,
                  if (ok) "ok" else "FAIL"))
}

# 🔴 THE CONTRACT ASSERTION. Nothing from a listing may reach the output. The
# fixture plants distinctive words, including in the print-output case, and none
# may appear.
for (leak in c("invented", "Invented", "PHREG", "GLM", "LOGISTIC", "Obs",
               "Maximum Likelihood", "Procedure")) {
  if (grepl(leak, j, fixed = TRUE)) {
    message("FAIL  output contains listing text: ", leak); fail <- fail + 1L
  }
}
if (!grepl("\"emits_listing_values\": false", j)) {
  message("FAIL  output does not declare that values are withheld"); fail <- fail + 1L
}
if (!fail) message(sprintf("%-26s %s", "no listing text in output", "ok"))

o2 <- file.path(root, "count.json")
system2(rscript, c(shQuote(normalizePath(scan_script)), "--root", shQuote(root),
                   "--out", shQuote(o2), "--count-only"),
        stdout = FALSE, stderr = FALSE)
if (file.exists(o2)) {
  message("FAIL  --count-only wrote an output file"); fail <- fail + 1L
} else message(sprintf("%-26s %s", "--count-only writes nothing", "ok"))

unlink(root, recursive = TRUE)
if (fail) { message("\n", fail, " failure(s)"); quit(save = "no", status = 1) }
message("\nall checks passed")
