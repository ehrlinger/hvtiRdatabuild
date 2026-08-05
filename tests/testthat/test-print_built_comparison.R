test_that("print summarises verdicts and row differences", {
  o <- data.frame(ccfidu = c("A1", "A2"), age = c(65, 70), gone = c(1, 2))
  r <- data.frame(ccfidu = c("A1", "A3"), age = c(65, 99))

  res <- compare_built(o, r, id = "ccfidu")
  out <- paste(capture.output(print(res)), collapse = "\n")

  expect_match(out, "Dataset comparison")
  expect_match(out, "rows: 2 oracle, 2 R, 1 common")
  expect_match(out, "only in oracle: 1")
  expect_match(out, "only in R: 1")
  expect_match(out, "absent_in_r")
})

test_that("print never emits identifiers by default", {
  # ccfidu is MRN + date of surgery. It must not reach output unasked.
  o <- data.frame(ccfidu = c("1234567820200115", "A2"), age = c(65, 70))
  r <- data.frame(ccfidu = c("A2", "9876543220190302"), age = c(70, 55))

  res <- compare_built(o, r, id = "ccfidu")
  out <- paste(capture.output(print(res)), collapse = "\n")

  expect_false(grepl("1234567820200115", out, fixed = TRUE))
  expect_false(grepl("9876543220190302", out, fixed = TRUE))
  expect_match(out, "only in oracle: 1")

  # But they remain reachable for a caller who needs them.
  expect_equal(attr(res, "rows")$only_oracle, "1234567820200115")
})

test_that("print emits identifiers only on explicit opt-in", {
  o <- data.frame(ccfidu = c("1234567820200115", "A2"), age = c(65, 70))
  r <- data.frame(ccfidu = "A2", age = 70)

  res <- compare_built(o, r, id = "ccfidu")
  out <- paste(capture.output(print(res, show_ids = TRUE)), collapse = "\n")

  expect_match(out, "1234567820200115", fixed = TRUE)
})

test_that("print never emits an overall pass or fail", {
  d <- data.frame(ccfidu = "A1", age = 1)
  out <- paste(capture.output(print(compare_built(d, d, id = "ccfidu"))),
               collapse = "\n")
  # Case-insensitive, so a future "Pass"/"ok" would also be caught. Word
  # boundaries keep "ok" from matching inside ordinary words.
  expect_false(grepl("\\b(pass|fail|ok)\\b", out, ignore.case = TRUE))
})

test_that("str() does not print identifiers", {
  # str() dispatches on the object, not through print.built_comparison(), so
  # the default method would dump the rows attribute verbatim. str() is typed
  # reflexively and its output gets pasted into issues and logs, so the
  # disclosure here is incidental rather than requested.
  o <- data.frame(ccfidu = c("1234567820200115", "A2"), age = c(65, 70))
  r <- data.frame(ccfidu = c("A2", "9876543220190302"), age = c(70, 55))
  res <- compare_built(o, r, id = "ccfidu")

  out <- paste(capture.output(str(res)), collapse = "\n")
  expect_false(grepl("1234567820200115", out, fixed = TRUE))
  expect_false(grepl("9876543220190302", out, fixed = TRUE))

  # Counts still reported, so the method stays useful.
  expect_match(out, "1 only in oracle")

  # Deliberate retrieval is unchanged.
  expect_equal(attr(res, "rows")$only_oracle, "1234567820200115")
})

test_that("compare_built returns no scalar verdict field", {
  d <- data.frame(ccfidu = "A1", age = 1)
  res <- compare_built(d, d, id = "ccfidu")
  expect_false(any(c("passed", "ok", "equivalent") %in% names(attributes(res))))
  expect_true(is.data.frame(res))
})
