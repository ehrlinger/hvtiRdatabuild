#!/usr/bin/env Rscript
# test-imputation-reconcile-scan.R
#
# Checks `imputation-reconcile-scan.R` against a synthetic corpus whose copy
# divergence is known by construction.
#
#   Rscript test-imputation-reconcile-scan.R
#
# The fixture pins the three distinctions the worksheet exists to make:
#   - which names disagree, and which agree
#   - whether the drift is confined to the default, or the body moved too
#   - which calls pass the parameter and which fall back on a default
#
# NO PHI. Every study name, macro, variable and value here is invented.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
scan_script <- file.path(here, "imputation-reconcile-scan.R")
stopifnot(file.exists(scan_script))

if (!requireNamespace("hvtiRutilities", quietly = TRUE)) {
  message("SKIP: hvtiRutilities could not be loaded, so the scan cannot run.\n",
          "  This R:   ", R.version.string, "\n",
          "  libPaths: ", paste(.libPaths(), collapse = "\n            "))
  quit(save = "no", status = 0)
}

root <- file.path(tempdir(), paste0("reconcile-fixture-", Sys.getpid()))
folder <- unique(hvtiRutilities::hvti_taxonomy()$folder)[[1]]
put <- function(study, file, lines) {
  d <- file.path(root, study, folder)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, file.path(d, file))
}

# ---- the corpus -------------------------------------------------------------

# mi_clean: three copies, all declaring 5. Agrees with itself, so it must NOT
# appear on the worksheet at all.
for (st in c("cardiac/a", "cardiac/b", "thoracic/c")) {
  put(st, "mult_imput_clean.sas",
      c("%macro mi_clean(data=, nimpute=5);",
        "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
}

# mi_hdr: defaults 1 and 10, bodies otherwise IDENTICAL. Spans 1. Reconciling
# this one is a one-line edit per copy, which is what
# distinct_bodies_ignoring_header = 1 says.
put("cardiac/d", "mult_imput_hdr.sas",
    c("%macro mi_hdr(data=, nimpute=1);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("cardiac/e", "mult_imput_hdr.sas",
    c("%macro mi_hdr(data=, nimpute=10);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("vascular/thoracic-aorta/f", "mult_imput_hdr.sas",
    c("%macro mi_hdr(data=, nimpute=10);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))

# mi_body: defaults 5 and 8, and the BODIES differ too. Reconciling this is a
# merge, not a one-line edit, and the default is only the visible part.
put("cardiac/g", "mult_imput_body.sas",
    c("%macro mi_body(data=, nimpute=5);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("thoracic/h", "mult_imput_body.sas",
    c("%macro mi_body(data=, nimpute=8);",
      "proc mi data=&data out=m nimpute=&nimpute seed=42;",
      "  var age;", "run;", "%mend;"))

# mi_named: the parameter feeding NIMPUTE is NOT called `nimpute`. A call is
# only "relying on a default" if it omits THAT parameter, so the test has to
# use the captured name rather than the literal string.
put("cardiac/i", "mult_imput_named.sas",
    c("%macro mi_named(data=, reps=5);",
      "proc mi data=&data out=m nimpute=&reps;", "run;", "%mend;"))
put("thoracic/j", "mult_imput_named.sas",
    c("%macro mi_named(data=, reps=20);",
      "proc mi data=&data out=m nimpute=&reps;", "run;", "%mend;"))
# one call passes `reps`, one omits it
put("cardiac/i", "driver_named.sas",
    c("%mi_named(data=w, reps=30);", "%mi_named(data=w);"))

# ⚠️ mi_mixed: the copies disagree STRUCTURALLY, not just numerically. One
# declares the NIMPUTE parameter as a keyword with a default; the other declares
# it POSITIONALLY, which in SAS has no default at all. That difference is what
# puts the name on the worksheet, and it means calls to it are positional. A
# default test that recognises only `name = value` counts such a call as an
# omission and inflates the tally that orders this work.
put("cardiac/k", "mult_imput_mixed.sas",
    c("%macro mi_mixed(data=, nimpute=5);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
put("thoracic/l", "mult_imput_mixed.sas",
    c("%macro mi_mixed(data, nimpute);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))
# one positional call supplying it, one omitting it entirely
put("cardiac/k", "driver_mixed.sas",
    c("%mi_mixed(w, 30);", "%mi_mixed(data=w);"))

# Two calls to mi_hdr, both omitting the parameter.
put("cardiac/d", "driver_hdr.sas", c("%mi_hdr(data=w);", "%mi_hdr(data=x);"))

# ---- run --------------------------------------------------------------------

outfile <- file.path(root, "out.json")
rscript <- file.path(R.home("bin"), "Rscript")
res <- system2(rscript, c(shQuote(normalizePath(scan_script)),
                          "--root", shQuote(root), "--out", shQuote(outfile)),
               stdout = TRUE, stderr = TRUE)
if (!file.exists(outfile)) { cat(res, sep = "\n"); stop("scan produced no output") }
raw <- readLines(outfile)
j <- paste(raw, collapse = " ")

# ⚠️ The worksheet is a LIST OF MACROS, so it must be a JSON ARRAY. Emitted as
# an object every element got the key "", which reads fine by eye and collapses
# to ONE entry in any parser. Assert the shape, not just the text: the earlier
# version of this test matched raw text and passed against the broken output.
if (!any(grepl("\"worksheet\": \\[", raw))) {
  message("FAIL  worksheet is not a JSON array")
  quit(save = "no", status = 1)
}
n_entries <- sum(grepl("\"macro\":", raw))

# Pull one macro's worksheet block out by name.
block <- function(macro) {
  i <- regexpr(paste0("\"macro\": \"", macro, "\""), j)
  if (i < 0) return(NA_character_)
  substring(j, i, i + 700)
}
fld <- function(macro, field) {
  b <- block(macro)
  if (is.na(b)) stop("macro not on the worksheet: ", macro)
  m <- regmatches(b, regexpr(paste0("\"", field, "\": *-?[0-9]+"), b))
  if (!length(m)) stop("field not found: ", macro, "/", field)
  as.integer(sub(".*: *", "", m))
}

checks <- list(
  # every conflicted macro survives the round trip as its own array element
  list("worksheet entries", n_entries, 4L),
  # mi_clean agrees with itself and must not be on the worksheet
  list("mi_clean absent", is.na(block("mi_clean")), TRUE),
  list("names conflicting", {
    m <- regmatches(j, regexpr("\"names_with_conflicting_defaults\": *[0-9]+", j))
    as.integer(sub(".*: *", "", m))
  }, 4L),
  # mi_hdr: 3 copies, defaults 1 and 10, bodies identical once the header goes
  list("mi_hdr copies", fld("mi_hdr", "copies"), 3L),
  list("mi_hdr bodies", fld("mi_hdr", "distinct_bodies"), 2L),
  list("mi_hdr bodies sans header",
       fld("mi_hdr", "distinct_bodies_ignoring_header"), 1L),
  list("mi_hdr calls", fld("mi_hdr", "calls"), 2L),
  list("mi_hdr on default", fld("mi_hdr", "calls_relying_on_a_default"), 2L),
  # mi_body: the body moved too, so it is a merge rather than a one-line edit
  list("mi_body bodies sans header",
       fld("mi_body", "distinct_bodies_ignoring_header"), 2L),
  # mi_named: parameter is `reps`; one call passes it, one does not
  list("mi_named calls", fld("mi_named", "calls"), 2L),
  list("mi_named on default", fld("mi_named", "calls_relying_on_a_default"), 1L),
  # ⭐ two calls, ONE positional supply and one omission. A name-only test reads
  # this as 2 and misorders the work.
  list("mi_mixed calls", fld("mi_mixed", "calls"), 2L),
  list("mi_mixed on default", fld("mi_mixed", "calls_relying_on_a_default"), 1L)
)

fail <- 0L
for (c in checks) {
  ok <- identical(c[[2]], c[[3]])
  if (!ok) fail <- fail + 1L
  message(sprintf("%-28s expected %-5s got %-5s %s", c[[1]],
                  format(c[[3]]), format(c[[2]]), if (ok) "ok" else "FAIL"))
}

# `spans_1` is a boolean, so check it as text.
sp <- regmatches(block("mi_hdr"), regexpr("\"spans_1\": *(true|false)", block("mi_hdr")))
ok <- length(sp) && grepl("true", sp)
message(sprintf("%-28s expected %-5s got %-5s %s", "mi_hdr spans 1", "TRUE",
                if (length(sp)) sub(".*: *", "", sp) else "?", if (ok) "ok" else "FAIL"))
if (!ok) fail <- fail + 1L

unlink(root, recursive = TRUE)
if (fail) { message("\n", fail, " failure(s)"); quit(save = "no", status = 1) }
message("\nall checks passed")
