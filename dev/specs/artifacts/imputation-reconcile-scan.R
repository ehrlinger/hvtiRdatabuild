#!/usr/bin/env Rscript
# imputation-reconcile-scan.R
#
# The worksheet for reconciling the divergent macro copies recorded in
# dev/specs/2026-09-05-divergent-macro-copies.md.
#
# THE PROBLEM IT SERVES. Five macro names exist in copies declaring different
# `NIMPUTE` defaults, and three of the five straddle 1, which is why 619 of 939
# calls cannot be attributed to a method. Reconciling them means deciding, per
# name, which default is canonical. ⭐ Nobody can do that yet, because every scan
# so far emits counts only and so cannot say WHICH five.
#
# This one names them, and reports what a decision needs:
#
#   - each declared default, with how many copies declare it
#   - whether the copies differ ONLY in the default, or in the body too
#   - how many calls reach the name, and how many rely on its default
#
# It also reports the default distribution across ALL macros binding NIMPUTE,
# without naming them, because the institutional norm is an argument for what
# canonical should be.
#
#   Rscript imputation-reconcile-scan.R --root /studies --out reconcile-scan.json
#   Rscript imputation-reconcile-scan.R --root /studies --no-calls    # seconds
#
# ⚠️ `--no-calls` skips the call tallies and reads only the 1,134 stem-matched
# files. That is where the decision content is; the call counts only say which
# name to settle first. Use it for a fast worksheet, then the full run if the
# ordering matters.
#
# PRIVACY CONTRACT -- ⚠️ NARROWER THAN THE COUNTING SCANS, deliberately.
#
# IT EMITS MACRO NAMES, for the five conflicted names only. A macro name is a
# job identifier, not a study or patient one, and the work cannot proceed
# without it: you cannot reconcile what you cannot name. This is the same
# trade `imputation-census-reconcile.R` makes for job stems.
#
# IT DOES NOT EMIT STUDY LOCATIONS. Deciding a canonical default needs the
# names and the numbers; going and editing the copies needs the paths, and that
# is a separate decision with the study owners. The output stays safe to copy
# off the share and to commit.
#
# It emits no source line, no macro body, no variable name and no path. Bodies
# are compared in memory and reduced to a COUNT of distinct variants.
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
root     <- normalise_root(getarg("--root", "/studies"))
outfile  <- getarg("--out", "reconcile-scan.json")
no_calls <- "--no-calls" %in% args

.folders <- taxonomy_folders()
study_of <- study_of_factory(root, .folders)
message("taxonomy folders: ", paste(.folders, collapse = ", "))

defs_files <- list.files(root, pattern = "^(imputsub|mult_imput).*\\.sas$",
                         recursive = TRUE, full.names = TRUE,
                         ignore.case = TRUE, no.. = TRUE)
message("definition files: ", length(defs_files))

# ---- pass 1: every copy of every macro binding NIMPUTE ----------------------
# One record per COPY, not per name, because the whole question is how the
# copies of one name differ from each other.
copies <- list()

for (i in seq_along(defs_files)) {
  st <- read_statements(defs_files[[i]])
  if (is.null(st)) next
  starts <- grep("^ *%macro +[a-z0-9_]+", st)
  if (!length(starts)) next
  ends <- grep("^ *%mend", st)
  for (s in starts) {
    m <- regmatches(st[[s]], regexec("^ *%macro +([a-z0-9_]+) *(\\((.*)\\))? *$", st[[s]]))[[1]]
    if (!length(m)) next
    nm <- m[2]
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

    # The declared default for whichever parameter feeds NIMPUTE.
    pname <- sub("^&+", "", gsub("[ %]", "", expr))
    dflt <- NA_character_
    if (length(m) >= 4L && nzchar(m[4])) {
      for (p in strsplit(m[4], ",", fixed = TRUE)[[1]]) {
        kv <- regmatches(trimws(p), regexec("^([a-z0-9_]+) *(= *(.*))?$", trimws(p)))[[1]]
        if (length(kv) && identical(kv[2], pname)) {
          dflt <- if (length(kv) >= 4L && nzchar(trimws(kv[4]))) trimws(kv[4]) else NA_character_
        }
      }
    }
    copies[[length(copies) + 1L]] <- list(
      name = nm,
      param = pname,
      default = dflt,
      # ⚠️ The two bodies below are held in memory ONLY to be compared. They are
      # reduced to a count of distinct variants and never emitted.
      full = paste(body, collapse = ";"),
      # The header carries the default, so strip it to ask the separate
      # question: did anything ELSE drift?
      sans_header = paste(body[-1], collapse = ";")
    )
  }
  if (i %% 200 == 0) message("  ", i, " / ", length(defs_files))
}
message("macro copies binding NIMPUTE: ", length(copies))

names_v <- vapply(copies, function(x) x$name, character(1))
dflt_v  <- vapply(copies, function(x) x$default, character(1))

# resolve() with no lookups: a default is only useful here if it is a literal.
as_int <- function(x) {
  v <- suppressWarnings(as.integer(gsub("[ %]", "", x)))
  ifelse(grepl("^ *[0-9]+ *$", x), v, NA_integer_)
}
dflt_i <- as_int(dflt_v)

# ---- which names disagree ---------------------------------------------------
by_name <- split(seq_along(copies), names_v)
conflicted <- names(Filter(function(ix) {
  length(unique(dflt_v[ix])) > 1L
}, by_name))
message("names with copies declaring different defaults: ", length(conflicted))

# ---- pass 2: how many calls reach each name --------------------------------
call_total <- setNames(integer(length(by_name)), names(by_name))
call_default <- call_total
if (!no_calls && length(conflicted)) {
  def_studies <- unique(stats::na.omit(study_of(defs_files)))
  dirs <- ifelse(def_studies == ".", root, file.path(root, def_studies))
  files <- unique(unlist(lapply(dirs, function(d) {
    list.files(d, pattern = "\\.sas$", recursive = TRUE,
               full.names = TRUE, ignore.case = TRUE, no.. = TRUE)
  }), use.names = FALSE))
  # One parameter name per macro. Pass 1 found the copies agree on it (they
  # differ in the DEFAULT, not the parameter); take the first.
  param_of <- vapply(by_name, function(ix) copies[[ix[1]]]$param, character(1))
  message("pass 2: call sites (", length(files), " files)")
  alt <- paste(conflicted, collapse = "|")
  call_re <- paste0("%(", alt, ") *\\(")
  arg_re  <- paste0("%(", alt, ") *\\((.*)\\)")
  for (i in seq_along(files)) {
    st <- read_statements(files[[i]])
    if (is.null(st)) next
    for (s in grep(call_re, st, value = TRUE)) {
      mm <- regmatches(s, regexec(arg_re, s))[[1]]
      if (length(mm) < 3L) next
      nm <- mm[2]
      call_total[[nm]] <- call_total[[nm]] + 1L
      # Does this call pass the parameter that feeds NIMPUTE, or fall back on
      # the declared default? Test the PARAMETER NAME captured in pass 1, not
      # the literal string "nimpute": the parameter is named by the macro's
      # author and need not be called that.
      pn <- param_of[[nm]]
      if (is.na(pn) || !grepl(paste0("(^|[(,] *)", pn, " *="), mm[3])) {
        call_default[[nm]] <- call_default[[nm]] + 1L
      }
    }
    if (i %% 5000 == 0) message("  ", i, " / ", length(files))
  }
} else {
  message("pass 2 skipped (--no-calls)")
}

# ---- worksheet --------------------------------------------------------------
worksheet <- lapply(conflicted, function(nm) {
  ix <- by_name[[nm]]
  d  <- dflt_v[ix]
  di <- dflt_i[ix]
  tab <- table(di[!is.na(di)])
  list(
    macro = nm,
    copies = length(ix),
    # ⭐ The decision content: what the copies declare, and how many say each.
    declared_defaults = if (length(tab)) as.list(tab) else list(),
    copies_with_no_readable_default = sum(is.na(di)),
    spans_1 = if (all(is.na(di))) NA else
      (any(di[!is.na(di)] <= 1L) && any(di[!is.na(di)] > 1L)),
    # ⭐ Is the drift confined to the default, or did the body move too? If the
    # bodies agree, reconciling is a one-line edit per copy. If they do not, it
    # is a merge, and the default is only the visible part of the divergence.
    distinct_bodies = length(unique(vapply(copies[ix], function(x) x$full, character(1)))),
    distinct_bodies_ignoring_header =
      length(unique(vapply(copies[ix], function(x) x$sans_header, character(1)))),
    calls = call_total[[nm]],
    calls_relying_on_a_default = call_default[[nm]]
  )
})
worksheet <- worksheet[order(-vapply(worksheet, function(w) w$calls, integer(1)),
                             -vapply(worksheet, function(w) w$copies, integer(1)))]

# The institutional norm, unnamed: what every macro binding NIMPUTE declares.
all_tab <- table(dflt_i[!is.na(dflt_i)])

out <- list(
  `_provenance` = list(
    script   = "imputation-reconcile-scan.R",
    question = "which macro names disagree about NIMPUTE, and what would reconciling them take?",
    run_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    root     = if (identical(root, "/studies")) "/studies" else "(non-default root)",
    mode     = if (no_calls) "definitions only (--no-calls)" else "definitions and call sites",
    hvtiRutilities_version = as.character(utils::packageVersion("hvtiRutilities")),
    taxonomy_folders       = paste(sort(.folders), collapse = ","),
    definition_files = length(defs_files),
    files_unreadable = unreadable_count(),
    # ⚠️ TRUE here, unlike the counting scans. Macro names only; no study
    # identifier, path, body or source line. See the header.
    emits_macro_names = TRUE
  ),
  summary = list(
    macro_names_binding_nimpute = length(by_name),
    macro_copies                = length(copies),
    names_with_conflicting_defaults = length(conflicted),
    # Unnamed: the distribution across every macro, as the argument for what
    # canonical ought to be.
    declared_defaults_all_macros = if (length(all_tab)) as.list(all_tab) else list(),
    copies_with_no_readable_default = sum(is.na(dflt_i))
  ),
  worksheet = worksheet
)

writeLines(to_json(out), outfile)

message("\n--- RECONCILIATION WORKSHEET ---")
for (w in worksheet) {
  dd <- paste(sprintf("%s x%s", names(w$declared_defaults),
                      unlist(w$declared_defaults)), collapse = ", ")
  message(sprintf("%-24s %3d copies   defaults: %-28s  bodies: %d (%d ignoring header)%s",
                  w$macro, w$copies, if (nzchar(dd)) dd else "(none readable)",
                  w$distinct_bodies, w$distinct_bodies_ignoring_header,
                  if (isTRUE(w$spans_1)) "   <- SPANS 1" else ""))
  if (!no_calls) {
    message(sprintf("%-24s     %d call(s), %d relying on a default",
                    "", w$calls, w$calls_relying_on_a_default))
  }
}
message("\nacross all macros, declared defaults: ",
        paste(sprintf("%s x%s", names(all_tab), as.integer(all_tab)), collapse = ", "))
message("\nwrote ", outfile)
