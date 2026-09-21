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
