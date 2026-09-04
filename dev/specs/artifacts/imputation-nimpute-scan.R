#!/usr/bin/env Rscript
# imputation-nimpute-scan.R
#
# Third pass. Answers the one question §2 of
# 2026-09-03-imputation-package-spec.md still turns on:
#
#   ⭐ DOES `mult_imput` PERFORM GENUINE MULTIPLE IMPUTATION?
#
# NIMPUTE=1 generates one completed dataset. It is single stochastic imputation:
# it understates variance the same way mean imputation does, and pooling is
# meaningless. If the corpus passes 1, then a macro named for multiple
# imputation is not doing it, and a package offering `mi()` would inherit the
# lie. That is the whole question.
#
#   Rscript imputation-nimpute-scan.R --root /studies --out nimpute-scan.json
#
# WHY THE FIRST TWO SCANS COULD NOT ANSWER IT.
#
# Scan 1 searched for a literal `nimpute=<digits>` and found 5 statements in the
# corpus. Scan 2 resolved macro variables but only WITHIN ONE FILE, and left
# 864 of 871 statements (99.2%) unresolved. Both failed for the same structural
# reason, visible in hindsight from scan 1's own output: the `PROC MI` lives
# inside a macro DEFINITION, where `nimpute` is a PARAMETER. The value is
# supplied by the CALLER, in a different file -- and often a different study,
# since `mult_imput` is called in 326 studies but defined in 277.
#
# So the value is two hops from where the earlier scans looked:
#
#   definition:  %macro mult_imput(data=, nimpute=5);
#                  proc mi data=&data nimpute=&nimpute;   <- binds to a PARAMETER
#   call site:   %mult_imput(data=w, nimpute=25);         <- supplies the VALUE
#
# THIS SCAN JOINS THE TWO. Pass 1 reads every macro definition and records which
# parameter feeds NIMPUTE, and that parameter's default. Pass 2 reads every call
# and resolves the argument bound to it. The map is keyed by MACRO NAME and is
# GLOBAL, not per study, because definitions and calls cross study boundaries.
#
# PRIVACY CONTRACT, unchanged.
#
# THE OUTPUT JSON carries counts and integers only. No path, file name, study
# identifier, variable name, macro name, or parameter name reaches it.
# ⚠️ This scan necessarily holds MACRO AND PARAMETER NAMES in memory -- that is
# what the join is made of. They are reduced to counts and resolved integers
# before output. Where the number of distinct names is informative it is
# emitted as a COUNT of distinct names, never as the names.
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
outfile <- getarg("--out", "nimpute-scan.json")
all_studies <- "--all-studies" %in% args

.folders <- taxonomy_folders()
study_of <- study_of_factory(root, .folders)
message("taxonomy folders: ", paste(.folders, collapse = ", "))

# ---- candidate files --------------------------------------------------------
# Same scoping as scan 2: a call and its definition are reachable from the
# studies that carry a stem-matched file. --all-studies lifts it.
stem_re <- "^(imputsub|mult_imput)"
defs_files <- list.files(root, pattern = paste0(stem_re, ".*\\.sas$"),
                         recursive = TRUE, full.names = TRUE,
                         ignore.case = TRUE, no.. = TRUE)
def_studies <- unique(stats::na.omit(study_of(defs_files)))
message("studies carrying a definition: ", length(def_studies))

if (all_studies) {
  files <- list.files(root, pattern = "\\.sas$", recursive = TRUE,
                      full.names = TRUE, ignore.case = TRUE, no.. = TRUE)
} else {
  dirs <- ifelse(def_studies == ".", root, file.path(root, def_studies))
  files <- unique(unlist(lapply(dirs, function(d) {
    list.files(d, pattern = "\\.sas$", recursive = TRUE,
               full.names = TRUE, ignore.case = TRUE, no.. = TRUE)
  }), use.names = FALSE))
}
message("candidate files: ", length(files))

# ---- parsing helpers --------------------------------------------------------

# `%macro name(p1=, p2=5)` -> name, and the parameters IN ORDER with defaults.
# Order matters because a call may pass arguments positionally.
parse_macro_header <- function(s) {
  m <- regmatches(s, regexec("^ *%macro +([a-z0-9_]+) *(\\((.*)\\))? *$", s))[[1]]
  if (!length(m)) return(NULL)
  name <- m[2]
  body <- if (length(m) >= 4L) m[4] else ""
  params <- character(0); defaults <- list()
  if (nzchar(body)) {
    for (p in strsplit(body, ",", fixed = TRUE)[[1]]) {
      p <- trimws(p)
      if (!nzchar(p)) next
      kv <- regmatches(p, regexec("^([a-z0-9_]+) *(= *(.*))?$", p))[[1]]
      if (!length(kv)) next
      params <- c(params, kv[2])
      d <- if (length(kv) >= 4L) trimws(kv[4]) else ""
      defaults[[kv[2]]] <- if (nzchar(d)) d else NA_character_
    }
  }
  list(name = name, params = params, defaults = defaults)
}

# `key=value` arguments of a macro call, plus positional values in order.
parse_call_args <- function(argstr) {
  kw <- list(); pos <- character(0)
  for (a in strsplit(argstr, ",", fixed = TRUE)[[1]]) {
    a <- trimws(a)
    if (!nzchar(a)) next
    kv <- regmatches(a, regexec("^([a-z0-9_]+) *= *(.*)$", a))[[1]]
    if (length(kv) == 3L) kw[[kv[2]]] <- trimws(kv[3]) else pos <- c(pos, a)
  }
  list(kw = kw, pos = pos)
}

# `%let name = value;` occurrences in a set of statements.
let_map <- function(st) {
  out <- list()
  for (l in grep("^ *%let ", st, value = TRUE)) {
    m <- regmatches(l, regexec("^ *%let +([a-z0-9_]+) *= *(.*?) *$", l))[[1]]
    if (length(m) == 3L) out[[m[2]]] <- m[3]
  }
  out
}

# Resolve an expression to an integer, following &references through a chain of
# lookups. Bounded depth: SAS macro variables can be self-referential, and an
# unbounded walk over a thirty-year corpus will find a cycle.
resolve <- function(expr, lookups, depth = 0L) {
  if (is.null(expr) || is.na(expr) || !nzchar(expr) || depth > 6L) return(NA_integer_)
  e <- gsub("[ %]", "", expr)
  if (grepl("^[0-9]+$", e)) return(as.integer(e))
  if (!grepl("^&+[a-z0-9_]+$", e)) return(NA_integer_)
  nm <- sub("^&+", "", e)
  for (L in lookups) {
    if (!is.null(L[[nm]])) return(resolve(L[[nm]], lookups, depth + 1L))
  }
  NA_integer_
}

# ---- pass 1: definitions ----------------------------------------------------
# For each `%macro`, does its body bind NIMPUTE, and to what?
#   literal  -> the number is in the definition; no call needed
#   param    -> the caller supplies it; record which parameter
#   local    -> a %let inside the body; resolvable without the caller
#
# SCOPE. Pass 1 reads the STEM-MATCHED files only, not all 104k. Scan 1
# established that 1,132 of 1,134 stem-matched files define a macro, so that is
# where the definitions are, and reading everything twice would roughly double a
# run already measured in tens of minutes. `--defs-all` widens it to every
# candidate file; `macros_binding_nimpute` is the number to watch if you suspect
# a definition lives outside the stems.
def_scan <- if ("--defs-all" %in% args) files else defs_files
message("pass 1: definitions (", length(def_scan), " files)")
defmap <- list()          # macro name -> binding
def_conflicts <- 0L
n_def_files <- 0L

for (i in seq_along(def_scan)) {
  st <- read_statements(def_scan[[i]])
  if (is.null(st)) next
  starts <- grep("^ *%macro +[a-z0-9_]+", st)
  if (!length(starts)) next
  n_def_files <- n_def_files + 1L
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
    for (m in mi) {
      g <- regmatches(m, regexpr("nimpute *= *[^ ]+", m))
      if (length(g)) { expr <- sub("^nimpute *= *", "", g); break }
    }
    if (is.na(expr)) next
    lm <- let_map(body)
    kind <- if (grepl("^[0-9]+$", expr)) "literal"
            else if (sub("^&+", "", gsub("[ %]", "", expr)) %in% h$params) "param"
            else if (!is.null(lm[[sub("^&+", "", gsub("[ %]", "", expr))]])) "local"
            else "unknown"
    entry <- list(kind = kind, expr = expr, params = h$params,
                  defaults = h$defaults, lets = lm)
    prev <- defmap[[h$name]]
    if (!is.null(prev) && !identical(prev$expr, entry$expr)) def_conflicts <- def_conflicts + 1L
    if (is.null(prev)) defmap[[h$name]] <- entry
  }
  if (i %% 500 == 0) message("  ", i, " / ", length(def_scan))
}
message("macros binding NIMPUTE: ", length(defmap))

# ---- pass 2: call sites -----------------------------------------------------
message("pass 2: call sites")
nimp <- integer(0)            # every resolved NIMPUTE, one per call
n_calls <- 0L
n_from_arg <- 0L; n_from_default <- 0L; n_unresolved <- 0L
n_literal_defs <- 0L          # PROC MI whose NIMPUTE needs no caller
call_studies <- character(0)
studies <- study_of(files)
macro_names <- names(defmap)

# A macro whose NIMPUTE is a literal or a body-local %let is settled without any
# call. Count those once per definition rather than per invocation.
for (nm in macro_names) {
  d <- defmap[[nm]]
  if (d$kind %in% c("literal", "local")) {
    v <- resolve(d$expr, list(d$lets))
    if (!is.na(v)) { nimp <- c(nimp, v); n_literal_defs <- n_literal_defs + 1L }
  }
}

if (length(macro_names)) {
  call_re <- paste0("%(", paste(macro_names, collapse = "|"), ") *\\(")
  for (i in seq_along(files)) {
    st <- read_statements(files[[i]])
    if (is.null(st)) next
    hits <- grep(call_re, st, value = TRUE)
    if (!length(hits)) next
    lm <- let_map(st)
    for (s in hits) {
      m <- regmatches(s, regexec(paste0("%(", paste(macro_names, collapse = "|"),
                                        ") *\\((.*)\\)"), s))[[1]]
      if (length(m) < 3L) next
      d <- defmap[[m[2]]]
      if (is.null(d) || !identical(d$kind, "param")) next
      n_calls <- n_calls + 1L
      call_studies <- c(call_studies, studies[[i]])
      pname <- sub("^&+", "", gsub("[ %]", "", d$expr))
      a <- parse_call_args(m[3])
      val <- a$kw[[pname]]
      if (is.null(val)) {
        # Positional: the parameter's index among the declared parameters.
        idx <- match(pname, d$params)
        if (!is.na(idx) && length(a$pos) >= idx && !length(a$kw)) val <- a$pos[[idx]]
      }
      from_default <- FALSE
      if (is.null(val)) { val <- d$defaults[[pname]]; from_default <- TRUE }
      v <- resolve(val, list(lm, d$lets))
      if (is.na(v)) {
        n_unresolved <- n_unresolved + 1L
      } else {
        nimp <- c(nimp, v)
        if (from_default) n_from_default <- n_from_default + 1L else n_from_arg <- n_from_arg + 1L
      }
    }
    if (i %% 5000 == 0) message("  ", i, " / ", length(files))
  }
}

# ---- aggregate --------------------------------------------------------------
vals <- nimp[!is.na(nimp)]
n1  <- sum(vals == 1L)
ngt <- sum(vals > 1L)
n0  <- sum(vals == 0L)

out <- list(
  `_provenance` = list(
    script   = "imputation-nimpute-scan.R",
    question = "spec 2026-09-03 S2: does mult_imput perform genuine multiple imputation?",
    run_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    root     = if (identical(root, "/studies")) "/studies" else "(non-default root)",
    scope    = if (all_studies) "every .sas under root" else "studies carrying a definition",
    hvtiRutilities_version = as.character(utils::packageVersion("hvtiRutilities")),
    taxonomy_folders       = paste(sort(.folders), collapse = ","),
    files_considered = length(files),
    contains_identifiers = FALSE
  ),
  definitions = list(
    files_scanned_for_definitions = length(def_scan),
    files_defining_a_macro   = n_def_files,
    macros_binding_nimpute   = length(defmap),
    # How the definition gets its NIMPUTE. "param" is the case that needs a
    # caller; the others are settled by the definition alone.
    binding_param   = sum(vapply(defmap, function(d) identical(d$kind, "param"), logical(1))),
    binding_literal = sum(vapply(defmap, function(d) identical(d$kind, "literal"), logical(1))),
    binding_local   = sum(vapply(defmap, function(d) identical(d$kind, "local"), logical(1))),
    binding_unknown = sum(vapply(defmap, function(d) identical(d$kind, "unknown"), logical(1))),
    # ⚠️ Definitions of the SAME macro name that bind NIMPUTE differently. These
    # are meant to be copies of one canonical file; a nonzero count means they
    # have drifted, and the global map resolves calls using the first seen.
    conflicting_redefinitions = def_conflicts
  ),
  calls = list(
    calls_to_parameterised_macros = n_calls,
    studies_calling               = length(unique(stats::na.omit(call_studies))),
    resolved_from_argument        = n_from_arg,
    resolved_from_default         = n_from_default,
    unresolved                    = n_unresolved,
    settled_by_definition_alone   = n_literal_defs
  ),
  # ⭐ THE ANSWER. Every NIMPUTE this scan could resolve.
  nimpute = list(
    resolved_total = length(vals),
    nimpute_0      = n0,    # diagnostics; not imputation at all
    nimpute_1      = n1,    # SINGLE imputation, whatever the macro is called
    nimpute_gt1    = ngt,   # genuine multiple imputation
    min    = if (length(vals)) min(vals) else NA_integer_,
    median = if (length(vals)) as.numeric(stats::median(vals)) else NA_real_,
    max    = if (length(vals)) max(vals) else NA_integer_,
    table  = if (length(vals)) as.list(table(vals)) else list()
  )
)

writeLines(to_json(out), outfile)

message("\n--- DEFINITIONS ---")
message("macros binding NIMPUTE:   ", out$definitions$macros_binding_nimpute,
        "  (param ", out$definitions$binding_param,
        ", literal ", out$definitions$binding_literal,
        ", local ", out$definitions$binding_local,
        ", unknown ", out$definitions$binding_unknown, ")")
message("conflicting redefinitions: ", out$definitions$conflicting_redefinitions)
message("\n--- CALLS ---")
message("calls resolved from an argument: ", out$calls$resolved_from_argument)
message("calls falling back to a default: ", out$calls$resolved_from_default)
message("calls unresolved:                ", out$calls$unresolved)
message("\n--- NIMPUTE ---")
message("resolved values: ", out$nimpute$resolved_total)
message("  nimpute = 1 (SINGLE imputation): ", out$nimpute$nimpute_1)
message("  nimpute > 1 (multiple):          ", out$nimpute$nimpute_gt1)
message("  nimpute = 0 (diagnostics only):  ", out$nimpute$nimpute_0)
message("\nwrote ", outfile)
