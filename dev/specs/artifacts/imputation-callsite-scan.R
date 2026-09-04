#!/usr/bin/env Rscript
# imputation-callsite-scan.R
#
# Follow-up to `imputation-method-scan.R`, which answered a narrower question
# than section 2 of 2026-09-03-imputation-package-spec.md asked.
#
# WHAT THE FIRST SCAN FOUND, and why this one exists. Of 1,134 stem-matched
# files, 1,132 DEFINE a macro and ZERO CALL one. So the first scan measured how
# many studies hold a COPY of the macro definition -- not how many ran
# imputation. A study can carry `imputsub.sas` and never invoke it. That also
# explains the implausible cleanliness of the result: 100% separation by stem,
# no file carrying both methods, no exceptions in thirty years. Not 1,134
# independent choices agreeing perfectly -- 1,134 copies of two canonical files.
#
# It also could not read NIMPUTE. Only 5 PROC MI statements in the whole corpus
# declared a literal `nimpute=<digits>`, and all five said 1. The rest
# parameterise it, which a literal-digit regex cannot see -- and a macro
# DEFINITION is exactly where a caller's varying argument becomes a parameter.
#
# ⚠️ NIMPUTE=1 is not multiple imputation. It generates one completed dataset
# and understates variance the same way mean imputation does. If that is what
# the corpus passes, the §2 distinction collapses in the opposite direction
# from the one anyone expected, and a package named for multiple imputation
# would be misnamed. That is the question this scan exists to answer.
#
# THIS SCAN THEREFORE ASKS:
#   1. Which studies CALL %imputsub / %mult_imput, as opposed to holding a copy?
#   2. What NIMPUTE value actually reaches PROC MI, resolving macro variables?
#
#   Rscript imputation-callsite-scan.R --root /studies --out callsite-scan.json
#
# SCOPE, and why it is not --wide. Only studies that already carry a
# stem-matched file are opened -- 547 of them, from the first scan. A call
# lives in the same study as the definition it invokes, so this bounds the walk
# to the studies that can possibly contain one, rather than every .sas on the
# share. Pass --all-studies to drop that restriction and pay for it.
#
# PRIVACY CONTRACT, unchanged from the first scan and stated precisely.
#
# THE OUTPUT JSON carries counts and integers only. No path, file name, study
# identifier, variable name, macro-parameter name or source line reaches it.
# ⚠️ Macro variables ARE resolved internally to read NIMPUTE, so identifier
# text exists in memory during the run. It is reduced to integers before
# output. Anything added here that emits a captured name breaks the contract.
#
# THE CONSOLE echoes the --root you passed, and nothing below it.

here <- (function() {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f)) dirname(f[[1]]) else "."
})()
source(file.path(here, "scan-common.R"))

args <- commandArgs(trailingOnly = TRUE)
getarg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[[i + 1L]]
}
root    <- normalise_root(getarg("--root", "/studies"))
outfile <- getarg("--out", "callsite-scan.json")
all_studies <- "--all-studies" %in% args

.folders <- taxonomy_folders()
study_of <- study_of_factory(root, .folders)
message("taxonomy folders: ", paste(.folders, collapse = ", "))

# ---- which studies to open --------------------------------------------------
# Find the definition files first (cheap, the same stem match as scan 1), take
# the studies they sit in, and open every .sas under those studies only.
stem_re <- "^(imputsub|mult_imput)"
defs <- list.files(root, pattern = paste0(stem_re, ".*\\.sas$"), recursive = TRUE,
                   full.names = TRUE, ignore.case = TRUE, no.. = TRUE)
def_studies <- unique(stats::na.omit(study_of(defs)))
message("studies carrying a definition: ", length(def_studies))

if (all_studies) {
  message("--all-studies: opening every .sas under the root")
  files <- list.files(root, pattern = "\\.sas$", recursive = TRUE,
                      full.names = TRUE, ignore.case = TRUE, no.. = TRUE)
} else {
  # A study label is a path relative to root, so rebuild the directory and walk
  # it. "." is the root itself.
  dirs <- ifelse(def_studies == ".", root, file.path(root, def_studies))
  files <- unlist(lapply(dirs, function(d) {
    list.files(d, pattern = "\\.sas$", recursive = TRUE,
               full.names = TRUE, ignore.case = TRUE, no.. = TRUE)
  }), use.names = FALSE)
  files <- unique(files)
}
message("candidate files: ", length(files))

# ---- NIMPUTE resolution -----------------------------------------------------
# Three ways a value reaches PROC MI, in increasing order of indirection:
#
#   nimpute=5                 literal on the statement
#   nimpute=&n                macro variable, resolved from `%let n = 5;` or
#                             from a `n=5` argument at a macro call in the file
#   (absent)                  the SAS default, which is positive -- so it
#                             imputes, but we do NOT record what the number is:
#                             the default has varied across releases and this
#                             corpus spans thirty years of them.
#
# ⚠️ Resolution is WITHIN ONE FILE. A value set in a driver and inherited by an
# included file is invisible here and is reported as unresolved, NOT as absent.
# The two must not be conflated: unresolved means "a number exists and we could
# not read it", absent means "no NIMPUTE was written".
resolve_nimpute <- function(st) {
  mi <- grep("proc mi\\b", st, value = TRUE)
  if (!length(mi)) return(NULL)

  # %let name = value;  -> a lookup table of literal assignments in this file.
  lets <- grep("^ *%let ", st, value = TRUE)
  lookup <- list()
  for (l in lets) {
    m <- regmatches(l, regexec("^ *%let +([a-z0-9_]+) *= *([^ ]+) *$", l))[[1]]
    if (length(m) == 3L && grepl("^[0-9]+$", m[3])) lookup[[m[2]]] <- as.integer(m[3])
  }
  # name=value passed as a macro-call argument, e.g. %mult_imput(nimpute=5).
  for (s in grep("%[a-z0-9_]+ *\\(", st, value = TRUE)) {
    for (m in regmatches(s, gregexpr("[a-z0-9_]+ *= *[0-9]+", s))[[1]]) {
      kv <- strsplit(gsub(" ", "", m), "=", fixed = TRUE)[[1]]
      if (length(kv) == 2L && is.null(lookup[[kv[1]]])) {
        lookup[[kv[1]]] <- as.integer(kv[2])
      }
    }
  }

  vapply(mi, function(s) {
    lit <- regmatches(s, regexpr("nimpute *= *[0-9]+", s))
    if (length(lit)) return(as.integer(sub("\\D+", "", lit)))
    ref <- regmatches(s, regexpr("nimpute *= *&+[a-z0-9_]+", s))
    if (length(ref)) {
      nm <- sub("^.*&+", "", ref)
      v <- lookup[[nm]]
      # -1 encodes "a value exists and could not be resolved". Never emitted as
      # a NIMPUTE value; counted separately.
      return(if (is.null(v)) -1L else v)
    }
    NA_integer_   # no NIMPUTE written at all: SAS default, positive
  }, integer(1), USE.NAMES = FALSE)
}

classify <- function(path) {
  st <- read_statements(path)
  if (is.null(st)) return(NULL)
  # A CALL is `%name(` or a bare `%name;`. `%macro imputsub(...)` must not
  # match: the substring "%imputsub" does not occur in "%macro imputsub", so
  # anchoring on the sigil is enough to keep definitions out.
  call_re <- function(nm) paste0("%", nm, " *[(;]|%", nm, " *$")
  list(
    study            = NA_character_,
    calls_imputsub   = any(grepl(call_re("imputsub"), st)),
    calls_mult_imput = any(grepl(call_re("mult_imput"), st)),
    defines_macro    = any(grepl("%macro +(imputsub|mult_imput)\\b", st)),
    # Inline, rather than via either macro.
    inline_replace   = any(grepl("replace", grep("proc standard", st, fixed = TRUE,
                                                 value = TRUE), fixed = TRUE)),
    proc_mi          = any(grepl("proc mi\\b", st)),
    ms_indicators    = any(grepl("\\bms_[a-z0-9_]+ *=", st)),
    nimpute          = list(resolve_nimpute(st))
  )
}

res <- vector("list", length(files))
studies <- study_of(files)
for (i in seq_along(files)) {
  r <- classify(files[[i]])
  if (!is.null(r)) { r$study <- studies[[i]]; res[[i]] <- r }
  if (i %% 500 == 0) message("  ", i, " / ", length(files))
}
res <- Filter(Negate(is.null), res)
message("readable files: ", length(res))

# ---- aggregate --------------------------------------------------------------
fld  <- function(f) vapply(res, function(r) r[[f]], logical(1))
stu  <- vapply(res, function(r) r$study, character(1))
sstud <- function(mask) unique(stu[mask & !is.na(stu)])

s_call_single <- sstud(fld("calls_imputsub"))
s_call_multi  <- sstud(fld("calls_mult_imput"))
s_inline      <- sstud(fld("inline_replace") & !fld("defines_macro"))

# Every resolved NIMPUTE across the corpus, one entry per PROC MI statement.
nimp <- unlist(lapply(res, function(r) r$nimpute[[1]]), use.names = FALSE)
n_absent     <- sum(is.na(nimp))
n_unresolved <- sum(!is.na(nimp) & nimp == -1L)
vals         <- nimp[!is.na(nimp) & nimp > 0L]

out <- list(
  `_provenance` = list(
    script   = "imputation-callsite-scan.R",
    question = "spec 2026-09-03 S2 follow-up: who CALLS the macros, and what NIMPUTE reaches PROC MI",
    run_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    root     = if (identical(root, "/studies")) "/studies" else "(non-default root)",
    scope    = if (all_studies) "every .sas under root" else "studies carrying a definition",
    hvtiRutilities_version = as.character(utils::packageVersion("hvtiRutilities")),
    taxonomy_folders       = paste(sort(.folders), collapse = ","),
    studies_with_definition = length(def_studies),
    files_considered = length(files),
    files_read       = length(res),
    contains_identifiers = FALSE
  ),
  calls = list(
    files_calling_imputsub   = sum(fld("calls_imputsub")),
    files_calling_mult_imput = sum(fld("calls_mult_imput")),
    studies_calling_imputsub   = length(s_call_single),
    studies_calling_mult_imput = length(s_call_multi),
    studies_calling_both       = length(intersect(s_call_single, s_call_multi)),
    # ⭐ THE NUMBER THIS SCAN EXISTS FOR. A study holding a definition it never
    # calls did not run imputation, and the first scan counted it as if it had.
    studies_with_definition_but_no_call =
      length(setdiff(def_studies, union(s_call_single, s_call_multi))),
    # Imputation written out longhand instead of via either macro. These are
    # invisible to a stem-matched scan entirely.
    studies_inline_replace_no_macro = length(setdiff(s_inline,
                                                     union(s_call_single, s_call_multi)))
  ),
  nimpute = list(
    # ⚠️ These three are DIFFERENT states and must not be added together.
    statements_total      = length(nimp),
    statements_absent     = n_absent,      # no NIMPUTE written; SAS default
    statements_unresolved = n_unresolved,  # a value exists, set outside this file
    statements_resolved   = length(vals),
    # ⭐ nimpute of 1 is SINGLE imputation, whatever the macro is called.
    statements_nimpute_1  = sum(vals == 1L),
    statements_nimpute_gt1 = sum(vals > 1L),
    min    = if (length(vals)) min(vals) else NA_integer_,
    median = if (length(vals)) as.numeric(stats::median(vals)) else NA_real_,
    max    = if (length(vals)) max(vals) else NA_integer_,
    table  = if (length(vals)) as.list(table(vals)) else list()
  ),
  ms_indicators = list(
    files   = sum(fld("ms_indicators")),
    studies = length(sstud(fld("ms_indicators")))
  )
)

writeLines(to_json(out), outfile)

message("\n--- CALL SITES ---")
message("studies holding a definition:        ", length(def_studies))
message("studies CALLING %imputsub:           ", out$calls$studies_calling_imputsub)
message("studies CALLING %mult_imput:         ", out$calls$studies_calling_mult_imput)
message("studies with a definition, NO call:  ",
        out$calls$studies_with_definition_but_no_call)
message("studies imputing inline, no macro:   ",
        out$calls$studies_inline_replace_no_macro)
message("\n--- NIMPUTE ---")
message("PROC MI statements:      ", out$nimpute$statements_total)
message("  resolved to a number:  ", out$nimpute$statements_resolved,
        "  (nimpute=1: ", out$nimpute$statements_nimpute_1,
        ", nimpute>1: ", out$nimpute$statements_nimpute_gt1, ")")
message("  set outside the file:  ", out$nimpute$statements_unresolved)
message("  no NIMPUTE written:    ", out$nimpute$statements_absent)
message("\nwrote ", outfile)
