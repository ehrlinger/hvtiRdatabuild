# No PHI: identifiers and values are invented.

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
