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

# --- S1: pull-stage oracles -------------------------------------------------
# The pull writes permanent datasets alongside `built`. Each is an oracle in
# its own right, so S1 is measurable without waiting for S2.

.pull_oracles <- c("bdbase", "bdstat", "echo", "fup", "bdevents")

.find_pull_oracle <- function(dir, stem) {
  # SAS names carry a pull date and are not consistently stem-first: bdbase,
  # bdstat, and bdevents are written stem_mmddyy, but echo and fup are
  # written study-prefixed (stXXXX_echo, stXXXX_fup). Match the stem anywhere
  # in the filename so both conventions are found; no study prefix is
  # hardcoded.
  hits <- list.files(dir, pattern = paste0(stem, ".*\\.sas7bdat$"),
                     full.names = TRUE)
  if (length(hits) == 0L) NA_character_ else sort(hits)[1]
}

# Records, per module, whether it was found-and-compared, found-but-skipped,
# or not found at all -- so a module can never drop out of the run without a
# trace. Populated by the per-module tests below; read by the coverage test
# at the end of this file.
.pull_module_log <- new.env(parent = emptyenv())

.run_pull_module_test <- function(stem) {
  title <- paste0("pull-stage oracle '", stem,
                  "' snapshots and self-compares as identical")
  test_that(title, {
    dir <- skip_unless_real_oracle()

    src <- .find_pull_oracle(dir, stem)
    if (is.na(src)) {
      assign(stem, "not_found", envir = .pull_module_log)
      skip(paste0("No '", stem, "' pull-stage dataset in HVTI_ORACLE_DIR."))
    }

    out  <- withr::local_tempfile(fileext = ".parquet")
    info <- snapshot_oracle(src, out)

    expect_gt(info$n_rows, 0L)
    expect_match(info$sha256, "^[0-9a-f]{64}$")

    d  <- haven::read_sas(src)
    id <- if ("masterid" %in% names(d)) "masterid" else names(d)[1]
    if (anyDuplicated(d[[id]]) > 0) {
      assign(stem, "skipped_nonunique_key", envir = .pull_module_log)
      skip(paste0(stem, ": identifier '", id, "' is not unique. This ",
                  "module is one-to-many by design and cannot ",
                  "self-compare on a single key."))
    }

    res <- compare_built(d, d, id = id)
    offending <- sum(res$verdict != "identical")
    assign(stem, "compared", envir = .pull_module_log)

    # Counts only. A value in a failure message would be PHI.
    expect_equal(
      offending, 0L,
      info = paste0(stem, ": ", offending,
                    " variable(s) not identical to themselves.")
    )
  })
}

for (.pull_stem in .pull_oracles) .run_pull_module_test(.pull_stem)

test_that("the pull-stage harness accounts for every declared module", {
  # Fixes the exact failure mode this suite exists to catch: a module that
  # silently drops out of the comparison with no failure and no skip. Every
  # module in .pull_oracles must land in the log as compared, explicitly
  # skipped, or explicitly not found -- never simply absent.
  skip_unless_real_oracle()
  skip_if(length(ls(.pull_module_log)) == 0L,
          "No pull-stage module was attempted in this run.")

  expect_setequal(ls(.pull_module_log), .pull_oracles)
})

test_that("row-set drift is reported apart from value differences", {
  dir <- skip_unless_real_oracle()
  src <- .find_pull_oracle(dir, "bdbase")
  skip_if(is.na(src), "No bdbase dataset in HVTI_ORACLE_DIR.")

  d  <- haven::read_sas(src)
  id <- if ("masterid" %in% names(d)) "masterid" else names(d)[1]
  skip_if(anyDuplicated(d[[id]]) > 0, "Identifier is not unique.")
  skip_if(nrow(d) < 4L, "Too few rows to split.")

  # Simulate the live-warehouse case: the R side has rows the oracle lacks.
  fewer <- d[seq_len(nrow(d) - 2L), , drop = FALSE]
  res   <- compare_built(fewer, d, id = id)

  # Every shared row still matches on value; the difference is row-set only.
  expect_equal(sum(res$verdict != "identical"), 0L)
  expect_gt(length(attr(res, "rows")$only_r), 0L)
})
