# Runs only when HVTI_ORACLE_DIR points at real SAS datasets. That directory
# holds PHI and lives outside this repository; nothing here copies from it.
#
#   HVTI_ORACLE_DIR=/studies/st1234/datasets Rscript -e 'devtools::test()'
#
# Assertions are on shape and verdicts only. No patient value may appear in a
# failure message.

.oracle_dir <- function() Sys.getenv("HVTI_ORACLE_DIR", unset = "")

skip_unless_real_oracle <- function() {
  skip_if_not_installed("arrow")
  d <- .oracle_dir()
  skip_if(!nzchar(d), "HVTI_ORACLE_DIR not set; skipping real-study tests.")
  skip_if(!dir.exists(d), paste0("HVTI_ORACLE_DIR does not exist: ", d))
  invisible(d)
}

test_that("a real SAS dataset reads and snapshots", {
  dir <- skip_unless_real_oracle()
  src <- file.path(dir, "built.sas7bdat")
  skip_if(!file.exists(src), "No built.sas7bdat in HVTI_ORACLE_DIR.")

  out <- withr::local_tempfile(fileext = ".parquet")
  res <- snapshot_oracle(src, out)

  # Shape only. Never print or assert on a value.
  expect_gt(res$n_rows, 0L)
  expect_gt(res$n_cols, 0L)
  expect_match(res$sha256, "^[0-9a-f]{64}$")
  expect_true(file.exists(out))
})

test_that("a real dataset compared against itself is wholly identical", {
  dir <- skip_unless_real_oracle()
  src <- file.path(dir, "built.sas7bdat")
  skip_if(!file.exists(src), "No built.sas7bdat in HVTI_ORACLE_DIR.")

  d <- haven::read_sas(src)
  id <- if ("ccfidu" %in% names(d)) "ccfidu" else names(d)[1]
  skip_if(anyDuplicated(d[[id]]) > 0,
          paste0("Identifier '", id, "' is not unique in this study."))

  res <- compare_built(d, d, id = id)

  # Report counts, never values, so a failure leaks nothing.
  offending <- sum(res$verdict != "identical")
  expect_equal(
    offending, 0L,
    info = paste0(offending, " variable(s) not identical to themselves; ",
                  "this indicates a defect in the comparison primitives, ",
                  "not in the data.")
  )
})

test_that("real-study output carries no identifiers by default", {
  dir <- skip_unless_real_oracle()
  src <- file.path(dir, "built.sas7bdat")
  skip_if(!file.exists(src), "No built.sas7bdat in HVTI_ORACLE_DIR.")

  d <- haven::read_sas(src)
  id <- if ("ccfidu" %in% names(d)) "ccfidu" else names(d)[1]
  skip_if(anyDuplicated(d[[id]]) > 0, "Identifier is not unique.")

  half <- d[seq_len(max(1, floor(nrow(d) / 2))), , drop = FALSE]
  res  <- compare_built(d, half, id = id)
  out  <- paste(capture.output(print(res)), collapse = "\n")

  dropped <- attr(res, "rows")$only_oracle
  skip_if(length(dropped) == 0, "No dropped ids to check.")
  expect_false(grepl(as.character(dropped[1]), out, fixed = TRUE))
})
