#!/usr/bin/env Rscript
# run-phase0.R: snapshot one master build and test its candidate keys.
#
#   Rscript run-phase0.R <sas_path> <out_dir> <n_rows> <n_cols> <keys> [chunk_rows]
#
# <n_rows> and <n_cols> are read by hand from the build's .log. <keys> is a
# semicolon-separated list of comma-separated key columns; prefix a candidate
# with '?' to test it on non-null rows only, e.g.
#   "ccfid,dt_surg;ccfidu;?emrn,dt_enc"
# Prints shape, checksums and key verdicts. No key or value is printed.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "key-verdict.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 5L) {
  stop("usage: run-phase0.R <sas> <out_dir> <n_rows> <n_cols> <keys>")
}
chunk <- if (length(args) >= 6L) as.numeric(args[[6]]) else 1e5
out <- file.path(args[[2]], sub("\\.sas7bdat$", ".parquet", basename(args[[1]])))

info <- hvtiRdatabuild::snapshot_oracle(
  args[[1]], out, chunk_rows = chunk,
  expect = list(n_rows = as.numeric(args[[3]]),
                n_cols = as.numeric(args[[4]])))
message("snapshot  ", info$n_rows, " rows x ", info$n_cols, " columns")
message("parquet   sha256 ", info$sha256)
message("source    sha256 ", info$source_sha256)
message("sidecar   ", info$meta_path)

for (cand in strsplit(args[[5]], ";", fixed = TRUE)[[1]]) {
  nonnull <- startsWith(cand, "?")
  cols <- strsplit(sub("^\\?", "", cand), ",", fixed = TRUE)[[1]]
  message(format_key_verdict(key_verdict(out, cols, nonnull_only = nonnull)))
}
