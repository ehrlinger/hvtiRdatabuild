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
#   ⭐ where their LIBNAME statements POINT, which is the upstream question
#
# ⚠️ IT DESCRIBES, IT DOES NOT INTERPRET. It does not try to read cohort
# criteria, derivations or variable semantics out of the code. Those need a
# decision about what HVTR is before a scan can count the right thing, and a
# scan that guesses would produce a number that answers neither consumer.
#
# PRIVACY CONTRACT -- as `imputation-reconcile-scan.R`, narrower than the
# counting scans.
#
# IT EMITS PROC NAMES, LIBREF ALIASES, AND LIBNAME TARGET PREFIXES, all capped by
# `--top` and all above a frequency floor (`--min-libref`, default 5 studies).
#
# ⚠️ A LIBREF IS AN ALIAS AND ANSWERS NOTHING. The first run of this scan
# returned `library` in 74 studies and `lib` in 21, which says only that people
# call their libraries "library". The upstream question is in the LIBNAME target,
# and that is a PATH.
#
# ⚠️ So paths are truncated to their leading `--path-depth` components (default
# 2) and floored. A study's own directory does not appear in five studies; an
# institutional mount does. No full path, no member name, no study identifier and
# no source line is emitted, and bodies are fingerprinted rather than retained.
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
# ⚠️ SCOPE BY TAXONOMY FOLDER, NOT BY FILENAME. The first run of this scan used
# `--stem ^build` and found 237 builds in 130 studies, fewer than one study in
# eleven of the 1,487 that hold SAS code. Studies that happen to name a file
# `build*.sas` are not a random sample of how builds are written, and this corpus
# has now misled a filename-scoped scan three times: `mult_imput`'s definitions
# were not in `mult_imput*.sas`, `vars`'s shape records were not in `vars.log`,
# and the job census counts by dot-field rather than by prefix.
#
# The taxonomy is structural rather than nominal: `hvtiRutilities` names
# `datasets` as the folder build jobs live in, and every study following the
# convention has one. `--folder` scopes by that; `--stem` still exists and
# restricts within it.
folder_scope <- getarg("--folder", "datasets")
stem        <- getarg("--stem", "")
top_n       <- as.integer(getarg("--top", "30"))
min_libref  <- as.integer(getarg("--min-libref", "5"))
# How many leading path components of a LIBNAME target to keep. Two is enough to
# distinguish institutional mounts and short enough that a study directory is
# unlikely to survive the frequency floor below.
path_depth  <- as.integer(getarg("--path-depth", "2"))
count_only  <- "--count-only" %in% args
# 🔴 NAMES ARE OPT-IN. The 2026-09-06 run emitted `/home/mgoormas`, a personal
# home directory naming an individual, and `st1027`, a study identifier used as a
# libref by 247 studies. Both cleared the frequency floor and both broke this
# scan's stated contract.
#
# ⚠️ THE FLOOR WAS THE WRONG INSTRUMENT. It assumed an identifying name is a RARE
# name. A shared reference to one study's library is common AND identifying, and
# a floor can never catch that. The filter below rejects the shapes I can
# enumerate, and I cannot enumerate them all, so the DEFAULT is now counts only:
# forgetting the flag yields a safe artifact rather than an unsafe one.
#
# `--emit-names` turns them on, for someone who will read the output before
# committing it. The provenance records which mode ran.
emit_names  <- "--emit-names" %in% args

.folders <- taxonomy_folders()
study_of <- study_of_factory(root, .folders)
message("taxonomy folders: ", paste(.folders, collapse = ", "))

pat <- if (nzchar(stem)) paste0(stem, ".*\\.sas$") else "\\.sas$"
files <- list.files(root, pattern = pat, recursive = TRUE,
                    full.names = TRUE, ignore.case = TRUE, no.. = TRUE)
if (nzchar(folder_scope)) {
  # Keep files sitting under a directory of that name, at any depth.
  files <- files[grepl(paste0("/", folder_scope, "/"), files, fixed = TRUE)]
}
message("candidate files: ", length(files),
        "  (folder: ", if (nzchar(folder_scope)) folder_scope else "any",
        ", stem: ", if (nzchar(stem)) stem else "any", ")")
if (count_only) {
  message("\n--count-only: nothing was read.")
  quit(save = "no", status = 0)
}

# ---- fingerprint --------------------------------------------------------------
# ⚠️ THE EARLIER FINGERPRINT COLLIDED, AND NOT ONLY IN THEORY. It was three
# statistics -- length, character sum, position-weighted character sum -- and
# both sums are SYMMETRIC under swapping a pair of characters around the centre,
# so `fingerprint("abba")` and `fingerprint("baab")` returned the same value.
# Distinct bodies could therefore merge, making `distinct_bodies` an UNDERCOUNT
# WITH NO BOUND. An earlier note said the overflow fix left the counts unchanged;
# that was true of overflow and said nothing about collisions, which were always
# the larger risk and were never tested.
#
# ⭐ Use a real digest where one exists. `digest` is present on this corpus's
# server and gives md5; the fallback keeps the machine running where it is not,
# and the output RECORDS WHICH RAN so a count is never read as stronger than the
# function that produced it.
.fp_digest <- requireNamespace("digest", quietly = TRUE)
# Macro-language keywords and built-in functions that can open a statement.
# ⚠️ Not exhaustive: SAS has many built-ins, and this list covers the ones that
# appear statement-initially. A name missing from it is counted as a user macro,
# so the metric errs toward over-counting composition rather than under.
SAS_MACRO_WORDS <- c(
  "macro", "mend", "let", "if", "then", "else", "do", "end", "to", "by",
  "while", "until", "global", "local", "return", "goto", "put", "abort",
  "include", "run", "quit", "sysfunc", "qsysfunc", "sysevalf", "eval",
  "str", "nrstr", "quote", "nrquote", "bquote", "nrbquote", "unquote",
  "scan", "qscan", "substr", "qsubstr", "upcase", "lowcase", "length",
  "index", "sysget", "symexist", "symglobl", "symlocal", "syscall",
  "window", "display", "input", "sysrc", "superq", "unquote")

fingerprint_method <- if (.fp_digest) "md5" else "weighted-sums (COLLISION-PRONE)"
fingerprint <- function(x) {
  if (!nzchar(x)) return("empty")
  if (.fp_digest) return(digest::digest(x, algo = "md5"))
  # ⚠️ Fallback only. A fourth statistic weighted by the SQUARE of position
  # breaks the symmetric-swap class above, but this is still not a hash and
  # collisions are not excluded. `fingerprint_method` says so in the output.
  v <- as.numeric(utf8ToInt(x)); i <- seq_along(v)
  paste(length(v), sum(v) %% 2147483647, sum(v * i) %% 2147483647,
        sum(v * i * i) %% 2147483647, sep = "-")
}

studies <- study_of(files)
bodies <- character(0); shapes <- character(0)
n_steps <- integer(0)
procs <- new.env(parent = emptyenv())     # proc name -> studies using it
librefs <- new.env(parent = emptyenv())   # libref    -> studies reading it
libpaths <- new.env(parent = emptyenv())  # LIBNAME target prefix -> studies
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
  # ⚠️ USER MACRO CALLS ONLY. The earlier test was `^ *%[a-z0-9_]+ *\\(`, which
  # counted built-in macro FUNCTIONS such as %sysfunc(), %scan() and %str() as
  # composition, missed parameterless invocations like `%refresh;`, and matched
  # inside macro DEFINITIONS as well as at top level. It did not measure whether
  # a build composes.
  #
  # Now: a statement-initial %name, with or without parentheses, that is neither
  # a macro-language keyword nor a built-in function, and not inside a %macro
  # body. The built-in list is not exhaustive; SAS has many, and the ones that
  # appear at the start of a statement are the ones that matter here.
  in_macro <- cumsum(grepl("^ *%macro\\b", st)) - cumsum(grepl("^ *%mend\\b", st))
  cand <- grepl("^ *%[a-z0-9_]+", st) & in_macro <= 0L
  nm_of <- sub("^ *%([a-z0-9_]+).*$", "\\1", st)
  if (any(cand & !nm_of %in% SAS_MACRO_WORDS)) n_macrocall <- n_macrocall + 1L

  # The libref a SET, MERGE or FROM reads. ⚠️ A LIBREF IS AN ALIAS AND NAMES
  # NOTHING. The first run returned `library` in 74 studies and `lib` in 21,
  # which says only that people call their libraries "library". The alias is
  # still recorded, because a study reading `work` only is different from one
  # reading anywhere else, but it does not answer the upstream question.
  for (m in regmatches(st, gregexpr("\\b(set|merge|from) +([a-z0-9_]+)\\.[a-z0-9_]+", st))) {
    for (one in m) {
      lib <- sub("^.* ", "", sub("\\..*$", "", one))
      if (nzchar(lib) && !lib %in% c("work")) bump(librefs, lib, s)
    }
  }

  # ⭐ THE UPSTREAM QUESTION IS IN THE LIBNAME TARGET, not the alias. `libname
  # library '/some/path';` is what says where a build actually reads from, and
  # that path is what a governed upstream would replace.
  #
  # ⚠️ A path can be study-specific, so only its DIRECTORY PREFIX is kept, to a
  # bounded depth, and the frequency floor below drops anything a handful of
  # studies use. A study's own directory does not clear that floor; an
  # institutional mount does.
  for (m in regmatches(st, gregexpr("libname +[a-z0-9_]+ +['\"][^'\"]+['\"]", st))) {
    for (one in m) {
      pth <- sub("^.*['\"]([^'\"]+)['\"].*$", "\\1", one)
      parts <- strsplit(sub("^/+", "", pth), "/", fixed = TRUE)[[1]]
      if (!length(parts)) next
      pref <- paste0("/", paste(utils::head(parts, path_depth), collapse = "/"))
      bump(libpaths, pref, s)
    }
  }
  if (i %% 200 == 0) message("  ", i, " / ", length(files))
}

# ⚠️ Shapes that identify a person or a study, rejected whatever their
# frequency. This list is not exhaustive and cannot be: it is a second line
# behind the counts-only default, not a substitute for it.
looks_identifying <- function(x) {
  grepl("^/home/|^/users?/|^/u/|^/export/home/", x) ||   # a personal directory
    grepl("(^|[/_.])(st|study)[0-9]{3,}", x) ||          # a study identifier
    grepl("(^|/)(mrn|phi|patient)", x)
}

top_of <- function(env, floor = 0L) {
  ks <- ls(env)
  n  <- vapply(ks, function(k) length(env[[k]]), integer(1))
  keep <- n >= floor & !vapply(ks, looks_identifying, logical(1))
  n_rejected <- sum(n >= floor & vapply(ks, looks_identifying, logical(1)))
  ks <- ks[keep]; n <- n[keep]
  o <- order(-n)
  list(
    # ⭐ Counts are always safe and always emitted.
    distinct = length(ks),
    # ⚠️ Cleared the floor but were rejected as identifying. Counted so a reader
    # knows something was withheld rather than absent.
    withheld_as_identifying = n_rejected,
    top = if (emit_names)
      lapply(head(o, top_n), function(i) list(name = ks[[i]], studies = n[[i]]))
    else list()
  )
}

out <- list(
  `_provenance` = list(
    script   = "build-structure-scan.R",
    question = "what is a study's data build made of, and what does it read from?",
    run_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    root     = if (identical(root, "/studies")) "/studies" else "(non-default root)",
    folder   = folder_scope,
    stem     = stem,
    path_depth = path_depth,
    fingerprint = fingerprint_method,
    hvtiRutilities_version = as.character(utils::packageVersion("hvtiRutilities")),
    taxonomy_folders       = paste(sort(.folders), collapse = ","),
    files_considered = length(files),
    files_read       = n_read,
    files_unreadable = unreadable_count(),
    emits_names = emit_names,
    libref_floor_studies = min_libref
  ),
  # ⚠️ NOT "BUILDS". This is every readable `.sas` file under the scoped folder,
  # which includes macro libraries, included fragments, configuration and other
  # support source. An earlier version called all 38,877 of them builds and drew
  # a conclusion about build variety from that; `steps_min = 0` was already the
  # evidence against it, sitting in the same output. No build-job criterion has
  # been established, so the population is described as what it is.
  sas_files_in_folder = list(
    files   = n_read,
    studies = length(unique(stu_seen)),
    # ⭐ Files carrying at least one DATA or PROC step. The nearest thing to a
    # build criterion available without one being defined, and the honest
    # denominator for the shape counts below.
    files_with_at_least_one_step = sum(n_steps > 0L),
    files_with_no_steps          = sum(n_steps == 0L),
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
    # ⚠️ Renamed: it counts files calling a USER macro at statement level,
    # outside a %macro body. See the note at the call site.
    calls_a_user_macro = n_macrocall
  ),
  # ⭐ The upstream question: which libraries a build reads from, by how many
  # studies read each. Floored, so a one-study name is not reported.
  # ⚠️ Aliases, and they name nothing. Kept for completeness.
  librefs_read = top_of(librefs, min_libref),
  # ⭐ The upstream question: where LIBNAME statements actually point, truncated
  # to `--path-depth` components and floored so study-specific paths drop out.
  libname_targets = top_of(libpaths, min_libref),
  procs_used   = top_of(procs, 1L)
)

writeLines(to_json(out), outfile)

b <- out$sas_files_in_folder
message("\n--- SAS FILES IN THE SCOPED FOLDER (not 'builds') ---")
message("files / studies:        ", b$files, " / ", b$studies)
message("  with >=1 DATA/PROC step: ", b$files_with_at_least_one_step,
        "   with none: ", b$files_with_no_steps)
message("distinct bodies:        ", b$distinct_bodies, "  (fingerprint: ",
        fingerprint_method, ")")
message("⭐ distinct step shapes: ", b$distinct_step_shapes)
message("steps per file:         ", b$steps_min, " / ",
        b$steps_median, " / ", b$steps_max, "  (min/median/max)")
message("uses %include:          ", b$uses_include)
message("calls a user macro:     ", b$calls_a_user_macro)
show <- function(label, blk, w) {
  message("\n--- ", label, " ---")
  message("  distinct: ", blk$distinct,
          "   withheld as identifying: ", blk$withheld_as_identifying)
  if (!length(blk$top)) {
    message("  (names withheld; pass --emit-names, and READ THE OUTPUT before ",
            "committing it)")
  } else for (l in blk$top) message(sprintf("  %-*s %5d", w, l$name, l$studies))
}
show("LIBNAME TARGETS (studies)", out$libname_targets, 40)
show("LIBREFS (aliases; they name nothing)", out$librefs_read, 16)
show("PROCS USED (studies)", out$procs_used, 16)
message("\nwrote ", outfile)
