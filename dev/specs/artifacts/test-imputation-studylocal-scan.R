#!/usr/bin/env Rscript
# test-imputation-studylocal-scan.R
#
# Checks `imputation-studylocal-scan.R` against a synthetic corpus built so that
# the CORPUS-WIDE answer and the STUDY-LOCAL answer differ, which is the whole
# claim the scan makes.
#
#   Rscript test-imputation-studylocal-scan.R
#
# NO PHI. Every study name, macro, variable and value here is invented.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
scan_script <- file.path(here, "imputation-studylocal-scan.R")
stopifnot(file.exists(scan_script))

if (!requireNamespace("hvtiRutilities", quietly = TRUE)) {
  message("SKIP: hvtiRutilities could not be loaded, so the scan cannot run.\n",
          "  This R:   ", R.version.string, "\n",
          "  libPaths: ", paste(.libPaths(), collapse = "\n            "))
  quit(save = "no", status = 0)
}

root <- file.path(tempdir(), paste0("studylocal-fixture-", Sys.getpid()))
folder <- unique(hvtiRutilities::hvti_taxonomy()$folder)[[1]]
put <- function(study, file, lines) {
  d <- file.path(root, study, folder)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, file.path(d, file))
}
defn <- function(nm, dflt) {
  c(paste0("%macro ", nm, "(data=, nimpute=", dflt, ");"),
    "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;")
}

# ---- the corpus -------------------------------------------------------------
# ⭐ `mi_shared` is declared with THREE different defaults across studies, so a
# corpus-wide map cannot settle any call to it. Every call below omits the
# argument, so under the old global resolution all four would be undeterminable.

# alpha holds the copy declaring 5, and calls it. Study-local answer: 5.
put("cardiac/alpha", "mult_imput_shared.sas", defn("mi_shared", 5))
put("cardiac/alpha", "driver.sas", c("%mi_shared(data=w);"))

# ⚠️ beta holds the copy declaring 1, and calls it. Study-local answer: 1.
# Globally indistinguishable from alpha's call; locally the opposite answer.
# This is the case the scan exists to separate.
put("cardiac/beta", "mult_imput_shared.sas", defn("mi_shared", 1))
put("cardiac/beta", "driver.sas", c("%mi_shared(data=w);"))

# gamma holds TWO copies that disagree with each other, so even locally the
# call is ambiguous. It must not be counted as determinate.
put("vascular/thoracic-aorta/gamma", "mult_imput_shared.sas", defn("mi_shared", 5))
put("vascular/thoracic-aorta/gamma", "mult_imput_shared2.sas", defn("mi_shared", 20))
put("vascular/thoracic-aorta/gamma", "driver.sas", c("%mi_shared(data=w);"))

# delta holds NO copy of mi_shared but calls it, so only the corpus-wide map is
# available -- and that map conflicts. Global fallback, flagged as conflicting.
# delta needs a stem file of its own to be in scope at all.
put("cardiac/delta", "mult_imput_other.sas", defn("mi_other", 7))
put("cardiac/delta", "driver.sas", c("%mi_shared(data=w);"))

# epsilon holds no copy of mi_agreed and calls it; every copy of mi_agreed
# anywhere declares 9, so the global fallback is usable.
put("cardiac/eps1", "mult_imput_agreed.sas", defn("mi_agreed", 9))
put("cardiac/eps2", "mult_imput_agreed.sas", defn("mi_agreed", 9))
put("cardiac/eps3", "mult_imput_x.sas", defn("mi_x", 4))
put("cardiac/eps3", "driver.sas", c("%mi_agreed(data=w);"))

# ⚠️ mi_sig: the two copies bind NIMPUTE through DIFFERENT PARAMETER NAMES.
# eta's copy uses `nimpute`, theta's uses `reps`. eta's call names `nimpute`, so
# it must read as stating its value. Keyed by macro name alone, whichever copy
# was read last would control parsing in BOTH studies, and eta's explicit
# argument would read as omitted and be credited to a default instead.
put("cardiac/eta", "mult_imput_sig.sas", defn("mi_sig", 5))
put("thoracic/theta", "mult_imput_sig.sas",
    c("%macro mi_sig(data=, reps=9);",
      "proc mi data=&data out=m nimpute=&reps;", "run;", "%mend;"))
put("cardiac/eta", "driver.sas", c("%mi_sig(data=w, nimpute=12);"))

# ⚠️ mi_mix: a MIXED call, positional then keyword, which SAS allows. The
# positional `30` supplies NIMPUTE. A positional lookup gated on the call having
# no keyword arguments discards it and reports the parameter as omitted.
put("cardiac/iota", "mult_imput_mix.sas",
    c("%macro mi_mix(data, nimpute, seed=);",
      "proc mi data=&data out=m nimpute=&nimpute seed=&seed;", "run;", "%mend;"))
put("cardiac/iota", "driver.sas", c("%mi_mix(w, 30, seed=7);"))

# zeta states the value outright, which beats every inference.
put("cardiac/zeta", "mult_imput_z.sas", defn("mi_z", 5))
put("cardiac/zeta", "driver.sas", c("%mi_z(data=w, nimpute=25);"))

# ---- run --------------------------------------------------------------------

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
  # alpha, beta, gamma, delta, eps3, eta, iota, zeta
  calls = 8L,
  # zeta's 25, eta's 12 (divergent parameter name), iota's 30 (mixed call)
  from_argument = 3L,
  # ⭐ alpha (5) and beta (1). Globally these two are the SAME undeterminable
  # call; locally they are opposite answers, and both are determinate.
  from_study_local = 2L,
  study_local_ambiguous = 1L,  # gamma holds two copies that disagree
  global_fallback_ok = 1L,     # eps3: every copy of mi_agreed says 9
  global_fallback_conflict = 1L,  # delta: mi_shared conflicts corpus-wide
  unresolved = 0L,
  # argument + study-local only: 25, 12, 30, 5, 1
  n = 5L,
  nimpute_1 = 1L,
  nimpute_gt1 = 4L,
  nimpute_0 = 0L
)

fail <- 0L
for (nm in names(expected)) {
  got <- num(nm)
  ok <- identical(got, expected[[nm]])
  if (!ok) fail <- fail + 1L
  message(sprintf("%-26s expected %2d  got %2d  %s", nm, expected[[nm]], got,
                  if (ok) "ok" else "FAIL"))
}

# The routes must partition the calls, or one was double-counted or dropped.
if (num("from_argument") + num("from_study_local") + num("study_local_ambiguous") +
    num("global_fallback_ok") + num("global_fallback_conflict") +
    num("unresolved") != num("calls")) {
  message("FAIL  routes do not partition the calls")
  fail <- fail + 1L
}

# ⭐ The claim, asserted directly: beta's 1 and alpha's 5 both appear, so the
# study-local route separated two calls a corpus-wide map cannot tell apart.
# Extract the block properly: `sub("\\}.*", "", j)` truncates at the FIRST
# closing brace in the document, which is many blocks earlier.
i <- regexpr("\"from_study_local\": \\{", j)
rest <- substring(j, i + attr(i, "match.length"))
loc <- substring(rest, 1, regexpr("\\}", rest) - 1)
if (!grepl("\"1\"", loc) || !grepl("\"5\"", loc)) {
  message("FAIL  study-local route did not yield both 1 and 5")
  fail <- fail + 1L
} else {
  message(sprintf("%-26s %s", "local route yields 1 and 5", "ok"))
}

unlink(root, recursive = TRUE)
if (fail) { message("\n", fail, " failure(s)"); quit(save = "no", status = 1) }
message("\nall checks passed")
