# No PHI: identifiers and values are invented.

# Echo and medication views for the master_demo encounters in helper-master-pull.R:
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

# A bare cohort table, as pull_master() builds it, for testing one leaf at a time.
flag_table <- function(con, mrn, dates) {
  DBI::dbExecute(con, paste("CREATE OR REPLACE TEMP TABLE study_cohort (mrn VARCHAR NOT",
                            "NULL, encounter_date DATE NOT NULL, active TINYINT NOT NULL",
                            "DEFAULT 1, crit_1 TINYINT)"))
  DBI::dbExecute(con, "INSERT INTO study_cohort (mrn, encounter_date) VALUES (?, ?)",
                 params = list(mrn, as.Date(dates)))
}

leaf_flags <- function(con, test) {
  leaf <- list(type = "leaf", col = "crit_1", test = test)
  DBI::dbExecute(con, .leaf_update_sql(leaf, "study_cohort", "master_demo", "\"mrn\"",
                                       "\"encounter_date\"", "duckdb"))
  out <- DBI::dbGetQuery(con, "SELECT mrn, crit_1 FROM study_cohort ORDER BY mrn")
  stats::setNames(as.integer(out$crit_1), out$mrn)
}
