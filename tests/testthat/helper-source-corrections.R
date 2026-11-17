# No PHI: identifiers and values are invented.

# Two warehouse sources and the master built from them. stg_echo is encounter-level,
# stg_patient patient-level. master_demo2's mr_severe is derived, not a source column.
seed_sources <- function(con) {
  DBI::dbWriteTable(con, "stg_echo", data.frame(
    mrn = c("SYN201", "SYN202", "SYN203", "SYN204", "SYN205"),
    encounter_date = as.Date(c("2020-01-01", "2020-02-01", "2020-03-01", "2020-04-01",
                               "2020-05-01")),
    lvef = c(30, NA, 40, 50, 55),
    mr_grade = c("2", "3", "1", NA, "4"),
    seen_on = as.Date(c("2019-12-01", NA, "2020-02-01", "2020-03-01", "2020-04-01")),
    stringsAsFactors = FALSE
  ))
  DBI::dbWriteTable(con, "stg_patient", data.frame(
    mrn = c("SYN201", "SYN202", "SYN203", "SYN204", "SYN205"),
    sex = c("F", "M", "F", "M", "F"),
    stringsAsFactors = FALSE
  ))
  DBI::dbExecute(con, paste(
    "CREATE VIEW master_demo2 AS SELECT e.mrn, e.encounter_date, e.lvef, e.mr_grade,",
    "p.sex, CASE WHEN e.mr_grade IN ('3', '4') THEN 1 ELSE 0 END AS mr_severe",
    "FROM stg_echo e JOIN stg_patient p ON p.mrn = e.mrn"
  ))
  invisible(con)
}

# A master.yml for master_demo2, declaring both sources and two deciders.
corrections_config <- function(env = parent.frame()) {
  dir <- withr::local_tempdir("corrections-", .local_envir = env)
  path <- file.path(dir, "master.yml")
  writeLines(c("name: master_demo2", "key: [mrn, encounter_date]",
               paste0("snapshots: ", dir), "current: built.sas7bdat",
               paste0("build_program: ", file.path(dir, "bd.sas")),
               "sources:",
               "  stg_echo: {key: [mrn, encounter_date]}",
               "  stg_patient: {key: [mrn]}",
               "deciders: [dm_one, dm_two]"), path)
  read_master_config(path)
}

# A duckdb connection with the sources only (no correction objects yet).
local_sources_db <- function(env = parent.frame()) {
  testthat::skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
  seed_sources(con)
}

# One corrections-table row, for tests that write the table directly.
corr_row <- function(id, mrn, date, variable, prior, prior_missing, new, new_missing,
                     asserted_on = "2026-01-01", asserted_by = "tester") {
  data.frame(correction_id = id, source = "stg_echo", mrn = mrn,
             encounter_date = as.Date(date), variable = variable,
             expected_prior = as.character(prior),
             expected_prior_missing = as.integer(prior_missing),
             new_value = as.character(new), new_value_missing = as.integer(new_missing),
             evidence_type = "chart_review", evidence_ref = "invented",
             asserted_by = asserted_by,
             asserted_on = as.POSIXct(asserted_on, tz = "UTC"),
             stringsAsFactors = FALSE)
}

dec_row <- function(id, correction_id, decision = "accept", on = "2026-02-01",
                    by = "dm_one") {
  data.frame(decision_id = id, correction_id = correction_id, decision = decision,
             decided_by = by, decided_on = as.POSIXct(on, tz = "UTC"),
             reason = NA_character_, stringsAsFactors = FALSE)
}

# The case matrix shared by the R/SQL agreement test. One row per rule:
case_corrections <- function() {
  rbind(
    corr_row("c01", "SYN201", "2020-01-01", "lvef", "30", 0L, "35", 0L),     # apply
    corr_row("c02", "SYN202", "2020-02-01", "lvef", NA, 1L, "45", 0L),       # fill-in
    corr_row("c03", "SYN203", "2020-03-01", "lvef", "40", 0L, "41", 0L),     # G1 disagree
    corr_row("c04", "SYN203", "2020-03-01", "lvef", "40", 0L, "42", 0L),     # G1 disagree
    corr_row("c05", "SYN201", "2020-01-01", "mr_grade", "2", 0L, "3", 0L),   # agree
    corr_row("c06", "SYN201", "2020-01-01", "mr_grade", "2", 0L, "3", 0L),   # agree
    corr_row("c07", "SYN203", "2020-03-01", "mr_grade", NA, 1L, "1", 0L),    # G7 agrees
    corr_row("c08", "SYN205", "2020-05-01", "mr_grade", NA, 1L, "2", 0L),    # G7 disagrees
    corr_row("c09", "SYN204", "2020-04-01", "lvef", "49", 0L, "51", 0L),     # mismatch
    corr_row("c10", "SYN204", "2020-04-01", "nosuch", "1", 0L, "2", 0L),     # no_variable
    corr_row("c11", "SYN299", "2020-04-01", "lvef", "1", 0L, "2", 0L),       # no_record
    corr_row("c12", "SYN205", "2020-05-01", "lvef", NA, NA, "60", 0L),       # prior_unknown
    corr_row("c13", "SYN203", "2020-03-01", "seen_on", "2020-02-01", 0L, "notadate", 0L),
    corr_row("c14", "SYN204", "2020-04-01", "mr_grade", NA, 1L, NA, 1L),     # apply, NA
    corr_row("c15", "SYN205", "2020-05-01", "seen_on", "2020-04-01", 0L, NA, 1L),
    corr_row("c16", "SYN202", "2020-02-01", "mr_grade", "3", 0L, "4", 0L),   # rejected
    corr_row("c17", "SYN202", "2020-02-01", "seen_on", NA, 1L, "2020-01-15", 0L)
  )
}

# c13 does not cast; c15 sets a value missing; c16 is accepted then rejected; c17 is
# never decided.
case_decisions <- function() {
  rbind(do.call(rbind, lapply(1:16, function(i) {
    dec_row(sprintf("d%02d", i), sprintf("c%02d", i))
  })), dec_row("d99", "c16", "reject", on = "2026-03-01"))
}

# Create stg_echo's correction tables, fill them, and create its four views.
deploy_echo <- function(con, corrections = case_corrections(),
                        decisions = case_decisions()) {
  types <- table_types(con, "stg_echo")
  key <- c("mrn", "encounter_date")
  for (s in source_corrections_ddl("stg_echo", types[key], "duckdb")) DBI::dbExecute(con, s)
  if (nrow(corrections)) DBI::dbAppendTable(con, "stg_echo_corrections", corrections)
  if (nrow(decisions)) DBI::dbAppendTable(con, "stg_echo_correction_decisions", decisions)
  for (s in source_views_sql("stg_echo", key, types, "duckdb")) DBI::dbExecute(con, s)
  invisible(con)
}

# Generate and deploy every declared source's correction objects.
deploy_sources <- function(con, cfg) {
  for (s in names(cfg$sources)) {
    st <- .corrections_statements(cfg, con, "duckdb")[[s]]
    for (x in c(st$tables, st$views)) DBI::dbExecute(con, x)
  }
  invisible(con)
}

# Write a filled template; `rows` are its rows as named character vectors.
write_submission <- function(cfg, rows, env = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".csv", .local_envir = env)
  cols <- .template_columns(cfg)
  df <- do.call(rbind, lapply(rows, function(r) {
    out <- stats::setNames(as.list(rep(NA_character_, length(cols))), cols)
    out[names(r)] <- as.list(r)
    as.data.frame(out, check.names = FALSE, stringsAsFactors = FALSE)
  }))
  utils::write.csv(df, path, row.names = FALSE, na = "")
  path
}

good_row <- function(...) {
  r <- c(source = "stg_echo", mrn = "SYN201", encounter_date = "2020-01-01",
         variable = "lvef", expected_prior = "30", expected_prior_missing = "0",
         new_value = "35", new_value_missing = "0", evidence_type = "chart_review",
         evidence_ref = "invented note 1", asserted_by = "reviewer_a")
  over <- c(...)
  r[names(over)] <- over
  r
}
