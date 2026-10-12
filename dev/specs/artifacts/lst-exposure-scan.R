#!/usr/bin/env Rscript
# lst-exposure-scan.R
#
# `2026-09-06-hvtr-cohort-metadata-scoping.md` records a number that is not about
# verification at all:
#
#   🔴 35,735 LISTINGS, 72.5% OF THOSE READ, MATCH A PATIENT-PRINT-OUT PATTERN.
#
# That note calls it an upper bound and says the conservative figure "was not
# separated out and should be". This scan separates it, and adds the half of the
# question nobody has measured.
#
# ⭐ EXPOSURE IS CONTENT TIMES REACHABILITY, AND ONLY CONTENT HAS BEEN MEASURED.
# 35,735 print-outs in owner-only directories is an inventory item. The same
# files readable by everyone on a shared research volume is a different
# conversation. A mode bit is not content: measuring it discloses nothing and
# decides which of the two this is.
#
#   Rscript lst-exposure-scan.R --root /studies --count-only
#   Rscript lst-exposure-scan.R --root /studies --out lst-exposure.json
#
# ⚠️ RUN `--count-only` FIRST on an uncounted root. The `.lst` population was
# 49,307 on 2026-09-06.
#
# 🔴 PRIVACY CONTRACT -- `lst-listing-scan.R`'s, WHICH IS THE STRICTEST HERE,
# PLUS TWO CLAUSES THIS SCAN NEEDS BECAUSE OF WHAT IT LOOKS AT.
#
# A `.lst` IS printed output, and a `PROC PRINT` listing is patient data by
# design rather than by accident. So, as in that scan: NO LINE SURVIVES A CHUNK,
# no fragment, match or capture group is stored, printed or written, and only
# flags and counters cross a chunk boundary.
#
# 🔴 NO ROW COUNT IS READ, AND THAT IS DELIBERATE. A `PROC PRINT` row count is a
# cohort size. `log-verifiability-scan.R` already declined to read the N and M
# out of a shape NOTE for that reason, and adding it here would drift into a
# disclosure a sibling scan refused on purpose. Volume is reported in BYTES,
# which answers "how much of this is there" without it.
#
# 🔴 NO OWNER NAME IS EMITTED. The scan counts DISTINCT owners, because "how many
# people's files is this" bears on who the finding goes to, and a count is not a
# name. Owner names live in a vector that is reduced to a set size and never
# written -- the pattern `rung-overlap-scan.R` uses for study identity. ⚠️ The
# artifact withdrawn on 2026-09-06 disclosed a personal home directory; that is
# this exact class of value, and the difference is aggregation, not filtering.
#
# IT EMITS no path, no file name, no study identifier, no owner, no row count and
# no listing text. Only counts, byte totals, and the seven taxonomy folder names,
# which are fixed in `hvtiRutilities` rather than read from the corpus.

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
outfile    <- getarg("--out", "lst-exposure.json")
count_only <- "--count-only" %in% args
chunk      <- as.integer(getarg("--chunk", "20000"))
max_mb     <- as.numeric(getarg("--max-lst-mb", "200"))

# ---- the detector, SPLIT ----------------------------------------------------
# 🔴 `lst-listing-scan.R` matches `^ *obs +|the (print|report) procedure` as ONE
# pattern, so its 35,735 cannot be decomposed and the artifact cannot say how
# much of the figure rests on the weaker half. The two are kept apart here.
#
# ⭐ RE_HEADING is the one to trust: SAS prints it above the procedure's output.
# ⚠️ RE_OBSLINE is the heuristic that over-matches -- a `PROC PRINT` page begins
# its columns with `Obs`, but so may a summary table with a column labelled that
# way. Neither is a superset of the other: a listing run with NOTITLE carries no
# heading, and a printed dataset with the OBS column suppressed carries no `obs`
# line. So the pair BRACKETS the truth rather than bounding it from one side, and
# `both` is the confident population.
RE_HEADING <- "the (print|report) procedure"
RE_OBSLINE <- "^ *obs +"
# 🔴 WHAT THE OLD PREFILTER ADMITTED, kept only to measure what it MISSED. Both
# this scan and `lst-listing-scan.R` prefiltered raw lines with `^ *[Oo]bs `
# BEFORE lowercasing, so a header SAS wrote as `OBS` was dropped before any
# pattern saw it. `obs_header_uppercase_only` counts the files that costs.
RE_OBSOLD  <- "^ *[Oo]bs "
# ⭐ THE CORROBORATION. A `PROC PRINT` page is an `Obs` header followed by rows
# that BEGIN with the observation number. Matching the header alone is a guess;
# matching a header with a numbered row beneath it is a print-out.
# ⚠️ This tests SHAPE, never content: the digits are matched and not read, which
# keeps the no-row-count rule above intact -- a row's ordinal is not a value.
# ⚠️ It is a LOWER bound. Only the IMMEDIATELY following line is checked, so a
# blank or continuation line between header and rows reads as uncorroborated.
RE_ROW     <- "^ *[0-9]+ "
# ⭐ HOW FAR BELOW A HEADER TO LOOK. The 2026-09-08 16:10 run checked ONLY the
# next line and corroborated 2 headers out of 36,634 -- a measurement of the
# check failing, not of the corpus. Something sits between a SAS `Obs` header and
# its first row essentially always; ⚠️ WHAT that is has not been established, and
# guessing it twice would repeat the error that made this scan claim
# `PROC PRINT` prints a procedure banner. So the OFFSET IS MEASURED rather than
# assumed: the distribution below says where the rows actually are, and a
# threshold can then be chosen from data.
ROW_WINDOW <- as.integer(getarg("--row-window", "8"))

.folders <- taxonomy_folders()
study_of <- study_of_factory(root, .folders)
message("taxonomy folders: ", paste(.folders, collapse = ", "))

message("listing .lst files -- the slow part on a share")
lsts <- list.files(root, pattern = "\\.lst$", recursive = TRUE,
                   full.names = TRUE, ignore.case = TRUE, no.. = TRUE)
message("candidate listings: ", length(lsts))
if (count_only) {
  message("\n--count-only: nothing was read. Decide on the count above before ",
          "running the full pass.")
  quit(save = "no", status = 0)
}

inspect <- function(path) {
  if (max_mb > 0) {
    sz <- file.size(path)
    if (!is.na(sz) && sz > max_mb * 1024^2) return("oversized")
  }
  con <- tryCatch(file(path, "r", encoding = "latin1"), error = function(e) NULL)
  if (is.null(con)) return(NULL)
  on.exit(close(con), add = TRUE)
  has <- c(heading = FALSE, obs = FALSE, oldform = FALSE)
  # Counts of the offset at which the first row-shaped line appears after each
  # `obs` header. Position ROW_WINDOW + 1 is "no row within the window".
  offs <- integer(ROW_WINDOW + 1L)

  # ⚠️ A HEADER NEEDS ROW_WINDOW LINES BENEATH IT TO BE JUDGED, so a header near
  # the end of a chunk cannot be resolved until the next chunk arrives. `tail`
  # holds the unresolved end of the buffer and is prepended to what follows.
  # Every header is processed EXACTLY ONCE: only indices with a full window are
  # evaluated, and those lines are then dropped.
  tail <- character(0)
  eof <- FALSE
  repeat {
    lines <- tryCatch(suppressWarnings(readLines(con, n = chunk, warn = FALSE)),
                      error = function(e) character(0))
    if (!length(lines)) eof <- TRUE
    buf <- c(tail, lines)
    if (!length(buf)) break

    # At end of file every remaining header is judged on the lines that exist.
    limit <- if (eof) length(buf) else length(buf) - ROW_WINDOW
    if (limit > 0L) {
      oi <- grep(RE_OBSLINE, utils::head(buf, limit), ignore.case = TRUE)
      if (length(oi)) {
        has[["obs"]] <- TRUE
        if (!has[["oldform"]] && any(grepl(RE_OBSOLD, buf[oi])))
          has[["oldform"]] <- TRUE
        for (h in oi) {
          hit <- ROW_WINDOW + 1L
          for (k in seq_len(ROW_WINDOW)) {
            j <- h + k
            if (j > length(buf)) break
            if (grepl(RE_ROW, buf[[j]])) { hit <- k; break }
          }
          offs[[hit]] <- offs[[hit]] + 1L
        }
      }
      if (!has[["heading"]]) {
        seg <- utils::head(buf, limit)
        keep <- grepl("rocedure", seg)
        if (any(keep) && any(grepl(RE_HEADING, tolower(seg[keep]))))
          has[["heading"]] <- TRUE
      }
      tail <- if (limit < length(buf)) buf[(limit + 1L):length(buf)] else character(0)
    } else {
      tail <- buf
    }
    rm(lines, buf)                       # nothing survives but flags and counts
    if (eof) break
  }
  list(heading = has[["heading"]], obs = has[["obs"]],
       offsets = offs,
       # Offset 1 exactly: the definition the 16:10 run used, kept so the two
       # runs remain comparable.
       rows1 = offs[[1L]] > 0L,
       # Anywhere in the window.
       rowsw = sum(offs[seq_len(ROW_WINDOW)]) > 0L,
       missed_old = has[["obs"]] && !has[["oldform"]])
}

# ---- reachability -----------------------------------------------------------
# ⭐ Needs no read at all, so it is measured for EVERY file including the ones
# skipped as oversized. A file too large to inspect is not too large to be
# readable by the wrong person.
#
# ⚠️ Mode bits can be SYNTHESISED by a network filesystem rather than stored, in
# which case they describe the mount's export options and not a per-file
# decision. `mode_bits_look_uniform` is recorded so a reader can tell: if every
# file carries one mode, that is the mount talking.
mode_of <- function(paths) {
  m <- file.info(paths, extra_cols = FALSE)$mode
  as.integer(m)
}
dir_mode_cache <- new.env(parent = emptyenv())
dir_mode <- function(d) {
  v <- dir_mode_cache[[d]]
  if (!is.null(v)) return(v)
  v <- as.integer(file.info(d, extra_cols = FALSE)$mode)
  if (length(v) != 1L || is.na(v)) v <- NA_integer_
  assign(d, v, envir = dir_mode_cache)
  v
}

stu <- study_of(lsts)
n <- c(read = 0L, unreadable = 0L, oversized = 0L,
       heading = 0L, obs = 0L, obs_rows = 0L, obs_rows_w = 0L,
       missed_old = 0L, neither = 0L)
# ⭐ The layout measurement: how far below an `obs` header its first row sits.
offsets_total <- integer(ROW_WINDOW + 1L)
bytes_all <- 0; bytes_print <- 0
s_any <- character(length(lsts)); s_rows <- character(length(lsts))
group_r <- 0L; other_r <- 0L; owner_only <- 0L; dir_other_x <- 0L
owners <- character(length(lsts))
modes <- integer(0)

sizes <- file.size(lsts)
fmodes <- mode_of(lsts)
finfo_owner <- file.info(lsts, extra_cols = TRUE)$uname

for (i in seq_along(lsts)) {
  sz <- sizes[[i]]
  if (!is.na(sz)) bytes_all <- bytes_all + sz
  md <- fmodes[[i]]
  if (!is.na(md)) {
    modes <- c(modes, md)
    gr <- bitwAnd(md, 32L) != 0L      # group read
    orr <- bitwAnd(md, 4L)  != 0L     # other read
    if (gr) group_r <- group_r + 1L
    if (orr) other_r <- other_r + 1L
    if (!gr && !orr) owner_only <- owner_only + 1L
  }
  # ⚠️ THE IMMEDIATE DIRECTORY ONLY, which OVER-COUNTS reachability: a file in a
  # world-traversable folder under a private parent is not actually reachable.
  # Walking every ancestor would answer it properly. Left as an upper bound
  # rather than silently presented as reachability.
  dm <- dir_mode(dirname(lsts[[i]]))
  if (!is.na(dm) && bitwAnd(dm, 1L) != 0L) dir_other_x <- dir_other_x + 1L
  if (!is.na(finfo_owner[[i]])) owners[[i]] <- finfo_owner[[i]]

  r <- inspect(lsts[[i]])
  if (identical(r, "oversized")) { n[["oversized"]] <- n[["oversized"]] + 1L; next }
  if (is.null(r)) { n[["unreadable"]] <- n[["unreadable"]] + 1L; next }
  n[["read"]] <- n[["read"]] + 1L
  if (r$heading) n[["heading"]] <- n[["heading"]] + 1L
  if (r$obs) {
    n[["obs"]] <- n[["obs"]] + 1L
    if (r$missed_old) n[["missed_old"]] <- n[["missed_old"]] + 1L
    offsets_total <- offsets_total + r$offsets
    if (r$rows1) n[["obs_rows"]] <- n[["obs_rows"]] + 1L
    if (r$rowsw) n[["obs_rows_w"]] <- n[["obs_rows_w"]] + 1L
  }
  if (!r$heading && !r$obs) n[["neither"]] <- n[["neither"]] + 1L
  if (r$heading || r$obs) {
    if (!is.na(sz)) bytes_print <- bytes_print + sz
    if (!is.na(stu[[i]])) s_any[[i]] <- stu[[i]]
    # ⭐ The CORROBORATED population: a header with a numbered row beneath it,
    # not a header alone.
    if (r$rowsw && !is.na(stu[[i]])) s_rows[[i]] <- stu[[i]]
  }
  if (i %% 2000 == 0) message("  ", i, " / ", length(lsts))
}

any_print <- n[["read"]] - n[["neither"]]
gb <- function(b) round(b / 1024^3, 2)

out <- list(
  `_provenance` = list(
    script = "lst-exposure-scan.R",
    question = "how much patient print-out is in .lst files, and who can read it?",
    run_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    root = if (identical(root, "/studies")) "/studies" else "(non-default root)",
    hvtiRutilities_version = as.character(utils::packageVersion("hvtiRutilities")),
    listings_considered = length(lsts),
    listings_unreadable = unname(n[["unreadable"]]),
    listings_oversized = unname(n[["oversized"]]),
    max_lst_mb = max_mb,
    # ⚠️ If every file carries one mode, the filesystem is reporting the mount's
    # export options rather than a per-file decision, and the reachability
    # figures below describe the mount.
    mode_bits_look_uniform = length(unique(modes)) <= 1L,
    distinct_modes = length(unique(modes)),
    contains_identifiers = FALSE,
    emits_owner_names = FALSE,
    emits_row_counts = FALSE,
    emits_listing_values = FALSE
  ),
  detection = list(
    read = unname(n[["read"]]),
    # ⚠️ Measured 2026-09-08 as ZERO across 49,298 files. SAS's classic LISTING
    # output for PROC PRINT carries NO procedure banner -- it prints the column
    # header and the rows -- so the arm this scan first called "the one to
    # trust" cannot fire on the file type it was built for.
    with_a_print_or_report_heading = unname(n[["heading"]]),
    obs_header = unname(n[["obs"]]),
    # ⭐ THE FIGURE TO QUOTE. A header with a numbered row beneath it.
    # Offset 1 exactly -- the 16:10 definition, kept for comparability. It
    # returned 2 of 36,634, which measured the CHECK failing, not the corpus.
    obs_header_with_a_row_at_offset_1 = unname(n[["obs_rows"]]),
    # ⭐ Anywhere in the window. THE FIGURE TO QUOTE once the distribution below
    # shows the window covers where rows actually are.
    obs_header_with_a_row_in_window = unname(n[["obs_rows_w"]]),
    obs_header_with_no_row_in_window =
      unname(n[["obs"]] - n[["obs_rows_w"]]),
    row_window = ROW_WINDOW,
    # 🔴 Files whose every `obs` header was uppercase, which the old `^ *[Oo]bs `
    # prefilter dropped before any pattern saw it. These are NEW to this run and
    # are the only reason `obs_header` may exceed the earlier 35,739.
    obs_header_uppercase_only = unname(n[["missed_old"]]),
    neither = unname(n[["neither"]]),
    any_print_pattern = unname(any_print)
  ),
  studies = list(
    with_any_print_pattern = length(unique(s_any[nzchar(s_any)])),
    # ⭐ Studies holding at least one CORROBORATED print-out: a header with a
    # numbered row beneath it, not a header alone.
    with_a_corroborated_print = length(unique(s_rows[nzchar(s_rows)]))
  ),
  # ⭐ WHERE THE ROWS ACTUALLY ARE, per header occurrence rather than per file.
  # ⚠️ If the mass sits at the far edge of the window the window is too small and
  # this is a lower bound; if it sits at "none" the row pattern itself is wrong.
  row_offset_distribution = setNames(
    as.list(offsets_total),
    c(paste0("offset_", seq_len(ROW_WINDOW)), "none_in_window")
  ),
  reachability = list(
    # ⚠️ Over ALL listings, including oversized ones: too large to inspect is not
    # too large to read.
    group_readable = group_r,
    other_readable = other_r,
    owner_only = owner_only,
    in_a_world_traversable_directory = dir_other_x,
    distinct_owners = length(unique(owners[nzchar(owners)]))
  ),
  volume = list(
    # Bytes as well as GB: GB rounds a fixture to zero, and a byte count is the
    # figure a test can assert on.
    all_listings_bytes = bytes_all,
    print_matched_bytes = bytes_print,
    all_listings_gb = gb(bytes_all),
    print_matched_gb = gb(bytes_print)
  )
)

writeLines(to_json(out), outfile)
message("\n--- DETECTION ---")
message("read:                      ", out$detection$read)
message("  print/report heading:    ", out$detection$with_a_print_or_report_heading)
message("  obs header:              ", out$detection$obs_header)
message("  ⭐ row within ", out$detection$row_window, " lines:  ",
        out$detection$obs_header_with_a_row_in_window, "   <- corroborated")
message("  row at offset 1 only:    ",
        out$detection$obs_header_with_a_row_at_offset_1)
message("  no row in window:        ",
        out$detection$obs_header_with_no_row_in_window)
message("  🔴 uppercase-only obs:    ", out$detection$obs_header_uppercase_only,
        "   <- missed by every run before 2026-09-08")
message("  neither:                 ", out$detection$neither)
message("\n--- WHERE THE ROWS ARE (per header) ---")
for (nm in names(out$row_offset_distribution))
  message(sprintf("  %-16s %d", nm, out$row_offset_distribution[[nm]]))
message("\n--- STUDIES ---")
message("with any print pattern:    ", out$studies$with_any_print_pattern)
message("⭐ with a corroborated one: ", out$studies$with_a_corroborated_print)
message("\n--- REACHABILITY (no file was read for these) ---")
message("group readable:            ", out$reachability$group_readable)
message("⚠️ other readable:          ", out$reachability$other_readable)
message("owner only:                ", out$reachability$owner_only)
message("in world-traversable dir:  ", out$reachability$in_a_world_traversable_directory)
message("distinct owners:           ", out$reachability$distinct_owners)
message("mode bits look uniform:    ", out$`_provenance`$mode_bits_look_uniform,
        "  (distinct modes: ", out$`_provenance`$distinct_modes, ")")
message("\n--- VOLUME ---")
message("all listings:              ", out$volume$all_listings_gb, " GB")
message("print-matched:             ", out$volume$print_matched_gb, " GB")
message("\nwrote ", outfile)
