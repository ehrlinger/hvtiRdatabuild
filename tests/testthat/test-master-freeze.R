# No PHI: identifiers and values are invented. Fixtures in helper-master-pull.R.

test_that("a query cohort runs through pull, build and freeze, end to end", {
  f <- local_freeze_setup()
  pull <- pull_demo(f$con, demo_query())
  build <- build_from_master(pull)
  release <- freeze_study_pull(pull, f$config, f$dir, "st0000_pull",
                               extract_date = "2026-11-16")

  expect_identical(tools::file_ext(release$file), "parquet")
  expect_identical(release$n_rows, nrow(build$data))
  prov <- read_pull_provenance(file.path(f$dir, release$file))
  expect_identical(prov$schema, 1L)
  expect_identical(prov$sql_commit, "abc1234")
  expect_setequal(unlist(prov$applied_correction_ids), c("C1", "C2"))
  expect_setequal(unlist(prov$corrections_in_effect), c("C1", "C2"))
  expect_identical(prov$cohort_definition$index, "first")
  expect_identical(unlist(prov$cohort_stages$stage_id),
                   c("qualifying", "prior_qualifying", "in_master"))
  expect_identical(prov$study_config_sha256,
                   digest::digest(f$config, algo = "sha256", file = TRUE))
})

test_that("retrying the same pull returns the same release", {
  f <- local_freeze_setup()
  pull <- pull_demo(f$con, demo_query())
  a <- freeze_study_pull(pull, f$config, f$dir, "st0000_pull", extract_date = "2026-11-16")
  b <- freeze_study_pull(pull, f$config, f$dir, "st0000_pull", extract_date = "2026-11-16")
  expect_identical(a$release_id, b$release_id)
})

test_that("a distinct pull with identical data keeps its own release and record", {
  f <- local_freeze_setup()
  first <- pull_demo(f$con, demo_query())
  DBI::dbExecute(f$con, paste("INSERT INTO master_demo_corrections_applied",
                              "VALUES ('C3', 'SYN104', DATE '2020-01-10')"))
  second <- pull_demo(f$con, demo_query())
  expect_identical(first$data, second$data)

  a <- freeze_study_pull(first, f$config, f$dir, "st0000_pull", extract_date = "2026-11-16")
  b <- freeze_study_pull(second, f$config, f$dir, "st0000_pull",
                         extract_date = "2026-11-16")

  expect_false(identical(a$release_id, b$release_id))
  expect_identical(b$revision, 2L)
  expect_false("C3" %in% unlist(read_pull_provenance(file.path(f$dir, a$file))$
                                  applied_correction_ids))
  expect_true("C3" %in% unlist(read_pull_provenance(file.path(f$dir, b$file))$
                                 applied_correction_ids))
})

test_that("a file without pull provenance is refused", {
  skip_if_not_installed("arrow")
  path <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(data.frame(x = 1), path)
  expect_error(read_pull_provenance(path), "no pull provenance")
})

test_that("only a master_pull is frozen", {
  expect_error(freeze_study_pull(list(), "x", tempdir(), "x"), "master_pull")
})
