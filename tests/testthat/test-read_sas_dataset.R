test_that(".read_sas_dataset reads a sas7bdat faithfully", {
  expected <- .fixture_frame()
  got <- .read_sas_dataset(.fixture_path())

  expect_s3_class(got, "data.frame")
  expect_equal(nrow(got), 4L)
  # Strip both sides: expected$age carries a "label" attribute that the
  # SAS round trip does not preserve identically, and expect_equal()
  # compares attributes. Comparing values is the intent here.
  expect_equal(as.numeric(got$age), as.numeric(expected$age))
  expect_equal(as.character(got$ccfidu), as.character(expected$ccfidu))
})

test_that(".read_sas_dataset rejects unknown extensions and missing files", {
  bad <- withr::local_tempfile(fileext = ".csv")
  writeLines("a,b", bad)
  expect_error(.read_sas_dataset(bad), "Unsupported")

  expect_error(.read_sas_dataset("no/such/file.sas7bdat"), "does not exist")
})
