# Synthetic, no PHI: ccfidu here is a made-up MRN + date-of-surgery-shaped
# string, invented for the test, never a real identifier.
.fake_pull_result <- function() {
  tables <- list(
    bdbase = data.frame(ccfidu = c("1234567820200115", "9876543220190302"),
                        age    = c(65, 70)),
    fup    = data.frame(ccfidu = "1234567820200115", fup_days = 30)
  )
  manifest <- data.frame(
    module    = c("base", "fup"),
    output    = c("bdbase", "fup"),
    n_rows    = c(2L, 1L),
    n_cols    = c(2L, 2L),
    pulled_at = rep(as.POSIXct("2026-08-04 09:00:00", tz = "UTC"), 2),
    stringsAsFactors = FALSE
  )
  structure(list(tables = tables, manifest = manifest), class = "pull_result")
}

test_that("print reports the module count and the manifest rows", {
  res <- .fake_pull_result()
  out <- paste(capture.output(print(res)), collapse = "\n")

  expect_match(out, "2 module\\(s\\)")
  expect_match(out, "base")
  expect_match(out, "fup")
  expect_match(out, "bdbase")
  expect_match(out, "2", fixed = TRUE)
})

test_that("print never emits a patient value from the pulled tables", {
  res <- .fake_pull_result()
  out <- paste(capture.output(print(res)), collapse = "\n")

  expect_false(grepl("1234567820200115", out, fixed = TRUE))
  expect_false(grepl("9876543220190302", out, fixed = TRUE))
})

test_that("print returns its argument invisibly", {
  res <- .fake_pull_result()
  invisible(capture.output(ret <- print(res)))

  expect_identical(withVisible(print(res))$visible, FALSE)
  expect_identical(ret, res)
})
