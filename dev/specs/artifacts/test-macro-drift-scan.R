#!/usr/bin/env Rscript
# test-macro-drift-scan.R
#
# Checks `macro-drift-scan.R` against a synthetic corpus whose drift is known by
# construction.
#
#   Rscript test-macro-drift-scan.R
#
# The fixture pins the distinction the scan exists to draw: a name whose copies
# differ only in the HEADER (signature or defaults drifted, which is what bit the
# imputation macros) against a name whose copies differ BELOW it (what the macro
# DOES drifted).
#
# NO PHI. Every study name, macro and value here is invented.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
scan_script <- file.path(here, "macro-drift-scan.R")
stopifnot(file.exists(scan_script))

if (!requireNamespace("hvtiRutilities", quietly = TRUE)) {
  message("SKIP: hvtiRutilities could not be loaded, so the scan cannot run.\n",
          "  This R:   ", R.version.string, "\n",
          "  libPaths: ", paste(.libPaths(), collapse = "\n            "))
  quit(save = "no", status = 0)
}

root <- file.path(tempdir(), paste0("drift-fixture-", Sys.getpid()))
folder <- unique(hvtiRutilities::hvti_taxonomy()$folder)[[1]]
put <- function(study, file, lines) {
  d <- file.path(root, study, folder)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, file.path(d, file))
}

# ---- the corpus -------------------------------------------------------------

# m_same: three identical copies. Several copies, no drift.
for (st in c("cardiac/a", "cardiac/b", "thoracic/c")) {
  put(st, "m_same.sas",
      c("%macro m_same(data=);", "proc means data=&data;", "run;", "%mend;"))
}

# m_hdr: two copies differing ONLY in the header, which is the imputation
# pattern: the signature or a default drifted, the work did not.
put("cardiac/d", "m_hdr.sas",
    c("%macro m_hdr(data=, n=5);", "proc mi data=&data nimpute=&n;", "run;", "%mend;"))
put("cardiac/e", "m_hdr.sas",
    c("%macro m_hdr(data=, n=10);", "proc mi data=&data nimpute=&n;", "run;", "%mend;"))

# m_body: two copies differing BELOW the header. What the macro does drifted.
put("cardiac/f", "m_body.sas",
    c("%macro m_body(data=);", "proc means data=&data;", "run;", "%mend;"))
put("thoracic/g", "m_body.sas",
    c("%macro m_body(data=);", "proc means data=&data;", "  var age;", "run;", "%mend;"))

# m_once: one copy only. Cannot drift, and must not be counted as many-copy.
put("cardiac/h", "m_once.sas",
    c("%macro m_once(data=);", "proc freq data=&data;", "run;", "%mend;"))

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
  macro_names = 4L,
  names_in_one_copy = 1L,          # m_once
  names_in_many_copies = 3L,       # m_same, m_hdr, m_body
  names_drifted = 2L,              # m_hdr and m_body; m_same is identical
  # ⭐ the distinction the scan exists to draw
  names_drifted_below_header = 1L, # m_body only
  names_drifted_header_only = 1L,  # m_hdr only
  macro_definitions = 8L,
  max_copies = 3L                  # m_same
)

fail <- 0L
for (nm in names(expected)) {
  got <- num(nm)
  ok <- identical(got, expected[[nm]])
  if (!ok) fail <- fail + 1L
  message(sprintf("%-28s expected %2d  got %2d  %s", nm, expected[[nm]], got,
                  if (ok) "ok" else "FAIL"))
}

# The three many-copy outcomes must partition, or a name was double-counted.
if (num("names_in_one_copy") + num("names_in_many_copies") != num("macro_names")) {
  message("FAIL  copy counts do not partition the names"); fail <- fail + 1L
}
if (num("names_drifted_below_header") + num("names_drifted_header_only") !=
    num("names_drifted")) {
  message("FAIL  drift kinds do not partition the drifted names"); fail <- fail + 1L
}

# `worst` must be a JSON array, per the serializer fix in #41, and must name the
# drifted macros and not the identical one.
if (!any(grepl("\"worst\": \\[", raw))) {
  message("FAIL  worst is not a JSON array"); fail <- fail + 1L
}
for (nm in c("m_hdr", "m_body")) {
  if (!grepl(paste0("\"macro\": \"", nm, "\""), j)) {
    message("FAIL  ", nm, " missing from worst"); fail <- fail + 1L
  }
}
if (grepl("\"macro\": \"m_same\"", j)) {
  message("FAIL  m_same has no drift and must not appear in worst"); fail <- fail + 1L
}
if (!fail) message(sprintf("%-28s %s", "worst names the drifted only", "ok"))

# --count-only must read nothing and write nothing.
o2 <- file.path(root, "count.json")
system2(rscript, c(shQuote(normalizePath(scan_script)), "--root", shQuote(root),
                   "--out", shQuote(o2), "--count-only"),
        stdout = FALSE, stderr = FALSE)
if (file.exists(o2)) {
  message("FAIL  --count-only wrote an output file"); fail <- fail + 1L
} else {
  message(sprintf("%-28s %s", "--count-only writes nothing", "ok"))
}

unlink(root, recursive = TRUE)
if (fail) { message("\n", fail, " failure(s)"); quit(save = "no", status = 1) }
message("\nall checks passed")
