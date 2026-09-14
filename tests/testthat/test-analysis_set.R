test_that("an unknown set name lists the declared ones", {
  cfg <- local_study(list(eda = eda_set()))
  expect_error(.set_raw("nope", cfg), "No analysis set `nope`.*Declared: eda")
})

test_that("a study with no analysis_sets says so", {
  cfg <- local_study()
  expect_error(.set_raw("eda", cfg), "Declared: none")
})

test_that("validation rejects unknown keys, missing id/vars, bad rules", {
  cfg <- local_study(list(eda = eda_set()))
  v <- function(b) .set_validate(b, "eda", cfg)
  expect_error(v(eda_set(derive = "x")), "unknown key.*derive")
  expect_error(v(eda_set(id = NULL)), "`id`")
  expect_error(v(eda_set(vars = NULL)), "`vars`")
  expect_error(v(eda_set(exclude = list(list(reason = "x")))), "rule 1.*`when`")
  expect_error(v(eda_set(exclude = list(list(reason = "a", when = "age > 1"),
                                        list(reason = "a", when = "age > 2")))),
               "duplicate reason")
  expect_error(v(eda_set(expect = list(rows = 3))), "`expect`.*rows")
})

test_that("a set may not be named like the built dataset", {
  cfg <- local_study(list(built = eda_set()))
  expect_error(.set_validate(.set_raw("built", cfg), "built", cfg), "same name")
})

test_that("validation normalizes vars to a character vector", {
  cfg <- local_study(list(eda = eda_set()))
  b <- .set_validate(.set_raw("eda", cfg), "eda", cfg)
  expect_type(b$vars, "character")
  expect_equal(b$expect, list())
})

test_that("the declaration hash tracks content and rule order", {
  a <- eda_set()
  expect_identical(.declaration_sha(a), .declaration_sha(eda_set()))
  b <- eda_set(exclude = rev(eda_set()$exclude))
  expect_false(identical(.declaration_sha(a), .declaration_sha(b)))
  expect_match(.declaration_sha(a), "^[0-9a-f]{64}$")
})

test_that("comments and layout in _study.yml do not change the hash", {
  cfg <- local_study(list(eda = eda_set()))
  h1 <- .declaration_sha(.set_raw("eda", cfg))
  old <- readLines(cfg$file)
  # Extra spaces after a real key, whatever its indentation.
  new <- sub("^(\\s*)id:\\s*", "\\1id:      ", old)
  # A comment inside the set block, and one at the top of the file.
  i <- grep("^\\s*eda:\\s*$", new)
  new <- append(new, "    # a comment inside the set block", after = i)
  new <- c("# a comment at the top", new)
  # Guard: the edit must really change the file, or this test proves nothing.
  expect_true(any(grepl("id:      ", new, fixed = TRUE)))
  expect_length(i, 1L)
  writeLines(new, cfg$file)
  h2 <- .declaration_sha(.set_raw("eda", cfg))
  expect_identical(h1, h2)
})
