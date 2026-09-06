#!/usr/bin/env Rscript
# lst-listing-scan.R
#
# What was actually filed, and whether it can check a port.
#
# TWO CONSUMERS. `2026-09-02-vars-port-and-attrition-design.md` §4 sets a
# three-rung ladder for verifying a ported `vars.sas`, and rung 3 is VALUES: a
# deterministic model listing fitted on the prepared data, whose coefficients a
# port must reproduce. Those listings live in `.lst` files. HVTR wants the same
# files for a different reason: they are what was actually FILED, as opposed to
# what the code would produce today.
#
#   Rscript lst-listing-scan.R --root /studies --count-only
#   Rscript lst-listing-scan.R --root /studies --out lst-listing.json
#
# ⚠️ RUN `--count-only` FIRST. The `.log` population is 50,608; the `.lst`
# population has not been counted.
#
# 🔴 PRIVACY CONTRACT -- THE SAME STRICTER ONE `log-verifiability-scan.R`
# CARRIES, AND FOR A STRONGER REASON.
#
# A `.log` may contain patient values incidentally, through a PUT statement or an
# error echoing a data line. ⚠️ A `.lst` IS THE PRINTED OUTPUT ITSELF. A
# `PROC PRINT` of a patient-level dataset is a `.lst` full of PHI by design, not
# by accident. This scan is therefore built to be incapable of emitting content
# rather than merely disinclined to.
#
# IT NEVER RETAINS A LINE. Each chunk is tested against fixed patterns and
# discarded, and nothing survives a chunk but integer counters.
#
# ⚠️ IT DETECTS `PROC PRINT` OUTPUT AND DOES NOT READ IT. Knowing how many
# listings are patient-level print-outs matters, because those are the ones
# nobody should be opening casually. Their PRESENCE is counted; not one
# character of them is looked at beyond the header pattern.
#
# IT READS NO NUMBER. A model listing is detected by its section headings, and
# no coefficient, estimate, count or value is parsed. Rung 3 needs the values
# eventually; establishing that a listing EXISTS is a different question, and
# this scan answers only that one.
#
# IT EMITS no path, no file name, no study identifier, no dataset or variable
# name and no listing text. Only counts.
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
outfile    <- getarg("--out", "lst-listing.json")
count_only <- "--count-only" %in% args
chunk      <- as.integer(getarg("--chunk", "20000"))
# As the log scan: chunking bounds memory, not work. A single enormous listing
# would otherwise own the run silently.
max_mb     <- as.numeric(getarg("--max-lst-mb", "200"))

.folders <- taxonomy_folders()
study_of <- study_of_factory(root, .folders)
message("taxonomy folders: ", paste(.folders, collapse = ", "))

message("listing .lst files -- the slow part on a share")
lsts <- list.files(root, pattern = "\\.lst$", recursive = TRUE,
                   full.names = TRUE, ignore.case = TRUE, no.. = TRUE)
message("candidate listings: ", length(lsts))
if (count_only) {
  message("\n--count-only: nothing was read.")
  quit(save = "no", status = 0)
}

# ---- what a listing has to contain to support rung 3 ------------------------
# Section headings SAS prints above a model's coefficients. Matched, never
# captured, and the coefficients themselves are never looked at.
RE_MODEL <- paste0("analysis of maximum likelihood estimates|",
                   "parameter estimates|",
                   "solution for fixed effects|",
                   "analysis of variance")
# ⚠️ A patient-level print-out. Counted so the corpus's PHI exposure through
# these files is known, and never read.
RE_PRINT <- "^ *obs +|the (print|report) procedure"
RE_ANYPROC <- "the [a-z]+ procedure"

inspect <- function(path) {
  if (max_mb > 0) {
    sz <- file.size(path)
    if (!is.na(sz) && sz > max_mb * 1024^2) return("oversized")
  }
  con <- tryCatch(file(path, "r", encoding = "latin1"), error = function(e) NULL)
  if (is.null(con)) return(NULL)
  on.exit(close(con), add = TRUE)
  has <- c(model = FALSE, print = FALSE, proc = FALSE)
  repeat {
    lines <- tryCatch(suppressWarnings(readLines(con, n = chunk, warn = FALSE)),
                      error = function(e) character(0))
    if (!length(lines)) break
    # ⭐ Cheap prefilter FIRST, as `log-verifiability-scan.R` learned to do.
    # Lowercasing every line and then running three patterns over it spends
    # nearly all its time on listing rows that cannot match. Every heading this
    # scan looks for contains one of these fragments, chosen to be
    # case-insensitive WITHOUT the cost of ignore.case: "Procedure" and
    # "procedure" both contain "rocedure", "Estimates" and "estimates" both
    # contain "stimates".
    keep <- grepl("rocedure|stimates|ariance|^ *[Oo]bs ", lines)
    if (!any(keep)) { rm(lines, keep); next }
    lines <- tolower(lines[keep])
    if (!has[["model"]] && any(grepl(RE_MODEL, lines))) has[["model"]] <- TRUE
    if (!has[["print"]] && any(grepl(RE_PRINT, lines))) has[["print"]] <- TRUE
    if (!has[["proc"]]  && any(grepl(RE_ANYPROC, lines))) has[["proc"]] <- TRUE
    if (all(has)) { rm(lines, keep); break }  # nothing left to learn here
    rm(lines, keep)                      # nothing survives the chunk but flags
  }
  list(model = has[["model"]], print = has[["print"]], proc = has[["proc"]])
}

stems <- c(vars = "^vars", build = "^build")
base  <- tolower(basename(lsts))
stem_of <- rep("other", length(lsts))
for (nm in names(stems)) stem_of[grepl(stems[[nm]], base)] <- nm
stu <- study_of(lsts)

n <- c(read = 0L, unreadable = 0L, oversized = 0L, model = 0L, print = 0L,
       proc = 0L, empty = 0L)
stu_any <- character(0); stu_model <- character(0)

for (i in seq_along(lsts)) {
  r <- inspect(lsts[[i]])
  if (identical(r, "oversized")) { n[["oversized"]] <- n[["oversized"]] + 1L; next }
  if (is.null(r)) { n[["unreadable"]] <- n[["unreadable"]] + 1L; next }
  n[["read"]] <- n[["read"]] + 1L
  if (!is.na(stu[[i]])) stu_any <- c(stu_any, stu[[i]])
  if (r$model) { n[["model"]] <- n[["model"]] + 1L
                 if (!is.na(stu[[i]])) stu_model <- c(stu_model, stu[[i]]) }
  if (r$print) n[["print"]] <- n[["print"]] + 1L
  if (r$proc)  n[["proc"]]  <- n[["proc"]]  + 1L
  if (!r$proc && !r$model && !r$print) n[["empty"]] <- n[["empty"]] + 1L
  if (i %% 2000 == 0) message("  ", i, " / ", length(lsts))
}

out <- list(
  `_provenance` = list(
    script   = "lst-listing-scan.R",
    question = "what was filed, and can it check a port at rung 3?",
    run_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    root     = if (identical(root, "/studies")) "/studies" else "(non-default root)",
    hvtiRutilities_version = as.character(utils::packageVersion("hvtiRutilities")),
    taxonomy_folders       = paste(sort(.folders), collapse = ","),
    listings_considered = length(lsts),
    listings_unreadable = n[["unreadable"]],
    listings_oversized  = n[["oversized"]],
    max_lst_mb = max_mb,
    contains_identifiers = FALSE,
    # ⚠️ Stated in the output as well as the header.
    emits_listing_values = FALSE
  ),
  listings = list(
    read                = n[["read"]],
    # ⭐ Carries a model listing, so it could check a port's VALUES at rung 3.
    with_model_listing  = n[["model"]],
    # ⚠️ Carries patient-level print output. Counted so the exposure is known;
    # not read.
    with_print_output   = n[["print"]],
    with_any_procedure  = n[["proc"]],
    with_nothing_recognised = n[["empty"]]
  ),
  studies = list(
    with_any_listing      = length(unique(stu_any)),
    # ⭐ The rung-3 counterpart to log-verifiability's rung-1 figure.
    with_a_model_listing  = length(unique(stu_model))
  )
)

writeLines(to_json(out), outfile)

message("\n--- LISTINGS ---")
message("read:                    ", out$listings$read,
        "  (unreadable ", n[["unreadable"]], ", oversized ", n[["oversized"]], ")")
message("  ⭐ with a model listing: ", out$listings$with_model_listing)
message("  ⚠️ with print output:    ", out$listings$with_print_output)
message("  with any procedure:     ", out$listings$with_any_procedure)
message("  nothing recognised:     ", out$listings$with_nothing_recognised)
message("\n--- STUDIES ---")
message("with any listing:        ", out$studies$with_any_listing)
message("⭐ with a model listing:  ", out$studies$with_a_model_listing)
message("\nwrote ", outfile)
