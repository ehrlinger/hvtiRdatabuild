#!/usr/bin/env Rscript
# imputation-direct-procmi-scan.R
#
# `NIMPUTE` for the studies that run `PROC MI` DIRECTLY, without the macro.
#
# WHY THIS EXISTS. Every imputation scan so far counted MACRO CALLS: 326 studies
# call `%mult_imput`, 223 call `%imputsub`. ⭐ `build-structure-scan.R` then found
# `PROC MI` in **822 studies**' `datasets` folders and `PROC STANDARD` in 1,292.
# Direct use is roughly two and a half times more common than the macro, and
# §2 of `2026-09-03-imputation-package-spec.md` is scoped to macro calls in a
# corpus that largely does not use the macro.
#
#   Rscript imputation-direct-procmi-scan.R --root /studies --out direct-procmi.json
#
# ⚠️ IT IS A SEPARATE SCAN, DELIBERATELY. The macro population and the direct
# population want different reporting, and the resolution problem is a different
# one. `imputation-nimpute-scan.R` resolves a value across a definition and a
# call site because the macro puts a PARAMETER between them. A direct `PROC MI`
# has no macro in between: `nimpute=` is a literal, or a `%let` in the same file,
# or a macro variable set somewhere this scan cannot see. Folding the two
# together is how the macro-call scoping error happened in the first place.
#
# ⭐ IT COUNTS ONLY DIRECT USE, and says so. A `PROC MI` inside a `%macro` body
# belongs to the macro population and is excluded here, so the two scans can be
# added without double counting. `procmi_inside_a_macro` reports how many were
# excluded on that ground.
#
# PRIVACY CONTRACT. Counts and integers only, as the counting scans. No path,
# study identifier, macro name, variable name or source line reaches the output.
# Study identifiers are held in memory to count distinct studies and are reduced
# to counts. The console echoes the --root you passed and nothing below it.

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
outfile    <- getarg("--out", "direct-procmi.json")
folder     <- getarg("--folder", "")          # "" = every .sas under root
count_only <- "--count-only" %in% args

.folders <- taxonomy_folders()
study_of <- study_of_factory(root, .folders)
message("taxonomy folders: ", paste(.folders, collapse = ", "))

files <- list.files(root, pattern = "\\.sas$", recursive = TRUE,
                    full.names = TRUE, ignore.case = TRUE, no.. = TRUE)
if (nzchar(folder)) files <- files[grepl(paste0("/", folder, "/"), files, fixed = TRUE)]
message("candidate files: ", length(files),
        "  (folder: ", if (nzchar(folder)) folder else "any", ")")
if (count_only) {
  message("\n--count-only: nothing was read.")
  quit(save = "no", status = 0)
}

as_int <- function(x) {
  if (is.null(x) || is.na(x) || !nzchar(x)) return(NA_integer_)
  if (grepl("^ *[0-9]+ *$", x)) as.integer(gsub("[ %]", "", x)) else NA_integer_
}

n <- c(files = 0L, stmts = 0L, in_macro = 0L, literal = 0L, let = 0L,
       unresolved = 0L, absent = 0L)
vals <- integer(0)
stu_direct <- character(0); stu_resolved <- character(0)
studies <- study_of(files)

for (i in seq_along(files)) {
  st <- read_statements(files[[i]])
  if (is.null(st)) next
  mi <- grep("proc mi\\b", st)
  if (!length(mi)) next
  n[["files"]] <- n[["files"]] + 1L
  s <- studies[[i]]

  # ⭐ Depth of %macro nesting at each statement. A PROC MI inside a definition
  # is the macro population's, not this one's, and is excluded so the two scans
  # can be added.
  depth <- cumsum(grepl("^ *%macro\\b", st)) - cumsum(grepl("^ *%mend\\b", st))

  # ⚠️ `%let` values are read IN ORDER, so a call sees only the assignments that
  # precede it. A whole-file map lets a later assignment decide an earlier
  # statement, which is the defect #36's review found in the macro scan.
  lm <- list()
  for (k in seq_along(st)) {
    p <- parse_let(st[[k]])
    if (!is.null(p)) { lm[[p$name]] <- p$value; next }
    if (!(k %in% mi)) next
    if (depth[[k]] > 0L) { n[["in_macro"]] <- n[["in_macro"]] + 1L; next }

    n[["stmts"]] <- n[["stmts"]] + 1L
    if (!is.na(s)) stu_direct <- c(stu_direct, s)

    g <- regmatches(st[[k]], regexpr("nimpute *= *[^ ]+", st[[k]]))
    if (!length(g)) {
      # No NIMPUTE at all: SAS applies its own default, which has varied across
      # releases. Counted, never guessed at.
      n[["absent"]] <- n[["absent"]] + 1L
      next
    }
    expr <- sub("^nimpute *= *", "", g)
    v <- as_int(expr)
    if (!is.na(v)) {
      n[["literal"]] <- n[["literal"]] + 1L
    } else {
      v <- resolve(expr, list(lm))
      if (!is.na(v)) n[["let"]] <- n[["let"]] + 1L
    }
    if (is.na(v)) { n[["unresolved"]] <- n[["unresolved"]] + 1L; next }
    vals <- c(vals, v)
    if (!is.na(s)) stu_resolved <- c(stu_resolved, s)
  }
  if (i %% 5000 == 0) message("  ", i, " / ", length(files))
}

out <- list(
  `_provenance` = list(
    script   = "imputation-direct-procmi-scan.R",
    question = "what NIMPUTE do the studies running PROC MI directly, without the macro, use?",
    run_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    root     = if (identical(root, "/studies")) "/studies" else "(non-default root)",
    folder   = if (nzchar(folder)) folder else "any",
    hvtiRutilities_version = as.character(utils::packageVersion("hvtiRutilities")),
    taxonomy_folders       = paste(sort(.folders), collapse = ","),
    files_considered = length(files),
    files_unreadable = unreadable_count(),
    contains_identifiers = FALSE,
    # ⚠️ Direct use only. A PROC MI inside a %macro body belongs to the macro
    # population and is excluded, so this scan and the nimpute scan can be added
    # without double counting.
    excludes_procmi_inside_macros = TRUE
  ),
  statements = list(
    files_with_a_procmi      = n[["files"]],
    direct_procmi_statements = n[["stmts"]],
    procmi_inside_a_macro    = n[["in_macro"]],
    # How the value was obtained. These partition the direct statements.
    from_a_literal           = n[["literal"]],
    from_a_let_in_the_file   = n[["let"]],
    no_nimpute_given         = n[["absent"]],
    unresolved               = n[["unresolved"]]
  ),
  studies = list(
    running_procmi_directly  = length(unique(stats::na.omit(stu_direct))),
    # ⭐ Compare with the 326 studies calling %mult_imput.
    with_a_resolved_nimpute  = length(unique(stats::na.omit(stu_resolved)))
  ),
  nimpute = list(
    resolved_total = length(vals),
    nimpute_0      = sum(vals == 0L),
    nimpute_1      = sum(vals == 1L),
    nimpute_gt1    = sum(vals > 1L),
    median = if (length(vals)) as.numeric(stats::median(vals)) else NA_real_,
    table  = if (length(vals)) as.list(table(vals)) else list()
  )
)

writeLines(to_json(out), outfile)

s <- out$statements
message("\n--- DIRECT PROC MI ---")
message("files with a PROC MI:      ", s$files_with_a_procmi)
message("direct statements:         ", s$direct_procmi_statements)
message("  excluded, inside a macro: ", s$procmi_inside_a_macro)
message("  from a literal:          ", s$from_a_literal)
message("  from a %let in the file: ", s$from_a_let_in_the_file)
message("  no NIMPUTE given:        ", s$no_nimpute_given)
message("  unresolved:              ", s$unresolved)
message("\n--- STUDIES ---")
message("running PROC MI directly:  ", out$studies$running_procmi_directly)
message("⭐ with a resolved NIMPUTE: ", out$studies$with_a_resolved_nimpute)
message("\n--- NIMPUTE ---")
message("resolved: ", out$nimpute$resolved_total,
        "   =1: ", out$nimpute$nimpute_1,
        "   >1: ", out$nimpute$nimpute_gt1,
        "   =0: ", out$nimpute$nimpute_0)
message("\nwrote ", outfile)
