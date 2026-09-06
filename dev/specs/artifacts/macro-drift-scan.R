#!/usr/bin/env Rscript
# macro-drift-scan.R
#
# Asks whether the copy drift found in the imputation macros is a property of
# imputation or of the corpus.
#
# WHAT PROMPTED IT. `2026-09-05-divergent-macro-copies.md` found that one macro
# name, `mult_imput`, exists in 423 copies with 381 distinct bodies, and that
# five names declare `NIMPUTE` defaults their copies disagree about. The cause is
# the per-study copy pattern, and ⭐ nothing about that pattern is specific to
# imputation. Every study carries its own copy of the jobs it runs. Nobody has
# checked whether other macro families drifted the same way.
#
#   Rscript macro-drift-scan.R --root /studies --count-only
#   Rscript macro-drift-scan.R --root /studies --out macro-drift.json
#
# ⚠️ RUN `--count-only` FIRST on any root you have not counted before. It lists
# the candidate files and stops without reading any.
#
# THE CORPUS IS 227,783 `.sas` FILES under `/studies`, from this scan's own
# `--count-only` on 2026-09-06. That is a little over twice the imputation walk,
# so a full pass is on the order of an hour and the whole corpus can be done in
# one go. No bounding is needed.
#
# ⚠️ An earlier version of this header said 3,847,221, "measured 2026-09-06".
# That figure did not come from this scan and should not have been written down
# as measured. The number above did.
#
# IF YOU DO NEED TO BOUND IT, bound by ROOT rather than by file count:
#
#   Rscript macro-drift-scan.R --root /studies/<tree> --out drift-<tree>.json
#
# ⭐ A clinical tree is a complete population for this question. Detecting drift
# means comparing every copy of a name against the others, so a subset of FILES
# undercounts it: copies outside the subset are invisible and the name looks more
# consistent than it is. A subset of STUDIES or TREES keeps each observed name's
# copies intact within the subset, and reads as a lower bound rather than a
# biased estimate.
#
# `--stems <regex>` restricts to files whose BASENAME matches, for one family.
# `--max-files N` bounds a smoke test. ⚠️ It samples RANDOMLY under a fixed seed
# rather than taking the first N, because `list.files()` returns directory order
# and the first N would be one subtree presented as a sample. It still
# undercounts drift for the reason above, so use it to check the scan runs, not
# to answer the question.
#
# HOW DRIFT IS MEASURED. For each `%macro` definition found, the body is reduced
# to a fingerprint and the fingerprints for one name are counted. Two figures per
# name, and the difference between them is the interesting part:
#
#   distinct_bodies          copies that differ anywhere, header included
#   distinct_bodies_no_hdr   copies that differ BELOW the header
#
# A name whose copies differ only in the header has drifted in its signature or
# its defaults, which is what bit the imputation macros. A name differing below
# it has drifted in what it does.
#
# ⚠️ THE FINGERPRINT IS NOT A CRYPTOGRAPHIC HASH. It is three cheap statistics
# over the text: length, character sum, and position-weighted character sum. Two
# genuinely different bodies would have to match on all three to be conflated,
# which is unlikely enough for counting and is NOT a claim of uniqueness. Full
# bodies are not retained, because a corpus-wide walk cannot hold them.
#
# PRIVACY CONTRACT -- ⚠️ NARROWER THAN THE COUNTING SCANS, as
# `imputation-reconcile-scan.R` is.
#
# IT EMITS MACRO NAMES, for the most-drifted names only and capped by
# `--top N`. A macro name is a job identifier, not a study or patient one, and
# naming the families is the point of the exercise. It emits no study location,
# no path, no macro body and no source line. Body text exists in memory only long
# enough to be fingerprinted.
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
root       <- normalise_root(getarg("--root", "/studies"))
outfile    <- getarg("--out", "macro-drift.json")
stems      <- getarg("--stems", NULL)
top_n      <- as.integer(getarg("--top", "25"))
max_files  <- suppressWarnings(as.integer(getarg("--max-files", NA)))
count_only <- "--count-only" %in% args

.folders <- taxonomy_folders()
study_of <- study_of_factory(root, .folders)
message("taxonomy folders: ", paste(.folders, collapse = ", "))

pat <- if (is.null(stems)) "\\.sas$" else paste0(stems, ".*\\.sas$")
message("listing .sas files", if (!is.null(stems)) paste0(" matching /", stems, "/") else "",
        " -- this is the slow part on a share")
files <- list.files(root, pattern = pat, recursive = TRUE, full.names = TRUE,
                    ignore.case = TRUE, no.. = TRUE)
message("candidate files: ", length(files))

if (count_only) {
  message("\n--count-only: nothing was read. Decide on the count above before ",
          "running the full pass.")
  quit(save = "no", status = 0)
}
if (!is.na(max_files) && length(files) > max_files) {
  # ⚠️ Random, not the first N: list.files() returns directory order, so the
  # head of it is one subtree wearing the costume of a sample. Seeded so a
  # repeat run reads the same files.
  set.seed(20260906L)
  files <- sort(sample(files, max_files))
  message("--max-files: reading a random ", max_files, " of the listing. ",
          "⚠️ This UNDERCOUNTS drift, because copies of a name outside the ",
          "sample are invisible and the name looks more consistent than it is. ",
          "Bound by --root instead to answer the question.")
}

# ---- fingerprint ------------------------------------------------------------
# Three statistics over the text. See the header: cheap, bounded in memory, and
# not a uniqueness claim.
fingerprint <- function(x) {
  if (!nzchar(x)) return("0-0-0")
  # ⚠️ as.numeric BEFORE multiplying. `v * seq_along(v)` on an INTEGER vector
  # overflows once any element exceeds 2^31, which needs a file of roughly 17
  # million characters. That yields NA for the element and NA for the sum, so
  # the third component collapses and two different files can share a
  # fingerprint. Observed 2026-09-06 as "NAs produced by integer overflow" on a
  # 38,878-file run, so at least one file in this corpus is that large.
  #
  # ⚠️ How much it moved the counts is UNMEASURED. Checked to 2.4 million
  # characters, integer and numeric agree exactly, so only the largest files are
  # affected and the effect is an UNDERCOUNT of distinct bodies rather than an
  # overcount. Any body-count from a run before this fix carries that caveat.
  v <- as.numeric(utf8ToInt(x))
  paste(length(v), sum(v) %% 2147483647,
        sum(v * seq_along(v)) %% 2147483647, sep = "-")
}

# ---- walk -------------------------------------------------------------------
by_name <- new.env(parent = emptyenv())   # name -> list(full=, nohdr=, studies=)
n_defs <- 0L
studies <- study_of(files)

for (i in seq_along(files)) {
  st <- read_statements(files[[i]])
  if (is.null(st)) next
  starts <- grep("^ *%macro +[a-z0-9_]+", st)
  if (!length(starts)) next
  ends <- grep("^ *%mend", st)
  for (s in starts) {
    h <- parse_macro_header(st[[s]])
    if (is.null(h)) next
    e <- ends[ends > s]
    e <- if (length(e)) e[1] else length(st)
    body <- st[seq(s, e)]
    n_defs <- n_defs + 1L
    rec <- by_name[[h$name]]
    if (is.null(rec)) rec <- list(full = character(0), nohdr = character(0),
                                  studies = character(0), n = 0L)
    rec$n     <- rec$n + 1L
    rec$full  <- unique(c(rec$full,  fingerprint(paste(body, collapse = ";"))))
    rec$nohdr <- unique(c(rec$nohdr, fingerprint(paste(body[-1], collapse = ";"))))
    if (!is.na(studies[[i]])) rec$studies <- unique(c(rec$studies, studies[[i]]))
    by_name[[h$name]] <- rec
  }
  if (i %% 5000 == 0) message("  ", i, " / ", length(files))
}

nms <- ls(by_name)
message("macro names defined: ", length(nms), " in ", n_defs, " definitions")

copies  <- vapply(nms, function(n) by_name[[n]]$n, integer(1))
nfull   <- vapply(nms, function(n) length(by_name[[n]]$full), integer(1))
nnohdr  <- vapply(nms, function(n) length(by_name[[n]]$nohdr), integer(1))
nstudy  <- vapply(nms, function(n) length(by_name[[n]]$studies), integer(1))

multi   <- copies > 1L          # names that exist in more than one copy
drifted <- multi & nfull > 1L   # ... whose copies are not all identical
below   <- multi & nnohdr > 1L  # ... that differ below the header
hdr_only <- drifted & !below    # ... that differ ONLY in the header

# ⭐ The headline: of the names that exist in more than one copy, how many
# drifted at all, and how many drifted in what they DO rather than how they are
# declared.
ord <- order(-nfull, -copies)
top <- head(nms[ord][drifted[ord]], max(0L, top_n))

out <- list(
  `_provenance` = list(
    script   = "macro-drift-scan.R",
    question = "is the copy drift found in the imputation macros a property of imputation or of the corpus?",
    run_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    root     = if (identical(root, "/studies")) "/studies" else "(non-default root)",
    scope    = if (is.null(stems)) "every .sas under root" else "basename-restricted",
    hvtiRutilities_version = as.character(utils::packageVersion("hvtiRutilities")),
    taxonomy_folders       = paste(sort(.folders), collapse = ","),
    files_considered = length(files),
    files_unreadable = unreadable_count(),
    macro_definitions = n_defs,
    # ⚠️ TRUE when --max-files subset the listing, in which case every drift
    # figure below is a LOWER BOUND: copies outside the sample were not seen.
    file_sampled = !is.na(max_files),
    # ⚠️ TRUE, like imputation-reconcile-scan.R. Macro names only, capped by
    # --top; no study identifier, path or body. See the header.
    emits_macro_names = TRUE,
    fingerprint = "length + char sum + position-weighted char sum; not a hash"
  ),
  summary = list(
    macro_names            = length(nms),
    names_in_one_copy      = sum(!multi),
    names_in_many_copies   = sum(multi),
    # ⭐ Of the names with several copies, how many are not all identical.
    names_drifted          = sum(drifted),
    names_drifted_below_header = sum(below),
    names_drifted_header_only  = sum(hdr_only),
    max_copies             = if (length(copies)) max(copies) else 0L,
    max_distinct_bodies    = if (length(nfull)) max(nfull) else 0L
  ),
  # For comparison with the imputation result, which is the reason for the scan.
  worst = lapply(top, function(n) list(
    macro = n,
    copies = by_name[[n]]$n,
    studies = length(by_name[[n]]$studies),
    distinct_bodies = length(by_name[[n]]$full),
    distinct_bodies_no_hdr = length(by_name[[n]]$nohdr)
  ))
)

writeLines(to_json(out), outfile)

message("\n--- DRIFT ACROSS MACRO FAMILIES ---")
message("macro names:                    ", out$summary$macro_names)
message("  defined in one copy only:     ", out$summary$names_in_one_copy)
message("  defined in several copies:    ", out$summary$names_in_many_copies)
message("    of those, copies differ:    ", out$summary$names_drifted)
message("      differ below the header:  ", out$summary$names_drifted_below_header)
message("      differ in the header only:", out$summary$names_drifted_header_only)
message("\nmost-drifted names:")
for (w in out$worst) {
  message(sprintf("  %-24s %5d copies / %4d studies   %5d distinct bodies (%d below header)",
                  w$macro, w$copies, w$studies, w$distinct_bodies,
                  w$distinct_bodies_no_hdr))
}
message("\nwrote ", outfile)
