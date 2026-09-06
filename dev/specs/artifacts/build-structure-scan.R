#!/usr/bin/env Rscript
# build-structure-scan.R
#
# What a study's data build is made of, and what it reads from.
#
# TWO CONSUMERS, ONE SCAN. `2026-08-06-hvtiRdatasets-s1-plan.md` records that S2
# (`build_dataset()`) "has a slice number and no shape", and the shape is what
# these files hold. HVTR is the other consumer, and it wants a different thing
# from the same files: ⭐ if it is to be the one governed upstream replacing a
# patchwork of one-off extracts, the first thing to know is WHAT THOSE EXTRACTS
# READ FROM. Both questions are answered by describing the build rather than by
# interpreting it, so one scan serves both.
#
#   Rscript build-structure-scan.R --root /studies --count-only
#   Rscript build-structure-scan.R --root /studies --out build-structure.json
#
# WHAT IT MEASURES
#
#   how many builds exist, and in how many studies
#   how stereotyped they are, by the fingerprint `macro-drift-scan.R` uses
#   which steps they are made of: DATA steps, and which PROCs
#   whether they compose, via %include or macro calls
#   ⭐ which LIBREFS they read, which is the upstream question
#
# ⚠️ IT DESCRIBES, IT DOES NOT INTERPRET. It does not try to read cohort
# criteria, derivations or variable semantics out of the code. Those need a
# decision about what HVTR is before a scan can count the right thing, and a
# scan that guesses would produce a number that answers neither consumer.
#
# PRIVACY CONTRACT -- as `imputation-reconcile-scan.R`, narrower than the
# counting scans.
#
# IT EMITS LIBREF AND PROC NAMES, capped by `--top`. A libref is a SAS library
# alias, typically an institutional name, and naming them IS the upstream
# question. ⚠️ A libref could in principle be study-specific, so they are emitted
# ONLY above a frequency floor (`--min-libref`, default 5 studies): a name used
# by one study is not an institutional source and is not reported.
#
# It emits no path, no study identifier, no dataset name, no variable name and no
# source line. Bodies are fingerprinted, never retained.
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
root        <- normalise_root(getarg("--root", "/studies"))
outfile     <- getarg("--out", "build-structure.json")
stem        <- getarg("--stem", "^build")
top_n       <- as.integer(getarg("--top", "30"))
min_libref  <- as.integer(getarg("--min-libref", "5"))
count_only  <- "--count-only" %in% args

.folders <- taxonomy_folders()
study_of <- study_of_factory(root, .folders)
message("taxonomy folders: ", paste(.folders, collapse = ", "))

files <- list.files(root, pattern = paste0(stem, ".*\\.sas$"), recursive = TRUE,
                    full.names = TRUE, ignore.case = TRUE, no.. = TRUE)
message("candidate builds: ", length(files))
if (count_only) {
  message("\n--count-only: nothing was read.")
  quit(save = "no", status = 0)
}

fingerprint <- function(x) {
  if (!nzchar(x)) return("0-0-0")
  v <- utf8ToInt(x)
  paste(length(v), sum(v) %% 2147483647,
        sum(v * seq_along(v)) %% 2147483647, sep = "-")
}

studies <- study_of(files)
bodies <- character(0); shapes <- character(0)
n_steps <- integer(0)
procs <- new.env(parent = emptyenv())     # proc name -> studies using it
librefs <- new.env(parent = emptyenv())   # libref    -> studies reading it
bump <- function(env, key, stu) {
  if (is.na(stu)) return(invisible())
  cur <- env[[key]]
  env[[key]] <- if (is.null(cur)) stu else unique(c(cur, stu))
}
n_include <- 0L; n_macrocall <- 0L; n_read <- 0L
stu_seen <- character(0)

for (i in seq_along(files)) {
  st <- read_statements(files[[i]])
  if (is.null(st)) next
  n_read <- n_read + 1L
  s <- studies[[i]]
  if (!is.na(s)) stu_seen <- c(stu_seen, s)

  # The steps a build is made of, in order. The SHAPE fingerprint is over that
  # sequence rather than the text, so two builds doing the same things in the
  # same order match even when their variable names differ. That is the number
  # S2 needs: how many distinct build shapes must be implemented.
  step <- rep(NA_character_, length(st))
  dat <- grepl("^ *data +[^;=]", st)
  step[dat] <- "data"
  pm <- regmatches(st, regexpr("^ *proc +[a-z0-9_]+", st))
  hasp <- grepl("^ *proc +[a-z0-9_]+", st)
  step[hasp] <- sub("^ *proc +", "", unlist(pm))
  seq_steps <- step[!is.na(step)]
  n_steps <- c(n_steps, length(seq_steps))
  for (p in unique(seq_steps[seq_steps != "data"])) bump(procs, p, s)

  bodies <- c(bodies, fingerprint(paste(st, collapse = ";")))
  shapes <- c(shapes, fingerprint(paste(seq_steps, collapse = ">")))

  if (any(grepl("^ *%include", st))) n_include <- n_include + 1L
  if (any(grepl("^ *%[a-z0-9_]+ *\\(", st))) n_macrocall <- n_macrocall + 1L

  # ⭐ The upstream question. A two-level name `lib.member` in a SET, MERGE or
  # FROM names the library it reads. The MEMBER is not recorded: it can be
  # study-specific, and the library is what a governed upstream would replace.
  for (m in regmatches(st, gregexpr("\\b(set|merge|from) +([a-z0-9_]+)\\.[a-z0-9_]+", st))) {
    for (one in m) {
      lib <- sub("^.* ", "", sub("\\..*$", "", one))
      if (nzchar(lib) && !lib %in% c("work")) bump(librefs, lib, s)
    }
  }
  if (i %% 200 == 0) message("  ", i, " / ", length(files))
}

top_of <- function(env, floor = 0L) {
  ks <- ls(env)
  n  <- vapply(ks, function(k) length(env[[k]]), integer(1))
  ks <- ks[n >= floor]; n <- n[n >= floor]
  o <- order(-n)
  lapply(head(o, top_n), function(i) list(name = ks[[i]], studies = n[[i]]))
}

out <- list(
  `_provenance` = list(
    script   = "build-structure-scan.R",
    question = "what is a study's data build made of, and what does it read from?",
    run_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    root     = if (identical(root, "/studies")) "/studies" else "(non-default root)",
    stem     = stem,
    hvtiRutilities_version = as.character(utils::packageVersion("hvtiRutilities")),
    taxonomy_folders       = paste(sort(.folders), collapse = ","),
    files_considered = length(files),
    files_read       = n_read,
    files_unreadable = unreadable_count(),
    emits_libref_and_proc_names = TRUE,
    libref_floor_studies = min_libref
  ),
  builds = list(
    files   = n_read,
    studies = length(unique(stu_seen)),
    # ⭐ How much there is to implement. `distinct_step_shapes` counts builds by
    # their SEQUENCE OF STEPS, so two builds doing the same things in the same
    # order are one shape however their text differs. `distinct_bodies` counts
    # them by text, and the gap between the two is how much of the variation is
    # cosmetic.
    distinct_bodies      = length(unique(bodies)),
    distinct_step_shapes = length(unique(shapes)),
    steps_min    = if (length(n_steps)) min(n_steps) else 0L,
    steps_median = if (length(n_steps)) as.numeric(stats::median(n_steps)) else NA_real_,
    steps_max    = if (length(n_steps)) max(n_steps) else 0L,
    uses_include    = n_include,
    calls_a_macro   = n_macrocall
  ),
  # ⭐ The upstream question: which libraries a build reads from, by how many
  # studies read each. Floored, so a one-study name is not reported.
  librefs_read = top_of(librefs, min_libref),
  procs_used   = top_of(procs, 1L)
)

writeLines(to_json(out), outfile)

message("\n--- BUILDS ---")
message("files / studies:        ", out$builds$files, " / ", out$builds$studies)
message("distinct bodies:        ", out$builds$distinct_bodies)
message("⭐ distinct step shapes: ", out$builds$distinct_step_shapes)
message("steps per build:        ", out$builds$steps_min, " / ",
        out$builds$steps_median, " / ", out$builds$steps_max, "  (min/median/max)")
message("uses %include:          ", out$builds$uses_include)
message("calls a macro:          ", out$builds$calls_a_macro)
message("\n--- LIBREFS READ (studies) ---")
for (l in out$librefs_read) message(sprintf("  %-16s %5d", l$name, l$studies))
message("\n--- PROCS USED (studies) ---")
for (p in utils::head(out$procs_used, 15)) message(sprintf("  %-16s %5d", p$name, p$studies))
message("\nwrote ", outfile)
