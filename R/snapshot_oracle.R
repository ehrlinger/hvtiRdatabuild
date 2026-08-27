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
#' Note that this does not remove \pkg{haven} from the chain of custody — it
#' confines it to a single audited step. A misread is faithfully preserved in
#' the parquet file. Supply `expect` to validate the conversion against
#' SAS-side `PROC CONTENTS` output.
#'
#' @param sas_path Path to the SAS dataset (`.sas7bdat`).
#' @param out_path Path to write the parquet file. Must not already exist.
#' @param expect Optional named list validating the conversion, with any of
#'   `n_rows`, `n_cols`, and `variables`. Supply values read from SAS-side
#'   `PROC CONTENTS`. A mismatch is an error.
#' @param manifest Optional path to a manifest YAML. When supplied, the
#'   snapshot is recorded with [hvtiRutilities::update_manifest()] so that
#'   [hvtiRutilities::verify_manifest()] can later detect a drifted oracle.
#'
#' @return Invisibly, a list with elements `path`, `n_rows`, `n_cols`,
#'   `variables`, and `sha256`.
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
                            manifest = NULL) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("Package 'arrow' is required to write oracle snapshots. ",
         "Install it with install.packages('arrow').", call. = FALSE)
  }
  if (file.exists(out_path)) {
    stop("Oracle snapshot already exists: ", out_path,
         ". Refusing to overwrite; delete it explicitly if that is intended.",
         call. = FALSE)
  }

  d <- .read_sas_dataset(sas_path)

  info <- list(
    path      = out_path,
    n_rows    = nrow(d),
    n_cols    = ncol(d),
    variables = names(d)
  )

  .validate_snapshot(info, expect)

  arrow::write_parquet(d, out_path)
  info$sha256 <- digest::digest(out_path, algo = "sha256", file = TRUE)

  if (!is.null(manifest)) {
    # n_rows is passed explicitly: hvtiRutilities:::.auto_count_rows() refuses
    # to guess row counts for a '.parquet', and that refusal is correct.
    hvtiRutilities::update_manifest(
      file          = out_path,
      manifest_path = manifest,
      n_rows        = info$n_rows,
      source        = paste0("Oracle snapshot of ", basename(sas_path))
    )
  }

  invisible(info)
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
