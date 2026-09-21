# Dataset publication: producer-owned immutable release state.
# Design: hvtiRutilities/dev/specs/2026-09-21-dataset-release-contract-design.md.

.publication_abort <- function(message) {
  stop("dataset catalog: ", message, call. = FALSE)
}

.publication_catalog_path <- function(datasets_dir) {
  file.path(datasets_dir, "dataset-catalog.yml")
}

.publication_scalar <- function(x, name, type = "character") {
  valid <- length(x) == 1L && !is.na(x)
  if (valid && identical(type, "character")) {
    valid <- is.character(x) && nzchar(x)
  }
  if (valid && identical(type, "integer")) {
    valid <- is.numeric(x) && is.finite(x) &&
      x >= -.Machine$integer.max && x <= .Machine$integer.max &&
      x == as.integer(x)
  }
  if (!valid) {
    .publication_abort(paste0(name, " is invalid"))
  }
  if (identical(type, "integer")) as.integer(x) else x
}

.publication_named_mapping <- function(x, name) {
  has_names <- !is.null(names(x)) && length(names(x)) == length(x) &&
    all(nzchar(names(x))) && !anyDuplicated(names(x))
  if (!is.list(x) || (length(x) && !has_names)) {
    .publication_abort(paste0(name, " must be a named mapping"))
  }
  x
}

.publication_valid_date <- function(x) {
  parsed <- suppressWarnings(as.Date(x, format = "%Y-%m-%d"))
  !is.na(parsed) && identical(format(parsed, "%Y-%m-%d"), x)
}

.publication_valid_timestamp <- function(x) {
  shape <- grepl(
    paste0(
      "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}",
      "(Z|[+-][0-9]{2}:[0-9]{2})$"
    ),
    x
  )
  compact <- sub("Z$", "+0000", x)
  compact <- sub("([+-][0-9]{2}):([0-9]{2})$", "\\1\\2", compact)
  parsed <- suppressWarnings(strptime(
    compact,
    format = "%Y-%m-%dT%H:%M:%S%z",
    tz = "UTC"
  ))
  shape && !is.na(parsed)
}

.publication_validate_release <- function(release, dataset_id, index) {
  where <- paste0("datasets.", dataset_id, ".releases[", index, "]")
  if (!is.list(release)) {
    .publication_abort(paste0(where, " must be a mapping"))
  }
  required <- c(
    "release_id", "sequence", "file", "extract_date", "revision",
    "published_at", "sha256", "n_rows", "n_cols", "status"
  )
  missing <- required[!vapply(required, function(field) {
    !is.null(release[[field]])
  }, logical(1))]
  if (length(missing)) {
    .publication_abort(paste0(where, " is missing ", paste(missing, collapse = ", ")))
  }

  release$release_id <- .publication_scalar(
    release$release_id,
    paste0(where, ".release_id")
  )
  valid_release_id <- grepl("^[a-z0-9][a-z0-9_-]*$", release$release_id) &&
    !identical(release$release_id, "latest")
  if (!valid_release_id) {
    .publication_abort(paste0(where, ".release_id is invalid"))
  }

  for (field in c("sequence", "revision", "n_rows", "n_cols")) {
    release[[field]] <- .publication_scalar(
      release[[field]],
      paste0(where, ".", field),
      "integer"
    )
  }
  if (release$sequence < 1L) {
    .publication_abort(paste0(where, ".sequence must be positive"))
  }
  if (release$revision < 1L) {
    .publication_abort(paste0(where, ".revision must be positive"))
  }
  if (release$n_rows < 0L) {
    .publication_abort(paste0(where, ".n_rows must be non-negative"))
  }
  if (release$n_cols < 1L) {
    .publication_abort(paste0(where, ".n_cols must be positive"))
  }

  release$file <- .publication_scalar(release$file, paste0(where, ".file"))
  if (!identical(basename(release$file), release$file) ||
      !nzchar(tools::file_ext(release$file))) {
    .publication_abort(paste0(where, ".file must be one basename with an extension"))
  }
  release$extract_date <- .publication_scalar(
    release$extract_date,
    paste0(where, ".extract_date")
  )
  if (!.publication_valid_date(release$extract_date)) {
    .publication_abort(paste0(where, ".extract_date is invalid"))
  }
  release$published_at <- .publication_scalar(
    release$published_at,
    paste0(where, ".published_at")
  )
  if (!.publication_valid_timestamp(release$published_at)) {
    .publication_abort(paste0(where, ".published_at is invalid"))
  }
  release$sha256 <- .publication_scalar(release$sha256, paste0(where, ".sha256"))
  if (!grepl("^[0-9a-f]{64}$", release$sha256)) {
    .publication_abort(paste0(where, ".sha256 is invalid"))
  }
  release$status <- .publication_scalar(release$status, paste0(where, ".status"))
  if (!release$status %in% c("published", "withdrawn")) {
    .publication_abort(paste0(where, ".status is invalid"))
  }
  if (!is.null(release$source)) {
    release$source <- .publication_scalar(release$source, paste0(where, ".source"))
  }
  if (identical(release$status, "withdrawn")) {
    release$withdrawal_reason <- .publication_scalar(
      release$withdrawal_reason,
      paste0(where, ".withdrawal_reason")
    )
  }
  if (!is.null(release$replacement_release_id)) {
    release$replacement_release_id <- .publication_scalar(
      release$replacement_release_id,
      paste0(where, ".replacement_release_id")
    )
    valid_replacement <- grepl(
      "^[a-z0-9][a-z0-9_-]*$",
      release$replacement_release_id
    ) && !identical(release$replacement_release_id, "latest")
    if (!valid_replacement) {
      .publication_abort(paste0(where, ".replacement_release_id is invalid"))
    }
  }
  release
}

.publication_read_catalog <- function(path, allow_missing = FALSE) {
  if (!file.exists(path)) {
    if (isTRUE(allow_missing)) {
      return(list(format_version = 1L, datasets = list()))
    }
    .publication_abort(paste0("file not found: ", path))
  }

  catalog <- yaml::read_yaml(path)
  if (!is.list(catalog)) {
    .publication_abort("root must be a mapping")
  }
  version <- .publication_scalar(catalog$format_version, "format_version", "integer")
  if (!identical(version, 1L)) {
    .publication_abort(paste0("unsupported format_version: ", version))
  }
  datasets <- .publication_named_mapping(catalog$datasets, "datasets")

  for (dataset_id in names(datasets)) {
    if (!grepl("^[a-z][a-z0-9_]*$", dataset_id)) {
      .publication_abort(paste0("invalid dataset_id: ", dataset_id))
    }
    dataset <- datasets[[dataset_id]]
    if (!is.list(dataset) || !is.list(dataset$releases) || !length(dataset$releases)) {
      .publication_abort(paste0(
        "datasets.", dataset_id, ".releases must be a non-empty sequence"
      ))
    }
    releases <- lapply(seq_along(dataset$releases), function(index) {
      .publication_validate_release(dataset$releases[[index]], dataset_id, index)
    })
    ids <- vapply(releases, function(release) release$release_id, character(1))
    sequences <- vapply(releases, function(release) release$sequence, integer(1))
    if (anyDuplicated(ids)) {
      .publication_abort(paste0(
        "datasets.", dataset_id, ".releases contains a duplicate release_id"
      ))
    }
    if (anyDuplicated(sequences)) {
      .publication_abort(paste0(
        "datasets.", dataset_id, ".releases contains a duplicate sequence"
      ))
    }
    if (length(sequences) > 1L && any(diff(sequences) <= 0L)) {
      .publication_abort(paste0(
        "datasets.", dataset_id, ".releases sequence must be strictly increasing"
      ))
    }
    dates <- vapply(releases, function(release) release$extract_date, character(1))
    for (date in unique(dates)) {
      revisions <- vapply(
        releases[dates == date],
        function(release) release$revision,
        integer(1)
      )
      if (!identical(revisions, seq_along(revisions))) {
        .publication_abort(paste0(
          "datasets.", dataset_id,
          ".releases revision must start at 1 and increase by 1 for extract_date ",
          date
        ))
      }
    }
    replacements <- vapply(releases, function(release) {
      if (is.null(release$replacement_release_id)) "" else release$replacement_release_id
    }, character(1))
    unknown <- setdiff(replacements[nzchar(replacements)], ids)
    if (length(unknown)) {
      .publication_abort(paste0(
        "datasets.", dataset_id, " has unknown replacement_release_id: ",
        paste(unknown, collapse = ", ")
      ))
    }
    dataset$releases <- releases
    datasets[[dataset_id]] <- dataset
  }

  files <- unlist(lapply(datasets, function(dataset) {
    vapply(dataset$releases, function(release) release$file, character(1))
  }), use.names = FALSE)
  repeated <- unique(files[duplicated(files)])
  if (length(repeated)) {
    .publication_abort(paste0(
      "file listed more than once: ", paste(repeated, collapse = ", ")
    ))
  }

  catalog$format_version <- version
  catalog$datasets <- datasets
  catalog
}

.publication_validate_request <- function(draft, dataset_id, datasets_dir,
                                          extract_date, source = NULL,
                                          file_stem = dataset_id) {
  if (!is.character(draft) || length(draft) != 1L || is.na(draft) || !nzchar(draft)) {
    stop("`draft` must be one non-empty file path.", call. = FALSE)
  }
  if (!file.exists(draft)) {
    stop("Draft dataset does not exist: ", draft, call. = FALSE)
  }
  if (!is.character(dataset_id) || length(dataset_id) != 1L ||
      is.na(dataset_id) || !grepl("^[a-z][a-z0-9_]*$", dataset_id)) {
    stop(
      "`dataset_id` must use lower-case letters, digits and underscores, ",
      "starting with a letter.",
      call. = FALSE
    )
  }
  if (!is.character(datasets_dir) || length(datasets_dir) != 1L ||
      is.na(datasets_dir) || !dir.exists(datasets_dir)) {
    stop("`datasets_dir` must be one existing directory.", call. = FALSE)
  }
  if (!is.character(file_stem) || length(file_stem) != 1L ||
      is.na(file_stem) || !grepl("^[a-z][a-z0-9_-]*$", file_stem)) {
    stop(
      "`file_stem` must be a safe basename using lower-case letters, digits, ",
      "underscores or hyphens, starting with a letter.",
      call. = FALSE
    )
  }
  if (!is.null(source) && (!is.character(source) || length(source) != 1L ||
      is.na(source) || !nzchar(source))) {
    stop("`source` must be NULL or one non-empty string.", call. = FALSE)
  }

  date <- if (inherits(extract_date, "Date") && length(extract_date) == 1L &&
      !is.na(extract_date)) {
    format(extract_date, "%Y-%m-%d")
  } else if (is.character(extract_date) && length(extract_date) == 1L &&
      !is.na(extract_date)) {
    extract_date
  } else {
    NA_character_
  }
  if (is.na(date) || !.publication_valid_date(date)) {
    stop("`extract_date` must be one valid ISO date.", call. = FALSE)
  }

  extension <- tolower(tools::file_ext(draft))
  supported <- c("sas7bdat", "csv", "xlsx", "xls", "rds")
  if (!extension %in% supported) {
    stop(
      "Unsupported draft extension '.", extension, "'. Supported: ",
      paste0(".", supported, collapse = ", "), ".",
      call. = FALSE
    )
  }

  list(
    draft = draft,
    dataset_id = dataset_id,
    datasets_dir = datasets_dir,
    extract_date = date,
    source = source,
    file_stem = file_stem,
    extension = extension
  )
}

.publication_stage_draft <- function(request) {
  hvtiRutilities::read_clinical_data(request$draft, convert_types = FALSE)
  staged_path <- tempfile(
    pattern = ".publish-",
    tmpdir = request$datasets_dir,
    fileext = paste0(".", request$extension)
  )
  if (!file.copy(request$draft, staged_path, overwrite = FALSE)) {
    stop("Could not stage draft dataset in ", request$datasets_dir, ".", call. = FALSE)
  }
  staged <- tryCatch(
    hvtiRutilities::read_clinical_data(staged_path, convert_types = FALSE),
    error = function(error) {
      unlink(staged_path)
      stop(conditionMessage(error), call. = FALSE)
    }
  )
  list(
    path = staged_path,
    extension = request$extension,
    sha256 = digest::digest(staged_path, algo = "sha256", file = TRUE),
    n_rows = as.integer(nrow(staged)),
    n_cols = as.integer(ncol(staged))
  )
}

.publication_identity <- function(catalog, request) {
  dataset <- catalog$datasets[[request$dataset_id]]
  releases <- if (is.null(dataset)) list() else dataset$releases
  sequence <- if (length(releases)) {
    max(vapply(releases, function(release) release$sequence, integer(1))) + 1L
  } else {
    1L
  }
  dates <- if (length(releases)) {
    vapply(releases, function(release) release$extract_date, character(1))
  } else {
    character()
  }
  revision <- sum(dates == request$extract_date) + 1L
  compact_date <- gsub("-", "", request$extract_date, fixed = TRUE)
  suffix <- if (revision == 1L) "" else paste0("_r", revision)

  list(
    release_id = paste0(request$dataset_id, "-", compact_date, "-r", revision),
    sequence = as.integer(sequence),
    revision = as.integer(revision),
    file = paste0(
      request$file_stem, "_", compact_date, suffix, ".", request$extension
    )
  )
}

.with_catalog_lock <- function(path, code, timeout = 10000) {
  lock_path <- paste0(path, ".lock")
  lock <- filelock::lock(lock_path, timeout = timeout)
  if (is.null(lock)) {
    stop("Timed out waiting for dataset catalog lock: ", lock_path, call. = FALSE)
  }
  on.exit(filelock::unlock(lock), add = TRUE)
  force(code)
}

.publication_write_catalog <- function(catalog, path) {
  tmp <- tempfile(pattern = ".catalog-", tmpdir = dirname(path), fileext = ".yml")
  on.exit(unlink(tmp), add = TRUE)
  yaml::write_yaml(catalog, tmp)
  .publication_read_catalog(tmp)
  if (!file.rename(tmp, path)) {
    stop("Could not atomically replace dataset catalog: ", path, call. = FALSE)
  }
  invisible(path)
}

.publication_timestamp <- function(time = Sys.time()) {
  paste0(format(time, "%Y-%m-%dT%H:%M:%S", tz = "UTC"), "Z")
}

.publication_existing_release <- function(catalog, request, staged) {
  dataset <- catalog$datasets[[request$dataset_id]]
  if (is.null(dataset)) {
    return(NULL)
  }
  matches <- vapply(dataset$releases, function(release) {
    identical(release$extract_date, request$extract_date) &&
      identical(release$sha256, staged$sha256) &&
      identical(release$status, "published")
  }, logical(1))
  if (!any(matches)) {
    return(NULL)
  }
  release <- dataset$releases[[tail(which(matches), 1L)]]
  path <- file.path(request$datasets_dir, release$file)
  actual <- if (file.exists(path)) {
    digest::digest(path, algo = "sha256", file = TRUE)
  } else {
    NA_character_
  }
  if (is.na(actual)) {
    stop("Published release is missing: ", path, call. = FALSE)
  }
  if (!identical(actual, release$sha256)) {
    stop(
      "Published release changed in place: ", path,
      "\n  expected: ", release$sha256,
      "\n  actual:   ", actual,
      call. = FALSE
    )
  }
  release
}

.publication_record <- function(identity, request, staged) {
  release <- list(
    release_id = identity$release_id,
    sequence = identity$sequence,
    file = identity$file,
    extract_date = request$extract_date,
    revision = identity$revision,
    published_at = .publication_timestamp(),
    sha256 = staged$sha256,
    n_rows = staged$n_rows,
    n_cols = staged$n_cols,
    status = "published"
  )
  if (!is.null(request$source)) {
    release$source <- request$source
  }
  release
}

.publication_append <- function(catalog, dataset_id, release) {
  if (is.null(catalog$datasets[[dataset_id]])) {
    catalog$datasets[[dataset_id]] <- list(releases = list())
  }
  catalog$datasets[[dataset_id]]$releases <- append(
    catalog$datasets[[dataset_id]]$releases,
    list(release)
  )
  catalog
}

#' Publish an immutable dataset release
#'
#' @param draft Path to a mutable draft dataset.
#' @param dataset_id Stable logical dataset identifier.
#' @param datasets_dir Directory that owns published files and the catalog.
#' @param extract_date Extract date as a `Date` or ISO date string.
#' @param source Optional publisher provenance.
#' @param file_stem Basename stem for dated release files.
#'
#' @return Invisibly, the published release record.
#'
#' @export
publish_dataset <- function(draft, dataset_id, datasets_dir,
                            extract_date = Sys.Date(), source = NULL,
                            file_stem = dataset_id) {
  request <- .publication_validate_request(
    draft,
    dataset_id,
    datasets_dir,
    extract_date,
    source,
    file_stem
  )
  staged <- .publication_stage_draft(request)
  on.exit(unlink(staged$path), add = TRUE)
  catalog_path <- .publication_catalog_path(request$datasets_dir)

  release <- .with_catalog_lock(catalog_path, {
    catalog <- .publication_read_catalog(catalog_path, allow_missing = TRUE)
    existing <- .publication_existing_release(catalog, request, staged)
    if (!is.null(existing)) {
      existing
    } else {
      identity <- .publication_identity(catalog, request)
      final_path <- file.path(request$datasets_dir, identity$file)
      if (file.exists(final_path)) {
        actual <- digest::digest(final_path, algo = "sha256", file = TRUE)
        if (!identical(actual, staged$sha256)) {
          stop(
            "Refusing to replace published filename with different bytes: ",
            final_path,
            "\n  staged:   ", staged$sha256,
            "\n  existing: ", actual,
            call. = FALSE
          )
        }
      } else if (!file.rename(staged$path, final_path)) {
        stop("Could not move staged release to ", final_path, ".", call. = FALSE)
      }

      candidate <- .publication_record(identity, request, staged)
      updated <- .publication_append(catalog, request$dataset_id, candidate)
      tryCatch(
        .publication_write_catalog(updated, catalog_path),
        error = function(error) {
          stop(
            "Published bytes remain as an unregistered orphan: ", final_path,
            ". Retry the same publication to complete registration.\n",
            "Catalog error: ", conditionMessage(error),
            call. = FALSE
          )
        }
      )
      candidate
    }
  })
  invisible(release)
}
