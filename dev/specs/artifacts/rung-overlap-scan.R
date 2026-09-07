#!/usr/bin/env Rscript
# rung-overlap-scan.R
#
# Answers the join `results/README.md` has listed as outstanding since
# 2026-09-06:
#
#   ⭐ HOW MANY STUDIES CAN BE VERIFIED AT BOTH RUNG 1 AND RUNG 3?
#
# `2026-09-02-vars-port-and-attrition-design.md` §4 sets a three-rung ladder for
# checking a ported `vars.sas`. Rung 1 is SHAPE, read from a saved log; rung 3 is
# MODEL AGREEMENT, read from a saved listing. `log-verifiability.json` says 1,180
# studies clear rung 1 and `lst-listing.json` says 676 clear rung 3, and NEITHER
# FILE CAN BE JOINED TO THE OTHER: both reduce their study set to
# `length(unique(...))` before writing, so the members are gone. Two counts of
# two sets whose overlap could be anything from 0 to 676.
#
# ⭐ THE JOIN IS COMPUTED HERE AND ONLY A SCALAR LEAVES. The obvious alternative
# -- emit both study lists and intersect them afterwards -- would put roughly
# 1,900 study identifiers into a committed artifact. A study identifier is the
# class `st1027` belonged to, withdrawn from `build-structure.json` on
# 2026-09-06. Aggregating where the data lives is what makes this scan safe; a
# filter on the way out is what failed last time.
#
#   Rscript rung-overlap-scan.R --root /studies --count-only
#   Rscript rung-overlap-scan.R --root /studies --out rung-overlap.json
#
# ⚠️ RUN `--count-only` FIRST. This walks BOTH populations -- 50,608 logs and
# 49,307 listings as of 2026-09-06 -- so it costs about what those two scans cost
# together, and it is the slowest scan in this directory.
#
# 🔴 PRIVACY CONTRACT -- THE STRICTER ONE, INHERITED FROM BOTH PARENTS AND
# WEAKENED BY NEITHER.
#
# This scan reads `.log` files, which can contain patient values directly (a PUT
# statement, an error echoing its data line, OPTIONS MPRINT expanding a macro),
# AND `.lst` files, which ARE printed output and whose PROC PRINT pages are
# patient data by design. It therefore holds the union of both contracts:
#
# NO LINE SURVIVES A CHUNK. Each chunk is tested against fixed patterns and
# dropped. No line, fragment, match or capture group is stored, printed or
# written. Only logical flags and integer counters cross a chunk boundary.
#
# NO DATASET DIMENSION AND NO LISTING VALUE IS READ. A shape NOTE is detected
# without reading its N and M; a model listing is detected without reading a
# coefficient.
#
# ⭐ AND NO STUDY IDENTIFIER IS EMITTED, WHICH IS THIS SCAN'S OWN ADDITION. It
# necessarily HOLDS study identity -- that is the join -- so identity lives in
# two `character` vectors that are reduced to set sizes and never written. The
# output carries eight integers and the provenance block.
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
outfile    <- getarg("--out", "rung-overlap.json")
count_only <- "--count-only" %in% args
chunk      <- as.integer(getarg("--chunk", "20000"))
# One ceiling for both file types. The parent scans carry separate flags because
# they ran separately; here a single value keeps the two halves comparable, and
# 200 MB is what both of them used.
max_mb     <- as.numeric(getarg("--max-mb", "200"))

# ---- detection: COPIED, AND THE COPYING IS THE RISK --------------------------
# 🔴 These three patterns are byte-for-byte copies from `log-verifiability-scan.R`
# and `lst-listing-scan.R`. If they drift, this scan reports the overlap of two
# populations that are NOT the ones the parent artifacts describe, while still
# looking exactly like an answer.
#
# ⭐ That is precisely the defect this whole body of work measured: 1,064 of
# 1,444 multi-copy macro names in this corpus have copies that disagree, and
# nobody noticed because a copy that has drifted still runs. So the drift is
# guarded rather than trusted -- `test-rung-overlap-scan.R` extracts these lines
# from all three scripts and fails if any pair differs. Change one, change all
# three, and let the test say so if you forget.
RE_SHAPE   <- "^note: the data set .* has [0-9]+ observations and [0-9]+ variables"
RE_ERROR   <- "^error"
RE_MODEL   <- paste0("analysis of maximum likelihood estimates|",
                     "parameter estimates|",
                     "solution for fixed effects|",
                     "analysis of variance")
# `lst-listing-scan.R`'s RE_PRINT and RE_ANYPROC are deliberately NOT copied:
# this scan does not count print output or bare procedures, and an unused copy
# is a copy free to drift unnoticed.

.folders <- taxonomy_folders()
study_of <- study_of_factory(root, .folders)
message("taxonomy folders: ", paste(.folders, collapse = ", "))

message("listing .log and .lst files -- the slow part on a share")
logs <- list.files(root, pattern = "\\.log$", recursive = TRUE,
                   full.names = TRUE, ignore.case = TRUE, no.. = TRUE)
lsts <- list.files(root, pattern = "\\.lst$", recursive = TRUE,
                   full.names = TRUE, ignore.case = TRUE, no.. = TRUE)
message("candidate logs:     ", length(logs))
message("candidate listings: ", length(lsts))

if (count_only) {
  message("\n--count-only: nothing was read. Decide on the counts above before ",
          "running the full pass.")
  quit(save = "no", status = 0)
}

# ---- readers ----------------------------------------------------------------
# Both mirror their parent scan: a size ceiling, a cheap anchored prefilter, and
# nothing but flags surviving a chunk.
inspect_log <- function(path) {
  if (max_mb > 0) {
    sz <- file.size(path)
    if (!is.na(sz) && sz > max_mb * 1024^2) return("oversized")
  }
  con <- tryCatch(file(path, "r", encoding = "latin1"), error = function(e) NULL)
  if (is.null(con)) return(NULL)
  on.exit(close(con), add = TRUE)
  has <- c(shape = FALSE, error = FALSE)
  repeat {
    lines <- tryCatch(suppressWarnings(readLines(con, n = chunk, warn = FALSE)),
                      error = function(e) character(0))
    if (!length(lines)) break
    # ⚠️ DELIBERATE divergence from the parent prefilter, which also admits
    # WARNING. This scan tracks no warning metric, and RE_SHAPE and RE_ERROR
    # match only NOTE and ERROR lines, so admitting WARNING would cost work and
    # change nothing. Narrowing a prefilter is safe ONLY while every pattern
    # behind it is anchored to what the prefilter still admits.
    keep <- grepl("^(NOTE|ERROR)", lines, ignore.case = TRUE)
    if (!any(keep)) { rm(lines, keep); next }
    lines <- tolower(lines[keep])
    if (!has[["shape"]] && any(grepl(RE_SHAPE, lines))) has[["shape"]] <- TRUE
    if (!has[["error"]] && any(grepl(RE_ERROR, lines))) has[["error"]] <- TRUE
    # ⚠️ NO EARLY BREAK ON `error`. A log that has not shown an error YET may
    # show one later, so `usable` is only known at end of file. Breaking when
    # both flags are TRUE is safe; breaking when either is would not be.
    if (all(has)) { rm(lines, keep); break }
    rm(lines, keep)
  }
  list(shape = has[["shape"]], error = has[["error"]])
}

inspect_lst <- function(path) {
  if (max_mb > 0) {
    sz <- file.size(path)
    if (!is.na(sz) && sz > max_mb * 1024^2) return("oversized")
  }
  con <- tryCatch(file(path, "r", encoding = "latin1"), error = function(e) NULL)
  if (is.null(con)) return(NULL)
  on.exit(close(con), add = TRUE)
  model <- FALSE
  repeat {
    lines <- tryCatch(suppressWarnings(readLines(con, n = chunk, warn = FALSE)),
                      error = function(e) character(0))
    if (!length(lines)) break
    keep <- grepl("rocedure|stimates|ariance|^ *[Oo]bs ", lines)
    if (!any(keep)) { rm(lines, keep); next }
    lines <- tolower(lines[keep])
    if (any(grepl(RE_MODEL, lines))) { model <- TRUE; rm(lines, keep); break }
    rm(lines, keep)
  }
  model
}

# ---- walk -------------------------------------------------------------------
# ⭐ Preallocate and assign by index. The parent scans grow a vector with c() in
# the loop, which is quadratic; at 50,000 files that is measurable and there is
# no reason to inherit it.
stu_log <- study_of(logs)
stu_lst <- study_of(lsts)

n <- c(logs_read = 0L, logs_unreadable = 0L, logs_oversized = 0L,
       lsts_read = 0L, lsts_unreadable = 0L, lsts_oversized = 0L,
       logs_usable = 0L, lsts_model = 0L)

any_log   <- character(length(logs)); use_log <- character(length(logs))
any_lst   <- character(length(lsts)); mod_lst <- character(length(lsts))

for (i in seq_along(logs)) {
  r <- inspect_log(logs[[i]])
  # Existence before any skip, as both parents were fixed to do on 2026-09-06.
  if (!is.na(stu_log[[i]])) any_log[[i]] <- stu_log[[i]]
  if (identical(r, "oversized")) { n[["logs_oversized"]] <- n[["logs_oversized"]] + 1L; next }
  if (is.null(r)) { n[["logs_unreadable"]] <- n[["logs_unreadable"]] + 1L; next }
  n[["logs_read"]] <- n[["logs_read"]] + 1L
  if (r$shape && !r$error) {
    n[["logs_usable"]] <- n[["logs_usable"]] + 1L
    if (!is.na(stu_log[[i]])) use_log[[i]] <- stu_log[[i]]
  }
  if (i %% 2000 == 0) message("  logs ", i, " / ", length(logs))
}

for (i in seq_along(lsts)) {
  r <- inspect_lst(lsts[[i]])
  if (!is.na(stu_lst[[i]])) any_lst[[i]] <- stu_lst[[i]]
  if (identical(r, "oversized")) { n[["lsts_oversized"]] <- n[["lsts_oversized"]] + 1L; next }
  if (is.null(r)) { n[["lsts_unreadable"]] <- n[["lsts_unreadable"]] + 1L; next }
  n[["lsts_read"]] <- n[["lsts_read"]] + 1L
  if (isTRUE(r)) {
    n[["lsts_model"]] <- n[["lsts_model"]] + 1L
    if (!is.na(stu_lst[[i]])) mod_lst[[i]] <- stu_lst[[i]]
  }
  if (i %% 2000 == 0) message("  listings ", i, " / ", length(lsts))
}

# ---- the join ---------------------------------------------------------------
# 🔴 The only place study identity is used, and it never leaves this block.
S_rung1 <- unique(use_log[nzchar(use_log)])
S_rung3 <- unique(mod_lst[nzchar(mod_lst)])
S_anylog <- unique(any_log[nzchar(any_log)])
S_anylst <- unique(any_lst[nzchar(any_lst)])

both   <- length(intersect(S_rung1, S_rung3))
either <- length(union(S_rung1, S_rung3))
seen   <- length(union(S_anylog, S_anylst))

out <- list(
  `_provenance` = list(
    script = "rung-overlap-scan.R",
    question = "how many studies can be verified at both rung 1 and rung 3?",
    run_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    root = if (identical(root, "/studies")) "/studies" else "(non-default root)",
    hvtiRutilities_version = as.character(utils::packageVersion("hvtiRutilities")),
    taxonomy_folders = paste(sort(.folders), collapse = ","),
    logs_considered = length(logs),
    listings_considered = length(lsts),
    logs_unreadable = unname(n[["logs_unreadable"]]),
    listings_unreadable = unname(n[["lsts_unreadable"]]),
    logs_oversized = unname(n[["logs_oversized"]]),
    listings_oversized = unname(n[["lsts_oversized"]]),
    max_mb = max_mb,
    contains_identifiers = FALSE,
    emits_study_identifiers = FALSE,
    emits_dataset_dimensions = FALSE,
    emits_listing_values = FALSE
  ),
  files = list(
    logs_read = unname(n[["logs_read"]]),
    logs_usable_for_rung_1 = unname(n[["logs_usable"]]),
    listings_read = unname(n[["lsts_read"]]),
    listings_with_a_model = unname(n[["lsts_model"]])
  ),
  studies = list(
    # ⭐ THE ANSWER. The three below it are what make it readable.
    both_rungs   = both,
    rung_1_only  = length(S_rung1) - both,
    rung_3_only  = length(S_rung3) - both,
    either_rung  = either,
    # Cross-checks against the two parent artifacts. These SHOULD reproduce
    # `log-verifiability.json`'s with_a_usable_log and `lst-listing.json`'s
    # with_a_model_listing. If they do not, the patterns have drifted and the
    # overlap above describes something other than what it claims.
    with_a_usable_log     = length(S_rung1),
    with_a_model_listing  = length(S_rung3),
    # ⚠️ NOT A DENOMINATOR. This is studies holding a log OR a listing, which is
    # the population this scan can SEE. A study with neither leaves no trace in
    # either walk, so "how many studies have NEITHER rung" is NOT answerable
    # here: it needs a universe from a scan that walks `.sas`. Divide by the
    # census figure, not by this.
    seen_with_any_log_or_listing = seen
  )
)

writeLines(to_json(out), outfile)
message("\nwrote ", outfile)
message("both rungs:    ", both)
message("rung 1 only:   ", out$studies$rung_1_only)
message("rung 3 only:   ", out$studies$rung_3_only)
message("⭐ either rung: ", either)
