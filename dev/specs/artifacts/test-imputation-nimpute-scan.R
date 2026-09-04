#!/usr/bin/env Rscript
# test-imputation-nimpute-scan.R
#
# Checks `imputation-nimpute-scan.R` against a synthetic corpus with a known
# answer. Same reasoning as its siblings: `dev/` is `.Rbuildignore`d, so the
# package suite never sees this script.
#
# The cases below encode every way a NIMPUTE value reaches PROC MI in this
# corpus -- keyword argument, positional argument, caller's %let, definition
# default, body-local %let, and a literal -- plus the two that must NOT resolve.
#
#   Rscript test-imputation-nimpute-scan.R
#
# NO PHI. Every study name, macro, variable and value here is invented.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
scan_script <- file.path(here, "imputation-nimpute-scan.R")
stopifnot(file.exists(scan_script))

if (!requireNamespace("hvtiRutilities", quietly = TRUE)) {
  message("SKIP: hvtiRutilities could not be loaded, so the scan cannot run.\n",
          "  This R:   ", R.version.string, "\n",
          "  libPaths: ", paste(.libPaths(), collapse = "\n            "), "\n",
          "It may be absent, or built by a different R than this one.")
  quit(save = "no", status = 0)
}

root <- file.path(tempdir(), paste0("nimpute-fixture-", Sys.getpid()))
folder <- unique(hvtiRutilities::hvti_taxonomy()$folder)[[1]]

put <- function(study, file, lines) {
  d <- file.path(root, study, folder)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, file.path(d, file))
}

# ---- the corpus -------------------------------------------------------------
# Each macro gets a distinct name: the map is global and keyed by name, so
# reusing one name across cases would collapse them into a single binding.

# mi_kw: keyword argument at the call site. THE dominant real-world shape --
# definition and call in different files, in different studies.
put("cardiac/alpha", "mult_imput_kw.sas",
    c("%macro mi_kw(data=, nimpute=5);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("cardiac/beta", "driver.sas", c("%mi_kw(data=w, nimpute=25);"))

# mi_pos: positional argument. Resolved by the parameter's index.
put("cardiac/gamma", "mult_imput_pos.sas",
    c("%macro mi_pos(data, nimpute);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("cardiac/gamma", "driver_pos.sas", c("%mi_pos(w, 7);"))

# mi_let: the caller passes a macro variable, set by %let in the caller's file.
# ⚠️ The value is 1 -- SINGLE imputation from a macro named for multiple.
put("cardiac/delta", "mult_imput_let.sas",
    c("%macro mi_let(data=, nimpute=);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("cardiac/delta", "driver_let.sas",
    c("%let n = 1;", "%mi_let(data=w, nimpute=&n);"))

# mi_def: the call omits the argument, so the definition's DEFAULT applies.
put("vascular/thoracic-aorta/eps", "mult_imput_def.sas",
    c("%macro mi_def(data=, nimpute=10);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("vascular/thoracic-aorta/eps", "driver_def.sas", c("%mi_def(data=w);"))

# mi_local: NIMPUTE comes from a %let inside the macro BODY. Settled by the
# definition alone; no call is needed and none is written.
put("cardiac/zeta", "mult_imput_local.sas",
    c("%macro mi_local(data=);", "%let inner = 3;",
      "proc mi data=&data out=m nimpute=&inner;", "run;", "%mend;"))

# mi_lit: a literal in the definition. Also settled without a call.
put("cardiac/eta", "mult_imput_lit.sas",
    c("%macro mi_lit(data=);",
      "proc mi data=&data out=m nimpute=40;", "run;", "%mend;"))

# mi_unres: the caller passes a macro variable never set anywhere we can see.
# Must count as unresolved, and must NOT contribute a value.
put("cardiac/theta", "mult_imput_unres.sas",
    c("%macro mi_unres(data=, nimpute=);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("cardiac/theta", "driver_unres.sas", c("%mi_unres(data=w, nimpute=&outside);"))

# A commented-out call must not count.
put("cardiac/iota", "mult_imput_cmt.sas",
    c("%macro mi_cmt(data=, nimpute=9);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("cardiac/iota", "driver_cmt.sas", c("* %mi_cmt(data=w, nimpute=2);"))

# ---- run --------------------------------------------------------------------

outfile <- file.path(root, "out.json")
rscript <- file.path(R.home("bin"), "Rscript")
res <- system2(rscript, c(shQuote(normalizePath(scan_script)),
                          "--root", shQuote(root), "--out", shQuote(outfile),
                          "--all-studies"),
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
  # eight macros, every one binding NIMPUTE
  macros_binding_nimpute = 8L,
  binding_literal = 1L,   # mi_lit
  binding_local   = 1L,   # mi_local
  binding_param   = 6L,   # the rest
  conflicting_redefinitions = 0L,
  # mi_kw, mi_pos, mi_let, mi_def, mi_unres. NOT mi_cmt -- commented out.
  calls_to_parameterised_macros = 5L,
  resolved_from_argument = 3L,   # 25, 7, 1
  resolved_from_default  = 1L,   # mi_def's 10
  unresolved             = 1L,   # mi_unres
  settled_by_definition_alone = 2L,  # mi_local's 3, mi_lit's 40
  # 25, 7, 1, 10, 3, 40
  resolved_total = 6L,
  nimpute_1   = 1L,
  nimpute_gt1 = 5L,
  nimpute_0   = 0L
)

fail <- 0L
for (nm in names(expected)) {
  got <- num(nm)
  ok <- identical(got, expected[[nm]])
  if (!ok) fail <- fail + 1L
  message(sprintf("%-32s expected %2d  got %2d  %s",
                  nm, expected[[nm]], got, if (ok) "ok" else "FAIL"))
}

# Call outcomes must partition, or a call was counted twice or lost.
if (num("resolved_from_argument") + num("resolved_from_default") +
    num("unresolved") != num("calls_to_parameterised_macros")) {
  message("FAIL  call outcomes do not partition the calls")
  fail <- fail + 1L
}
# Every resolved value is accounted for by exactly one bucket.
if (num("nimpute_0") + num("nimpute_1") + num("nimpute_gt1") !=
    num("resolved_total")) {
  message("FAIL  NIMPUTE buckets do not partition the resolved values")
  fail <- fail + 1L
}

unlink(root, recursive = TRUE)
if (fail) {
  message("\n", fail, " failure(s)")
  quit(save = "no", status = 1)
}
message("\nall checks passed")
