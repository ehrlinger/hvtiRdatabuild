#' Freeze a SAS-built dataset as a checksummed parquet oracle
#'
#' Reads a SAS dataset once with \pkg{haven}, writes it as parquet, and
#' returns a record of what was written including a SHA-256 checksum of the
#' parquet file.
#'
#' The snapshot exists so that equivalence testing has a fixed reference. A
#' SAS-built dataset on a shared volume can be regenerated at any time; if it
#' changes mid-migration, every previously passing comparison silently becomes
#' meaningless. A checksummed snapshot is a citable fixed point.
#'
#' Note that this does not remove \pkg{haven} from the chain of custody; it
#' confines it to a single audited step. A misread is faithfully preserved in
#' the parquet file. Supply `expect` to validate the conversion against
#' SAS-side `PROC CONTENTS` output.
#'
#' Writing the sidecar needs \pkg{jsonlite}.
#'
#' @param sas_path Path to the SAS dataset (`.sas7bdat`).
#' @param out_path Path to write the parquet file. Must not already exist.
#' @param expect Optional named list validating the conversion, with any of
#'   `n_rows`, `n_cols`, and `variables`. Supply values read from SAS-side
#'   `PROC CONTENTS`. A mismatch is an error.
#' @param manifest Optional path to a manifest YAML. When supplied, the
#'   snapshot is recorded with [hvtiRutilities::update_manifest()] so that
#'   [hvtiRutilities::verify_manifest()] can later detect a drifted oracle.
#' @param chunk_rows Optional single positive number. When supplied, the SAS
#'   dataset is read and written this many rows at a time, as parquet row
#'   groups in one file, so a dataset too large to hold in memory can be
#'   snapshotted. A chunk whose schema differs from the first chunk's is an
#'   error, and the partial file is removed. The chunked file reads back
#'   identical to an unchunked one, but its bytes and checksum differ, because
#'   its row groups differ.
#'
#' @return Invisibly, a list with elements `path`, `n_rows`, `n_cols`,
#'   `variables`, `sha256` (of the parquet file), `source_sha256` (of the SAS
#'   dataset) and `meta_path`. The metadata sidecar at `meta_path` records
#'   both checksums, the shape, and each column's label, SAS format, SAS type
#'   and R class, so the metadata survives into systems that cannot read R's
#'   attributes.
#'
#' @seealso [compare_built()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("arrow", quietly = TRUE)) {
#'   src <- system.file("extdata", "oracle_small.sas7bdat",
#'                      package = "hvtiRdatabuild")
#'   snapshot_oracle(src, tempfile(fileext = ".parquet"))
#' }
#' }
#'
#' @export
snapshot_oracle <- function(sas_path, out_path, expect = NULL,
                            manifest = NULL, chunk_rows = NULL) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("Package 'arrow' is required to write oracle snapshots. ",
         "Install it with install.packages('arrow').", call. = FALSE)
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package 'jsonlite' is required to write the snapshot's metadata ",
         "sidecar. Install it with install.packages('jsonlite').", call. = FALSE)
  }
  if (!is.null(chunk_rows) &&
        (!is.numeric(chunk_rows) || length(chunk_rows) != 1L ||
           is.na(chunk_rows) || chunk_rows < 1)) {
    stop("'chunk_rows' must be NULL or a single positive number.", call. = FALSE)
  }
  if (file.exists(out_path)) {
    stop("Oracle snapshot already exists: ", out_path,
         ". Refusing to overwrite; delete it explicitly if that is intended.",
         call. = FALSE)
  }
  meta_path <- .snapshot_meta_path(out_path)
  if (file.exists(meta_path)) {
    stop("Snapshot metadata sidecar already exists: ", meta_path,
         ". Refusing to overwrite; delete it explicitly if that is intended.",
         call. = FALSE)
  }

  if (is.null(chunk_rows)) {
    d <- .read_sas_dataset(sas_path)
    info <- list(path = out_path, n_rows = nrow(d), n_cols = ncol(d),
                 variables = names(d))
    .validate_snapshot(info, expect)
    arrow::write_parquet(d, out_path)
  } else {
    written <- .write_chunked(sas_path, out_path, as.integer(chunk_rows))
    d <- written$first
    info <- list(path = out_path, n_rows = written$n_rows, n_cols = ncol(d),
                 variables = names(d))
    tryCatch(.validate_snapshot(info, expect), error = function(e) {
      unlink(out_path)
      stop(e)
    })
  }

  info$sha256 <- digest::digest(out_path, algo = "sha256", file = TRUE)
  info$source_sha256 <- digest::digest(sas_path, algo = "sha256", file = TRUE)
  info$meta_path <- meta_path
  jsonlite::write_json(.snapshot_meta(d, info, sas_path), meta_path,
                       auto_unbox = TRUE, null = "null", pretty = TRUE)

  if (!is.null(manifest)) {
    # n_rows is passed explicitly: hvtiRutilities:::.auto_count_rows() refuses
    # to guess row counts for a '.parquet', and that refusal is correct.
    hvtiRutilities::update_manifest(
      file          = out_path,
      manifest_path = manifest,
      n_rows        = info$n_rows,
      source        = paste0("Oracle snapshot of ", basename(sas_path),
                             " (source sha256 ", info$source_sha256, ")")
    )
  }

  invisible(info)
}

#' Write a SAS dataset to one parquet file, a chunk of rows at a time
#'
#' @param sas_path Path to the SAS dataset.
#' @param out_path Path of the parquet file to create.
#' @param chunk_rows Integer. Rows per chunk, and per row group.
#'
#' @return A list with `n_rows`, the rows written, and `first`, the first
#'   chunk as a data frame, which carries the labels and formats.
#'
#' @keywords internal
#' @noRd
.write_chunked <- function(sas_path, out_path, chunk_rows) {
  first <- .read_sas_dataset(sas_path, skip = 0L, n_max = chunk_rows)
  first_tbl <- arrow::arrow_table(first)
  schema <- first_tbl$schema

  sink <- arrow::FileOutputStream$create(out_path)
  writer <- arrow::ParquetFileWriter$create(
    schema, sink,
    properties = arrow::ParquetWriterProperties$create(names(schema))
  )
  ok <- FALSE
  on.exit({
    writer$Close()
    sink$close()
    if (!ok) unlink(out_path)
  }, add = TRUE)

  writer$WriteTable(first_tbl, chunk_size = chunk_rows)
  n_rows <- nrow(first)
  last_n <- nrow(first)
  while (last_n == chunk_rows) {
    chunk <- .read_sas_dataset(sas_path, skip = n_rows, n_max = chunk_rows)
    last_n <- nrow(chunk)
    if (last_n == 0L) break
    tbl <- arrow::arrow_table(chunk)
    .check_chunk_schema(schema, tbl$schema, n_rows)
    writer$WriteTable(tbl, chunk_size = chunk_rows)
    n_rows <- n_rows + last_n
  }
  ok <- TRUE
  list(n_rows = n_rows, first = first)
}

#' Stop when a chunk's schema differs from the first chunk's
#'
#' @param expected,got Arrow schemas.
#' @param at_row Integer. Rows written before this chunk.
#'
#' @return `NULL`, invisibly. Called for the error it raises.
#'
#' @keywords internal
#' @noRd
.check_chunk_schema <- function(expected, got, at_row) {
  if (!got$Equals(expected, check_metadata = FALSE)) {
    stop("The chunk starting at row ", at_row + 1, " has a different schema ",
         "from the first chunk. A SAS column's type cannot change within a ",
         "file, so this is a reader defect; the partial parquet is removed.",
         call. = FALSE)
  }
  invisible(NULL)
}

#' The sidecar path for a parquet snapshot
#'
#' @param out_path Path of the parquet file.
#'
#' @return The path with `.parquet` replaced by `.meta.json`.
#'
#' @keywords internal
#' @noRd
.snapshot_meta_path <- function(out_path) {
  paste0(sub("\\.parquet$", "", out_path, ignore.case = TRUE), ".meta.json")
}

#' The sidecar contents for a snapshot
#'
#' @param d Data frame holding at least the first rows, with attributes.
#' @param info The snapshot record, with both checksums.
#' @param sas_path Path to the SAS dataset.
#'
#' @return A list ready for [jsonlite::write_json()].
#'
#' @keywords internal
#' @noRd
.snapshot_meta <- function(d, info, sas_path) {
  one_attr <- function(x, which) {
    a <- attr(x, which, exact = TRUE)
    if (is.null(a)) NULL else as.character(a)[[1]]
  }
  columns <- lapply(names(d), function(v) {
    x <- d[[v]]
    list(variable   = v,
         label      = one_attr(x, "label"),
         sas_format = one_attr(x, "format.sas"),
         sas_type   = if (is.character(x)) "character" else "numeric",
         r_class    = class(x)[[1]])
  })
  list(source = basename(sas_path), source_sha256 = info$source_sha256,
       parquet = basename(info$path), parquet_sha256 = info$sha256,
       n_rows = info$n_rows, n_cols = info$n_cols, columns = columns)
}

#' Validate a snapshot against SAS-side PROC CONTENTS
#'
#' @param info List produced by [snapshot_oracle()].
#' @param expect Optional named list; see [snapshot_oracle()].
#'
#' @return `NULL`, invisibly. Called for the error it raises.
#'
#' @keywords internal
#' @noRd
.validate_snapshot <- function(info, expect) {
  if (is.null(expect)) {
    return(invisible(NULL))
  }
  known <- c("n_rows", "n_cols", "variables")
  unknown <- setdiff(names(expect), known)
  if (length(unknown)) {
    stop("Unknown 'expect' element(s): ", paste(unknown, collapse = ", "),
         ". Expected any of: ", paste(known, collapse = ", "), call. = FALSE)
  }

  for (k in c("n_rows", "n_cols")) {
    if (!is.null(expect[[k]]) && !identical(as.integer(expect[[k]]),
                                            as.integer(info[[k]]))) {
      stop("Snapshot validation failed: ", k, " is ", info[[k]],
           " but SAS reported ", expect[[k]], ".", call. = FALSE)
    }
  }

  if (!is.null(expect$variables)) {
    missing_r  <- setdiff(expect$variables, info$variables)
    missing_sas <- setdiff(info$variables, expect$variables)
    if (length(missing_r) || length(missing_sas)) {
      stop("Snapshot validation failed: variable sets differ. ",
           "In SAS but not snapshot: ",
           if (length(missing_r)) paste(missing_r, collapse = ", ") else "none",
           ". In snapshot but not SAS: ",
           if (length(missing_sas)) paste(missing_sas, collapse = ", ") else "none",
           ".", call. = FALSE)
    }
  }

  invisible(NULL)
}
