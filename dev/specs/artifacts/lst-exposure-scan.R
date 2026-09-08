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
  has <- c(heading = FALSE, obs = FALSE)
  repeat {
    lines <- tryCatch(suppressWarnings(readLines(con, n = chunk, warn = FALSE)),
                      error = function(e) character(0))
    if (!length(lines)) break
    keep <- grepl("rocedure|^ *[Oo]bs ", lines)
    if (!any(keep)) { rm(lines, keep); next }
    lines <- tolower(lines[keep])
    if (!has[["heading"]] && any(grepl(RE_HEADING, lines))) has[["heading"]] <- TRUE
    if (!has[["obs"]]     && any(grepl(RE_OBSLINE, lines))) has[["obs"]]     <- TRUE
    if (all(has)) { rm(lines, keep); break }
    rm(lines, keep)
  }
  list(heading = has[["heading"]], obs = has[["obs"]])
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
       heading_only = 0L, obs_only = 0L, both = 0L, neither = 0L)
bytes_all <- 0; bytes_print <- 0
s_any <- character(length(lsts)); s_conf <- character(length(lsts))
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
  k <- if (r$heading && r$obs) "both" else if (r$heading) "heading_only" else
       if (r$obs) "obs_only" else "neither"
  n[[k]] <- n[[k]] + 1L
  if (k != "neither") {
    if (!is.na(sz)) bytes_print <- bytes_print + sz
    if (!is.na(stu[[i]])) s_any[[i]] <- stu[[i]]
    # ⭐ The CONFIDENT population: a procedure heading, not the `obs` heuristic
    # alone. `heading_only` and `both` both qualify.
    if (r$heading && !is.na(stu[[i]])) s_conf[[i]] <- stu[[i]]
  }
  if (i %% 2000 == 0) message("  ", i, " / ", length(lsts))
}

any_print <- n[["heading_only"]] + n[["obs_only"]] + n[["both"]]
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
    # ⭐ The bracket. `both` is confident; `obs_only` is the weakest evidence and
    # is what `lst-listing-scan.R`'s single figure silently folded in.
    both = unname(n[["both"]]),
    heading_only = unname(n[["heading_only"]]),
    obs_only = unname(n[["obs_only"]]),
    neither = unname(n[["neither"]]),
    any_print_pattern = unname(any_print),
    with_a_procedure_heading = unname(n[["both"]] + n[["heading_only"]])
  ),
  studies = list(
    with_any_print_pattern = length(unique(s_any[nzchar(s_any)])),
    with_a_heading_backed_print = length(unique(s_conf[nzchar(s_conf)]))
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
message("\n--- DETECTION (the bracket) ---")
message("read:                      ", out$detection$read)
message("  heading AND obs line:    ", out$detection$both, "   <- confident")
message("  heading only:            ", out$detection$heading_only)
message("  ⚠️ obs line only:         ", out$detection$obs_only, "   <- weakest evidence")
message("  neither:                 ", out$detection$neither)
message("  any print pattern:       ", out$detection$any_print_pattern)
message("\n--- STUDIES ---")
message("with any print pattern:    ", out$studies$with_any_print_pattern)
message("⭐ with heading-backed:     ", out$studies$with_a_heading_backed_print)
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
