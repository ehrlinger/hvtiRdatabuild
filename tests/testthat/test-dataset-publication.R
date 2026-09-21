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

test_that("first publication creates immutable bytes and a catalog record", {
  dir <- local_publication_dir()
  draft <- write_synthetic_draft(dir, n = 3L)
  draft_sha <- digest::digest(draft, algo = "sha256", file = TRUE)

  expect_invisible(
    publish_dataset(draft, "cohort", dir, extract_date = "2026-09-21")
  )

  catalog <- .publication_read_catalog(.publication_catalog_path(dir))
  release <- catalog$datasets$cohort$releases[[1L]]
  release_path <- file.path(dir, release$file)
  expect_identical(release$release_id, "cohort-20260921-r1")
  expect_identical(release$sequence, 1L)
  expect_identical(release$revision, 1L)
  expect_identical(release$file, "cohort_20260921.csv")
  expect_identical(release$sha256, draft_sha)
  expect_identical(release$n_rows, 3L)
  expect_identical(release$n_cols, 3L)
  expect_identical(release$status, "published")
  expect_null(release$source)
  expect_null(release$draft)
  expect_identical(
    readBin(release_path, "raw", n = file.info(release_path)$size),
    readBin(draft, "raw", n = file.info(draft)$size)
  )
  expect_length(list.files(dir, pattern = "^\\.publish-", all.files = TRUE), 0L)
})

test_that("publication assigns same-day revisions and later-date identity", {
  dir <- local_publication_dir()
  first_draft <- write_synthetic_draft(dir, "first.csv", n = 3L)
  second_draft <- write_synthetic_draft(dir, "second.csv", n = 4L)
  third_draft <- write_synthetic_draft(dir, "third.csv", n = 5L)

  first <- publish_dataset(
    first_draft, "cohort", dir, "2026-09-21", source = "Synthetic build 1"
  )
  second <- publish_dataset(second_draft, "cohort", dir, "2026-09-21")
  third <- publish_dataset(third_draft, "cohort", dir, "2026-09-22")

  expect_identical(first$file, "cohort_20260921.csv")
  expect_identical(first$source, "Synthetic build 1")
  expect_identical(second$file, "cohort_20260921_r2.csv")
  expect_identical(second$sequence, 2L)
  expect_identical(second$revision, 2L)
  expect_identical(third$file, "cohort_20260922.csv")
  expect_identical(third$sequence, 3L)
  expect_identical(third$revision, 1L)
})

test_that("publishing identical same-date bytes is idempotent", {
  dir <- local_publication_dir()
  draft <- write_synthetic_draft(dir)

  first <- publish_dataset(draft, "cohort", dir, "2026-09-21")
  second <- publish_dataset(draft, "cohort", dir, "2026-09-21")
  catalog <- .publication_read_catalog(.publication_catalog_path(dir))

  expect_identical(second, first)
  expect_length(catalog$datasets$cohort$releases, 1L)
  expect_identical(list.files(dir, pattern = "^cohort_.*\\.csv$"), first$file)
})

test_that("publishing withdrawn bytes preserves the withdrawn release", {
  dir <- local_publication_dir()
  draft <- write_synthetic_draft(dir)

  first <- publish_dataset(draft, "cohort", dir, "2026-09-21")
  withdrawn <- withdraw_dataset_release(
    "cohort", first$release_id, dir, "Synthetic source correction"
  )
  repeated <- publish_dataset(draft, "cohort", dir, "2026-09-21")
  catalog <- .publication_read_catalog(.publication_catalog_path(dir))

  expect_identical(repeated, withdrawn)
  expect_identical(repeated$status, "withdrawn")
  expect_length(catalog$datasets$cohort$releases, 1L)
  expect_identical(list.files(dir, pattern = "^cohort_.*\\.csv$"), first$file)
})

test_that("publication refuses different bytes at the next final filename", {
  dir <- local_publication_dir()
  first_draft <- write_synthetic_draft(dir, "first.csv", n = 3L)
  next_draft <- write_synthetic_draft(dir, "next.csv", n = 4L)
  publish_dataset(first_draft, "cohort", dir, "2026-09-21")
  collision <- file.path(dir, "cohort_20260921_r2.csv")
  writeLines("different synthetic bytes", collision)
  collision_sha <- digest::digest(collision, algo = "sha256", file = TRUE)
  catalog_before <- readLines(.publication_catalog_path(dir))

  expect_error(
    publish_dataset(next_draft, "cohort", dir, "2026-09-21"),
    "different bytes"
  )

  expect_identical(digest::digest(collision, algo = "sha256", file = TRUE), collision_sha)
  expect_identical(readLines(.publication_catalog_path(dir)), catalog_before)
  expect_length(list.files(dir, pattern = "^\\.publish-", all.files = TRUE), 0L)
})

test_that("retry registers a matching orphan without rewriting it", {
  dir <- local_publication_dir()
  draft <- write_synthetic_draft(dir)
  orphan <- file.path(dir, "cohort_20260921.csv")

  testthat::with_mocked_bindings(
    expect_error(
      publish_dataset(draft, "cohort", dir, "2026-09-21"),
      "unregistered orphan"
    ),
    .publication_write_catalog = function(...) stop("injected catalog failure"),
    .package = "hvtiRdatabuild"
  )
  expect_true(file.exists(orphan))
  expect_false(file.exists(.publication_catalog_path(dir)))
  orphan_sha <- digest::digest(orphan, algo = "sha256", file = TRUE)
  orphan_mtime <- file.info(orphan)$mtime

  release <- publish_dataset(draft, "cohort", dir, "2026-09-21")

  expect_identical(release$sha256, orphan_sha)
  expect_identical(file.info(orphan)$mtime, orphan_mtime)
  catalog <- .publication_read_catalog(.publication_catalog_path(dir))
  expect_length(catalog$datasets$cohort$releases, 1L)
})

test_that("orphan recovery rejects a symbolic link outside datasets_dir", {
  dir <- local_publication_dir()
  outside <- local_publication_dir()
  draft <- write_synthetic_draft(outside)
  orphan <- file.path(dir, "cohort_20260921.csv")
  if (!file.symlink(draft, orphan)) {
    testthat::skip("This platform cannot create the test symbolic link")
  }

  expect_error(
    publish_dataset(draft, "cohort", dir, "2026-09-21"),
    "symbolic link"
  )

  expect_identical(Sys.readlink(orphan), draft)
  expect_false(file.exists(.publication_catalog_path(dir)))
})

test_that("concurrent publications serialize catalog identity", {
  testthat::skip_on_os("windows")
  dir <- local_publication_dir()
  drafts <- c(
    write_synthetic_draft(dir, "first.csv", n = 3L),
    write_synthetic_draft(dir, "second.csv", n = 4L)
  )

  results <- parallel::mclapply(
    drafts,
    function(draft) {
      tryCatch(
        publish_dataset(draft, "cohort", dir, "2026-09-21"),
        error = function(error) error
      )
    },
    mc.cores = 2L
  )

  expect_false(any(vapply(results, inherits, logical(1), "error")))
  catalog <- .publication_read_catalog(.publication_catalog_path(dir))
  releases <- catalog$datasets$cohort$releases
  expect_identical(vapply(releases, function(x) x$sequence, integer(1)), 1:2)
  expect_identical(vapply(releases, function(x) x$revision, integer(1)), 1:2)
  expect_length(unique(vapply(releases, function(x) x$file, character(1))), 2L)
  for (release in releases) {
    expect_identical(
      digest::digest(file.path(dir, release$file), algo = "sha256", file = TRUE),
      release$sha256
    )
  }
})

test_that("withdrawal changes only catalog metadata", {
  dir <- local_publication_dir()
  draft <- write_synthetic_draft(dir)
  published <- publish_dataset(draft, "cohort", dir, "2026-09-21")
  release_path <- file.path(dir, published$file)
  bytes_before <- readBin(release_path, "raw", n = file.info(release_path)$size)
  sha_before <- digest::digest(release_path, algo = "sha256", file = TRUE)
  mtime_before <- file.info(release_path)$mtime

  expect_invisible(
    withdraw_dataset_release(
      "cohort",
      published$release_id,
      dir,
      reason = "Synthetic source correction"
    )
  )

  expect_true(file.exists(release_path))
  expect_identical(
    readBin(release_path, "raw", n = file.info(release_path)$size),
    bytes_before
  )
  expect_identical(digest::digest(release_path, algo = "sha256", file = TRUE), sha_before)
  expect_identical(file.info(release_path)$mtime, mtime_before)
  catalog <- .publication_read_catalog(.publication_catalog_path(dir))
  withdrawn <- catalog$datasets$cohort$releases[[1L]]
  expect_identical(withdrawn$status, "withdrawn")
  expect_identical(withdrawn$withdrawal_reason, "Synthetic source correction")
})

test_that("withdrawal validates identity, reason and replacement", {
  dir <- local_publication_dir()
  first_draft <- write_synthetic_draft(dir, "first.csv", n = 3L)
  second_draft <- write_synthetic_draft(dir, "second.csv", n = 4L)
  other_draft <- write_synthetic_draft(dir, "other.csv", n = 5L)
  first <- publish_dataset(first_draft, "cohort", dir, "2026-09-21")
  second <- publish_dataset(second_draft, "cohort", dir, "2026-09-22")
  other <- publish_dataset(other_draft, "imaging", dir, "2026-09-21")

  expect_error(
    withdraw_dataset_release("cohort", first$release_id, dir, ""),
    "reason"
  )
  expect_error(
    withdraw_dataset_release("missing", first$release_id, dir, "Synthetic correction"),
    "dataset_id"
  )
  expect_error(
    withdraw_dataset_release("cohort", "missing-release", dir, "Synthetic correction"),
    "release_id"
  )
  expect_error(
    withdraw_dataset_release(
      "cohort", first$release_id, dir, "Synthetic correction",
      replacement_release_id = "missing-release"
    ),
    "replacement_release_id"
  )
  expect_error(
    withdraw_dataset_release(
      "cohort", first$release_id, dir, "Synthetic correction",
      replacement_release_id = other$release_id
    ),
    "replacement_release_id"
  )
  expect_error(
    withdraw_dataset_release(
      "cohort", first$release_id, dir, "Synthetic correction",
      replacement_release_id = first$release_id
    ),
    "itself"
  )

  withdrawn <- withdraw_dataset_release(
    "cohort",
    first$release_id,
    dir,
    "Synthetic correction",
    replacement_release_id = second$release_id
  )
  expect_identical(withdrawn$replacement_release_id, second$release_id)
  expect_error(
    withdraw_dataset_release("cohort", first$release_id, dir, "Again"),
    "already withdrawn"
  )
})

test_that("withdrawal and publication serialize without losing either change", {
  testthat::skip_on_os("windows")
  dir <- local_publication_dir()
  first_draft <- write_synthetic_draft(dir, "first.csv", n = 3L)
  second_draft <- write_synthetic_draft(dir, "second.csv", n = 4L)
  first <- publish_dataset(first_draft, "cohort", dir, "2026-09-21")

  results <- parallel::mclapply(
    c("withdraw", "publish"),
    function(operation) {
      tryCatch(
        if (identical(operation, "withdraw")) {
          withdraw_dataset_release(
            "cohort", first$release_id, dir, "Synthetic correction"
          )
        } else {
          publish_dataset(second_draft, "cohort", dir, "2026-09-22")
        },
        error = function(error) error
      )
    },
    mc.cores = 2L
  )

  expect_false(any(vapply(results, inherits, logical(1), "error")))
  catalog <- .publication_read_catalog(.publication_catalog_path(dir))
  releases <- catalog$datasets$cohort$releases
  expect_length(releases, 2L)
  expect_identical(releases[[1L]]$status, "withdrawn")
  expect_identical(releases[[2L]]$status, "published")
})
