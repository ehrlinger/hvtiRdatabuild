#!/usr/bin/env Rscript
# imputation-studylocal-scan.R
#
# Resolves NIMPUTE against the copy of the macro IN THE CALLING STUDY, rather
# than against a map keyed by macro name across the whole corpus.
#
# WHY. `imputation-nimpute-scan.R` built its map GLOBALLY, and that was the
# right call for the question it asked: `mult_imput` is called in 326 studies
# and defined in 277, so a per-study join would have lost the difference. But it
# is that global map which makes 619 of 939 calls look undeterminable. Five
# macro names exist in copies declaring different defaults, so a call falling
# back on "the" default has no single answer at corpus scale.
#
# ⭐ At study scale it usually does. Every study carries its OWN copy, so a call
# in a study resolves against that study's copy, not against a population of
# 423. What looked like a property of the corpus is partly an artifact of asking
# the question corpus-wide.
#
#   Rscript imputation-studylocal-scan.R --root /studies --out studylocal-scan.json
#
# ⚠️ THIS IS AN INFERENCE, NOT PROOF, and the output is worded to keep that
# visible. Which copy SAS actually loaded depends on the autocall path and
# `%include` order at run time, not merely on which file sits in the study
# directory. A study holding exactly one copy that declares one default is
# strong evidence and not a certainty. It is testable, against the studies that
# kept their logs, and this scan does not test it.
#
# THE ROUTES ARE KEPT APART, because they carry different weight:
#
#   from_argument         the call states the value. Proof, near enough.
#   study_local           the calling study holds exactly one copy, which
#                         declares one readable default. Strong inference.
#   study_local_ambiguous the study holds copies that disagree with each other.
#   global_fallback       the study holds no copy, so the corpus-wide map is all
#                         there is. Weaker, and flagged when that map conflicts.
#   unresolved            no readable default anywhere.
#
# PRIVACY CONTRACT. Counts and integers only, as the counting scans. No path,
# study identifier, macro name, parameter name or source line reaches the
# output. Study identifiers are held in memory to do the join and are reduced to
# counts. The console echoes the --root you passed and nothing below it.

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
outfile <- getarg("--out", "studylocal-scan.json")

.folders <- taxonomy_folders()
study_of <- study_of_factory(root, .folders)
message("taxonomy folders: ", paste(.folders, collapse = ", "))

defs_files <- list.files(root, pattern = "^(imputsub|mult_imput).*\\.sas$",
                         recursive = TRUE, full.names = TRUE,
                         ignore.case = TRUE, no.. = TRUE)
def_studies <- unique(stats::na.omit(study_of(defs_files)))
message("definition files: ", length(defs_files),
        " across ", length(def_studies), " studies")

as_int <- function(x) {
  if (is.null(x) || is.na(x)) return(NA_integer_)
  if (grepl("^ *[0-9]+ *$", x)) as.integer(gsub("[ %]", "", x)) else NA_integer_
}

# ---- pass 1: definitions, keyed BOTH ways -----------------------------------
# `local_map` is keyed by study and name, `global_map` by name alone. The two
# are built in one walk because the fallback needs both.
local_map  <- new.env(parent = emptyenv())
global_map <- new.env(parent = emptyenv())
# ⚠️ The parameter metadata is keyed by STUDY AND NAME, like `local_map`, not by
# name alone. Keyed by name, the last copy read would control argument parsing
# in every study -- so if one study binds NIMPUTE through `nimpute` and another
# copy of the same macro through `reps`, an explicit argument in the first study
# reads as omitted and the call is credited to its local default instead. The
# worksheet in 4a of the finding note measured 381 distinct bodies for one name,
# so signature divergence between copies is the expected case here, not an edge.
local_param  <- new.env(parent = emptyenv())
local_params <- new.env(parent = emptyenv())
# Kept by name too, for the fallback when a calling study holds no copy. Every
# variant is retained rather than the last, so the fallback can say when the
# corpus-wide signature is itself ambiguous.
global_param  <- new.env(parent = emptyenv())
global_params <- new.env(parent = emptyenv())

add <- function(env, key, value) {
  cur <- if (!is.null(env[[key]])) env[[key]] else integer(0)
  env[[key]] <- c(cur, value)
}

def_study <- study_of(defs_files)
for (i in seq_along(defs_files)) {
  st <- read_statements(defs_files[[i]])
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
    mi <- grep("proc mi\\b", body, value = TRUE)
    if (!length(mi)) next
    expr <- NA_character_
    for (one in mi) {
      g <- regmatches(one, regexpr("nimpute *= *[^ ]+", one))
      if (length(g)) { expr <- sub("^nimpute *= *", "", g); break }
    }
    if (is.na(expr)) next
    pname <- sub("^&+", "", gsub("[ %]", "", expr))
    dflt  <- as_int(h$defaults[[pname]])

    add(global_map, h$name, dflt)
    global_param[[h$name]]  <- unique(c(global_param[[h$name]], pname))
    global_params[[h$name]] <- c(global_params[[h$name]], list(h$params))
    stu <- def_study[[i]]
    if (!is.na(stu)) {
      key <- paste0(stu, "\r", h$name)
      add(local_map, key, dflt)
      local_param[[key]]  <- unique(c(local_param[[key]], pname))
      local_params[[key]] <- c(local_params[[key]], list(h$params))
    }
  }
  if (i %% 200 == 0) message("  ", i, " / ", length(defs_files))
}
macro_names <- ls(global_map)
message("macros binding NIMPUTE: ", length(macro_names))

# A set of declared defaults resolves only if every entry is readable and they
# all agree. `NA` in the set means one copy declares no readable default, which
# is a gap rather than a disagreement, and either way it is not determinate.
settle <- function(v) {
  if (!length(v) || anyNA(v)) return(NA_integer_)
  u <- unique(v)
  if (length(u) == 1L) u else NA_integer_
}
disagrees <- function(v) {
  w <- v[!is.na(v)]
  length(unique(w)) > 1L
}

# ---- pass 2: calls ----------------------------------------------------------
dirs <- ifelse(def_studies == ".", root, file.path(root, def_studies))
files <- unique(unlist(lapply(dirs, function(d) {
  list.files(d, pattern = "\\.sas$", recursive = TRUE,
             full.names = TRUE, ignore.case = TRUE, no.. = TRUE)
}), use.names = FALSE))
message("candidate files: ", length(files))

n <- c(argument = 0L, local = 0L, local_ambiguous = 0L,
       global_ok = 0L, global_conflict = 0L, unresolved = 0L)
vals_arg <- integer(0); vals_local <- integer(0); vals_global <- integer(0)
call_studies <- character(0)

alt     <- paste(macro_names, collapse = "|")
call_re <- paste0("%(", alt, ") *\\(")
arg_re  <- paste0("%(", alt, ") *\\((.*)\\)")
studies <- study_of(files)

for (i in seq_along(files)) {
  st <- read_statements(files[[i]])
  if (is.null(st)) next
  if (!any(grepl(call_re, st))) next
  lm <- list()
  for (k in seq_along(st)) {
    s <- st[[k]]
    p <- parse_let(s)
    if (!is.null(p)) { lm[[p$name]] <- p$value; next }
    if (!grepl(call_re, s)) next
    mm <- regmatches(s, regexec(arg_re, s))[[1]]
    if (length(mm) < 3L) next
    nm <- mm[2]
    stu <- studies[[i]]
    key <- if (is.na(stu)) NULL else paste0(stu, "\r", nm)

    # ⭐ Read the signature from the CALLING STUDY's copy where there is one,
    # and only fall back to the corpus-wide one otherwise. Same reasoning as the
    # default itself: the copy in the study is what the call resolved against.
    pns <- if (!is.null(key) && !is.null(local_param[[key]])) local_param[[key]]
           else global_param[[nm]]
    pps <- if (!is.null(key) && !is.null(local_params[[key]])) local_params[[key]]
           else global_params[[nm]]
    if (is.null(pns)) next
    call_studies <- c(call_studies, stu)

    # 1. Did the call state the value? Try every parameter name the relevant
    # copies use, since copies of one macro may name it differently.
    a <- parse_call_args(mm[3])
    val <- NULL
    for (pn in pns) {
      val <- arg_value(a, pn, pps)
      if (!is.null(val)) break
    }
    if (!is.null(val)) {
      v <- resolve(val, list(lm))
      if (!is.na(v)) {
        n[["argument"]] <- n[["argument"]] + 1L
        vals_arg <- c(vals_arg, v)
        next
      }
    }

    # 2. The copy in THIS study.
    loc <- if (!is.null(key)) local_map[[key]] else NULL
    if (!is.null(loc)) {
      v <- settle(loc)
      if (!is.na(v)) {
        n[["local"]] <- n[["local"]] + 1L
        vals_local <- c(vals_local, v)
      } else if (disagrees(loc)) {
        n[["local_ambiguous"]] <- n[["local_ambiguous"]] + 1L
      } else {
        n[["unresolved"]] <- n[["unresolved"]] + 1L
      }
      next
    }

    # 3. No copy in this study, so the corpus-wide map is all there is.
    g <- global_map[[nm]]
    v <- settle(g)
    if (!is.na(v)) {
      n[["global_ok"]] <- n[["global_ok"]] + 1L
      vals_global <- c(vals_global, v)
    } else if (disagrees(g)) {
      n[["global_conflict"]] <- n[["global_conflict"]] + 1L
    } else {
      n[["unresolved"]] <- n[["unresolved"]] + 1L
    }
  }
  if (i %% 5000 == 0) message("  ", i, " / ", length(files))
}

tab <- function(v) if (length(v)) as.list(table(v)) else list()
# ⚠️ `argument` and `local` only. The global fallback is a weaker route and is
# reported beside the headline rather than inside it.
determinate <- c(vals_arg, vals_local)

out <- list(
  `_provenance` = list(
    script   = "imputation-studylocal-scan.R",
    question = "does resolving NIMPUTE against the CALLING STUDY's own copy determine the calls a corpus-wide map could not?",
    run_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    root     = if (identical(root, "/studies")) "/studies" else "(non-default root)",
    hvtiRutilities_version = as.character(utils::packageVersion("hvtiRutilities")),
    taxonomy_folders       = paste(sort(.folders), collapse = ","),
    definition_files = length(defs_files),
    candidate_files  = length(files),
    files_unreadable = unreadable_count(),
    contains_identifiers = FALSE,
    # ⚠️ Read with the header's caveat: a study's own copy is strong evidence of
    # what its calls ran, not proof. The autocall path decides at run time.
    inference = "study-local copy, not verified against run logs"
  ),
  routes = list(
    calls                 = sum(n),
    studies_calling       = length(unique(stats::na.omit(call_studies))),
    from_argument         = n[["argument"]],
    from_study_local      = n[["local"]],
    study_local_ambiguous = n[["local_ambiguous"]],
    global_fallback_ok        = n[["global_ok"]],
    global_fallback_conflict  = n[["global_conflict"]],
    unresolved            = n[["unresolved"]]
  ),
  # ⭐ The comparison this scan exists to make.
  determinate = list(
    n           = length(determinate),
    nimpute_1   = sum(determinate == 1L),
    nimpute_gt1 = sum(determinate > 1L),
    nimpute_0   = sum(determinate == 0L),
    median      = if (length(determinate)) as.numeric(stats::median(determinate)) else NA_real_,
    table       = tab(determinate)
  ),
  by_route = list(
    from_argument    = tab(vals_arg),
    from_study_local = tab(vals_local),
    global_fallback  = tab(vals_global)
  )
)

writeLines(to_json(out), outfile)

message("\n--- ROUTES ---")
message("calls:                     ", out$routes$calls)
message("  states the value:        ", out$routes$from_argument)
message("  study's own copy:        ", out$routes$from_study_local)
message("  study's copies disagree: ", out$routes$study_local_ambiguous)
message("  no local copy, global agrees:   ", out$routes$global_fallback_ok)
message("  no local copy, global conflicts:", out$routes$global_fallback_conflict)
message("  unresolved:              ", out$routes$unresolved)
message("\n--- DETERMINATE (argument or study-local) ---")
message("n = ", out$determinate$n,
        "   nimpute=1: ", out$determinate$nimpute_1,
        "   nimpute>1: ", out$determinate$nimpute_gt1,
        "   nimpute=0: ", out$determinate$nimpute_0)
message("\nwrote ", outfile)
