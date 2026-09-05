#!/usr/bin/env Rscript
# imputation-census-reconcile.R
#
# Explains why the scans and the job census disagree about `mult_imput`.
#
# THE DISCREPANCY. Scan 1 returned 506 `mult_imput` files across 277 studies
# against a census of 411 files and 242 studies -- HIGHER than a census that
# counts every extension and should therefore be a superset of a `.sas`-only
# scan. `imputsub` meanwhile matched the census EXACTLY at 309 studies. A root
# or extension difference would move both; only `mult_imput` moved.
#
# THE HYPOTHESIS. `hvtiRutilities::job_files()` derives `stem` as the basename
# minus its final extension, so a census counting `stem == "mult_imput"` is an
# EXACT match. The scans match `^(imputsub|mult_imput)` -- a PREFIX -- which
# also takes `mult_imputation`, `mult_imput2`, `mult_imput_old` and anything
# else beginning with those letters. If variant stems exist for `mult_imput`
# and not for `imputsub`, that accounts for the whole asymmetry:
#
#   imputsub:    no variants  -> same studies (309), fewer files (.sas only)
#   mult_imput:  variants     -> more studies AND more files, despite .sas only
#
#   Rscript imputation-census-reconcile.R --root /studies --out census-reconcile.json
#
# WHICH IS IT? Read `exact` against `prefix_only` in the output. If
# `prefix_only` is empty for `imputsub` and non-empty for `mult_imput`, the
# hypothesis holds and the scan figures should be quoted as PREFIX counts, not
# as the census's stem counts.
#
# PRIVACY CONTRACT -- ⚠️ NARROWER THAN ITS SIBLINGS, deliberately.
#
# This scan EMITS JOB STEMS, because the stems are the thing in question and a
# count cannot name which variant inflated the total. It emits ONLY stems
# beginning with `imputsub` or `mult_imput`, which are institutional job-naming
# conventions, not study or patient identifiers. It emits no path, no directory,
# no study identifier, no variable name and no file content. If that is not an
# acceptable trade for your purpose, do not run it -- the sibling scans answer
# their questions without it.
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
outfile <- getarg("--out", "census-reconcile.json")

.folders <- taxonomy_folders()
study_of <- study_of_factory(root, .folders)
message("taxonomy folders: ", paste(.folders, collapse = ", "))

# ⚠️ NO extension filter. The census has none either, and the extension gap is
# half of what is being explained -- filtering here would hide it.
files <- list.files(root, pattern = "^(imputsub|mult_imput)", recursive = TRUE,
                    full.names = TRUE, ignore.case = TRUE, no.. = TRUE)
message("prefix-matched files (all extensions): ", length(files))

base <- tolower(basename(files))
# Same stem rule as job_files(): basename minus the FINAL extension, and a
# dotfile with nothing before the dot keeps its whole name.
has_ext <- grepl("[.]", base)
stem <- ifelse(has_ext, sub("[.][^.]*$", "", base), base)
stem <- ifelse(has_ext & !nzchar(stem), base, stem)
ext  <- ifelse(has_ext & nzchar(sub("[.][^.]*$", "", base)),
               sub("^.*[.]", "", base), NA_character_)
stu  <- study_of(files)

group <- ifelse(startsWith(stem, "mult_imput"), "mult_imput",
                ifelse(startsWith(stem, "imputsub"), "imputsub", "other"))

nstud <- function(mask) length(unique(stu[mask & !is.na(stu)]))

summarise <- function(g) {
  m <- group == g
  exact <- m & stem == g
  variant <- m & stem != g
  # Per-stem counts, variants only -- the exact stem is reported above them.
  vs <- sort(table(stem[variant]), decreasing = TRUE)
  list(
    # What the census counts: exactly this stem, every extension.
    exact = list(files = sum(exact), studies = nstud(exact)),
    # What the census counts if it also excluded non-.sas.
    exact_sas_only = list(
      files   = sum(exact & !is.na(ext) & ext == "sas"),
      studies = nstud(exact & !is.na(ext) & ext == "sas")
    ),
    # What the scans counted: any stem starting with this, .sas only.
    prefix_sas_only = list(
      files   = sum(m & !is.na(ext) & ext == "sas"),
      studies = nstud(m & !is.na(ext) & ext == "sas")
    ),
    # ⭐ The difference between the two, itemised. Empty here means the
    # hypothesis is wrong for this stem and the gap is something else.
    prefix_only = list(
      distinct_stems = length(vs),
      files          = sum(variant),
      studies        = nstud(variant),
      by_stem        = as.list(vs)
    ),
    # ⚠️ VARIANTS WHOSE NAME SAYS THEY DID NOT RUN. A partial traversal of the
    # share found `imputsub.test` at 312 files -- over a third of every
    # `imputsub` prefix match -- plus `mult_imput_dead` and `mult_imput.iso_dead`.
    # The sibling scans match by PREFIX, so every one of these was counted as
    # evidence that a study ran imputation. A test fixture and a retired job are
    # not that. This is a DIFFERENT defect from the census gap and matters more:
    # it can move the study counts in §2 directly.
    #
    # Reported, deliberately not filtered. Which markers really mean "did not
    # run" here is a judgement about this corpus's conventions, not something
    # this scan should decide silently.
    suspect = list(
      test_files    = sum(m & grepl("(^|[._])test([._]|$)", stem)),
      test_studies  = nstud(m & grepl("(^|[._])test([._]|$)", stem)),
      dead_files    = sum(m & grepl("(^|[._])(dead|old|bak|orig|backup)([._]|$)", stem)),
      dead_studies  = nstud(m & grepl("(^|[._])(dead|old|bak|orig|backup)([._]|$)", stem)),
      # Studies whose ONLY prefix match is a test or dead file -- these are
      # studies the sibling scans credited with imputation on no other evidence.
      studies_only_suspect = {
        susp <- grepl("(^|[._])(test|dead|old|bak|orig|backup)([._]|$)", stem)
        length(setdiff(unique(stu[m & susp & !is.na(stu)]),
                       unique(stu[m & !susp & !is.na(stu)])))
      }
    ),
    extensions = as.list(sort(table(ifelse(is.na(ext[m]), "(none)", ext[m])),
                              decreasing = TRUE))
  )
}

out <- list(
  `_provenance` = list(
    script   = "imputation-census-reconcile.R",
    question = "why do the scans and the job census disagree about mult_imput?",
    run_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    root     = if (identical(root, "/studies")) "/studies" else "(non-default root)",
    hvtiRutilities_version = as.character(utils::packageVersion("hvtiRutilities")),
    taxonomy_folders       = paste(sort(.folders), collapse = ","),
    files_considered = length(files),
    # ⚠️ TRUE here, unlike its siblings: job stems are emitted. See the header.
    contains_identifiers = FALSE,
    emits_job_stems = TRUE
  ),
  # For comparison with the figures quoted in the spec.
  census_reference = list(
    imputsub_files = 926, imputsub_studies = 309,
    mult_imput_files = 411, mult_imput_studies = 242
  ),
  imputsub   = summarise("imputsub"),
  mult_imput = summarise("mult_imput")
)

writeLines(to_json(out), outfile)

for (g in c("imputsub", "mult_imput")) {
  s <- out[[g]]
  message("\n--- ", g, " ---")
  message("exact stem, all extensions:   ", s$exact$files, " files / ",
          s$exact$studies, " studies")
  message("exact stem, .sas only:        ", s$exact_sas_only$files, " files / ",
          s$exact_sas_only$studies, " studies")
  message("prefix match, .sas only:      ", s$prefix_sas_only$files, " files / ",
          s$prefix_sas_only$studies, " studies   <- what the scans counted")
  message("variant stems (prefix only):  ", s$prefix_only$distinct_stems,
          " distinct, ", s$prefix_only$files, " files / ",
          s$prefix_only$studies, " studies")
}
message("\nwrote ", outfile)
