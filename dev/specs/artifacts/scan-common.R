# scan-common.R
#
# Helpers shared by the corpus scans in this directory.
#
# WHY THIS FILE EXISTS. `imputation-method-scan.R` and
# `imputation-callsite-scan.R` both report STUDY counts, and those counts are
# only comparable if both scans agree on what a study is. Two copies of
# `study_of()` would be two definitions that drift, and the drift would present
# as a disagreement between the scans rather than as a defect in either. One
# definition, sourced by both.
#
# Nothing here reads or writes study data. `source()` this; it defines
# functions and does not run a scan.

# ---- guard ------------------------------------------------------------------
# Check BEFORE any traversal: the walk is the expensive part, and discovering a
# missing package after an hour of it is the failure this guard prevents.
#
# ⚠️ Do NOT say "not installed". requireNamespace() returns FALSE for ANY load
# failure -- absent, broken, or built by a newer R than this one -- and cannot
# tell them apart. A server carrying several R versions makes the last of those
# the likely case, and it is the one a bare "not installed" sends the reader
# hunting in the wrong direction: the library path carries <major>.<minor>, so
# R 4.4 and R 4.6 cannot share one.
require_hvtiRutilities <- function() {
  if (requireNamespace("hvtiRutilities", quietly = TRUE)) return(invisible(TRUE))
  stop("hvtiRutilities could not be loaded -- it defines what a study is, and ",
       "without it the study counts cannot reconcile with the census.\n",
       "  This R:      ", R.version.string, "\n",
       "  R_HOME:      ", R.home(), "\n",
       "  libPaths:    ", paste(.libPaths(), collapse = "\n               "), "\n",
       "It may be absent, or present but built by a different R than this one. ",
       "Check the library paths above before installing anything.",
       call. = FALSE)
}

taxonomy_folders <- function() {
  require_hvtiRutilities()
  unique(hvtiRutilities::hvti_taxonomy()$folder)
}

# ---- root -------------------------------------------------------------------
# path.expand() FIRST: list.files() expands a tilde root but returns expanded
# paths, so an unexpanded root would misalign substring() by a constant and
# leave fragments of the root path inside every study label. Then strip
# trailing slashes ONCE -- comparing against normalizePath() instead silently
# no-ops under a symlinked or automounted root (very plausible for a share),
# which would collapse every study to one id with no error.
normalise_root <- function(root) {
  root <- path.expand(root)
  if (!dir.exists(root)) stop("root not found: ", root, call. = FALSE)
  sub("/+$", "", root)
}

# ---- study attribution ------------------------------------------------------
# A STUDY IS THE DIRECTORY HOLDING A TAXONOMY FOLDER, and the nearest such
# ancestor wins. This is hvtiRutilities' definition (R/job_census.R:1-12) and
# the one that produced the census counts these scans reconcile against.
#
# ⚠️ An earlier draft took the first two path components as "<tree>/<study>".
# Measured against the real share, taxonomy folders sit at three depths (28,
# 812 and 2743 directories at depths 3, 4 and 5 below /studies), so that draft
# would have misattributed over 99% of the corpus to subject areas rather than
# studies -- and still emitted a clean-looking result.
study_of_factory <- function(root, folders) {
  function(paths) {
    # substring(), not sub(): `root` is a path, not a regex, and a directory
    # named "study (copy)" or "v1.2+" carries metacharacters that would match
    # the wrong thing while still looking like it worked.
    # iconv() first: ONE Latin-1 filename anywhere on the share makes
    # substring() abort with "invalid multibyte string" -- after the whole
    # traversal, for zero output.
    paths <- iconv(paths, "", "UTF-8", sub = "byte")
    rel   <- substring(paths, nchar(root) + 2L)
    parts <- strsplit(rel, "/", fixed = TRUE)
    vapply(parts, function(p) {
      dirs <- utils::head(p, -1L)              # only directories can be a folder
      hits <- which(dirs %in% folders)
      if (!length(hits)) return(NA_character_) # unplaced: no taxonomy ancestor
      i <- max(hits)                           # nearest to the file
      if (i == 1L) "." else paste(dirs[seq_len(i - 1L)], collapse = "/")
    }, character(1))
  }
}

# ---- SAS lexing -------------------------------------------------------------
# SAS is case-insensitive and free-form: a statement may wrap lines, so match
# against the whole file with newlines collapsed to spaces, and split on ';' to
# keep one statement's options from bleeding into the next.
statements <- function(txt) {
  one <- paste(txt, collapse = " ")
  one <- gsub("/\\*.*?\\*/", " ", one)          # strip /* block comments */
  one <- tolower(gsub("[[:space:]]+", " ", one))
  st  <- strsplit(one, ";", fixed = TRUE)[[1]]
  # SAS `* ... ;` and macro `%* ... ;` comments end at the semicolon, so after
  # the split each is its own element. Drop them. Without this a commented-out
  # or historical `* proc standard replace;` -- ordinary in a 30-year corpus --
  # counts as if it had run, and in one direction only.
  st[!grepl("^ *%?\\*", st)]
}

read_statements <- function(path) {
  txt <- tryCatch(readLines(path, warn = FALSE, encoding = "latin1"),
                  error = function(e) character(0))
  if (!length(txt)) return(NULL)
  statements(txt)
}

# ---- output -----------------------------------------------------------------
# Minimal JSON writer so the scans need no packages.
to_json <- function(x, ind = 0) {
  pad <- strrep(" ", ind)
  if (is.null(x) || (length(x) == 1 && is.na(x) && !is.character(x))) return("null")
  if (is.list(x)) {
    if (!length(x)) return("{}")
    nm <- names(x)
    items <- vapply(seq_along(x), function(i) {
      paste0(pad, "  \"", nm[i], "\": ", to_json(x[[i]], ind + 2))
    }, character(1))
    return(paste0("{\n", paste(items, collapse = ",\n"), "\n", pad, "}"))
  }
  if (is.character(x)) return(paste0("\"", gsub("\"", "'", x), "\""))
  if (is.logical(x))   return(if (isTRUE(x)) "true" else "false")
  if (is.na(x))        return("null")
  format(x, scientific = FALSE)
}
