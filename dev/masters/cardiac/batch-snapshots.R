#!/usr/bin/env Rscript
# batch-snapshots.R: snapshot every dated build in a folder, resumably.
#
#   Rscript batch-snapshots.R <snapshot_dir> <out_dir> [chunk_rows]
#
# Skips a build whose parquet already exists. Historical builds have no retained
# log, so their shape is recorded, not validated (spec §4.2). Appends one row per
# build to <out_dir>/batch-log.csv, then reports whether the undated
# built.sas7bdat matches a dated build's source checksum. Run on the scan host.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) {
  stop("usage: batch-snapshots.R <snapshot_dir> <out_dir> [chunk_rows]")
}
chunk <- if (length(args) >= 3L) as.numeric(args[[3]]) else 1e5
log_path <- file.path(args[[2]], "batch-log.csv")
files <- sort(list.files(args[[1]], pattern = "^built_.*\\.sas7bdat$",
                         full.names = TRUE))

for (f in files) {
  out <- file.path(args[[2]], sub("\\.sas7bdat$", ".parquet", basename(f)))
  if (file.exists(out)) {
    message("skip  ", basename(f))
    next
  }
  row <- tryCatch({
    info <- hvtiRdatabuild::snapshot_oracle(f, out, chunk_rows = chunk)
    data.frame(file = basename(f), n_rows = info$n_rows,
               n_cols = info$n_cols, sha256 = info$sha256,
               source_sha256 = info$source_sha256, status = "ok")
  }, error = function(e) {
    message("FAIL  ", basename(f), ": ", conditionMessage(e))
    data.frame(file = basename(f), n_rows = NA, n_cols = NA, sha256 = NA,
               source_sha256 = NA, status = "failed")
  })
  row$finished <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  utils::write.table(row, log_path, sep = ",", row.names = FALSE,
                     col.names = !file.exists(log_path),
                     append = file.exists(log_path))
  message(row$status, "    ", basename(f), "  ", row$n_rows, " x ",
          row$n_cols)
}

undated <- file.path(args[[1]], "built.sas7bdat")
if (file.exists(undated) && file.exists(log_path)) {
  sha <- digest::digest(undated, algo = "sha256", file = TRUE)
  log <- utils::read.csv(log_path, stringsAsFactors = FALSE)
  hit <- log$file[log$source_sha256 %in% sha]
  message("built.sas7bdat ",
          if (length(hit)) paste("is a copy of", hit[[1]]) else
            "matches no dated build")
}
