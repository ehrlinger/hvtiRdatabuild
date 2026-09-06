#!/usr/bin/env Rscript
# test-build-structure-scan.R
#
# Checks `build-structure-scan.R` against synthetic builds whose structure is
# known by construction.
#
#   Rscript test-build-structure-scan.R
#
# NO PHI. Every study name, library, dataset and variable here is invented.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
scan_script <- file.path(here, "build-structure-scan.R")
stopifnot(file.exists(scan_script))

if (!requireNamespace("hvtiRutilities", quietly = TRUE)) {
  message("SKIP: hvtiRutilities could not be loaded, so the scan cannot run.\n",
          "  This R:   ", R.version.string, "\n",
          "  libPaths: ", paste(.libPaths(), collapse = "\n            "))
  quit(save = "no", status = 0)
}

root <- file.path(tempdir(), paste0("build-fixture-", Sys.getpid()))
folder <- unique(hvtiRutilities::hvti_taxonomy()$folder)[[1]]
put <- function(study, file, lines) {
  d <- file.path(root, study, folder)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, file.path(d, file))
}

# ---- the corpus -------------------------------------------------------------

# ⭐ alpha and beta run the SAME STEPS IN THE SAME ORDER with different text.
# Two distinct bodies, ONE step shape. The gap between those two counts is how
# much of the corpus variation is cosmetic, which is the number S2 needs.
put("cardiac/alpha", "build.sas",
    c("data one; set src.raw;", "run;",
      "proc sort data=one; by id;", "run;",
      "proc means data=one;", "run;"))
put("cardiac/beta", "build.sas",
    c("data two; set src.other;", "run;",
      "proc sort data=two; by key;", "run;",
      "proc means data=two;", "run;"))

# gamma runs a different shape, and reads a second library.
put("thoracic/gamma", "build.sas",
    c("data g; merge whse.a whse.b; by id;", "run;",
      "proc freq data=g;", "run;"))

# delta composes: it includes another file and calls a macro.
put("cardiac/delta", "build.sas",
    c("%include 'vars.sas';", "%vars(data=d);",
      "data d; set src.raw;", "run;"))

# ⚠️ epsilon reads a library only IT uses. Below the floor, so its name must not
# be emitted: a one-study libref is not an institutional source.
put("cardiac/eps", "build.sas",
    c("data e; set privatelib.thing;", "run;"))

# ---- run --------------------------------------------------------------------

outfile <- file.path(root, "out.json")
rscript <- file.path(R.home("bin"), "Rscript")
res <- system2(rscript, c(shQuote(normalizePath(scan_script)),
                          "--root", shQuote(root), "--out", shQuote(outfile),
                          "--min-libref", "2"),
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
  files = 5L,
  studies = 5L,
  # alpha/beta differ in text, gamma, delta, eps
  distinct_bodies = 5L,
  # ⭐ THREE shapes from five builds: `data>sort>means` (alpha and beta, whose
  # text differs), `data>freq` (gamma), and a bare `data` (delta and eps).
  # ⚠️ delta and eps share a shape although their text does not: %include and a
  # macro call are not steps, so delta reduces to its one DATA step. That is the
  # metric working rather than failing. Five distinct bodies, three shapes.
  distinct_step_shapes = 3L,
  uses_include = 1L,
  calls_a_macro = 1L
)

fail <- 0L
for (nm in names(expected)) {
  got <- num(nm)
  ok <- identical(got, expected[[nm]])
  if (!ok) fail <- fail + 1L
  message(sprintf("%-24s expected %2d  got %2d  %s", nm, expected[[nm]], got,
                  if (ok) "ok" else "FAIL"))
}

# `src` is read by alpha, beta and delta, so it clears a floor of 2 and is named.
if (!grepl("\"name\": \"src\"", j)) {
  message("FAIL  the shared libref src was not reported"); fail <- fail + 1L
} else message(sprintf("%-24s %s", "shared libref reported", "ok"))

# ⚠️ THE FLOOR ASSERTION. `privatelib` is read by one study only and must not
# appear: a one-study library alias is not an institutional source, and emitting
# it would widen this scan's contract past what it claims.
if (grepl("privatelib", j, fixed = TRUE)) {
  message("FAIL  a one-study libref was emitted despite the floor"); fail <- fail + 1L
} else message(sprintf("%-24s %s", "one-study libref withheld", "ok"))

# `whse` is read by gamma only, also below the floor.
if (grepl("\"name\": \"whse\"", j)) {
  message("FAIL  whse is below the floor and was emitted"); fail <- fail + 1L
}

# PROC names are reported; `sort`, `means` and `freq` all appear.
for (p in c("sort", "means", "freq")) {
  if (!grepl(paste0("\"name\": \"", p, "\""), j)) {
    message("FAIL  proc not reported: ", p); fail <- fail + 1L
  }
}

# --count-only reads nothing and writes nothing.
o2 <- file.path(root, "count.json")
system2(rscript, c(shQuote(normalizePath(scan_script)), "--root", shQuote(root),
                   "--out", shQuote(o2), "--count-only"),
        stdout = FALSE, stderr = FALSE)
if (file.exists(o2)) {
  message("FAIL  --count-only wrote an output file"); fail <- fail + 1L
} else message(sprintf("%-24s %s", "--count-only writes nothing", "ok"))

unlink(root, recursive = TRUE)
if (fail) { message("\n", fail, " failure(s)"); quit(save = "no", status = 1) }
message("\nall checks passed")
