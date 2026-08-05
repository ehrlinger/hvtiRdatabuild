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
