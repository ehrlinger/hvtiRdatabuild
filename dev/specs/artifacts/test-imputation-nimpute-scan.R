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

# ⚠️ mi_conf: TWO copies of one macro name binding the same EXPRESSION but
# declaring DIFFERENT DEFAULTS. Comparing expressions alone reported zero
# conflicts and silently used whichever copy was read first. The call omits the
# argument, so which value ran is genuinely unknown: it must be counted as a
# conflicting default and kept OUT of the distribution, not guessed.
# ⚠️ Its defaults STRADDLE 1 -- one copy single-imputes, the other does 50 -- so
# here the ambiguity reaches the conclusion and the call must count as `mixed`,
# not `all_gt1`. Contrast mi_safe below.
put("cardiac/kappa", "mult_imput_conf.sas",
    c("%macro mi_conf(data=, nimpute=1);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("thoracic/lambda", "mult_imput_conf.sas",
    c("%macro mi_conf(data=, nimpute=50);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("cardiac/kappa", "driver_conf.sas", c("%mi_conf(data=w);"))

# ⭐ mi_safe: copies declaring DIFFERENT defaults that are BOTH > 1. The value is
# unknown, but the ANSWER is not -- whichever copy this call used, it ran
# multiple imputation. In the real corpus 622 of 939 calls sit on a conflicting
# default, so whether their ambiguity reaches the conclusion is the question
# that decides §2.
put("cardiac/nu", "mult_imput_safe.sas",
    c("%macro mi_safe(data=, nimpute=5);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("thoracic/xi", "mult_imput_safe.sas",
    c("%macro mi_safe(data=, nimpute=10);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("cardiac/nu", "driver_safe.sas", c("%mi_safe(data=w);"))

# ⚠️ mi_empty: copies where one declares a default and the other declares NONE
# (`nimpute=`, caller must supply). The scan cannot read the second, so the call
# is a MEASUREMENT GAP -- not evidence that it single-imputed. An earlier
# version filed this under the same `mixed` bucket as a genuine straddle, which
# made that bucket unreadable: the real corpus put 619 calls in it and there was
# no way to tell which fact it was reporting.
put("cardiac/omicron", "mult_imput_empty.sas",
    c("%macro mi_empty(data=, nimpute=8);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("thoracic/pi", "mult_imput_empty.sas",
    c("%macro mi_empty(data=, nimpute=);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("cardiac/omicron", "driver_empty.sas", c("%mi_empty(data=w);"))

# ⚠️ mi_ord: one file, one macro variable REASSIGNED between two calls. Building
# a whole-file %let map first let the later assignment decide the earlier call,
# resolving both to 10. Correct is 5 then 10.
put("cardiac/mu", "mult_imput_ord.sas",
    c("%macro mi_ord(data=, nimpute=);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("cardiac/mu", "driver_ord.sas",
    c("%let n = 5;", "%mi_ord(data=w, nimpute=&n);",
      "%let n = 10;", "%mi_ord(data=w, nimpute=&n);"))

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
  # ten macros, every one binding NIMPUTE
  macros_binding_nimpute = 12L,
  binding_literal = 1L,   # mi_lit
  binding_local   = 1L,   # mi_local
  binding_param   = 10L,  # the rest
  # mi_conf's two copies share an expression, so this stays 0 ...
  conflicting_redefinitions = 0L,
  # ... and the disagreement shows up here instead. This is the pair the
  # expression-only comparison could not see.
  conflicting_defaults = 3L,   # mi_conf (1 vs 50), mi_safe (5 vs 10), mi_empty (8 vs none)
  macros_conflicted    = 3L,
  # the same three, classified from the definitions alone -- a pass-1 fact
  conflicted_macros_all_gt1      = 1L,   # mi_safe
  conflicted_macros_straddles_1  = 1L,   # mi_conf
  conflicted_macros_unresolvable = 1L,   # mi_empty
  # mi_kw, mi_pos, mi_let, mi_def, mi_unres, mi_conf, and mi_ord TWICE.
  # NOT mi_cmt -- commented out.
  calls_to_parameterised_macros = 10L,
  # 25, 7, 1, and mi_ord's 5 and 10
  resolved_from_argument = 5L,
  resolved_from_default  = 1L,   # mi_def's 10
  unresolved_conflicting_default = 3L,  # mi_conf, mi_safe, mi_empty
  # ⭐ mi_safe: 5 or 10, both > 1, so the ANSWER survives the ambiguity.
  conflicting_default_all_gt1 = 1L,
  # ⭐ The three states kept apart. Under the old two-bucket version mi_conf and
  # mi_empty both landed in `mixed`, which is exactly the collapse that made the
  # corpus result unreadable.
  conflicting_default_straddles_1  = 1L,   # mi_conf: 1 or 50
  conflicting_default_unresolvable = 1L,   # mi_empty: 8 or unreadable
  unresolved             = 1L,   # mi_unres
  # mi_local's 3 and mi_lit's 40 -- definitions, NOT calls, and no longer
  # pooled into the call distribution below.
  settled_by_definition_alone = 2L,
  # 25, 7, 1, 5, 10, 10 -- calls only
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
    num("unresolved_conflicting_default") + num("unresolved") !=
    num("calls_to_parameterised_macros")) {
  message("FAIL  call outcomes do not partition the calls")
  fail <- fail + 1L
}
# The distribution must count CALLS only. If a definition settled without a
# caller leaks into it, this fails.
if (num("resolved_total") !=
    num("resolved_from_argument") + num("resolved_from_default")) {
  message("FAIL  the distribution is not calls-only")
  fail <- fail + 1L
}

# ⚠️ THE ORDERING CHECK, and it has to look at the DISTRIBUTION rather than the
# counts. Under the order-blind bug mi_ord resolves to 10 and 10 instead of 5
# and 10 -- and every count above is IDENTICAL either way: still 8 calls, still
# 5 from arguments, still 1 nimpute_1, still 5 nimpute_gt1. Only the values
# differ. `nimpute` is emitted last, so its table is the final one.
tbl <- sub(".*\"table\"", "", j)
ord_ok <- grepl("\"5\" *: *1", tbl) && grepl("\"10\" *: *2", tbl)
message(sprintf("%-32s %s", "ordered %let resolution",
                if (ord_ok) "ok  (5 once, 10 twice)" else "FAIL"))
if (!ord_ok) fail <- fail + 1L
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
