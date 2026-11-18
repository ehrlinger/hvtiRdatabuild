# Plan 3 rehearsal: the plan 2a source-corrections SQL on SQL Server.
#
# No PHI: every table here is created by this script from invented values, in a scratch
# schema, and dropped at the end. Output is PASS / FAIL / INFO lines with verdicts and
# counts only, never a key or a value.
#
# Plan 2a tested on duckdb only. This script runs the same path against the warehouse:
#
#   R1  snapshot isolation is allowed (every intake and decision runs in a snapshot txn)
#   R2  the generated tables and views deploy, COLLATE branch included
#   R3  intake's #temp table works inside the snapshot transaction
#   R4  keys match exactly: case and trailing spaces name different rows (BIN2 + DATALENGTH)
#   R5  old `datetime` columns: does intake accept a value read back from the column?
#   R6  decide_corrections() writes decisions; the corrected view applies them
#   R7  the nvarchar(max) distinct count sees "Yes"/"yes" and "x"/"x " as disagreeing
#   R8  every view agrees with the R reference, correction by correction
#   R9  a resubmitted row is refused as a duplicate (needs PR #127)
#   R10 an append waits for another submission's per-source lock (needs PR #127)
#
# How to run (on lri; never from the Mac against a mount):
#
#   mkdir -p /studies/general/_development/plan3-rehearsal/lib
#   cd /studies/general/_development/plan3-rehearsal
#   (once) install the build under test into ./lib with that same Rscript, for example
#   remotes::install_github() of ehrlinger/hvtiRdatabuild at main, or at a PR's branch
#   HVTI_MASTER_TEST_DSN=<scratch DSN> HVTI_MASTER_TEST_SCHEMA=<scratch schema> \
#     env -u R_HOME -u R_LIBS -u R_LIBS_USER /opt/R/4.6.0/bin/Rscript --vanilla \
#     <checkout>/dev/rehearsal/plan3-mssql-source-corrections.R 2>&1 | tee rehearsal.log
#
# Check `ls -d /opt/R/*` for the 4.6 build. The DSN holds the credential, so nothing secret
# enters R (AGENTS.md, the credential ladder). The script stops unless the DSN's default
# schema is the scratch schema, as test-master-integration.R does.

.libPaths(c(file.path(getwd(), "lib"), .libPaths()))
suppressPackageStartupMessages({
  library(DBI)
  library(hvtiRdatabuild)
})
ns <- asNamespace("hvtiRdatabuild")
int <- function(name) get(name, envir = ns)

ledger <- new.env()
ledger$lines <- character()
report <- function(id, label, ok = NA, info = NULL) {
  tag <- if (is.na(ok)) "INFO" else if (isTRUE(ok)) "PASS" else "FAIL"
  detail <- if (is.null(info)) "" else paste0(": ", info)
  line <- sprintf("%-4s %-4s %s%s", tag, id, label, detail)
  ledger$lines <- c(ledger$lines, line)
  cat(line, "\n")
}
# Run a step; on error report the condition class only (driver messages can carry values).
attempt <- function(id, label, code) {
  tryCatch({
    force(code)
    TRUE
  }, error = function(e) {
    report(id, label, FALSE, paste("error of class", paste(class(e), collapse = "/")))
    FALSE
  })
}

# The script's own stops carry no data, so their message is shown; any other condition
# (a driver error or warning can quote a value) is reported by class only.
halt <- function(msg) stop(errorCondition(msg, class = "rehearsal_stop"))
classes <- function(cnd) paste(class(cnd), collapse = "/")

# The body is a function so that its on.exit() cleanup runs on return and on error: at the
# top level of an Rscript file, on.exit() is never run. It returns the number of FAILs.
rehearse <- function() {
  dsn <- Sys.getenv("HVTI_MASTER_TEST_DSN")
  schema <- Sys.getenv("HVTI_MASTER_TEST_SCHEMA")
  if (!nzchar(dsn) || !nzchar(schema)) {
    halt("Set HVTI_MASTER_TEST_DSN and HVTI_MASTER_TEST_SCHEMA.")
  }
  con <- dbConnect(odbc::odbc(), dsn = dsn)
  if (!identical(dbGetQuery(con, "SELECT SCHEMA_NAME() AS s")$s, schema)) {
    dbDisconnect(con)
    halt("The DSN's default schema is not the scratch schema; nothing was run.")
  }
  cat(sprintf("hvtiRdatabuild %s, odbc %s, R %s\n", packageVersion("hvtiRdatabuild"),
              packageVersion("odbc"), getRversion()))
  has_dup_check <- exists(".held_corrections", envir = ns, inherits = FALSE)

  stamp <- format(Sys.time(), "%H%M%S")
  src <- paste0("rh_echo_", stamp)
  master <- paste0("rh_master_", stamp)
  tabs <- int(".source_tables")(src)
  work <- tempfile("plan3-")
  dir.create(work)

  on.exit({
    for (v in c(tabs$corrected, tabs$applied, tabs$stale, tabs$conflicts, master)) {
      try(dbExecute(con, sprintf("IF OBJECT_ID('%1$s', 'V') IS NOT NULL DROP VIEW [%1$s]", v)),
          silent = TRUE)
    }
    for (t in c(tabs$corrections, tabs$decisions, src)) {
      try(dbExecute(con, sprintf("IF OBJECT_ID('%1$s', 'U') IS NOT NULL DROP TABLE [%1$s]", t)),
          silent = TRUE)
    }
    dbDisconnect(con)
    unlink(work, recursive = TRUE)
    n_tag <- function(tag) sum(startsWith(ledger$lines, tag))
    cat("\nSummary:", n_tag("PASS"), "pass,", n_tag("FAIL"), "fail,", n_tag("INFO"), "info\n")
  }, add = TRUE)

  # R1. Snapshot isolation. Without it, SET TRANSACTION ISOLATION LEVEL SNAPSHOT succeeds and
  # the first read inside the transaction fails.
  snap <- dbGetQuery(con, "SELECT snapshot_isolation_state_desc AS s FROM sys.databases
                           WHERE name = DB_NAME()")$s
  report("R1", "database allows snapshot isolation", identical(snap, "ON"), snap)

  # The source: invented rows. Three keys differ only by case or a trailing space, so they are
  # three rows to an exact comparison and one to the default collation.
  dbExecute(con, sprintf(paste(
    "CREATE TABLE [%s] (mrn nvarchar(16) NOT NULL, encounter_date date NOT NULL,",
    "lvef float NULL, mr_grade nvarchar(8) NULL, note nvarchar(max) NULL,",
    "seen_dt datetime NULL, seen_dt2 datetime2(6) NULL)"
  ), src))
  dbExecute(con, sprintf(paste(
    "INSERT INTO [%s] VALUES",
    "(N'SYN1', '2020-01-01', 30, N'2', N'n1', '2020-01-01 10:00:00.997',",
    " '2020-01-01 10:00:00.123456'),",
    "(N'syn1', '2020-01-01', 31, N'2', N'n2', NULL, NULL),",
    "(N'SYN1 ', '2020-01-01', 32, N'2', N'n3', NULL, NULL),",
    "(N'SYN2', '2020-02-01', 40, N'3', N'n4', '2020-02-01 09:00:00.003',",
    " '2020-02-01 09:00:00.654321'),",
    "(N'SYN3', '2020-03-01', NULL, N'1', NULL, '2020-03-01 08:00:00', NULL)"
  ), src))
  dbExecute(con, sprintf("CREATE VIEW [%s] AS SELECT * FROM [%s]", master, src))

  cfg_path <- file.path(work, "master.yml")
  writeLines(c(paste0("name: ", master), "key: [mrn, encounter_date]",
               paste0("snapshots: '", work, "'"), "current: x.sas7bdat",
               "build_program: x.sas", "sources:",
               paste0("  ", src, ": {key: [mrn, encounter_date]}"),
               "deciders: [rh_decider]"), cfg_path)
  cfg <- read_master_config(cfg_path)

  # R2. Deploy the generated objects, mssql branch.
  deployed <- attempt("R2", "generated tables and views deploy", {
    st <- int(".corrections_statements")(cfg, con, "mssql")[[src]]
    for (x in c(st$tables, st$views)) dbExecute(con, x)
  })
  if (deployed) report("R2", "generated tables and views deploy", TRUE)
  if (!deployed) halt("Nothing further can run without the deployed objects.")

  cols <- int(".template_columns")(cfg)
  submission <- function(rows) {
    path <- tempfile(fileext = ".csv", tmpdir = work)
    df <- do.call(rbind, lapply(rows, function(r) {
      out <- stats::setNames(as.list(rep(NA_character_, length(cols))), cols)
      out[names(r)] <- as.list(r)
      as.data.frame(out, check.names = FALSE, stringsAsFactors = FALSE)
    }))
    utils::write.csv(df, path, row.names = FALSE, na = "")
    path
  }
  row <- function(mrn, date, variable, prior, new, prior_missing = "0", new_missing = "0") {
    c(source = src, mrn = mrn, encounter_date = date, variable = variable,
      expected_prior = prior, expected_prior_missing = prior_missing, new_value = new,
      new_value_missing = new_missing, evidence_type = "chart_review",
      evidence_ref = "invented rehearsal note", asserted_by = "rh_reviewer")
  }
  propose <- function(rows, dry_run = TRUE) {
    suppressMessages(propose_corrections(cfg, con, submission(rows), dry_run = dry_run,
                                         dialect = "mssql"))
  }

  # The datetime priors a submitter would copy: the value as R reads it back from the column.
  back <- dbGetQuery(con, sprintf(
    "SELECT seen_dt, seen_dt2 FROM [%s] WHERE mrn = N'SYN2'", src
  ))
  vt <- int("value_text")
  dt_prior <- vt(back$seen_dt[[1]])
  dt2_prior <- vt(back$seen_dt2[[1]])

  rows <- list(
    r01 = row("SYN1", "2020-01-01", "lvef", "30", "35"),
    r02 = row("syn1", "2020-01-01", "lvef", "31", "36"),
    r03 = row("SYN1 ", "2020-01-01", "lvef", "32", "37"),
    r04 = row("Syn1", "2020-01-01", "lvef", "30", "38"),
    r05 = row("SYN2", "2020-02-01", "lvef", "99", "41"),
    r06 = row("SYN2", "2020-02-01", "seen_dt", dt_prior, "2020-02-02 09:00:00"),
    r07 = row("SYN2", "2020-02-01", "seen_dt", dt_prior, "2020-02-02 09:00:00.123456"),
    r08 = row("SYN2", "2020-02-01", "seen_dt2", dt2_prior, "2020-02-02 09:00:00.123456"),
    r09 = row("SYN2", "2020-02-01", "mr_grade", "3", "Yes"),
    r10 = row("SYN2", "2020-02-01", "mr_grade", "3", "yes"),
    r11 = row("SYN3", "2020-03-01", "mr_grade", "1", "x"),
    r12 = row("SYN3", "2020-03-01", "mr_grade", "1", "x ")
  )

  # R3 and R4: one dry run carries every row.
  dry <- NULL
  ok3 <- attempt("R3", "intake dry run inside a snapshot transaction", dry <- propose(rows))
  if (ok3) {
    report("R3", "intake dry run inside a snapshot transaction", TRUE)
    v <- stats::setNames(dry$verdicts$verdict, names(rows))
    report("R4", "upper-case key names its own row", v[["r01"]] == "appendable", v[["r01"]])
    report("R4", "lower-case key names its own row", v[["r02"]] == "appendable", v[["r02"]])
    report("R4", "trailing-space key names its own row", v[["r03"]] == "appendable",
           v[["r03"]])
    report("R4", "mixed-case key names no row", v[["r04"]] == "unknown_key", v[["r04"]])
    report("R4", "a wrong prior is a prior_mismatch", v[["r05"]] == "prior_mismatch",
           v[["r05"]])
    # The open question from plan 2a: datetime keeps 1/300 s, the stored text keeps 6 places.
    report("R5", "datetime: prior read back from the column, whole-second new value", NA,
           v[["r06"]])
    report("R5", "datetime: new value with microseconds (expected does_not_cast)",
           v[["r07"]] == "does_not_cast", v[["r07"]])
    report("R5", "datetime2(6): prior read back, microsecond new value",
           v[["r08"]] == "appendable", v[["r08"]])
    report("R7", "case-only and trailing-space new values are each appendable",
           all(v[c("r09", "r10", "r11", "r12")] == "appendable"),
           paste(v[c("r09", "r10", "r11", "r12")], collapse = ","))
  }

  # R6. Append what was appendable, accept all of it through decide_corrections().
  appended <- character()
  if (ok3) {
    keep <- rows[dry$verdicts$verdict == "appendable"]
    if (attempt("R6", "append the appendable rows", out <- propose(keep, dry_run = FALSE))) {
      appended <- out$correction_ids
      report("R6", "append the appendable rows", length(appended) == length(keep),
             sprintf("%d of %d", length(appended), length(keep)))
      decisions <- data.frame(source = src, correction_id = appended, decision = "accept",
                              decided_by = "rh_decider", stringsAsFactors = FALSE)
      if (attempt("R6", "decide_corrections() accepts them", suppressMessages(
        decide_corrections(cfg, con, decisions, dry_run = FALSE, dialect = "mssql")
      ))) {
        report("R6", "decide_corrections() accepts them", TRUE)
      }
      lvef <- dbGetQuery(con, sprintf(paste(
        "SELECT COUNT(*) AS n FROM [%s] WHERE encounter_date = '2020-01-01'",
        "AND lvef IN (35, 36, 37)"
      ), tabs$corrected))$n
      report("R6", "corrected view applies each exact-key correction to one row", lvef == 3,
             sprintf("%d of 3 rows", lvef))
    }
  }

  # R7 and R8. The views against the R reference.
  if (length(appended)) {
    conflicts <- dbGetQuery(con, sprintf("SELECT correction_id, reason FROM [%s]",
                                         tabs$conflicts))
    ids_mr <- appended[names(rows)[dry$verdicts$verdict == "appendable"] %in%
                         c("r09", "r10", "r11", "r12")]
    report("R7", "Yes/yes and x/'x ' are accepted_disagree",
           setequal(conflicts$correction_id[conflicts$reason == "accepted_disagree"], ids_mr),
           sprintf("%d of %d", sum(conflicts$correction_id %in% ids_mr), length(ids_mr)))

    base <- dbGetQuery(con, sprintf("SELECT * FROM [%s]", src))
    corr <- dbGetQuery(con, sprintf("SELECT * FROM [%s]", tabs$corrections))
    dec <- dbGetQuery(con, sprintf("SELECT * FROM [%s]", tabs$decisions))
    ref <- int("resolve_source_corrections")(base, corr, dec, c("mrn", "encounter_date"))
    status_of <- function(view) {
      d <- dbGetQuery(con, sprintf("SELECT * FROM [%s]", view))
      if (!"reason" %in% names(d)) d$reason <- "apply"
      stats::setNames(d$reason, d$correction_id)
    }
    sql_status <- c(status_of(tabs$applied), status_of(tabs$stale), status_of(tabs$conflicts))
    ref_status <- c(stats::setNames(rep("apply", length(ref$applied$correction_id)),
                                    ref$applied$correction_id),
                    stats::setNames(ref$stale$reason, ref$stale$correction_id),
                    stats::setNames(ref$conflicts$reason, ref$conflicts$correction_id))
    same <- setequal(names(sql_status), names(ref_status)) &&
      all(sql_status[names(ref_status)] == ref_status)
    report("R8", "applied, stale and conflict views agree with the R reference", same,
           sprintf("%d corrections in SQL, %d in R", length(sql_status), length(ref_status)))
    ref_data <- ref$data[order(ref$data$mrn, ref$data$encounter_date), ]
    view_data <- dbGetQuery(con, sprintf("SELECT * FROM [%s]", tabs$corrected))
    view_data <- view_data[order(view_data$mrn, view_data$encounter_date), names(ref_data)]
    rownames(ref_data) <- rownames(view_data) <- NULL
    report("R8", "corrected view equals the R reference's data",
           isTRUE(all.equal(ref_data, view_data, check.attributes = FALSE)),
           sprintf("%d rows", nrow(view_data)))
  }

  # R9. Duplicates: an accepted one, and a pending one.
  if (length(appended) && has_dup_check) {
    v_acc <- propose(rows["r01"])$verdicts$verdict
    report("R9", "resubmitting an accepted correction", v_acc == "duplicate_accepted", v_acc)
    pend <- list(row("SYN2", "2020-02-01", "lvef", "40", "42"))
    if (attempt("R9", "append a pending correction", propose(pend, dry_run = FALSE))) {
      v_pend <- propose(pend)$verdicts$verdict
      report("R9", "resubmitting a pending correction", v_pend == "duplicate_pending", v_pend)
    }
  } else if (!has_dup_check) {
    report("R9", "duplicate check not in this build (PR #127); skipped", NA)
  }

  # R10. The per-source lock (PR #127): with the lock held on a second connection, an
  # append waits out its 60-second timeout and fails, rather than reading past it.
  if (length(appended) && exists(".source_lock_sql", envir = ns, inherits = FALSE)) {
    other <- dbConnect(odbc::odbc(), dsn = dsn)
    dbBegin(other)
    for (x in int(".source_lock_sql")(src, "mssql")) dbExecute(other, x)
    t0 <- Sys.time()
    blocked <- tryCatch({
      propose(list(row("SYN3", "2020-03-01", "mr_grade", "1", "z")), dry_run = FALSE)
      FALSE
    }, error = function(e) TRUE)
    waited <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    try(dbRollback(other), silent = TRUE)
    dbDisconnect(other)
    outcome <- sprintf("%s after %.0f s", if (blocked) "refused" else "appended", waited)
    report("R10", "an append waits for another submission's lock, then fails",
           blocked && waited >= 55, outcome)
  } else {
    report("R10", "source lock not in this build (PR #127); skipped", NA)
  }
  sum(startsWith(ledger$lines, "FAIL"))
}

failed <- tryCatch(
  withCallingHandlers(rehearse(), warning = function(w) {
    cat("WARN  a warning of class", classes(w), "\n")
    invokeRestart("muffleWarning")
  }),
  error = function(e) {
    what <- if (inherits(e, "rehearsal_stop")) conditionMessage(e) else
      paste("an error of class", classes(e))
    cat("ERROR", what, "\n")
    NA_integer_
  }
)
quit(status = if (is.na(failed) || failed > 0L) 1L else 0L, save = "no")
