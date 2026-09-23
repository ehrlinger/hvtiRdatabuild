#' Read a SAS dataset
#'
#' Internal reader used by [snapshot_oracle()]. Reads the `.sas7bdat` files a
#' SAS `libname` writes. This is the only point in the package where a SAS
#' format is touched, and it is read-only: nothing here ever writes SAS.
#'
#' @param path Path to a `.sas7bdat` file.
#' @param skip Rows to skip before reading. Passed to [haven::read_sas()].
#' @param n_max Maximum rows to read. Passed to [haven::read_sas()].
#'
#' @return A data frame.
#'
#' @keywords internal
#' @noRd
.read_sas_dataset <- function(path, skip = 0L, n_max = Inf) {
  if (!file.exists(path)) {
    stop("SAS dataset does not exist: ", path, call. = FALSE)
  }
  ext <- tolower(tools::file_ext(path))
  if (!identical(ext, "sas7bdat")) {
    stop("Unsupported SAS dataset extension '.", ext,
         "'. Expected '.sas7bdat'.", call. = FALSE)
  }
  as.data.frame(haven::read_sas(path, skip = skip, n_max = n_max))
}
