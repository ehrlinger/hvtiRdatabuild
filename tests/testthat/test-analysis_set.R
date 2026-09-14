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

exclusion_data <- function() {
  data.frame(ccfid = 1:6, age = c(10, 15, 40, NA, 50, 60),
             aggrc = c(NA, 1, NA, 2, 3, 4))
}
rule_block <- function(rules) {
  list(id = "ccfid", vars = "age", exclude = rules, expect = list())
}

test_that("first match wins and attrition counts each rule once", {
  skip_if_not_installed("hvtiPlotR")
  b <- rule_block(list(list(reason = "No aggrecan", when = "is.na(aggrc)"),
                       list(reason = "Under 18", when = "age < 18")))
  ex <- .apply_exclusions(exclusion_data(), b, "eda")
  # row 1 matches both rules: counted under rule 1 only
  expect_equal(ex$attrition$n_excluded, c(2L, 1L))
  expect_equal(ex$attrition$n_before, c(6L, 4L))
  expect_equal(ex$attrition$n_after, c(4L, 3L))
  expect_equal(ex$keep, c(FALSE, FALSE, FALSE, TRUE, TRUE, TRUE))
})

test_that("NA in a predicate excludes nothing", {
  skip_if_not_installed("hvtiPlotR")
  b <- rule_block(list(list(reason = "Under 18", when = "age < 18")))
  ex <- .apply_exclusions(exclusion_data(), b, "eda")
  expect_true(ex$keep[4])  # age is NA
})

test_that("a predicate cannot see the global environment", {
  skip_if_not_installed("hvtiPlotR")
  assign("hv_test_cutoff", 18, envir = globalenv())
  withr::defer(rm("hv_test_cutoff", envir = globalenv()))
  b <- rule_block(list(list(reason = "Young", when = "age < hv_test_cutoff")))
  expect_error(.apply_exclusions(exclusion_data(), b, "eda"),
               "analysis set `eda`, rule 1.*hv_test_cutoff")
})

test_that("bad predicates are named", {
  skip_if_not_installed("hvtiPlotR")
  d <- exclusion_data()
  expect_error(.apply_exclusions(d, rule_block(list(list(reason = "x", when = "age <"))),
                                 "eda"), "rule 1.*does not parse")
  expect_error(.apply_exclusions(d, rule_block(list(list(reason = "x", when = "age"))),
                                 "eda"), "rule 1.*one TRUE/FALSE per row")
})

test_that("no rules keeps every row and needs no hvtiPlotR", {
  ex <- .apply_exclusions(exclusion_data(), rule_block(list()), "eda")
  expect_true(all(ex$keep))
  expect_equal(nrow(ex$attrition), 0L)
})

test_that("write produces parquet, sidecar and manifest entry", {
  skip_if_not_installed("arrow"); skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set()))
  side <- write_analysis_set("eda", cfg)
  p <- .set_paths("eda", cfg)
  expect_true(file.exists(p$parquet)); expect_true(file.exists(p$sidecar))
  out <- arrow::read_parquet(p$parquet)
  expect_equal(names(out), c("age", "aggrc", "dead", "iv_dead"))
  expect_equal(nrow(out), 18L)  # 20 rows, 1 with NA aggrc, then 1 under 18 not already excluded
  expect_equal(side$counts$n, 18L)
  expect_equal(side$counts$n_events + side$counts$n_censored, 18L)
  m <- yaml::read_yaml(p$manifest)
  expect_true("eda.parquet" %in% vapply(m$datasets, function(e) e$file, character(1)))
})

test_that("the sidecar and manifest carry no identifier value", {
  skip_if_not_installed("arrow"); skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set()))
  write_analysis_set("eda", cfg)
  p <- .set_paths("eda", cfg)
  side_txt <- readLines(p$sidecar)
  expect_false(any(grepl("ccfid", side_txt)))
  expect_false("ccfid" %in% names(arrow::read_parquet(p$parquet)))
})

test_that("an expect mismatch writes nothing", {
  skip_if_not_installed("arrow"); skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set(expect = list(n = 99))))
  expect_error(write_analysis_set("eda", cfg), "expected n = 99, got 18")
  p <- .set_paths("eda", cfg)
  expect_false(file.exists(p$parquet)); expect_false(file.exists(p$sidecar))
  m <- yaml::read_yaml(p$manifest)
  expect_false("eda.parquet" %in% vapply(m$datasets, function(e) e$file, character(1)))
})

test_that("missing columns and a non-unique id are errors", {
  skip_if_not_installed("arrow"); skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(a = eda_set(vars = c("age", "nope")),
                          b = eda_set(id = "junk")))
  expect_error(write_analysis_set("a", cfg), "not in the built dataset: nope")
  expect_error(write_analysis_set("b", cfg), "`junk` is not unique")
})

test_that("attrition is written as one YAML entry per rule", {
  skip_if_not_installed("arrow"); skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set()))
  side <- write_analysis_set("eda", cfg)
  p <- .set_paths("eda", cfg)
  expect_equal(side$attrition[[1]]$reason, "No aggrecan")
  expect_equal(side$attrition[[1]]$n_excluded, 1L)
  expect_equal(yaml::read_yaml(p$sidecar)$attrition[[2]]$n_after, 18L)
})
