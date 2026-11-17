# No PHI: identifiers and values are invented.

# One master and the three contract views. SYN101 had a qualifying CABG in 1998,
# before the test epoch, and another in 2010.
seed_master <- function(con) {
  DBI::dbWriteTable(con, "master_demo", data.frame(
    mrn = c("SYN101", "SYN101", "SYN102", "SYN103", "SYN104"),
    encounter_date = as.Date(c("1998-05-01", "2010-03-01", "2012-07-15",
                               "2015-06-30", "2020-01-10")),
    proc = c("CABG", "CABG", "AVR", "CABG", "CABG"),
    age = c(50, 62, 70, 55, 66),
    stringsAsFactors = FALSE
  ))
  DBI::dbWriteTable(con, "master_demo_corrections_applied", data.frame(
    correction_id = c("C1", "C2"),
    mrn = c("SYN101", "SYN103"),
    encounter_date = as.Date(c("2010-03-01", "2015-06-30")),
    stringsAsFactors = FALSE
  ))
  DBI::dbWriteTable(con, "master_demo_deployment",
                    data.frame(sql_commit = "abc1234", stringsAsFactors = FALSE))
  DBI::dbWriteTable(con, "master_demo_parity", data.frame(
    sql_commit = "abc1234", verdict = "pass",
    verified_at = as.POSIXct("2026-11-01 12:00:00", tz = "UTC"),
    stringsAsFactors = FALSE
  ))
  invisible(con)
}

local_master_db <- function(env = parent.frame()) {
  testthat::skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
  seed_master(con)
}

demo_epoch <- as.Date(c("2000-01-01", "2024-07-31"))

demo_query <- function(...) cohort_query("proc = 'CABG'", demo_epoch, ...)

second_cabg <- "INSERT INTO master_demo VALUES ('SYN103', DATE '2018-02-02', 'CABG', 58)"

# A one-stage cohort of supplied encounter units.
unit_cohort <- function(mrn, dates) {
  units <- cohort_unit_id(mrn, as.Date(dates))
  new_cohort_record(
    members = data.frame(patient_id = units, stage_id = "supplied", included = TRUE,
                         reason = NA_character_, stringsAsFactors = FALSE),
    stages = data.frame(stage_id = "supplied", order = 1L, label = "Supplied cohort",
                        source = "upstream", provenance = "test fixture",
                        stringsAsFactors = FALSE),
    patient_id_col = "cohort_unit"
  )
}

# A study configuration shared by tests that never edit it.
demo_config <- local({
  path <- tempfile("study-config-", fileext = ".yaml")
  writeLines("study: st0000", path)
  path
})

pull_demo <- function(con, cohort, var_cols = "age", path = demo_config) {
  pull_master(con, "master_demo", cohort, var_cols = var_cols, path = path,
              dialect = "duckdb")
}

add_parity <- function(con, commit, verdict, at) {
  DBI::dbExecute(con, "INSERT INTO master_demo_parity VALUES (?, ?, ?)",
                 params = list(commit, verdict, as.POSIXct(at, tz = "UTC")))
}

active_units <- function(cohort) {
  last <- utils::tail(cohort$stages$stage_id[order(cohort$stages$order)], 1L)
  cohort$members$patient_id[cohort$members$stage_id == last & cohort$members$included]
}

local_freeze_setup <- function(env = parent.frame()) {
  testthat::skip_if_not_installed("arrow")
  con <- local_master_db(env)
  list(con = con, config = demo_config,
       dir = withr::local_tempdir("published-", .local_envir = env))
}

# Criteria fixtures. They live here, beside the master they read, so every helper they
# call is defined in this file.

# Echo and medication views for the master_demo encounters above:
# SYN101 2010-03-01, SYN103 2015-06-30 (and 2018-02-02 with second_cabg),
# SYN104 2020-01-10.
seed_criteria_views <- function(con) {
  DBI::dbWriteTable(con, "echo_demo", data.frame(
    mrn = c("SYN101", "SYN101", "SYN103", "SYN103", "SYN103"),
    measured_on = as.Date(c("2010-02-20", "2010-01-01", "2015-06-25", "2015-06-25",
                            "2018-01-30")),
    lvef = c(22, 50, 30, 20, 24),
    stringsAsFactors = FALSE
  ))
  DBI::dbWriteTable(con, "med_demo", data.frame(
    mrn = c("SYN101", "SYN103", "SYN104"),
    given_at = as.POSIXct(c("2010-02-27 08:00", "2015-06-29 10:00", "2020-01-14 09:00"),
                          tz = "UTC"),
    drug_class = c("inotrope", "inotrope", "inotrope"),
    stringsAsFactors = FALSE
  ))
  invisible(con)
}

# A duckdb master with the criteria views.
criteria_db <- function(env = parent.frame()) {
  con <- local_master_db(env)
  seed_criteria_views(con)
}

# A pull with one criterion routing undetermined units to review, and one review
# criterion: it is left awaiting review.
review_pull <- function(env = parent.frame()) {
  con <- local_master_db(env)
  seed_criteria_views(con)
  routed <- criterion("lvef", "LVEF 25% or less", "include",
                      view_rows("echo_demo", "measured_on", c(-30, 0), "nearest",
                                "lvef <= 25"),
                      undetermined = "review")
  strategy <- review_criterion("strategy", "Planned alternative support", "exclude")
  pull_demo(con, demo_query(criteria = list(routed, strategy), index_on = "qualifying"))
}

# SYN103 and SYN104 are routed to review at lvef; SYN103 (age 55) also fails the later
# age criterion, SYN104 (age 66) passes it.
routed_then_age <- function(env = parent.frame()) {
  con <- local_master_db(env)
  seed_criteria_views(con)
  routed <- criterion("lvef", "LVEF 25% or less", "include",
                      view_rows("echo_demo", "measured_on", c(-30, 0), "nearest",
                                "lvef <= 25"),
                      undetermined = "review")
  age <- criterion("age", "Age 60 or over", "include", master_row("age >= 60"), "exclude")
  pull_demo(con, demo_query(criteria = list(routed, age), index_on = "qualifying"))
}

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
