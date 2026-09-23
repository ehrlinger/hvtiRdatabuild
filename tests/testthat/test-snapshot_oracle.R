test_that("snapshot_oracle writes parquet and reports a stable checksum", {
  skip_if_not_installed("arrow")

  out <- withr::local_tempfile(fileext = ".parquet")
  res <- snapshot_oracle(
    .fixture_path(),
    out
  )

  expect_true(file.exists(out))
  expect_equal(res$n_rows, 4L)
  expect_equal(res$n_cols, 5L)
  expect_setequal(res$variables,
                  c("ccfidu", "age", "bmi", "dt_surg", "surgeon"))
  expect_match(res$sha256, "^[0-9a-f]{64}$")

  # Idempotent: same input yields the same checksum.
  out2 <- withr::local_tempfile(fileext = ".parquet")
  res2 <- snapshot_oracle(
    .fixture_path(),
    out2
  )
  expect_equal(res$sha256, res2$sha256)
})

test_that("snapshot_oracle round-trips variable labels", {
  skip_if_not_installed("arrow")

  out <- withr::local_tempfile(fileext = ".parquet")
  snapshot_oracle(
    .fixture_path(),
    out
  )
  back <- as.data.frame(arrow::read_parquet(out))
  expect_equal(attr(back$age, "label"), "Age at surgery")
})

test_that("snapshot_oracle refuses to overwrite silently", {
  skip_if_not_installed("arrow")

  out <- withr::local_tempfile(fileext = ".parquet")
  writeLines("x", out)
  expect_error(
    snapshot_oracle(
      .fixture_path(),
      out
    ),
    "already exists"
  )
})

test_that("snapshot_oracle validates against PROC CONTENTS expectations", {
  skip_if_not_installed("arrow")
  src <- .fixture_path()

  ok <- withr::local_tempfile(fileext = ".parquet")
  expect_silent(
    snapshot_oracle(src, ok, expect = list(n_rows = 4, n_cols = 5))
  )

  bad <- withr::local_tempfile(fileext = ".parquet")
  expect_error(
    snapshot_oracle(src, bad, expect = list(n_rows = 99)),
    "n_rows is 4 but SAS reported 99"
  )
  expect_false(file.exists(bad))

  bad2 <- withr::local_tempfile(fileext = ".parquet")
  expect_error(
    snapshot_oracle(src, bad2, expect = list(variables = c("ccfidu", "nope"))),
    "variable sets differ"
  )

  bad3 <- withr::local_tempfile(fileext = ".parquet")
  expect_error(
    snapshot_oracle(src, bad3, expect = list(n_row = 4)),
    "Unknown 'expect' element"
  )
})

test_that("snapshot_oracle records the snapshot in a manifest", {
  skip_if_not_installed("arrow")

  dir <- withr::local_tempdir()
  out <- file.path(dir, "oracle.parquet")
  man <- file.path(dir, "manifest.yaml")

  res <- snapshot_oracle(.fixture_path(), out, manifest = man)

  expect_true(file.exists(man))
  entries <- yaml::read_yaml(man)
  expect_true(length(entries) >= 1)

  # verify_manifest() re-hashes the file; an untouched oracle verifies clean.
  # It returns a data frame with columns: file, status ("OK"/"FAIL"), message.
  ok <- hvtiRutilities::verify_manifest(
    manifest_path = man, data_dir = dir, stop_on_error = FALSE
  )
  expect_true(all(ok$status == "OK"))

  # A drifted oracle is detected. This is the spec requirement that an oracle
  # whose recorded checksum no longer matches the file is an error.
  writeLines("corrupted", out)
  # Capture the warning explicitly. Letting it escape into the suite would
  # mask a future unexpected warning behind this expected one.
  expect_warning(
    drifted <- hvtiRutilities::verify_manifest(
      manifest_path = man, data_dir = dir, stop_on_error = FALSE
    ),
    "SHA-256 mismatch"
  )
  expect_true(any(drifted$status == "FAIL"))
})

test_that("chunked snapshot reads back identical to the unchunked one", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")

  whole <- withr::local_tempfile(fileext = ".parquet")
  parts <- withr::local_tempfile(fileext = ".parquet")
  snapshot_oracle(.fixture_path(), whole)
  res <- snapshot_oracle(.fixture_path(), parts, chunk_rows = 3)

  expect_equal(res$n_rows, 4L)
  expect_equal(arrow::ParquetFileReader$create(parts)$num_row_groups, 2L)
  a <- as.data.frame(arrow::read_parquet(whole))
  b <- as.data.frame(arrow::read_parquet(parts))
  expect_equal(b, a)
  expect_equal(attr(b$age, "label"), "Age at surgery")
})

test_that("a chunk size that divides the rows exactly still counts every row", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")

  out <- withr::local_tempfile(fileext = ".parquet")
  res <- snapshot_oracle(.fixture_path(), out, chunk_rows = 2)
  expect_equal(res$n_rows, 4L)
  expect_equal(arrow::ParquetFileReader$create(out)$num_row_groups, 2L)
})

test_that("the sidecar records both checksums and every column", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")

  out <- withr::local_tempfile(fileext = ".parquet")
  res <- snapshot_oracle(.fixture_path(), out)

  expect_equal(res$source_sha256,
               digest::digest(.fixture_path(), algo = "sha256", file = TRUE))
  expect_true(file.exists(res$meta_path))
  meta <- jsonlite::read_json(res$meta_path, simplifyVector = TRUE)
  expect_equal(meta$source_sha256, res$source_sha256)
  expect_equal(meta$parquet_sha256, res$sha256)
  expect_equal(meta$n_rows, 4L)
  expect_setequal(meta$columns$variable,
                  c("ccfidu", "age", "bmi", "dt_surg", "surgeon"))
  expect_equal(meta$columns$label[meta$columns$variable == "age"], "Age at surgery")
  expect_equal(meta$columns$sas_type[meta$columns$variable == "surgeon"], "character")
})

test_that("snapshot_oracle refuses to overwrite an existing sidecar", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")

  out <- withr::local_tempfile(fileext = ".parquet")
  writeLines("{}", sub("\\.parquet$", ".meta.json", out))
  expect_error(snapshot_oracle(.fixture_path(), out), "sidecar already exists")
})

test_that("chunk_rows must be a single positive number", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")

  out <- withr::local_tempfile(fileext = ".parquet")
  expect_error(snapshot_oracle(.fixture_path(), out, chunk_rows = 0), "chunk_rows")
  expect_error(snapshot_oracle(.fixture_path(), out, chunk_rows = c(1, 2)), "chunk_rows")
})

test_that("a failed validation removes the chunked output", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")

  out <- withr::local_tempfile(fileext = ".parquet")
  expect_error(snapshot_oracle(.fixture_path(), out, expect = list(n_rows = 5),
                               chunk_rows = 3),
               "n_rows is 4")
  expect_false(file.exists(out))
})

test_that("a chunk whose schema differs from the first is an error", {
  skip_if_not_installed("arrow")

  expect_error(
    .check_chunk_schema(arrow::schema(a = arrow::float64()),
                        arrow::schema(a = arrow::utf8()), 10),
    "row 11"
  )
})
