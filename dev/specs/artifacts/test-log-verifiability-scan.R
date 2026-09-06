#!/usr/bin/env Rscript
# test-log-verifiability-scan.R
#
# Checks `log-verifiability-scan.R` against synthetic logs whose verifiability is
# known by construction.
#
#   Rscript test-log-verifiability-scan.R
#
# ⚠️ NO PHI, AND NOTHING RESEMBLING IT. These are invented SAS log lines. A real
# log may carry patient values, which is the whole reason that scan's contract is
# stricter than its siblings'; a fixture must not smuggle a realistic-looking one
# into the repository.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
scan_script <- file.path(here, "log-verifiability-scan.R")
stopifnot(file.exists(scan_script))

if (!requireNamespace("hvtiRutilities", quietly = TRUE)) {
  message("SKIP: hvtiRutilities could not be loaded, so the scan cannot run.\n",
          "  This R:   ", R.version.string, "\n",
          "  libPaths: ", paste(.libPaths(), collapse = "\n            "))
  quit(save = "no", status = 0)
}

root <- file.path(tempdir(), paste0("log-fixture-", Sys.getpid()))
folder <- unique(hvtiRutilities::hvti_taxonomy()$folder)[[1]]
put <- function(study, file, lines) {
  d <- file.path(root, study, folder)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, file.path(d, file))
}

SHAPE <- "NOTE: The data set WORK.EXAMPLE has 100 observations and 7 variables."
ENDED <- "NOTE: The SAS System used: real time 0.05 seconds"

# alpha: a clean vars log that recorded a shape. Usable for rung 1.
put("cardiac/alpha", "vars.log", c("NOTE: Invented log for a test.", SHAPE, ENDED))

# ⚠️ beta: recorded a shape AND failed. A log full of errors is not evidence of
# a build that happened, so it must NOT be usable.
put("cardiac/beta", "vars.log",
    c(SHAPE, "ERROR: Invented failure for a test.", ENDED))

# gamma: ran and ended, but recorded no dataset shape. Rung 1 needs the shape.
put("cardiac/gamma", "build.log", c("NOTE: Invented log with no shape note.", ENDED))

# delta: two logs, only one usable. The STUDY still counts once.
put("thoracic/delta", "vars.log", c(SHAPE, ENDED))
put("thoracic/delta", "build.log", c("ERROR: Invented failure.", ENDED))

# epsilon: a warning but no error, and a shape. Warnings do not disqualify.
put("cardiac/eps", "build.log",
    c(SHAPE, "WARNING: Invented warning for a test.", ENDED))

# ⚠️ oversize: a study whose ONLY log exceeds the ceiling. It must still count in
# `with_any_log`, which is an EXISTENCE metric, while contributing to no content
# metric. The skip used to precede study attribution, so this study reported as
# having no log at all.
put("cardiac/oversize", "vars.log", c(SHAPE, ENDED))

# zeta: a log under a stem the scan does not name, to exercise "other".
put("cardiac/zeta", "hazard.log", c(SHAPE, ENDED))

# ---- run --------------------------------------------------------------------

outfile <- file.path(root, "out.json")
rscript <- file.path(R.home("bin"), "Rscript")
# A tiny ceiling makes every fixture log "oversized" for a second run below; the
# first run uses the default so the content metrics are exercised normally.
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
  logs_considered = 8L,
  read = 8L,
  # alpha, beta, delta/vars, eps, zeta
  with_shape_note = 6L,
  with_error = 2L,             # beta, delta/build
  with_warning = 1L,           # eps
  ended_normally = 8L,
  # ⭐ shape AND no error: alpha, delta/vars, eps, zeta. NOT beta.
  usable_for_rung_1 = 5L,
  with_any_log = 7L,
  # ⭐ alpha, delta, eps, zeta. gamma has no shape; beta's only log failed.
  with_a_usable_log = 5L
)

fail <- 0L
for (nm in names(expected)) {
  got <- num(nm)
  ok <- identical(got, expected[[nm]])
  if (!ok) fail <- fail + 1L
  message(sprintf("%-22s expected %2d  got %2d  %s", nm, expected[[nm]], got,
                  if (ok) "ok" else "FAIL"))
}

# ⚠️ THE CONTRACT ASSERTION, and the reason this scan exists in its own file.
# The output must carry no log text at all. The fixture plants distinctive words
# in the logs; none may appear in the JSON.
for (leak in c("Invented", "WORK.EXAMPLE", "observations", "real time")) {
  if (grepl(leak, j, fixed = TRUE)) {
    message("FAIL  output contains log text: ", leak); fail <- fail + 1L
  }
}
# And the dataset dimensions are detected but never read.
for (dim in c("\"100\"", ": 100", "\"7\"")) {
  if (grepl(dim, j, fixed = TRUE)) {
    message("FAIL  output may contain a dataset dimension: ", dim)
    fail <- fail + 1L
  }
}
if (!grepl("\"emits_dataset_dimensions\": false", j)) {
  message("FAIL  output does not declare that dimensions are withheld")
  fail <- fail + 1L
}
if (!fail) message(sprintf("%-22s %s", "no log text in output", "ok"))

# ⚠️ THE OVERSIZED ASSERTION. Rerun with a ceiling so small every log is skipped:
# no content metric may fire, and yet every study must still be counted as having
# a log. Under the old ordering `with_any_log` collapsed to 0.
o3 <- file.path(root, "tiny.json")
system2(rscript, c(shQuote(normalizePath(scan_script)), "--root", shQuote(root),
                   "--out", shQuote(o3), "--max-log-mb", "0.000001"),
        stdout = FALSE, stderr = FALSE)
jt <- paste(readLines(o3), collapse = " ")
numt <- function(f) as.integer(sub(".*: *", "",
  regmatches(jt, regexpr(paste0("\"", f, "\": *-?[0-9]+"), jt))))
for (c in list(list("all-oversized: read", numt("read"), 0L),
               list("all-oversized: any log", numt("with_any_log"), 7L),
               list("all-oversized: usable", numt("with_a_usable_log"), 0L))) {
  ok <- identical(c[[2]], c[[3]])
  if (!ok) fail <- fail + 1L
  message(sprintf("%-26s expected %2d  got %2d  %s", c[[1]], c[[3]], c[[2]],
                  if (ok) "ok" else "FAIL"))
}

# --count-only reads nothing and writes nothing.
o2 <- file.path(root, "count.json")
system2(rscript, c(shQuote(normalizePath(scan_script)), "--root", shQuote(root),
                   "--out", shQuote(o2), "--count-only"),
        stdout = FALSE, stderr = FALSE)
if (file.exists(o2)) {
  message("FAIL  --count-only wrote an output file"); fail <- fail + 1L
} else {
  message(sprintf("%-22s %s", "--count-only writes nothing", "ok"))
}

unlink(root, recursive = TRUE)
if (fail) { message("\n", fail, " failure(s)"); quit(save = "no", status = 1) }
message("\nall checks passed")
