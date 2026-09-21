test_that("the shared version-1 catalog fixture validates", {
  catalog <- .publication_read_catalog(local_catalog_fixture())

  expect_identical(catalog$format_version, 1L)
  expect_identical(
    catalog$datasets$surgery_cohort$releases[[2L]]$sequence,
    2L
  )
})

test_that("missing catalogs are allowed only for first publication", {
  path <- file.path(local_publication_dir(), "dataset-catalog.yml")

  expect_error(.publication_read_catalog(path), "file not found")
  expect_identical(
    .publication_read_catalog(path, allow_missing = TRUE),
    list(format_version = 1L, datasets = list())
  )
})

test_that("catalog paths are derived from the datasets directory", {
  dir <- local_publication_dir()
  expect_identical(
    .publication_catalog_path(dir),
    file.path(dir, "dataset-catalog.yml")
  )
})

test_that("catalog rejects malformed roots and release fields", {
  cases <- list(
    version = list("format_version", function(x) {
      x$format_version <- 2L
      x
    }),
    dataset_id = list("dataset_id", function(x) {
      names(x$datasets) <- "Surgery Cohort"
      x
    }),
    missing_sha = list("sha256", function(x) {
      x$datasets$surgery_cohort$releases[[1L]]$sha256 <- NULL
      x
    }),
    bad_date = list("extract_date", function(x) {
      x$datasets$surgery_cohort$releases[[1L]]$extract_date <- "2026-02-31"
      x
    }),
    bad_time = list("published_at", function(x) {
      x$datasets$surgery_cohort$releases[[1L]]$published_at <- "2026-09-20 16:00"
      x
    }),
    bad_sha = list("sha256", function(x) {
      x$datasets$surgery_cohort$releases[[1L]]$sha256 <- "abc"
      x
    }),
    bad_sequence = list("sequence", function(x) {
      x$datasets$surgery_cohort$releases[[1L]]$sequence <- 0L
      x
    }),
    fractional_rows = list("n_rows", function(x) {
      x$datasets$surgery_cohort$releases[[1L]]$n_rows <- 1.5
      x
    }),
    empty_columns = list("n_cols", function(x) {
      x$datasets$surgery_cohort$releases[[1L]]$n_cols <- 0L
      x
    }),
    bad_status = list("status", function(x) {
      x$datasets$surgery_cohort$releases[[1L]]$status <- "draft"
      x
    }),
    escaped_file = list("basename", function(x) {
      x$datasets$surgery_cohort$releases[[1L]]$file <- "../cohort.csv"
      x
    })
  )

  for (case in names(cases)) {
    path <- local_catalog_fixture()
    rewrite_catalog(path, cases[[case]][[2L]])
    expect_error(
      .publication_read_catalog(path),
      cases[[case]][[1L]],
      info = case
    )
  }
})

test_that("catalog rejects duplicate and out-of-order identities", {
  cases <- list(
    duplicate_id = list("duplicate release_id", function(x) {
      first <- x$datasets$surgery_cohort$releases[[1L]]$release_id
      x$datasets$surgery_cohort$releases[[2L]]$release_id <- first
      x
    }),
    duplicate_sequence = list("duplicate sequence", function(x) {
      x$datasets$surgery_cohort$releases[[2L]]$sequence <- 1L
      x
    }),
    decreasing_sequence = list("strictly increasing", function(x) {
      x$datasets$surgery_cohort$releases[[1L]]$sequence <- 2L
      x$datasets$surgery_cohort$releases[[2L]]$sequence <- 1L
      x
    }),
    duplicate_file = list("file listed more than once", function(x) {
      first <- x$datasets$surgery_cohort$releases[[1L]]$file
      x$datasets$surgery_cohort$releases[[2L]]$file <- first
      x
    })
  )

  for (case in names(cases)) {
    path <- local_catalog_fixture()
    rewrite_catalog(path, cases[[case]][[2L]])
    expect_error(
      .publication_read_catalog(path),
      cases[[case]][[1L]],
      info = case
    )
  }
})

test_that("catalog revisions are contiguous within each extract date", {
  cases <- list(
    initial = c(2L, 3L),
    duplicate = c(1L, 1L),
    descending = c(2L, 1L),
    skipped = c(1L, 3L)
  )

  for (case in names(cases)) {
    path <- local_catalog_fixture()
    rewrite_catalog(path, function(x) {
      releases <- x$datasets$surgery_cohort$releases
      releases[[2L]]$extract_date <- releases[[1L]]$extract_date
      releases[[1L]]$revision <- cases[[case]][[1L]]
      releases[[2L]]$revision <- cases[[case]][[2L]]
      x$datasets$surgery_cohort$releases <- releases
      x
    })
    expect_error(.publication_read_catalog(path), "revision", info = case)
  }
})

test_that("withdrawn releases require valid withdrawal metadata", {
  path <- local_catalog_fixture()
  rewrite_catalog(path, function(x) {
    x$datasets$surgery_cohort$releases[[1L]]$status <- "withdrawn"
    x
  })
  expect_error(.publication_read_catalog(path), "withdrawal_reason")

  path <- local_catalog_fixture()
  rewrite_catalog(path, function(x) {
    release <- x$datasets$surgery_cohort$releases[[1L]]
    release$status <- "withdrawn"
    release$withdrawal_reason <- "Synthetic fixture correction"
    release$replacement_release_id <- "missing-release"
    x$datasets$surgery_cohort$releases[[1L]] <- release
    x
  })
  expect_error(.publication_read_catalog(path), "replacement_release_id")
})

test_that("publication requests reject unsafe inputs before writing", {
  dir <- local_publication_dir()
  draft <- write_synthetic_draft(dir)
  text <- file.path(dir, "draft.txt")
  writeLines("synthetic", text)
  not_dir <- file.path(dir, "not-a-directory")
  writeLines("synthetic", not_dir)

  expect_error(
    .publication_validate_request(
      file.path(dir, "missing.csv"), "cohort", dir, "2026-09-21"
    ),
    "does not exist"
  )
  expect_error(
    .publication_validate_request(text, "cohort", dir, "2026-09-21"),
    "Unsupported"
  )
  expect_error(
    .publication_validate_request(draft, "Bad ID", dir, "2026-09-21"),
    "dataset_id"
  )
  expect_error(
    .publication_validate_request(draft, "cohort", dir, "2026-02-31"),
    "extract_date"
  )
  expect_error(
    .publication_validate_request(
      draft, "cohort", dir, "2026-09-21", file_stem = "../cohort"
    ),
    "file_stem"
  )
  expect_error(
    .publication_validate_request(draft, "cohort", not_dir, "2026-09-21"),
    "datasets_dir"
  )
})

test_that("request failures do not print synthetic row values", {
  dir <- local_publication_dir()
  draft <- write_synthetic_draft(dir)
  condition <- expect_error(
    .publication_validate_request(draft, "Bad ID", dir, "2026-09-21")
  )

  expect_false(grepl("SYN001", conditionMessage(condition), fixed = TRUE))
})

test_that("staging preserves bytes and derives shape from the staged read", {
  dir <- local_publication_dir()
  draft <- write_synthetic_draft(dir, n = 3L)
  request <- .publication_validate_request(draft, "cohort", dir, "2026-09-21")
  staged <- .publication_stage_draft(request)
  withr::defer(unlink(staged$path))

  expect_identical(
    digest::digest(staged$path, algo = "sha256", file = TRUE),
    digest::digest(draft, algo = "sha256", file = TRUE)
  )
  expect_identical(staged$sha256, digest::digest(draft, algo = "sha256", file = TRUE))
  expect_identical(staged$n_rows, 3L)
  expect_identical(staged$n_cols, 3L)
  expect_identical(staged$extension, "csv")
})

test_that("staging re-reads the copied bytes after initial draft validation", {
  dir <- local_publication_dir()
  draft <- write_synthetic_draft(dir, n = 3L)
  request <- .publication_validate_request(draft, "cohort", dir, "2026-09-21")
  real_read <- hvtiRutilities::read_clinical_data
  reads <- 0L
  testthat::local_mocked_bindings(
    read_clinical_data = function(file, ...) {
      out <- real_read(file, ...)
      reads <<- reads + 1L
      if (reads == 1L) {
        write_synthetic_draft(dir, n = 4L)
      }
      out
    },
    .package = "hvtiRutilities"
  )

  staged <- .publication_stage_draft(request)
  withr::defer(unlink(staged$path))

  expect_identical(reads, 2L)
  expect_identical(staged$n_rows, 4L)
  expect_identical(staged$sha256, digest::digest(draft, algo = "sha256", file = TRUE))
})

test_that("release identity increments sequence and date-local revision", {
  dir <- local_publication_dir()
  draft <- write_synthetic_draft(dir)
  request <- .publication_validate_request(
    draft,
    "surgery_cohort",
    dir,
    "2026-09-21",
    file_stem = "cohort"
  )
  empty <- list(format_version = 1L, datasets = list())
  first <- .publication_identity(empty, request)

  expect_identical(first$sequence, 1L)
  expect_identical(first$revision, 1L)
  expect_identical(first$release_id, "surgery_cohort-20260921-r1")
  expect_identical(first$file, "cohort_20260921.csv")

  catalog <- .publication_read_catalog(local_catalog_fixture())
  same_day <- .publication_identity(catalog, request)
  expect_identical(same_day$sequence, 3L)
  expect_identical(same_day$revision, 2L)
  expect_identical(same_day$file, "cohort_20260921_r2.csv")

  request$extract_date <- "2026-09-22"
  later <- .publication_identity(catalog, request)
  expect_identical(later$sequence, 3L)
  expect_identical(later$revision, 1L)
  expect_identical(later$release_id, "surgery_cohort-20260922-r1")
  expect_identical(later$file, "cohort_20260922.csv")
})
