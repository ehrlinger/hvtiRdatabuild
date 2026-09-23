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
  expect_error(v(eda_set(vars = c("age", "age"))), "duplicate.*age")
  expect_error(v(eda_set(exclude = list(list(reason = "x")))), "rule 1.*`when`")
  expect_error(v(eda_set(exclude = list(list(reason = "a", when = "age > 1"),
                                        list(reason = "a", when = "age > 2")))),
               "duplicate reason")
  expect_error(v(eda_set(expect = list(rows = 3))), "`expect`.*rows")
  expect_error(v(eda_set(expect = 99)), "`expect`.*named list")
  expect_error(v(eda_set(expect = list(99))), "`expect`.*named list")
  expect_error(v(eda_set(expect = list(n = 18.9))), "`expect: n`.*whole")
  expect_error(v(eda_set(expect = list(n = -1))), "`expect: n`.*non-negative")
  expect_error(v(eda_set(expect = list(n = c(18, 19)))), "`expect: n`.*single")
})

test_that("event is optional, set-local, and required by event counts", {
  cfg <- local_study(list(eda = eda_set()))
  v <- function(b) .set_validate(b, "eda", cfg)
  expect_null(v(eda_set(event = NULL))$event)
  expect_error(v(eda_set(event = c("dead", "age"))), "`event` must name one column")
  expect_error(v(eda_set(event = "")), "`event` must name one column")
  expect_error(v(eda_set(event = "junk")), "event column `junk` is not in `vars`")
  expect_error(v(eda_set(event = NULL, expect = list(n_events = 9))),
               "`expect: n_events` needs an `event`")
  expect_error(v(eda_set(event = NULL, expect = list(n_censored = 9))),
               "`expect: n_censored` needs an `event`")
})

test_that("a set without an event writes only n", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set(event = NULL)))
  side <- write_analysis_set("eda", cfg)
  expect_named(side$counts, "n")
})

test_that("a set may not be named like the built dataset", {
  cfg <- local_study(list(built = eda_set()))
  expect_error(.set_validate(.set_raw("built", cfg), "built", cfg), "same name")
})

test_that("a set may not be named like a registered named dataset", {
  cfg <- local_study(list(eda = eda_set()))
  cfg$additional_datasets <- list(
    eda_source = list(built = "eda.csv", cohort = NULL)
  )

  expect_error(
    .set_validate(.set_raw("eda", cfg), "eda", cfg),
    "registered dataset"
  )
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

test_that("the declaration hash ignores mapping key order", {
  a <- eda_set(expect = list(n = 18, n_events = 9))
  b <- a[c("expect", "exclude", "event", "vars", "id")]
  b$expect <- b$expect[c("n_events", "n")]
  b$exclude <- lapply(b$exclude, function(rule) rule[c("when", "reason")])
  expect_identical(.declaration_sha(a), .declaration_sha(b))
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

test_that("a predicate error never prints identifier values", {
  d <- exclusion_data()
  d$ccfid <- 910001:910006
  b <- rule_block(list(list(reason = "bad rule", when = "stop(ccfid)")))
  err <- expect_error(.apply_exclusions(d, b, "eda"), "evaluation failed")
  leaked <- vapply(as.character(d$ccfid), function(id) {
    grepl(id, err$message, fixed = TRUE)
  }, logical(1))
  expect_false(any(leaked))
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

test_that("tracker scratch columns cannot overwrite built columns", {
  b <- rule_block(list(list(reason = "young", when = "age < 18")))
  for (column in c(".hv_rule_1", ".hv_start", ".hv_reason", ".hv_keep")) {
    d <- exclusion_data()
    d[[column]] <- seq_len(nrow(d))
    expect_error(.apply_exclusions(d, b, "eda"), "reserved scratch column")
  }
})

test_that("write produces parquet, sidecar and manifest entry", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set()))
  side <- write_analysis_set("eda", cfg)
  p <- .set_paths("eda", cfg)
  expect_equal(
    normalizePath(dirname(p$parquet), winslash = "/"),
    normalizePath(file.path(cfg$root, "00_datasets"), winslash = "/")
  )
  expect_true(file.exists(p$parquet))
  expect_true(file.exists(p$sidecar))
  out <- arrow::read_parquet(p$parquet)
  expect_equal(names(out), c("age", "aggrc", "dead", "iv_dead"))
  expect_equal(nrow(out), 18L)  # 20 rows, 1 with NA aggrc, then 1 under 18 not already excluded
  expect_equal(side$counts$n, 18L)
  expect_equal(side$counts$n_events + side$counts$n_censored, 18L)
  m <- yaml::read_yaml(p$manifest)
  expect_true("eda.parquet" %in% vapply(m$datasets, function(e) e$file, character(1)))
})

test_that("write preserves an adopted legacy datasets layout", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set()))
  numbered <- c("00_datasets", "10_descriptive", "20_distributions",
                "30_analyses", "40_graphs", "50_documents",
                "90_estimates")
  legacy <- c("datasets", "descriptive", "distributions", "analyses",
              "graphs", "documents", "estimates")
  for (i in seq_along(numbered)) {
    file.rename(file.path(cfg$root, numbered[[i]]),
                file.path(cfg$root, legacy[[i]]))
  }
  cfg <- hvtiRutilities::study_config(cfg$root)

  write_analysis_set("eda", cfg)

  expect_true(file.exists(file.path(cfg$root, "datasets", "eda.parquet")))
  expect_true(file.exists(file.path(cfg$root, "datasets", "eda.set.yml")))
  expect_false(file.exists(file.path(cfg$root, "00_datasets")))
})

test_that("the sidecar and manifest carry no identifier value", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set()))
  write_analysis_set("eda", cfg)
  p <- .set_paths("eda", cfg)
  side_txt <- readLines(p$sidecar)
  expect_false(any(grepl("ccfid", side_txt)))
  expect_false("ccfid" %in% names(arrow::read_parquet(p$parquet)))
})

test_that("an expect mismatch writes nothing", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set(expect = list(n = 99))))
  expect_error(write_analysis_set("eda", cfg), "expected n = 99, got 18")
  p <- .set_paths("eda", cfg)
  expect_false(file.exists(p$parquet))
  expect_false(file.exists(p$sidecar))
  m <- yaml::read_yaml(p$manifest)
  expect_false("eda.parquet" %in% vapply(m$datasets, function(e) e$file, character(1)))
})

test_that("missing columns and a non-unique id are errors", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(a = eda_set(vars = c("age", "nope"), event = NULL),
                          b = eda_set(id = "junk")))
  expect_error(write_analysis_set("a", cfg), "not in the built dataset: nope")
  expect_error(write_analysis_set("b", cfg), "`junk` is not unique")
})

test_that("attrition is written as one YAML entry per rule", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set()))
  side <- write_analysis_set("eda", cfg)
  p <- .set_paths("eda", cfg)
  expect_equal(side$attrition[[1]]$reason, "No aggrecan")
  expect_equal(side$attrition[[1]]$n_excluded, 1L)
  expect_equal(yaml::read_yaml(p$sidecar)$attrition[[2]]$n_after, 18L)
})

test_that("the parent checkpoint uses a canonical UTC timestamp", {
  cfg <- local_study(list(eda = eda_set()))
  expect_match(.built_state(cfg)$mtime, "Z$")
})

test_that("a built rewrite during materialization writes nothing", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set()))
  original_read <- hvtiRutilities::read_built
  testthat::local_mocked_bindings(
    read_built = function(cfg) {
      out <- original_read(cfg)
      cat("21,70,5,0,3,1\n", file = hvtiRutilities::built_path(cfg), append = TRUE)
      out
    },
    .package = "hvtiRutilities"
  )
  expect_error(write_analysis_set("eda", cfg), "changed while it was being read")
  p <- .set_paths("eda", cfg)
  expect_false(file.exists(p$parquet))
  expect_false(file.exists(p$sidecar))
})

test_that("read round-trips the written set with its attrition", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set()))
  write_analysis_set("eda", cfg)
  d <- read_analysis_set("eda", cfg)
  expect_equal(nrow(d), 18L)
  expect_equal(attr(d, "attrition")$n_excluded, c(1L, 1L))
})

test_that("a no-rule set reads back with typed empty attrition", {
  skip_if_not_installed("arrow")
  cfg <- local_study(list(eda = eda_set(exclude = list())))
  write_analysis_set("eda", cfg)
  attrition <- attr(read_analysis_set("eda", cfg), "attrition")
  expect_s3_class(attrition, "data.frame")
  expect_named(attrition, c("rule", "reason", "n_before", "n_excluded", "n_after"))
  expect_equal(nrow(attrition), 0L)
})

test_that("an unwritten set says how to write it", {
  skip_if_not_installed("arrow")
  cfg <- local_study(list(eda = eda_set()))
  expect_error(read_analysis_set("eda", cfg), 'write_analysis_set\\("eda"\\)')
})

test_that("a rewritten built dataset makes the set stale", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set()))
  write_analysis_set("eda", cfg)
  f <- hvtiRutilities::built_path(cfg)
  cat("21,70,5,0,3,1\n", file = f, append = TRUE)
  expect_error(read_analysis_set("eda", cfg), "built dataset has changed")
})

test_that("an edited rule makes the set stale", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set()))
  write_analysis_set("eda", cfg)
  y <- yaml::read_yaml(cfg$file)
  y$analysis_sets$eda$exclude[[2]]$when <- "age < 21"
  yaml::write_yaml(y, cfg$file)
  expect_error(read_analysis_set("eda", cfg), "declaration .* has changed")
})

test_that("a corrupted parquet fails the integrity check", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set()))
  write_analysis_set("eda", cfg)
  p <- .set_paths("eda", cfg)
  con <- file(p$parquet, "ab")
  writeBin(as.raw(0), con)
  close(con)
  expect_error(read_analysis_set("eda", cfg), "does not match its manifest")
})
