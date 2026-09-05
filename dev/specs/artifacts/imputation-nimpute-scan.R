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

# One `%let name = value;` statement, or NULL.
parse_let <- function(s) {
  m <- regmatches(s, regexec("^ *%let +([a-z0-9_]+) *= *(.*?) *$", s))[[1]]
  if (length(m) == 3L) list(name = m[2], value = m[3]) else NULL
}

# `%let` occurrences in a set of statements, later assignments winning.
#
# ⚠️ ORDER-BLIND, and only safe where order cannot matter. A file that reassigns
# a macro variable between two calls --
#
#     %let n = 5;  %mult_imput(nimpute=&n);
#     %let n = 10; %mult_imput(nimpute=&n);
#
# -- resolves BOTH calls to 10 under this function, silently. Pass 2 therefore
# does NOT use it: it walks the statements in order and resolves each call
# against the assignments that precede it. This remains for macro BODIES, where
# there is one binding site and no call sequence to interleave with.
let_map <- function(st) {
  out <- list()
  for (l in grep("^ *%let ", st, value = TRUE)) {
    p <- parse_let(l)
    if (!is.null(p)) out[[p$name]] <- p$value
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
conflicted <- list()      # macro names whose copies disagree
def_conflicts <- 0L       # copies binding NIMPUTE to a different expression
def_default_conflicts <- 0L  # same expression, different declared default
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
    pname <- if (identical(kind, "param")) sub("^&+", "", gsub("[ %]", "", expr))
             else NA_character_
    dflt <- if (!is.na(pname)) h$defaults[[pname]] else NA_character_
    if (is.null(dflt)) dflt <- NA_character_
    entry <- list(kind = kind, expr = expr, param = pname, default = dflt,
                  params = h$params, defaults = h$defaults, lets = lm)
    prev <- defmap[[h$name]]
    if (is.null(prev)) {
      entry$seen <- list(dflt)
      defmap[[h$name]] <- entry
    } else {
      # ⭐ Keep EVERY distinct default declared for this name, not just the
      # first. A conflict makes a default-resolved call ambiguous in VALUE, but
      # not necessarily ambiguous in the ANSWER: if every copy declares a
      # default above 1, the call ran multiple imputation whichever copy it
      # used. Without the full set that distinction cannot be drawn, and 622 of
      # 939 calls in this corpus rest on it.
      if (!any(vapply(prev$seen, identical, logical(1), dflt))) {
        defmap[[h$name]]$seen <- c(prev$seen, list(dflt))
      }
      # ⚠️ Compare the DEFAULT as well as the expression. Two copies of one
      # macro that bind `nimpute=&nimpute` but declare different DEFAULTS are
      # IDENTICAL in `expr` and materially different in what they run. Comparing
      # `expr` alone reported zero conflicts and silently used whichever copy
      # was read first -- and 69% of calls in this corpus resolve from a
      # default, so that is the least checked input to the most load-bearing
      # number. A default conflict makes every default-resolved call to this
      # macro AMBIGUOUS, so pass 2 counts those separately and keeps them out of
      # the headline distribution rather than picking one.
      if (!identical(prev$expr, entry$expr)) {
        def_conflicts <- def_conflicts + 1L
        conflicted[[h$name]] <- TRUE
      } else if (!identical(prev$default, entry$default)) {
        def_default_conflicts <- def_default_conflicts + 1L
        conflicted[[h$name]] <- TRUE
      }
    }
  }
  if (i %% 500 == 0) message("  ", i, " / ", length(def_scan))
}
message("macros binding NIMPUTE: ", length(defmap))

# ---- pass 1 verdict on the conflicted macros --------------------------------
# ⭐ Printed HERE, before pass 2, because this is the question §2 turns on and
# pass 1 costs seconds where pass 2 walks 100k files. What a conflicted macro's
# copies DECLARE is a property of the definitions alone; only the per-call
# tallies need the walk.
conf_names <- names(conflicted)
conf_classify <- function(nm) {
  d <- defmap[[nm]]
  sv <- vapply(d$seen, function(x) resolve(x, list(d$lets)), integer(1))
  # ⚠️ FOUR outcomes. `not all > 1` is not the same as `straddles`: defaults of
  # {0, 1} mean EVERY copy fails to multiple-impute, which is a settled NEGATIVE
  # answer, not an open one. Reporting it as a straddle would say the question
  # is unresolved when it has in fact been resolved the other way.
  if (anyNA(sv)) "unresolvable"
  else if (all(sv > 1L)) "all_gt1"
  else if (all(sv <= 1L)) "all_le1"
  else "straddles_1"
}
conf_class <- vapply(conf_names, conf_classify, character(1))
conf_vals <- unlist(lapply(conf_names, function(nm) {
  sv <- vapply(defmap[[nm]]$seen, function(x) resolve(x, list(defmap[[nm]]$lets)),
               integer(1))
  sv[!is.na(sv)]
}), use.names = FALSE)
message("conflicted macros: ", length(conf_names),
        "  (all defaults >1: ", sum(conf_class == "all_gt1"),
        ", straddling 1: ", sum(conf_class == "straddles_1"),
        ", all <=1: ", sum(conf_class == "all_le1"),
        ", a default unreadable: ", sum(conf_class == "unresolvable"), ")")
if (length(conf_vals)) {
  message("  declared defaults seen on conflicted macros: ",
          paste(sprintf("%s x%d", names(table(conf_vals)), as.integer(table(conf_vals))),
                collapse = ", "))
}

# ---- pass 2: call sites -----------------------------------------------------
message("pass 2: call sites")
# ⚠️ TWO SEPARATE COLLECTIONS, deliberately not merged.
#
# `nimp_calls` holds one value per resolved CALL. `nimp_defs` holds one value
# per DEFINITION that settles NIMPUTE without any caller -- a literal, or a
# %let in the macro body. An earlier version pooled them, which put a
# definition that is never invoked into the same denominator as 939 actual
# calls and reported the mixture as though every entry were a call. The
# headline distribution is calls only.
nimp_calls <- integer(0)
nimp_defs  <- integer(0)
n_calls <- 0L
n_from_arg <- 0L; n_from_default <- 0L; n_unresolved <- 0L
n_from_conflicted <- 0L       # default-resolved, but the copies disagree
n_conf_all_gt1 <- 0L          # ... and every declared default resolves > 1
n_conf_straddle <- 0L         # ... all resolve, and they span 1 in both directions
n_conf_all_le1 <- 0L          # ... all resolve and NONE exceeds 1: settled NEGATIVE
n_conf_unres   <- 0L          # ... at least one default cannot be resolved at all
n_literal_defs <- 0L          # PROC MI whose NIMPUTE needs no caller
call_studies <- character(0)
studies <- study_of(files)
macro_names <- names(defmap)

for (nm in macro_names) {
  d <- defmap[[nm]]
  if (d$kind %in% c("literal", "local")) {
    v <- resolve(d$expr, list(d$lets))
    if (!is.na(v)) { nimp_defs <- c(nimp_defs, v); n_literal_defs <- n_literal_defs + 1L }
  }
}

if (length(macro_names)) {
  name_alt <- paste(macro_names, collapse = "|")
  call_re  <- paste0("%(", name_alt, ") *\\(")
  arg_re   <- paste0("%(", name_alt, ") *\\((.*)\\)")
  for (i in seq_along(files)) {
    st <- read_statements(files[[i]])
    if (is.null(st)) next
    if (!any(grepl(call_re, st))) next
    # ⚠️ WALK THE STATEMENTS IN ORDER, carrying the %let assignments seen so
    # far. Building one map for the whole file first lets a LATER assignment
    # decide an EARLIER call: `%let n=5; call; %let n=10; call;` resolved both
    # calls to 10. Each call must see only what precedes it.
    lm <- list()
    for (k in seq_along(st)) {
      s <- st[[k]]
      p <- parse_let(s)
      if (!is.null(p)) { lm[[p$name]] <- p$value; next }
      if (!grepl(call_re, s)) next
      m <- regmatches(s, regexec(arg_re, s))[[1]]
      if (length(m) < 3L) next
      d <- defmap[[m[2]]]
      if (is.null(d) || !identical(d$kind, "param")) next
      n_calls <- n_calls + 1L
      call_studies <- c(call_studies, studies[[i]])
      pname <- d$param
      a <- parse_call_args(m[3])
      val <- a$kw[[pname]]
      if (is.null(val)) {
        # Positional: the parameter's index among the declared parameters.
        idx <- match(pname, d$params)
        if (!is.na(idx) && length(a$pos) >= idx && !length(a$kw)) val <- a$pos[[idx]]
      }
      from_default <- FALSE
      if (is.null(val)) { val <- d$default; from_default <- TRUE }
      v <- resolve(val, list(lm, d$lets))
      if (is.na(v)) {
        n_unresolved <- n_unresolved + 1L
      } else if (from_default && isTRUE(conflicted[[m[2]]])) {
        # The copies of this macro declare different defaults, so which value
        # this call ran is genuinely unknown. Counted, and kept OUT of the
        # headline distribution rather than guessed.
        n_from_conflicted <- n_from_conflicted + 1L
        # ⭐ But unknown VALUE is not always unknown ANSWER. Resolve every
        # default this name was seen to declare: if all of them exceed 1, the
        # call ran multiple imputation whichever copy it picked up.
        # ⚠️ THREE OUTCOMES, NOT TWO. An earlier version had `all_gt1` and a
        # catch-all `mixed`, which put "the copies straddle 1" and "one copy
        # declares no default at all" in the same bucket. Those are different
        # facts: the first says the ANSWER is open, the second says the scan
        # could not read one of the inputs. `nimpute=` with an empty default --
        # a macro requiring the caller to supply it -- is common, and it made
        # `mixed` unreadable as evidence.
        sv <- vapply(d$seen, function(x) resolve(x, list(lm, d$lets)), integer(1))
        if (anyNA(sv)) {
          n_conf_unres <- n_conf_unres + 1L
        } else if (all(sv > 1L)) {
          n_conf_all_gt1 <- n_conf_all_gt1 + 1L
        } else if (all(sv <= 1L)) {
          # Settled the OTHER way: no copy of this macro multiple-imputes.
          n_conf_all_le1 <- n_conf_all_le1 + 1L
        } else {
          n_conf_straddle <- n_conf_straddle + 1L
        }
      } else {
        nimp_calls <- c(nimp_calls, v)
        if (from_default) n_from_default <- n_from_default + 1L else n_from_arg <- n_from_arg + 1L
      }
    }
    if (i %% 5000 == 0) message("  ", i, " / ", length(files))
  }
}

# ---- aggregate --------------------------------------------------------------
# The headline distribution is CALLS ONLY -- see the note above `nimp_calls`.
vals <- nimp_calls[!is.na(nimp_calls)]
n1  <- sum(vals == 1L)
ngt <- sum(vals > 1L)
n0  <- sum(vals == 0L)
dvals <- nimp_defs[!is.na(nimp_defs)]

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
    files_unreadable = unreadable_count(),
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
    # ⚠️ Copies of the SAME macro name that disagree. These are meant to be
    # copies of one canonical file, so a nonzero count means they have drifted.
    # The two are separate because they fail differently: a different
    # EXPRESSION binds NIMPUTE to something else entirely, while a different
    # DEFAULT is invisible in the expression and decides 69% of the calls.
    conflicting_redefinitions = def_conflicts,
    conflicting_defaults      = def_default_conflicts,
    macros_conflicted         = length(conflicted),
    # ⭐ The conflicted macros classified by what their copies DECLARE. This is
    # a pass-1 fact and needs no corpus walk; the per-call tallies under `calls`
    # are the same classification weighted by how often each macro is invoked.
    conflicted_macros_all_gt1     = sum(conf_class == "all_gt1"),
    conflicted_macros_straddles_1 = sum(conf_class == "straddles_1"),
    conflicted_macros_all_le1     = sum(conf_class == "all_le1"),
    conflicted_macros_unresolvable = sum(conf_class == "unresolvable"),
    # Every readable default declared on a conflicted macro. Integers only.
    conflicted_default_values = if (length(conf_vals)) as.list(table(conf_vals)) else list()
  ),
  calls = list(
    calls_to_parameterised_macros = n_calls,
    studies_calling               = length(unique(stats::na.omit(call_studies))),
    resolved_from_argument        = n_from_arg,
    resolved_from_default         = n_from_default,
    # Default-resolved, but the macro's copies declare different defaults, so
    # which value ran is genuinely unknown. Kept OUT of the distribution below
    # rather than guessed. These four buckets partition the calls.
    unresolved_conflicting_default = n_from_conflicted,
    # ⭐ Of those, the ones whose ambiguity does NOT reach the conclusion:
    # every default the name declares is > 1, so the call ran multiple
    # imputation regardless of which copy it used. `mixed` is the remainder,
    # where the answer itself is open.
    # Every declared default resolves above 1: the call ran multiple imputation
    # whichever copy it used, so the ambiguity does not reach the conclusion.
    conflicting_default_all_gt1 = n_conf_all_gt1,
    # All defaults resolve and they span 1 in BOTH directions: the answer is
    # genuinely open for this call.
    conflicting_default_straddles_1 = n_conf_straddle,
    # All defaults resolve and NONE exceeds 1: settled, and settled NEGATIVE --
    # no copy of this macro performs multiple imputation. Not uncertainty.
    conflicting_default_all_le1 = n_conf_all_le1,
    # At least one copy declares a default the scan cannot read -- typically an
    # empty `nimpute=`, which requires the caller to supply a value. A
    # measurement gap, NOT evidence that the call single-imputed.
    conflicting_default_unresolvable = n_conf_unres,
    unresolved                    = n_unresolved,
    # NOT a call: a definition that settles NIMPUTE without any caller. Counted
    # here and reported separately in `definition_settled`, never pooled into
    # the call distribution.
    settled_by_definition_alone   = n_literal_defs
  ),
  definition_settled = list(
    n      = length(dvals),
    table  = if (length(dvals)) as.list(table(dvals)) else list()
  ),
  # ⭐ THE ANSWER. One entry per resolved CALL; definitions settled without a
  # caller are in `definition_settled` above and are not counted here.
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
message("conflicting redefinitions: ", out$definitions$conflicting_redefinitions,
        "  (differing defaults: ", out$definitions$conflicting_defaults, ")")
message("\n--- CALLS ---")
message("calls resolved from an argument: ", out$calls$resolved_from_argument)
message("calls falling back to a default: ", out$calls$resolved_from_default)
message("calls on a conflicting default:  ", out$calls$unresolved_conflicting_default,
        "\n    all defaults >1 (multiple):   ", out$calls$conflicting_default_all_gt1,
        "\n    straddling 1 (open):          ", out$calls$conflicting_default_straddles_1,
        "\n    all <=1 (NOT multiple):       ", out$calls$conflicting_default_all_le1,
        "\n    a default unreadable (gap):   ", out$calls$conflicting_default_unresolvable)
message("calls unresolved:                ", out$calls$unresolved)
message("\n--- NIMPUTE ---")
message("resolved values: ", out$nimpute$resolved_total)
message("  nimpute = 1 (SINGLE imputation): ", out$nimpute$nimpute_1)
message("  nimpute > 1 (multiple):          ", out$nimpute$nimpute_gt1)
message("  nimpute = 0 (diagnostics only):  ", out$nimpute$nimpute_0)
message("\nwrote ", outfile)
