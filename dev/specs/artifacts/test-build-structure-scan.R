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
    c("libname src '/invented/mount/alpha';",
      "data one; set src.raw;", "run;",
      "proc sort data=one; by id;", "run;",
      "proc means data=one;", "run;"))
put("cardiac/beta", "build.sas",
    c("libname src '/invented/mount/beta';",
      "data two; set src.other;", "run;",
      "proc sort data=two; by key;", "run;",
      "proc means data=two;", "run;"))

# gamma runs a different shape, and reads a second library.
put("thoracic/gamma", "build.sas",
    c("data g; merge whse.a whse.b; by id;", "run;",
      "proc freq data=g;", "run;"))

# delta composes: it includes another file and calls a macro.
put("cardiac/delta", "build.sas",
    c("libname src '/invented/mount/delta';",
      "%include 'vars.sas';", "%vars(data=d);",
      "data d; set src.raw;", "run;"))

# ⚠️ zeta exercises the macro-call metric in both directions. `%sysfunc(...)` is
# a BUILT-IN FUNCTION and must not count as composition; `%refresh;` is a
# parameterless USER call and must; and `%helper()` inside a %macro body is a
# definition's internals, not the build's flow.
put("cardiac/zeta", "build.sas",
    c("%let n = %sysfunc(today());",
      "%macro inner(); %helper(); %mend;",
      "%refresh;",
      "data z; set src.raw;", "run;"))

# ⚠️ eta has NO steps at all, only an include. It must not be counted among the
# files carrying a DATA or PROC step: the earlier version called every file in
# the folder a build, and `steps_min = 0` was the evidence against that.
put("cardiac/eta", "build.sas", c("%include 'other.sas';"))

# ⚠️ epsilon reads a library only IT uses, and points it at a path only it uses.
# Both are below the floor and neither may be emitted: a one-study alias is not
# an institutional source, and a one-study path is a study identifier.
put("cardiac/eps", "build.sas",
    c("libname privatelib '/someones/private/corner';",
      "data e; set privatelib.thing;", "run;"))

# 🔴 IDENTIFYING NAMES THAT CLEAR THE FLOOR. The 2026-09-06 run emitted
# `/home/mgoormas`, a personal directory naming an individual, and `st1027`, a
# study identifier used as a libref by 247 studies. Both were COMMON, so the
# frequency floor passed them: the floor assumes an identifying name is a rare
# name, and a shared reference to one study's library is neither.
# Three studies each, so both clear a floor of 2 and must still be rejected.
for (stx in c("cardiac/i1", "cardiac/i2", "thoracic/i3")) {
  put(stx, "build.sas",
      c("libname home1 '/home/someuser/lib';",
        "data z; set st9999.thing;", "run;"))
}

# ⚠️ A build OUTSIDE the taxonomy folder. Folder scoping must exclude it, so
# nothing here reaches any count.
d <- file.path(root, "cardiac/outside", "notafolder")
dir.create(d, recursive = TRUE, showWarnings = FALSE)
writeLines(c("data x; set excluded.thing;", "run;"), file.path(d, "build.sas"))

# ---- run --------------------------------------------------------------------

outfile <- file.path(root, "out.json")
rscript <- file.path(R.home("bin"), "Rscript")
res <- system2(rscript, c(shQuote(normalizePath(scan_script)),
                          "--root", shQuote(root), "--out", shQuote(outfile),
                          "--min-libref", "2", "--path-depth", "2"),
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
  files = 10L,
  studies = 10L,
  # alpha/beta differ in text, gamma, delta, eps, and the three identical i* ones
  distinct_bodies = 8L,
  # ⭐ THREE shapes from five builds: `data>sort>means` (alpha and beta, whose
  # text differs), `data>freq` (gamma), and a bare `data` (delta and eps).
  # ⚠️ delta and eps share a shape although their text does not: %include and a
  # macro call are not steps, so delta reduces to its one DATA step. That is the
  # metric working rather than failing. Five distinct bodies, three shapes.
  # data>sort>means, data>freq, bare data, and eta's empty shape
  distinct_step_shapes = 4L,
  # ⭐ eta has none; every other file has at least one
  files_with_at_least_one_step = 9L,
  files_with_no_steps = 1L,
  uses_include = 2L,
  # ⭐ delta's %vars(...) and zeta's parameterless %refresh;. NOT zeta's
  # %sysfunc (a built-in) and NOT %helper (inside a %macro body).
  calls_a_user_macro = 2L
)

fail <- 0L
for (nm in names(expected)) {
  got <- num(nm)
  ok <- identical(got, expected[[nm]])
  if (!ok) fail <- fail + 1L
  message(sprintf("%-24s expected %2d  got %2d  %s", nm, expected[[nm]], got,
                  if (ok) "ok" else "FAIL"))
}

# 🔴 THE DEFAULT IS COUNTS ONLY. Without --emit-names no name may appear at all,
# so forgetting the flag yields a safe artifact rather than an unsafe one.
if (grepl("\"name\":", j, fixed = TRUE)) {
  message("FAIL  names were emitted without --emit-names"); fail <- fail + 1L
} else message(sprintf("%-30s %s", "default emits no names", "ok"))

# Now the opt-in run, which is where the filters have to hold.
o3 <- file.path(root, "named.json")
system2(rscript, c(shQuote(normalizePath(scan_script)), "--root", shQuote(root),
                   "--out", shQuote(o3), "--min-libref", "2", "--emit-names"),
        stdout = FALSE, stderr = FALSE)
jn <- paste(readLines(o3), collapse = " ")

if (!grepl("\"name\": \"src\"", jn)) {
  message("FAIL  the shared libref src was not reported"); fail <- fail + 1L
} else message(sprintf("%-30s %s", "named run reports src", "ok"))

if (grepl("privatelib", jn, fixed = TRUE)) {
  message("FAIL  a one-study libref was emitted despite the floor"); fail <- fail + 1L
} else message(sprintf("%-30s %s", "one-study libref withheld", "ok"))

# 🔴 THE IDENTIFIER ASSERTIONS. Both of these clear the floor and must still be
# rejected: a personal home directory and a study identifier.
if (grepl("someuser", jn, fixed = TRUE) || grepl("/home/", jn, fixed = TRUE)) {
  message("FAIL  a personal home directory was emitted"); fail <- fail + 1L
} else message(sprintf("%-30s %s", "personal directory rejected", "ok"))
if (grepl("st9999", jn, fixed = TRUE)) {
  message("FAIL  a study identifier was emitted"); fail <- fail + 1L
} else message(sprintf("%-30s %s", "study identifier rejected", "ok"))
if (!grepl("withheld_as_identifying\": [1-9]", jn)) {
  message("FAIL  rejections were not counted"); fail <- fail + 1L
} else message(sprintf("%-30s %s", "rejections counted", "ok"))

# `whse` is read by gamma only, also below the floor.
if (grepl("\"name\": \"whse\"", jn)) {
  message("FAIL  whse is below the floor and was emitted"); fail <- fail + 1L
}

# ⭐ THE UPSTREAM ASSERTION. Three studies point a LIBNAME at /invented/mount/...,
# so the two-component prefix clears a floor of 2 and is reported. This is what
# the libref alias could not tell us.
if (!grepl("/invented/mount", jn, fixed = TRUE)) {
  message("FAIL  the shared LIBNAME target was not reported"); fail <- fail + 1L
} else message(sprintf("%-24s %s", "shared LIBNAME reported", "ok"))

# ⚠️ AND THE FLOOR ON PATHS. epsilon's path is used by one study and must not
# appear: a one-study path is a study identifier, not an institutional mount.
if (grepl("someones", jn, fixed = TRUE) || grepl("private/corner", jn, fixed = TRUE)) {
  message("FAIL  a one-study LIBNAME path was emitted"); fail <- fail + 1L
} else message(sprintf("%-24s %s", "one-study path withheld", "ok"))

# ⚠️ And the folder scope excluded the build outside the taxonomy folder.
if (grepl("excluded", jn, fixed = TRUE)) {
  message("FAIL  a build outside the taxonomy folder was scanned"); fail <- fail + 1L
}

# PROC names are reported; `sort`, `means` and `freq` all appear.
for (p in c("sort", "means", "freq")) {
  if (!grepl(paste0("\"name\": \"", p, "\""), jn)) {
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
