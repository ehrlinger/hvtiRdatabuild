#!/usr/bin/env Rscript
# test-rung-overlap-scan.R
#
# Checks `rung-overlap-scan.R` against synthetic logs and listings whose overlap
# is known BY CONSTRUCTION.
#
#   Rscript test-rung-overlap-scan.R
#
# ⚠️ NO PHI, AND NOTHING RESEMBLING IT. Every line below is invented. A real
# `.log` can contain patient values and a real `.lst` IS printed output, which is
# why the scan's contract is the strictest in this directory; a fixture must not
# smuggle a realistic-looking one into the repository. The "print output" case
# carries invented column headers and NO rows.
#
# ⭐ THE FIXTURE IS BUILT SO EVERY JOIN FIELD HAS A DIFFERENT EXPECTED VALUE
# (both = 1, rung_1_only = 2, rung_3_only = 3, either = 6, seen = 7). Three
# fixtures in this directory previously passed while the code under them was
# wrong, each because two cases collapsed to the same number and cancelled.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
scan_script <- file.path(here, "rung-overlap-scan.R")
stopifnot(file.exists(scan_script))

if (!requireNamespace("hvtiRutilities", quietly = TRUE)) {
  message("SKIP: hvtiRutilities could not be loaded, so the scan cannot run.\n",
          "  This R:   ", R.version.string, "\n",
          "  libPaths: ", paste(.libPaths(), collapse = "\n            "))
  quit(save = "no", status = 0)
}

fail <- 0L

# ---- 1. the drift guard -----------------------------------------------------
# 🔴 `rung-overlap-scan.R` copies its detection patterns from the two scans it
# joins. A copy that drifts still runs, and the scan would then report the
# overlap of two populations that are not the ones the parent artifacts
# describe. This corpus contains 1,064 macro names whose copies drifted exactly
# that way, so the copy is GUARDED rather than trusted.
#
# ⭐ Compare the EVALUATED strings, not the source text. RE_MODEL is built with
# paste0() across four lines in both files; a textual diff would break on
# reindentation while a semantic one catches only real divergence.
patterns_in <- function(path, names) {
  env <- new.env(parent = baseenv())
  for (e in parse(path)) {
    if (is.call(e) && length(e) == 3L &&
        as.character(e[[1]]) %in% c("<-", "=") &&
        is.name(e[[2]]) && as.character(e[[2]]) %in% names) {
      assign(as.character(e[[2]]), eval(e[[3]], env), envir = env)
    }
  }
  mget(intersect(names, ls(env)), envir = env)
}

join <- patterns_in(scan_script, c("RE_SHAPE", "RE_ERROR", "RE_MODEL"))
from_log <- patterns_in(file.path(here, "log-verifiability-scan.R"),
                        c("RE_SHAPE", "RE_ERROR"))
from_lst <- patterns_in(file.path(here, "lst-listing-scan.R"), c("RE_MODEL"))
parents <- c(from_log, from_lst)

for (nm in names(parents)) {
  if (!nm %in% names(join)) {
    message("FAIL  ", nm, " is not defined in rung-overlap-scan.R"); fail <- fail + 1L
  } else if (!identical(join[[nm]], parents[[nm]])) {
    message("FAIL  ", nm, " has DRIFTED from its parent scan"); fail <- fail + 1L
  } else {
    message(sprintf("%-28s %s", paste0(nm, " matches parent"), "ok"))
  }
}
if (length(parents) != 3L) {
  message("FAIL  expected 3 parent patterns, found ", length(parents))
  fail <- fail + 1L
}

# ---- 2. the join itself -----------------------------------------------------
root <- file.path(tempdir(), paste0("rung-fixture-", Sys.getpid()))
folder <- unique(hvtiRutilities::hvti_taxonomy()$folder)[[1]]
put <- function(study, file, lines) {
  d <- file.path(root, study, folder)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, file.path(d, file))
}
SHAPE <- "NOTE: The data set WORK.INVENTED has 1 observations and 1 variables."
ENDOK <- "NOTE: SAS Institute Inc., invented fixture."
MODEL <- c("The INVENTED Procedure", "Parameter Estimates")

# A: usable log AND a model listing        -> BOTH
put("cardiac/a", "run.log", c(SHAPE, ENDOK))
put("cardiac/a", "fit.lst", MODEL)
# B: usable log only                       -> rung 1 only
put("cardiac/b", "run.log", c(SHAPE, ENDOK))
# G: usable log only, so rung_1_only is 2 and cannot be confused with `both`
put("cardiac/g", "run.log", c(SHAPE, ENDOK))
# C: model listing only                    -> rung 3 only
put("cardiac/c", "fit.lst", MODEL)
# D: log has a shape BUT an ERROR, so rung 1 fails; listing still gives rung 3.
#    ⭐ This is the case that separates "kept a log" from "kept a usable one".
put("thoracic/d", "run.log", c(SHAPE, "ERROR: invented failure.", ENDOK))
put("thoracic/d", "fit.lst", MODEL)
# E: a log with no shape and a listing with print output only -> NEITHER rung,
#    but still SEEN. ⚠️ Invented headers, no rows.
put("thoracic/e", "run.log", c("NOTE: invented note with no shape.", ENDOK))
put("thoracic/e", "out.lst", c("The PRINT Procedure",
                               "Obs    InventedColumn    AnotherInvented"))
# F: two listings, only one a model, so the study is counted ONCE
put("cardiac/f", "fit.lst", MODEL)
put("cardiac/f", "freq.lst", c("The INVENTED Procedure", "(no estimates here)"))

outfile <- file.path(root, "out.json")
rscript <- file.path(R.home("bin"), "Rscript")
res <- system2(rscript, c(shQuote(normalizePath(scan_script)),
                          "--root", shQuote(root), "--out", shQuote(outfile)),
               stdout = TRUE, stderr = TRUE)
if (!file.exists(outfile)) { cat(res, sep = "\n"); stop("scan produced no output") }
j <- paste(readLines(outfile), collapse = " ")
num <- function(field) {
  m <- regmatches(j, regexpr(paste0("\"", field, "\": *-?[0-9]+"), j))
  if (!length(m)) stop("field not found: ", field)
  as.integer(sub(".*: *", "", m))
}

expected <- list(
  logs_read              = 5L,   # a, b, g, d, e
  logs_usable_for_rung_1 = 3L,   # a, b, g -- d has an ERROR, e has no shape
  listings_read          = 6L,   # a, c, d, e, f x2
  listings_with_a_model  = 4L,   # a, c, d, f
  both_rungs             = 1L,   # a
  rung_1_only            = 2L,   # b, g
  rung_3_only            = 3L,   # c, d, f
  either_rung            = 6L,
  with_a_usable_log      = 3L,
  with_a_model_listing   = 4L,   # ⭐ f counted once despite two listings
  seen_with_any_log_or_listing = 7L
)
for (nm in names(expected)) {
  got <- num(nm)
  ok <- identical(got, expected[[nm]])
  if (!ok) fail <- fail + 1L
  message(sprintf("%-28s expected %2d  got %2d  %s", nm, expected[[nm]], got,
                  if (ok) "ok" else "FAIL"))
}

# ---- 3. the contract --------------------------------------------------------
# 🔴 Nothing from a log or a listing, and NO STUDY IDENTIFIER, may reach the
# output. The fixture plants distinctive words and study names, and none may
# appear.
for (leak in c("invented", "Invented", "INVENTED", "cardiac", "thoracic",
               "Parameter Estimates", "Obs", "Procedure", "WORK.")) {
  if (grepl(leak, j, fixed = TRUE)) {
    message("FAIL  output contains fixture text: ", leak); fail <- fail + 1L
  }
}
for (decl in c("\"emits_study_identifiers\": false",
               "\"emits_dataset_dimensions\": false",
               "\"emits_listing_values\": false")) {
  if (!grepl(decl, j, fixed = TRUE)) {
    message("FAIL  output does not declare: ", decl); fail <- fail + 1L
  }
}
if (!fail) message(sprintf("%-28s %s", "no fixture text in output", "ok"))

# ---- 4. existence survives the oversized skip -------------------------------
# ⭐ Both parent scans were fixed on 2026-09-06 because they attributed a study
# AFTER skipping oversized files, so a study whose only log was oversized read as
# having no log at all. This scan was written with the corrected ordering, and
# this run is what holds it there: with the ceiling below every file, EXISTENCE
# must survive intact while every content metric goes to zero.
o3 <- file.path(root, "oversized.json")
system2(rscript, c(shQuote(normalizePath(scan_script)), "--root", shQuote(root),
                   "--out", shQuote(o3), "--max-mb", "0.000001"),
        stdout = FALSE, stderr = FALSE)
if (!file.exists(o3)) {
  message("FAIL  the all-oversized run produced no output"); fail <- fail + 1L
} else {
  j <- paste(readLines(o3), collapse = " ")
  over <- list(logs_read = 0L, listings_read = 0L, logs_usable_for_rung_1 = 0L,
               listings_with_a_model = 0L, both_rungs = 0L, either_rung = 0L,
               logs_oversized = 5L, listings_oversized = 6L,
               seen_with_any_log_or_listing = 7L)   # ⭐ existence is untouched
  for (nm in names(over)) {
    got <- num(nm)
    ok <- identical(got, over[[nm]])
    if (!ok) fail <- fail + 1L
    message(sprintf("oversized: %-17s expected %2d  got %2d  %s", nm, over[[nm]],
                    got, if (ok) "ok" else "FAIL"))
  }
}

# ---- 5. --count-only writes nothing -----------------------------------------
o2 <- file.path(root, "count.json")
system2(rscript, c(shQuote(normalizePath(scan_script)), "--root", shQuote(root),
                   "--out", shQuote(o2), "--count-only"),
        stdout = FALSE, stderr = FALSE)
if (file.exists(o2)) {
  message("FAIL  --count-only wrote an output file"); fail <- fail + 1L
} else message(sprintf("%-28s %s", "--count-only writes nothing", "ok"))

unlink(root, recursive = TRUE)
if (fail) { message("\n", fail, " failure(s)"); quit(save = "no", status = 1) }
message("\nall checks passed")
