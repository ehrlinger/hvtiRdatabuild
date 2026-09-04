#!/usr/bin/env Rscript
# imputation-method-scan.R
#
# Settles section 2 of hvtiRdatabuild/dev/specs/2026-09-03-imputation-package-spec.md:
# of the studies carrying an `imputsub` or `mult_imput` job, which ran SINGLE
# mean imputation and which ran MULTIPLE imputation?
#
# Run where the studies share is mounted. REQUIRES hvtiRutilities, which
# defines what a study is; everything else is base R.
#
#   Rscript imputation-method-scan.R --root /studies --out imputation-scan.json
#
# PRIVACY CONTRACT, stated precisely.
#
# THE OUTPUT JSON carries counts only: every field is an integer, a fixed
# string, or a literal. No path, file name, study identifier, variable name or
# source line reaches it.
#
# THE RUNNING PROCESS does hold study directory names in memory -- `study_of()`
# returns the study directory path so that distinct studies can be counted. That value
# is reduced to a count by `nstud()` and never emitted. It is NOT anonymised,
# so anything added here that prints or writes `stu` would break the contract.
#
# THE CONSOLE echoes the --root you passed (and nothing below it), so do not
# pass a root that is itself sensitive.

args <- commandArgs(trailingOnly = TRUE)
getarg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[[i + 1L]]
}
root    <- getarg("--root", "/studies")
outfile <- getarg("--out", "imputation-scan.json")
# --wide also scans every .sas for imputation calls, not just the two stems.
# Far slower (millions of files). Off by default; the stem scan answers S2.
wide    <- "--wide" %in% args

# path.expand() FIRST: list.files() expands a tilde root but returns expanded
# paths, so an unexpanded `root` would misalign the substring() below by a
# constant and leave fragments of the root path inside every study label.
root <- path.expand(root)
if (!dir.exists(root)) stop("root not found: ", root, call. = FALSE)

# The study definition comes from hvtiRutilities. Check it BEFORE the walk:
# the traversal is the expensive part, and discovering a missing package after
# an hour of it is the failure this guard exists to prevent.
if (!requireNamespace("hvtiRutilities", quietly = TRUE)) {
  stop("hvtiRutilities is required -- it defines what a study is. ",
       "Without it the study counts cannot reconcile with the census.",
       call. = FALSE)
}
.folders <- unique(hvtiRutilities::hvti_taxonomy()$folder)
message("taxonomy folders: ", paste(.folders, collapse = ", "))
# list.files(full.names = TRUE) prefixes the literal string it was given.
# Strip trailing slashes ONCE, here, and use this same string everywhere --
# comparing against normalizePath() instead silently no-ops under a symlinked
# or automounted root (very plausible for a share), which would collapse every
# study to one id and make every `studies` count wrong without any error.
root <- sub("/+$", "", root)

message("Scanning (", if (wide) "WIDE: all .sas" else "stem-matched .sas", ")")

# ---- locate candidate files -------------------------------------------------
# The census counted by file-name prefix; match the same two stems so the
# result reconciles against it (926 imputsub files, 411 mult_imput).
# Anchored: the census counted by file-name PREFIX, so an unanchored match
# (which would also take `xx_imputsub_old.sas`) would inflate the count.
# NOTE the census's 926/411 have NO extension allowlist -- they include .log,
# .lst and the rest -- so this .sas-only scan will legitimately return FEWER
# files. That gap is a definition difference, not a scan defect.
stem_re <- "^(imputsub|mult_imput)"
pat     <- if (wide) "\\.sas$" else paste0(stem_re, ".*\\.sas$")

files <- list.files(root, pattern = pat, recursive = TRUE,
                    full.names = TRUE, ignore.case = TRUE,
                    all.files = FALSE, no.. = TRUE)
message("candidate files: ", length(files))

# ---- study attribution ---------------------------------------------------
# A STUDY IS THE DIRECTORY HOLDING A TAXONOMY FOLDER, and the nearest such
# ancestor wins. This is hvtiRutilities' definition (R/job_census.R:1-12) and
# it is the one that produced the census counts this scan reconciles against,
# so it is reused rather than reinvented.
#
# ⚠️ An earlier draft took the first two path components as "<tree>/<study>".
# That is WRONG for this corpus and would have reported subject areas as
# studies: real studies sit at variable depth -- `cardiac/pericardium` at two,
# `cardiac/support/avecor` and `vascular/thoracic-aorta/previous_surgery` at
# three.
#
# The folder list is read from hvtiRutilities (loaded above) rather than
# hardcoded, so it cannot drift from the taxonomy.

study_of <- function(paths) {
  # substring(), not sub(): `root` is a path, not a regex, and a directory
  # named "study (copy)" or "v1.2+" carries metacharacters that would match
  # the wrong thing while still looking like it worked.
  # iconv() first: ONE Latin-1 filename anywhere on the share makes
  # substring() abort with "invalid multibyte string" -- after the whole
  # traversal, for zero output. hvtiRutilities documents this as having
  # already bitten this corpus.
  paths <- iconv(paths, "", "UTF-8", sub = "byte")
  rel   <- substring(paths, nchar(root) + 2L)
  parts <- strsplit(rel, "/", fixed = TRUE)
  vapply(parts, function(p) {
    dirs <- utils::head(p, -1L)              # only directories can be a folder
    hits <- which(dirs %in% .folders)
    if (!length(hits)) return(NA_character_) # unplaced: no taxonomy ancestor
    i <- max(hits)                           # nearest to the file
    if (i == 1L) "." else paste(dirs[seq_len(i - 1L)], collapse = "/")
  }, character(1))
}

# ---- classifiers ------------------------------------------------------------
# SAS is case-insensitive and free-form: a statement may wrap lines, so match
# against the whole file with newlines collapsed to spaces, and split on ';'
# to keep one statement's options from bleeding into the next.
statements <- function(txt) {
  one <- paste(txt, collapse = " ")
  one <- gsub("/\\*.*?\\*/", " ", one)          # strip /* block comments */
  one <- tolower(gsub("[[:space:]]+", " ", one))
  st  <- strsplit(one, ";", fixed = TRUE)[[1]]
  # SAS `* ... ;` and macro `%* ... ;` comments end at the semicolon, so after
  # the split each is its own element. Drop them. Without this a commented-out
  # or historical `* proc standard replace;` -- ordinary in a 30-year corpus --
  # counts as single mean imputation, biasing the ONE number S2 blocks on, and
  # in one direction only.
  st[!grepl("^ *%?\\*", st)]
}

classify <- function(path) {
  txt <- tryCatch(readLines(path, warn = FALSE, encoding = "latin1"),
                  error = function(e) character(0))
  if (!length(txt)) return(NULL)
  st <- statements(txt)

  std <- grep("proc standard", st, fixed = TRUE, value = TRUE)
  # REPLACE is what fills missing values. MEAN=/STD= on the SAME statement
  # turn it into standardisation, which is NOT imputation -- the distinction
  # #33 rests on. Count the three cases separately.
  std_replace  <- grep("replace", std, fixed = TRUE, value = TRUE)
  has_mean_std <- grepl("\\bmean *=|\\bstd *=", std_replace)

  list(
    study            = NA_character_,   # filled by caller
    std_replace_mean = any(!has_mean_std),   # single mean imputation
    std_replace_z    = any(has_mean_std),    # standardisation, not imputation
    std_no_replace   = length(std) > length(std_replace),
    proc_mi          = any(grepl("proc mi\\b", st)),
    proc_mianalyze   = any(grepl("proc mianalyze\\b", st)),
    nimpute          = {
      m <- regmatches(st, regexpr("nimpute *= *[0-9]+", st))
      m <- unlist(m)
      if (length(m)) as.integer(sub("\\D+", "", m[1])) else NA_integer_
    },
    calls_imputsub   = any(grepl("%imputsub", st, fixed = TRUE)),
    calls_mult_imput = any(grepl("%mult_imput", st, fixed = TRUE)),
    defines_macro    = any(grepl("%macro +(imputsub|mult_imput)", st)),
    ms_indicators    = any(grepl("\\bms_[a-z0-9_]+ *=", st)),
    stem = if (grepl("mult_imput", basename(path), ignore.case = TRUE)) "mult_imput"
           else if (grepl("imputsub", basename(path), ignore.case = TRUE)) "imputsub"
           else "other"
  )
}

studies <- study_of(files)
res <- vector("list", length(files))
for (i in seq_along(files)) {
  r <- classify(files[[i]])
  if (!is.null(r)) { r$study <- studies[[i]]; res[[i]] <- r }
  if (i %% 200 == 0) message("  ", i, " / ", length(files))
}
res <- Filter(Negate(is.null), res)
message("readable files: ", length(res))

# ---- aggregate --------------------------------------------------------------
fld  <- function(f) vapply(res, function(r) r[[f]], logical(1))
stem <- vapply(res, function(r) r$stem, character(1))
stu  <- vapply(res, function(r) r$study, character(1))

nstud <- function(mask) length(unique(stu[mask & !is.na(stu)]))

single <- fld("std_replace_mean")
multi  <- fld("proc_mi") | fld("proc_mianalyze")

by_stem <- function(s) {
  m <- stem == s
  list(
    files                 = sum(m),
    studies               = nstud(m),
    single_mean_imputation= sum(m & single),
    multiple_imputation   = sum(m & multi),
    both                  = sum(m & single & multi),
    neither               = sum(m & !single & !multi),
    standardisation_only  = sum(m & !single & !multi & fld("std_replace_z")),
    calls_macro           = sum(m & (fld("calls_imputsub") | fld("calls_mult_imput"))),
    defines_macro         = sum(m & fld("defines_macro")),
    ms_indicators         = sum(m & fld("ms_indicators"))
  )
}

nimp <- vapply(res, function(r) r$nimpute, integer(1))
nimp <- nimp[!is.na(nimp)]

out <- list(
  `_provenance` = list(
    script  = "imputation-method-scan.R",
    question= "spec 2026-09-03-imputation-package-spec.md S2: single vs multiple imputation",
    run_at  = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    root    = if (identical(root, "/studies")) "/studies" else "(non-default root)",
    mode    = if (wide) "wide: all .sas" else "stem-matched .sas",
    files_considered = length(files),
    files_read       = length(res),
    contains_identifiers = FALSE
  ),
  totals = list(
    files                  = length(res),
    studies                = nstud(rep(TRUE, length(res))),
    files_unplaced         = sum(is.na(stu)),
    single_mean_imputation = sum(single),
    multiple_imputation    = sum(multi),
    both_in_one_file       = sum(single & multi),
    neither                = sum(!single & !multi),
    studies_single         = nstud(single),
    studies_multiple       = nstud(multi),
    studies_both           = nstud(single & multi),
    # A job that CALLS %imputsub instead of inlining `proc standard replace`
    # classifies as `neither`. Without these, a corpus that mostly calls the
    # macro would print "single mean imputation: 0 studies", which reads as
    # "nobody ran single imputation" -- the opposite of the truth, from a
    # clean-looking run. S2 must be read with these alongside the two above.
    files_calls_imputsub   = sum(fld("calls_imputsub")),
    files_calls_mult_imput = sum(fld("calls_mult_imput")),
    studies_calls_imputsub  = nstud(fld("calls_imputsub")),
    studies_calls_mult_imput= nstud(fld("calls_mult_imput"))
  ),
  by_stem = list(imputsub = by_stem("imputsub"),
                 mult_imput = by_stem("mult_imput"),
                 other = by_stem("other")),
  # FILE counts, and they OVERLAP: one file may carry both a mean-imputing and
  # a standardising PROC STANDARD, so these can sum past files_read. They are
  # not a partition; `exclusive` below is.
  proc_standard_detail = list(
    files_replace_without_mean_std = sum(fld("std_replace_mean")),
    files_replace_with_mean_std    = sum(fld("std_replace_z")),
    files_standard_without_replace = sum(fld("std_no_replace")),
    exclusive = list(
      imputation_only     = sum(fld("std_replace_mean") & !fld("std_replace_z")),
      standardisation_only= sum(!fld("std_replace_mean") & fld("std_replace_z")),
      both_in_one_file    = sum(fld("std_replace_mean") & fld("std_replace_z"))
    )
  ),
  nimpute = list(
    n_files_declaring = length(nimp),
    min = if (length(nimp)) min(nimp) else NA_integer_,
    median = if (length(nimp)) as.numeric(stats::median(nimp)) else NA_real_,
    max = if (length(nimp)) max(nimp) else NA_integer_,
    table = if (length(nimp)) as.list(table(nimp)) else list()
  )
)

# ---- emit -------------------------------------------------------------------
# Minimal JSON writer so the script needs no packages.
to_json <- function(x, ind = 0) {
  pad <- strrep(" ", ind)
  if (is.null(x) || (length(x) == 1 && is.na(x) && !is.character(x))) return("null")
  if (is.list(x)) {
    if (!length(x)) return("{}")
    nm <- names(x)
    items <- vapply(seq_along(x), function(i)
      paste0(pad, "  \"", nm[i], "\": ", to_json(x[[i]], ind + 2)), character(1))
    return(paste0("{\n", paste(items, collapse = ",\n"), "\n", pad, "}"))
  }
  if (is.character(x)) return(paste0("\"", gsub("\"", "'", x), "\""))
  if (is.logical(x))   return(if (isTRUE(x)) "true" else "false")
  if (is.na(x))        return("null")
  format(x, scientific = FALSE)
}
writeLines(to_json(out), outfile)

message("\n--- S2 ANSWER ---")
message("files read:              ", out$totals$files)
message("studies:                 ", out$totals$studies)
message("single mean imputation:  ", out$totals$single_mean_imputation,
        " files / ", out$totals$studies_single, " studies")
message("multiple imputation:     ", out$totals$multiple_imputation,
        " files / ", out$totals$studies_multiple, " studies")
message("both in one file:        ", out$totals$both_in_one_file)
message("neither (macro call/other): ", out$totals$neither)
message("  of which call %imputsub:   ", out$totals$files_calls_imputsub,
        " files / ", out$totals$studies_calls_imputsub, " studies")
message("  of which call %mult_imput: ", out$totals$files_calls_mult_imput,
        " files / ", out$totals$studies_calls_mult_imput, " studies")
message("\nPROC STANDARD REPLACE without MEAN=/STD= (imputation): ",
        out$proc_standard_detail$files_replace_without_mean_std)
message("PROC STANDARD REPLACE with MEAN=/STD= (standardisation, NOT imputation): ",
        out$proc_standard_detail$files_replace_with_mean_std)
message("\nwrote ", outfile)
