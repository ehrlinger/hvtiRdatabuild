#!/usr/bin/env Rscript
# test-imputation-direct-procmi-scan.R
#
# Checks `imputation-direct-procmi-scan.R` against a synthetic corpus whose
# direct PROC MI use is known by construction.
#
#   Rscript test-imputation-direct-procmi-scan.R
#
# NO PHI. Every study name, macro, variable and value here is invented.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
scan_script <- file.path(here, "imputation-direct-procmi-scan.R")
stopifnot(file.exists(scan_script))

if (!requireNamespace("hvtiRutilities", quietly = TRUE)) {
  message("SKIP: hvtiRutilities could not be loaded, so the scan cannot run.\n",
          "  This R:   ", R.version.string, "\n",
          "  libPaths: ", paste(.libPaths(), collapse = "\n            "))
  quit(save = "no", status = 0)
}

root <- file.path(tempdir(), paste0("direct-fixture-", Sys.getpid()))
folder <- unique(hvtiRutilities::hvti_taxonomy()$folder)[[1]]
put <- function(study, file, lines) {
  d <- file.path(root, study, folder)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, file.path(d, file))
}

# ---- the corpus -------------------------------------------------------------

# alpha: a literal. The simplest direct case.
put("cardiac/alpha", "analysis.sas",
    c("proc mi data=w out=m nimpute=25;", "run;"))

# ⚠️ beta: the value comes from a %let EARLIER IN THE SAME FILE, and is then
# REASSIGNED before a second PROC MI. Order matters: 5 then 10, not 10 twice.
put("cardiac/beta", "analysis.sas",
    c("%let n = 5;", "proc mi data=w out=m nimpute=&n;", "run;",
      "%let n = 10;", "proc mi data=x out=m2 nimpute=&n;", "run;"))

# ⭐ gamma: a PROC MI INSIDE a %macro body. That belongs to the macro population,
# not this one, and must be excluded so the two scans can be added without
# double counting.
put("thoracic/gamma", "mult_imput_g.sas",
    c("%macro mi_g(data=, nimpute=5);",
      "proc mi data=&data out=m nimpute=&nimpute;", "run;", "%mend;"))

# delta: no NIMPUTE at all, so SAS applies its own default. Counted, not guessed.
put("cardiac/delta", "analysis.sas",
    c("proc mi data=w out=m seed=1;", "run;"))

# eps: NIMPUTE from a macro variable set nowhere this scan can see.
put("cardiac/eps", "analysis.sas",
    c("proc mi data=w out=m nimpute=&outside;", "run;"))

# ⚠️ zeta: NIMPUTE=1, which is single imputation whatever the procedure is
# called, and the value the whole §2 question turns on.
put("cardiac/zeta", "analysis.sas",
    c("proc mi data=w out=m nimpute=1;", "run;"))

# eta: a file with a direct PROC MI *and* one inside a macro, so both branches
# are exercised in one file.
put("cardiac/eta", "analysis.sas",
    c("%macro helper(); proc mi data=q nimpute=7; run; %mend;",
      "proc mi data=w out=m nimpute=20;", "run;"))

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
  # alpha, beta, gamma, delta, eps, zeta, eta
  files_with_a_procmi = 7L,
  # alpha, beta x2, delta, eps, zeta, eta. NOT gamma's or eta's in-macro one.
  direct_procmi_statements = 7L,
  # ⭐ gamma's and eta's
  procmi_inside_a_macro = 2L,
  from_a_literal = 3L,          # alpha 25, zeta 1, eta 20. NOT delta, which
  #                               gives no NIMPUTE at all and is counted below.
  from_a_let_in_the_file = 2L,  # beta's 5 and 10
  no_nimpute_given = 1L,        # delta
  unresolved = 1L,              # eps
  running_procmi_directly = 6L, # every study but gamma
  with_a_resolved_nimpute = 4L, # alpha, beta, zeta, eta
  resolved_total = 5L,          # 25, 5, 10, 1, 20
  nimpute_1 = 1L,
  nimpute_gt1 = 4L
)

fail <- 0L
for (nm in names(expected)) {
  got <- num(nm)
  ok <- identical(got, expected[[nm]])
  if (!ok) fail <- fail + 1L
  message(sprintf("%-28s expected %2d  got %2d  %s", nm, expected[[nm]], got,
                  if (ok) "ok" else "FAIL"))
}

# The routes must partition the direct statements.
if (num("from_a_literal") + num("from_a_let_in_the_file") +
    num("no_nimpute_given") + num("unresolved") !=
    num("direct_procmi_statements")) {
  message("FAIL  routes do not partition the direct statements"); fail <- fail + 1L
}

# ⚠️ ORDERED %let. Under a whole-file map beta's two calls both resolve to 10 and
# every count above is IDENTICAL; only the values differ. Assert the
# distribution, which is the only place the difference shows.
tbl <- sub(".*\"table\"", "", j)
ord_ok <- grepl("\"5\" *: *1", tbl) && grepl("\"10\" *: *1", tbl)
message(sprintf("%-28s %s", "ordered %let resolution",
                if (ord_ok) "ok  (5 once, 10 once)" else "FAIL"))
if (!ord_ok) fail <- fail + 1L

unlink(root, recursive = TRUE)
if (fail) { message("\n", fail, " failure(s)"); quit(save = "no", status = 1) }
message("\nall checks passed")
