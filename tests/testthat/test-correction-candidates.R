# No PHI: identifiers and values are invented.

candidates_setup <- function(env = parent.frame()) {
  f <- local_freeze_setup(env)
  DBI::dbWriteTable(f$con, "master_demo_lineage", data.frame(
    master_column = "age", source = "stg_demo", source_column = "age_years",
    stringsAsFactors = FALSE
  ))
  pull <- pull_demo(f$con, demo_query(), var_cols = c("proc", "age"))
  release <- freeze_study_pull(pull, f$config, f$dir, "st0000_pull",
                               extract_date = "2026-11-16")
  frozen <- file.path(f$dir, release$file)
  cfg_path <- withr::local_tempfile(fileext = ".yml", .local_envir = env)
  writeLines(c("name: master_demo", "key: [mrn, encounter_date]", "snapshots: snap",
               "current: x.sas7bdat", "build_program: x.sas", "sources:",
               "  stg_demo: {key: [mrn, encounter_date]}"), cfg_path)
  list(con = f$con, cfg = read_master_config(cfg_path), frozen = frozen,
       data = as.data.frame(arrow::read_parquet(frozen)))
}

test_that("a pass-through fix becomes a template row; a derived fix is only counted", {
  s <- candidates_setup()
  data <- s$data
  data$age[data$mrn == "SYN103"] <- 56          # pass-through: a candidate
  data$proc[data$mrn == "SYN104"] <- "CABG+AVR"  # derived: counted only
  out_path <- withr::local_tempfile(fileext = ".csv")
  out <- study_correction_candidates(s$cfg, s$con, s$frozen, data, out_path,
                                     dialect = "duckdb")
  expect_identical(out$candidates, 1L)
  expect_identical(out$derived$column, "proc")
  expect_identical(out$derived$n_cells, 1L)
  rows <- utils::read.csv(out_path, colClasses = "character", na.strings = "")
  expect_identical(names(rows), .template_columns(s$cfg))
  expect_identical(rows$source, "stg_demo")
  expect_identical(rows$variable, "age_years")
  expect_identical(c(rows$expected_prior, rows$new_value), c("55", "56"))
  expect_true(is.na(rows$evidence_type))
  expect_true(is.na(rows$asserted_by))
})

test_that("a patient-level cell is a candidate only if every encounter agrees", {
  f <- local_freeze_setup()
  DBI::dbExecute(f$con, second_cabg)  # SYN103 gains a 2018 encounter
  DBI::dbWriteTable(f$con, "master_demo_lineage", data.frame(
    master_column = "proc", source = "stg_pat", source_column = "proc_group",
    stringsAsFactors = FALSE
  ))
  pull <- pull_demo(f$con, demo_query(index = "all"), var_cols = c("proc", "age"))
  release <- freeze_study_pull(pull, f$config, f$dir, "st0000_pull",
                               extract_date = "2026-11-16")
  frozen <- file.path(f$dir, release$file)
  cfg_path <- withr::local_tempfile(fileext = ".yml")
  writeLines(c("name: master_demo", "key: [mrn, encounter_date]", "snapshots: snap",
               "current: x.sas7bdat", "build_program: x.sas", "sources:",
               "  stg_pat: {key: [mrn]}"), cfg_path)
  cfg <- read_master_config(cfg_path)
  data <- as.data.frame(arrow::read_parquet(frozen))
  later <- data$mrn == "SYN103" & data$encounter_date == as.Date("2018-02-02")
  data$proc[later] <- "OPCAB"           # one encounter changed, the other not
  one <- study_correction_candidates(cfg, f$con, frozen, data,
                                     withr::local_tempfile(fileext = ".csv"),
                                     dialect = "duckdb")
  expect_identical(c(one$candidates, one$inconsistent), c(0L, 1L))
  data$proc[data$mrn == "SYN103"] <- "OPCAB"   # both agree: one source cell
  both <- study_correction_candidates(cfg, f$con, frozen, data,
                                      withr::local_tempfile(fileext = ".csv"),
                                      dialect = "duckdb")
  expect_identical(c(both$candidates, both$inconsistent), c(1L, 0L))
})

test_that("candidates need the lineage the pull was made with", {
  s <- candidates_setup()
  DBI::dbExecute(s$con, "UPDATE master_demo_deployment SET sql_commit = 'def5678'")
  expect_error(study_correction_candidates(s$cfg, s$con, s$frozen, s$data,
                                           withr::local_tempfile(fileext = ".csv"),
                                           dialect = "duckdb"),
               class = "hvtiRdatabuild_lineage_moved")
})

test_that("a study row not in the pull stops, and no value is printed", {
  s <- candidates_setup()
  data <- s$data
  data$mrn[[1]] <- "SYN999"
  err <- tryCatch(study_correction_candidates(s$cfg, s$con, s$frozen, data,
                                              withr::local_tempfile(fileext = ".csv"),
                                              dialect = "duckdb"),
                  error = function(e) e)
  expect_s3_class(err, "hvtiRdatabuild_unknown_units")
  expect_false(grepl("SYN", conditionMessage(err)))
})
