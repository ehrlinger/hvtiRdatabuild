# No PHI: identifiers and values are invented.

# One master and the two plan-3 contract views. SYN101 had a qualifying CABG in 1998,
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

pull_demo <- function(con, cohort, columns = "age") {
  pull_master(con, "master_demo", cohort, columns = columns, dialect = "duckdb")
}

active_units <- function(cohort) {
  last <- utils::tail(cohort$stages$stage_id[order(cohort$stages$order)], 1L)
  cohort$members$patient_id[cohort$members$stage_id == last & cohort$members$included]
}
