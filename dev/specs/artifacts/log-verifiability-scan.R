#!/usr/bin/env Rscript
# log-verifiability-scan.R
#
# Answers the number `2026-09-02-vars-port-and-attrition-design.md` §6 says
# nobody has:
#
#   ⭐ FOR WHAT FRACTION OF STUDIES COULD A PORT BE VERIFIED AT ALL?
#
# That note's §4 sets a three-step ladder for checking a ported `vars.sas`, and
# the first rung is SHAPE: rows and variables before and after, read from the
# study's saved SAS log. A study that kept no log cannot be checked that way, and
# a port that cannot be checked is, in that note's words, a machine for producing
# unverifiable data preparation. The fraction also bounds how much of the corpus
# is recoverable by any means, hand-written ports included.
#
#   Rscript log-verifiability-scan.R --root /studies --count-only
#   Rscript log-verifiability-scan.R --root /studies --out log-verifiability.json
#
# ⚠️ RUN `--count-only` FIRST. The `.sas` population is 227,783 files; the `.log`
# population has never been counted, and logs are far larger per file than
# source.
#
# 🔴 PRIVACY CONTRACT -- STRICTER THAN EVERY OTHER SCAN HERE, AND THE REASON IS
# THE FILE TYPE.
#
# A `.sas` file is code. ⚠️ A `.log` IS OUTPUT, and a SAS log can contain patient
# values directly: a `PUT` statement, an error echoing the data line that caused
# it, `OPTIONS MPRINT` expanding a macro with real values in it. Every other scan
# in this directory reads code and could afford a contract about what it chose to
# emit. This one reads text that may be PHI, so the contract is about what it is
# CAPABLE of emitting.
#
# THE SCAN NEVER RETAINS A LINE. Each chunk of a log is tested against fixed
# patterns and discarded; no line, fragment, match or capture group is stored,
# printed or written. The only values that survive a chunk are integer counters.
#
# IT DOES NOT EMIT THE NUMBERS INSIDE THE NOTES. A `NOTE: The data set X has N
# observations and M variables` line is detected, and N and M are NOT read. That
# is deliberate: a dataset row count is a cohort size, small ones can be
# disclosive, and the question here is whether the shape was RECORDED, not what
# it was. Add them only with a decision to do so, not by drifting into it.
#
# IT EMITS no path, no file name, no study identifier, no dataset name, no
# variable name and no log text. Only counts, and macro-family labels fixed in
# this file rather than read from the corpus.
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
outfile    <- getarg("--out", "log-verifiability.json")
count_only <- "--count-only" %in% args
chunk      <- as.integer(getarg("--chunk", "20000"))

.folders <- taxonomy_folders()
study_of <- study_of_factory(root, .folders)
message("taxonomy folders: ", paste(.folders, collapse = ", "))

message("listing .log files -- the slow part on a share")
logs <- list.files(root, pattern = "\\.log$", recursive = TRUE,
                   full.names = TRUE, ignore.case = TRUE, no.. = TRUE)
message("candidate logs: ", length(logs))

if (count_only) {
  message("\n--count-only: nothing was read. Decide on the count above before ",
          "running the full pass.")
  quit(save = "no", status = 0)
}

# ---- what a log has to contain to support rung 1 ----------------------------
# The shape NOTE is SAS's own record of a dataset's dimensions. ⚠️ Matched, never
# captured: see the contract above.
RE_SHAPE <- "^note: the data set .* has [0-9]+ observations and [0-9]+ variables"
RE_ERROR <- "^error"
RE_WARN  <- "^warning"
# A log that ends normally says so. One that does not may be truncated, and a
# truncated log is not evidence of a completed build.
RE_END   <- "^note: sas institute inc|^note: the sas system used"

# Read a log in bounded chunks. ⚠️ A SAS log can be tens of megabytes, and
# holding one whole would be both wasteful and a larger PHI surface than
# necessary. Each chunk is tested and dropped.
inspect <- function(path) {
  con <- tryCatch(file(path, "r", encoding = "latin1"), error = function(e) NULL)
  if (is.null(con)) return(NULL)
  on.exit(close(con), add = TRUE)
  has <- c(shape = FALSE, error = FALSE, warn = FALSE, end = FALSE)
  n_shape <- 0L
  repeat {
    lines <- tryCatch(suppressWarnings(readLines(con, n = chunk, warn = FALSE)),
                      error = function(e) character(0))
    if (!length(lines)) break
    lines <- tolower(lines)
    hits <- grepl(RE_SHAPE, lines)
    if (any(hits)) { has[["shape"]] <- TRUE; n_shape <- n_shape + sum(hits) }
    if (!has[["error"]] && any(grepl(RE_ERROR, lines))) has[["error"]] <- TRUE
    if (!has[["warn"]]  && any(grepl(RE_WARN,  lines))) has[["warn"]]  <- TRUE
    if (any(grepl(RE_END, lines))) has[["end"]] <- TRUE
    rm(lines, hits)                     # nothing survives the chunk but counters
  }
  list(shape = has[["shape"]], n_shape = n_shape, error = has[["error"]],
       warn = has[["warn"]], end = has[["end"]])
}

# ---- walk -------------------------------------------------------------------
stems <- c(vars = "^vars", build = "^build",
           imputsub = "^imputsub", mult_imput = "^mult_imput")
base  <- tolower(basename(logs))
stem_of <- rep("other", length(logs))
for (nm in names(stems)) stem_of[grepl(stems[[nm]], base)] <- nm
stu <- study_of(logs)

n <- c(read = 0L, unreadable = 0L, shape = 0L, error = 0L, warn = 0L,
       ended = 0L, usable = 0L)
shape_by_stem <- setNames(integer(length(stems) + 1L), c(names(stems), "other"))
logs_by_stem  <- shape_by_stem
usable_by_stem <- shape_by_stem
stu_any <- character(0); stu_usable <- character(0)

for (i in seq_along(logs)) {
  r <- inspect(logs[[i]])
  sk <- stem_of[[i]]
  logs_by_stem[[sk]] <- logs_by_stem[[sk]] + 1L
  if (is.null(r)) { n[["unreadable"]] <- n[["unreadable"]] + 1L; next }
  n[["read"]] <- n[["read"]] + 1L
  if (!is.na(stu[[i]])) stu_any <- c(stu_any, stu[[i]])
  if (r$shape) { n[["shape"]] <- n[["shape"]] + 1L
                 shape_by_stem[[sk]] <- shape_by_stem[[sk]] + 1L }
  if (r$error) n[["error"]] <- n[["error"]] + 1L
  if (r$warn)  n[["warn"]]  <- n[["warn"]]  + 1L
  if (r$end)   n[["ended"]] <- n[["ended"]] + 1L
  # ⭐ Rung 1 needs a log that RECORDED a shape and did not fail. A log full of
  # errors is not evidence of a build that happened.
  if (r$shape && !r$error) {
    n[["usable"]] <- n[["usable"]] + 1L
    usable_by_stem[[sk]] <- usable_by_stem[[sk]] + 1L
    if (!is.na(stu[[i]])) stu_usable <- c(stu_usable, stu[[i]])
  }
  if (i %% 2000 == 0) message("  ", i, " / ", length(logs))
}

studies_any    <- length(unique(stu_any))
studies_usable <- length(unique(stu_usable))

out <- list(
  `_provenance` = list(
    script   = "log-verifiability-scan.R",
    question = "for what fraction of studies could a ported vars.sas be verified at rung 1?",
    run_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    root     = if (identical(root, "/studies")) "/studies" else "(non-default root)",
    hvtiRutilities_version = as.character(utils::packageVersion("hvtiRutilities")),
    taxonomy_folders       = paste(sort(.folders), collapse = ","),
    logs_considered = length(logs),
    logs_unreadable = n[["unreadable"]],
    contains_identifiers = FALSE,
    # ⚠️ Stated in the output as well as the header: the numbers inside the
    # shape NOTEs are detected and deliberately not read. See the contract.
    emits_dataset_dimensions = FALSE
  ),
  logs = list(
    read              = n[["read"]],
    with_shape_note   = n[["shape"]],
    with_error        = n[["error"]],
    with_warning      = n[["warn"]],
    ended_normally    = n[["ended"]],
    # ⭐ THE ANSWER, at log level: recorded a shape and did not fail.
    usable_for_rung_1 = n[["usable"]]
  ),
  studies = list(
    with_any_log            = studies_any,
    # ⭐ THE ANSWER, at study level. This is the fraction §6 asks for, once set
    # against the number of studies that exist.
    with_a_usable_log       = studies_usable
  ),
  by_stem = lapply(c(names(stems), "other"), function(k) list(
    stem = k, logs = logs_by_stem[[k]],
    with_shape_note = shape_by_stem[[k]],
    usable_for_rung_1 = usable_by_stem[[k]]
  ))
)

writeLines(to_json(out), outfile)

message("\n--- LOGS ---")
message("read:                 ", out$logs$read, "  (unreadable ",
        out$`_provenance`$logs_unreadable, ")")
message("  recorded a shape:   ", out$logs$with_shape_note)
message("  carried an ERROR:   ", out$logs$with_error)
message("  carried a WARNING:  ", out$logs$with_warning)
message("  ended normally:     ", out$logs$ended_normally)
message("  ⭐ usable for rung 1: ", out$logs$usable_for_rung_1)
message("\n--- STUDIES ---")
message("with any log:         ", out$studies$with_any_log)
message("⭐ with a usable log:  ", out$studies$with_a_usable_log)
message("\n--- BY STEM ---")
for (b in out$by_stem) {
  message(sprintf("  %-12s %7d logs   %7d with shape   %7d usable",
                  b$stem, b$logs, b$with_shape_note, b$usable_for_rung_1))
}
message("\nwrote ", outfile)
