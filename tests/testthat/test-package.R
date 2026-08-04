test_that("package loads and declares its dependencies", {
  expect_true(requireNamespace("hvtiRdatasets", quietly = TRUE))
  expect_true(requireNamespace("hvtiRutilities", quietly = TRUE))
})
