# Helpers for test-rubric.R. No PHI.

# Each deprecation warns once per session; clear the record so every test sees it.
fresh_deprecations <- function(env = parent.frame()) {
  rm(list = ls(.deprecation_seen), envir = .deprecation_seen)
  withr::defer(rm(list = ls(.deprecation_seen), envir = .deprecation_seen), envir = env)
}

# The family's conformance check for a provenance record.
expect_provenance_record <- function(p) {
  fields <- c("package", "version", "sha", "method", "seed", "rng_kind", "time")
  testthat::expect_true(all(fields %in% names(p)))
  testthat::expect_true(is.character(p$package) && length(p$package) == 1L)
  testthat::expect_true(is.character(p$version) && length(p$version) == 1L)
  testthat::expect_true(is.character(p$sha) && length(p$sha) == 1L)
  testthat::expect_true(is.character(p$method) && length(p$method) >= 1L)
  testthat::expect_true(is.integer(p$seed) && length(p$seed) == 1L)
  testthat::expect_true(is.character(p$rng_kind) && length(p$rng_kind) == 3L)
  testthat::expect_true(inherits(p$time, "POSIXct") && length(p$time) == 1L)
}
