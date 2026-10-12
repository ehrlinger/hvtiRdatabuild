#!/usr/bin/env Rscript
# test-lst-exposure-scan.R
#
# Checks `lst-exposure-scan.R` against synthetic listings whose detection class,
# permissions and byte size are known by construction.
#
#   Rscript test-lst-exposure-scan.R
#
# ⚠️ NO PHI, AND NOTHING RESEMBLING IT. A real `.lst` IS printed output and a
# `PROC PRINT` one is patient data by design, which is why the scan's contract is
# the strictest in this directory. The fixture's "print output" cases carry
# invented column headers and NO rows at all.
#
# ⭐ EVERY DETECTION FIELD HAS A DIFFERENT EXPECTED VALUE. Three fixtures here
# have previously passed over broken code because two cases collapsed to the same
# number and cancelled.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
scan_script <- file.path(here, "lst-exposure-scan.R")
stopifnot(file.exists(scan_script))

if (!requireNamespace("hvtiRutilities", quietly = TRUE)) {
  message("SKIP: hvtiRutilities could not be loaded, so the scan cannot run.\n",
          "  This R:   ", R.version.string, "\n",
          "  libPaths: ", paste(.libPaths(), collapse = "\n            "))
  quit(save = "no", status = 0)
}

fail <- 0L
root <- file.path(tempdir(), paste0("lstexp-fixture-", Sys.getpid()))
folder <- unique(hvtiRutilities::hvti_taxonomy()$folder)[[1]]

# ⭐ Fixed-width bodies so the byte totals are known exactly. Each line is padded
# to 40 characters, so a file of k lines is k * 41 bytes with newlines.
pad <- function(x) formatC(x, width = 40, flag = "-")
HEAD <- pad("The PRINT Procedure")          # RE_HEADING
OBS  <- pad("Obs   InventedCol   Another")  # RE_OBSLINE, invented headers, no rows
UOBS <- pad("OBS   InventedCol   Another")  # 🔴 uppercase: dropped by every run
                                            #    before 2026-09-08
ROW  <- pad("     1   0   0")               # a numbered row. ⚠️ INVENTED ZEROS:
                                            #    shape only, no value is real
# 🔴 A line carrying a digit that is NOT a row. Without it, unanchoring RE_ROW
# changes nothing, because every other non-row line here is digit-free -- the
# fixture would confirm the anchor it never tested.
NOTROW <- pad("(invented note 7, not a row)")
FILL <- pad("(invented fixture line)")
LINE <- 41L

put <- function(study, file, lines, mode) {
  d <- file.path(root, study, folder)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  f <- file.path(d, file)
  writeLines(lines, f)
  Sys.chmod(f, mode)
  length(lines) * LINE
}

bytes <- 0L
add <- function(...) bytes <<- bytes + put(...)

# 🔴 THE DISCRIMINATOR. A non-print procedure heading. Under the correct
# RE_HEADING this file is `neither`; under a regex widened to `the [a-z]+
# procedure` it becomes `heading_only`. Without it the fixture cannot tell the
# two apart, and a widened heading regex passed every check -- found by mutation
# testing on 2026-09-08, not by reading the fixture.
FREQ <- pad("The FREQ Procedure")

# --- both (heading AND obs line): 4 files ------------------------------------
add("cardiac/alpha",   "p1.lst", c(HEAD, OBS),       "0644")
add("cardiac/alpha",   "p2.lst", c(HEAD, OBS, FILL), "0644")
add("cardiac/delta",   "p3.lst", c(HEAD, OBS),       "0644")
add("cardiac/epsilon", "p4.lst", c(HEAD, OBS, FILL), "0644")
# --- heading only: 3 files ---------------------------------------------------
add("cardiac/alpha",   "h1.lst", c(HEAD, FILL),      "0644")
add("cardiac/alpha",   "h2.lst", c(HEAD),            "0640")
# --- obs line only: 6 files. ⚠️ The weakest evidence, and what the parent
#     scan's single figure silently folded in.
add("thoracic/beta",   "o1.lst", c(OBS, FILL),       "0640")
add("thoracic/beta",   "o2.lst", c(OBS),             "0640")
add("cardiac/zeta",    "o3.lst", c(OBS),             "0600")
add("cardiac/zeta",    "o4.lst", c(OBS, FILL),       "0600")
add("cardiac/theta",   "o5.lst", c(OBS),             "0600")
add("cardiac/theta",   "o6.lst", c(OBS, FILL),       "0600")
add("cardiac/theta",   "o7.lst", c(OBS),             "0640")
# --- obs header WITH a numbered row beneath: the corroborated population -----
add("cardiac/kappa",  "r1.lst", c(OBS, ROW),        "0640")
add("cardiac/kappa",  "r2.lst", c(FILL, OBS, ROW),  "0640")
# ⭐ Uppercase header AND a row. Invisible to every run before 2026-09-08, and
#    corroborated once seen -- so it tests the case fix and the row check at once.
add("cardiac/lambda", "r3.lst", c(UOBS, ROW),       "0640")
# ⚠️ A header whose row does not immediately follow. Corroboration is a LOWER
#    bound and this file is what says so: obs header, not corroborated.
add("cardiac/kappa",  "r4.lst", c(OBS, FILL, ROW),  "0640")
# ⚠️ Header followed by a line CONTAINING a digit but not shaped like a row.
#    Anchored, not corroborated; unanchored, wrongly corroborated.
add("cardiac/kappa",  "r5.lst", c(OBS, NOTROW),     "0640")
# ⭐ A row four lines down: inside the default window, outside a naive check.
add("cardiac/kappa",  "r6.lst", c(OBS, FILL, FILL, FILL, ROW), "0640")
# ⚠️ A row TEN lines down: outside the window, so it must count as "none" and
#    the corroborated figure must stay a lower bound rather than creeping.
add("cardiac/mu",     "r7.lst", c(OBS, rep(FILL, 9L), ROW),    "0640")
# 🔴 A header PAST THE FIRST WINDOW BOUNDARY. Under `--chunk 1` the buffer grows
#    beyond ROW_WINDOW before this header is reached, so the unresolved tail must
#    be carried forward. Discarding it loses the header entirely -- a mutation
#    that escaped every other file here, because none put a header that deep.
add("cardiac/kappa",  "r8.lst", c(rep(FILL, 9L), OBS, ROW),    "0640")

# --- neither: 2 files, one of them the FREQ discriminator --------------------
add("cardiac/gamma",   "n1.lst", c(FILL),            "0600")
add("cardiac/gamma",   "f1.lst", c(FREQ, FILL),      "0600")
# 🔴 A SECOND DISCRIMINATOR, for the ANCHOR rather than the wording. This line
# reaches RE_OBSLINE (the prefilter admits it on "rocedure") and contains "obs"
# away from the line start. Anchored, it is not a print-out; unanchored, it is.
# ⚠️ Without it the anchor is enforced only by the prefilter, which carries the
# same `^ *[Oo]bs ` and would mask a widened RE_OBSLINE entirely.
add("cardiac/gamma",   "f2.lst", c(pad("The FREQ Procedure by obs group")), "0600")

# gamma's two files are the only non-print ones: 1 line + 2 lines
# gamma's three non-print files: 1 + 2 + 1 lines
print_bytes <- bytes - (4L * LINE)

# ⭐ One folder made non-traversable by others, so the reachability figure has
# something to exclude. Without this every directory is 0755 and the field would
# pass while never being read at all -- found by mutation testing.
Sys.chmod(file.path(root, "thoracic/beta", folder), "0750")

outfile <- file.path(root, "out.json")
rscript <- file.path(R.home("bin"), "Rscript")
res <- system2(rscript, c(shQuote(normalizePath(scan_script)),
                          "--root", shQuote(root), "--out", shQuote(outfile)),
               stdout = TRUE, stderr = TRUE)
if (!file.exists(outfile)) { cat(res, sep = "\n"); stop("scan produced no output") }
j <- paste(readLines(outfile), collapse = " ")
num <- function(field) {
  m <- regmatches(j, regexpr(paste0("\"", field, "\": *-?[0-9]+"), j))
  if (!length(m)) stop("field not found: ", field)
  as.integer(sub(".*: *", "", m))
}

expected <- list(
  read                        = 24L,
  # ⚠️ ZERO in the corpus: SAS's LISTING output for PROC PRINT carries no
  # procedure banner. The fixture still plants six, because the arm has to be
  # shown working before its zero can be read as a finding rather than a bug.
  with_a_print_or_report_heading = 6L,
  # p1-p4, o1-o7, r1-r4  (r3's header is uppercase and now counts)
  obs_header                  = 19L,
  # ⭐ r1, r2, r3 only. p1-p4 and o1-o7 have headers with no row beneath.
  obs_header_with_a_row_at_offset_1 = 4L,
  # ⭐ r1, r2, r3 at offset 1; r4 at 2; r6 at 4. r5 has no row, r7's is at 10.
  obs_header_with_a_row_in_window   = 6L,
  obs_header_with_no_row_in_window  = 13L,
  # ⚠️ r4's row is one line further down: corroboration is a LOWER bound.

  # 🔴 r3 alone. Invisible to every run before 2026-09-08.
  obs_header_uppercase_only   = 1L,
  neither                     = 3L,
  any_print_pattern           = 21L,
  # alpha, delta, epsilon, beta, zeta, theta, kappa, lambda
  with_any_print_pattern      = 9L,
  # ⭐ kappa and lambda only
  with_a_corroborated_print   = 2L,
  group_readable              = 17L,
  other_readable              = 5L,
  owner_only                  = 7L,
  distinct_owners             = 1L,
  in_a_world_traversable_directory = 22L,
  all_listings_bytes          = bytes,
  print_matched_bytes         = print_bytes
)
for (nm in names(expected)) {
  got <- num(nm)
  ok <- identical(got, as.integer(expected[[nm]]))
  if (!ok) fail <- fail + 1L
  message(sprintf("%-29s expected %5d  got %5d  %s", nm, expected[[nm]], got,
                  if (ok) "ok" else "FAIL"))
}

# ---- the offset distribution is the layout measurement ----------------------
# ⭐ r1, r2, r3 put a row at offset 1; r4 at offset 2; r6 at offset 4. r5 has no
# row at all and r7's sits at offset 10, beyond the window -- both must land in
# `none_in_window`, together with every header in p1-p4 and o1-o7.
# 🔴 RE-READ THE MAIN OUTPUT. Later sections reassign `j` to the oversized and
# chunked runs, and this block first sat after them -- asserting the layout
# against a run where every detection figure is deliberately zero. It reported
# 0 for every offset and looked like a scan defect.
j <- paste(readLines(outfile), collapse = " ")
for (nm in c("offset_1", "offset_2", "offset_3", "offset_4", "none_in_window")) {
  want <- c(offset_1 = 4L, offset_2 = 1L, offset_3 = 0L, offset_4 = 1L,
            none_in_window = 13L)[[nm]]
  got <- num(nm)
  ok <- identical(got, want)
  if (!ok) fail <- fail + 1L
  message(sprintf("distribution: %-15s expected %5d  got %5d  %s", nm, want, got,
                  if (ok) "ok" else "FAIL"))
}

# ---- the contract -----------------------------------------------------------
# 🔴 No listing text, no owner name, no path and no study identifier may reach
# the output. The fixture plants distinctive words and names, and none may appear.
me <- Sys.info()[["user"]]
for (leak in c("invented", "Invented", "InventedCol", "PRINT Procedure", "Obs",
               "cardiac", "thoracic", "alpha", "gamma", "kappa", "FREQ", me)) {
  if (nzchar(leak) && grepl(leak, j, fixed = TRUE)) {
    message("FAIL  output contains fixture text: ", leak); fail <- fail + 1L
  }
}
for (decl in c("\"emits_owner_names\": false", "\"emits_row_counts\": false",
               "\"emits_listing_values\": false")) {
  if (!grepl(decl, j, fixed = TRUE)) {
    message("FAIL  output does not declare: ", decl); fail <- fail + 1L
  }
}
if (!fail) message(sprintf("%-29s %s", "no fixture text in output", "ok"))

# ---- mode uniformity is REPORTED, not assumed -------------------------------
# ⚠️ A network filesystem can synthesise one mode for every file, in which case
# the reachability figures describe the mount rather than any per-file decision.
# The fixture uses four distinct modes, so the flag must be false here; a run
# where it is TRUE is a run whose reachability section must be read differently.
if (!grepl('"mode_bits_look_uniform": false', j, fixed = TRUE)) {
  message("FAIL  mode uniformity not reported as false on a mixed-mode fixture")
  fail <- fail + 1L
} else message(sprintf("%-29s %s", "mode uniformity reported", "ok"))

# ---- reachability survives the oversized skip -------------------------------
# ⭐ A file too large to inspect is not too large to READ. With the ceiling below
# every file, detection must go to zero while every reachability figure and the
# byte total stay exactly as they were.
o2 <- file.path(root, "oversized.json")
system2(rscript, c(shQuote(normalizePath(scan_script)), "--root", shQuote(root),
                   "--out", shQuote(o2), "--max-lst-mb", "0.000001"),
        stdout = FALSE, stderr = FALSE)
if (!file.exists(o2)) {
  message("FAIL  the all-oversized run produced no output"); fail <- fail + 1L
} else {
  j <- paste(readLines(o2), collapse = " ")
  over <- list(read = 0L, any_print_pattern = 0L, obs_header = 0L,
               listings_oversized = 24L, print_matched_bytes = 0L,
               group_readable = 17L, other_readable = 5L, owner_only = 7L,
               all_listings_bytes = bytes)
  for (nm in names(over)) {
    got <- num(nm)
    ok <- identical(got, as.integer(over[[nm]]))
    if (!ok) fail <- fail + 1L
    message(sprintf("oversized: %-18s expected %5d  got %5d  %s", nm, over[[nm]],
                    got, if (ok) "ok" else "FAIL"))
  }
}

# ---- the corroboration survives a chunk boundary ----------------------------
# 🔴 The adjacency check reads line i+1. When an `obs` header is the LAST line of
# a chunk its row is the FIRST line of the next, and without a carry-over flag
# the corroboration silently fails there. At 20,000 lines a chunk that is rare
# enough in the corpus to look like a property of the data.
#
# ⭐ `--chunk 1` puts EVERY line on a boundary, so if the carry-over is broken
# `obs_header_with_rows` collapses to zero while `obs_header` is unchanged.
o4 <- file.path(root, "chunked.json")
system2(rscript, c(shQuote(normalizePath(scan_script)), "--root", shQuote(root),
                   "--out", shQuote(o4), "--chunk", "1"),
        stdout = FALSE, stderr = FALSE)
if (!file.exists(o4)) {
  message("FAIL  the --chunk 1 run produced no output"); fail <- fail + 1L
} else {
  j <- paste(readLines(o4), collapse = " ")
  for (nm in c("obs_header", "obs_header_with_a_row_in_window",
               "obs_header_uppercase_only",
               "with_a_corroborated_print")) {
    got <- num(nm)
    ok <- identical(got, as.integer(expected[[nm]]))
    if (!ok) fail <- fail + 1L
    message(sprintf("chunk=1: %-20s expected %5d  got %5d  %s", nm,
                    expected[[nm]], got, if (ok) "ok" else "FAIL"))
  }
}

# ---- --count-only writes nothing --------------------------------------------
o3 <- file.path(root, "count.json")
system2(rscript, c(shQuote(normalizePath(scan_script)), "--root", shQuote(root),
                   "--out", shQuote(o3), "--count-only"),
        stdout = FALSE, stderr = FALSE)
if (file.exists(o3)) {
  message("FAIL  --count-only wrote an output file"); fail <- fail + 1L
} else message(sprintf("%-29s %s", "--count-only writes nothing", "ok"))

unlink(root, recursive = TRUE)
if (fail) { message("\n", fail, " failure(s)"); quit(save = "no", status = 1) }
message("\nall checks passed")
