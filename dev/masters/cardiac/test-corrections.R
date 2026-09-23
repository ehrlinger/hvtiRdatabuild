#!/usr/bin/env Rscript
# test-corrections.R: the R reference resolver, and the generated SQL agreeing
# with it on duckdb. Every id and value is invented. NO PHI.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "test-harness.R"))
skip_unless(c("duckdb", "DBI"))
source(file.path(here, "sql-common.R"))
source(file.path(here, "value-text.R"))
source(file.path(here, "corrections.R"))

check("a double round-trips through text", parse_value(value_text(0.1), "numeric") == 0.1)
check("a date is written ISO", value_text(as.Date("2020-01-15")) == "2020-01-15")
check("missing is NA text", is.na(value_text(NA_real_)))

key <- c("id", "dt_surg")
base <- data.frame(
  id      = c("K1", "K2", "K3", "K4"),
  dt_surg = as.Date(c("2020-01-01", "2020-02-01", "2020-03-01", "2020-04-01")),
  age     = c(65.5, 70.25, 1 / 3, NA),
  bmi     = c(31.2, NA, 22.8, 27.4),
  dt_dis  = as.Date(c("2020-01-09", "2020-02-09", "2020-03-09", "2020-04-09")),
  surgeon = c("S1", "S2", "S1", NA),
  stringsAsFactors = FALSE)
t0 <- as.POSIXct("2026-01-01 00:00:00", tz = "UTC")
corr <- function(cid, id, dt, variable, prior, prior_missing, new, new_missing, at) {
  data.frame(correction_id = cid, master = "m", id = id, dt_surg = as.Date(dt),
             variable = variable, expected_prior = prior,
             expected_prior_missing = prior_missing, new_value = new,
             new_value_missing = new_missing, evidence_type = "chart_review",
             evidence_ref = "invented", asserted_by = "tester", asserted_on = t0 + at,
             stringsAsFactors = FALSE)
}
corrections <- rbind(
  corr("c01", "K1", "2020-01-01", "age",     "65.5", 0L, "66",         0L, 1),  # applied
  corr("c02", "K3", "2020-03-01", "bmi",     "99",   0L, "23",         0L, 2),  # prior_mismatch
  corr("c03", "K4", "2020-04-01", "age",     NA,     1L, "61",         0L, 3),  # NA matches NULL
  corr("c04", "K1", "2020-01-01", "bmi",     "31.2", 0L, "30",         0L, 4),  # loses to c05
  corr("c05", "K1", "2020-01-01", "bmi",     "31.2", 0L, "29.5",       0L, 5),  # wins
  corr("c06", "K2", "2020-02-01", "dt_dis",  "2020-02-09", 0L, "2020-02-10", 0L, 6),  # rejected
  corr("c07", "K2", "2020-02-01", "surgeon", "S2",   0L, "S3",         0L, 7),  # baked
  corr("c08", "K9", "2020-09-01", "age",     "1",    0L, "2",          0L, 8),  # no_record
  corr("c09", "K3", "2020-03-01", "surgeon", NA,     NA, "S4",         0L, 9),  # prior_unknown
  corr("c10", "K1", "2020-01-01", "height",  "1",    0L, "2",          0L, 10), # no_variable
  corr("c11", "K1", "2020-01-01", "surgeon", "S1",   0L, NA,           1L, 11), # set missing
  corr("c12", "K2", "2020-02-01", "age",     "70.25", 0L, "71",        0L, 12), # other master
  corr("c13", "K3", "2020-03-01", "age",     value_text(1 / 3), 0L,
       value_text(2 / 3), 0L, 13)) # full-precision double through CAST
corrections$master[corrections$correction_id == "c12"] <- "other"
decision <- function(did, cid, what, at) {
  data.frame(decision_id = did, correction_id = cid, decision = what, decided_by = "tester",
             decided_on = t0 + 100 + at, reason = NA_character_, stringsAsFactors = FALSE)
}
decisions <- rbind(
  do.call(rbind, lapply(sprintf("c%02d", c(1:5, 8:13)), function(cid)
    decision(paste0("d", cid), cid, "accept", 0))),
  decision("d06a", "c06", "accept", 0), decision("d06b", "c06", "reject", 1),
  decision("d07", "c07", "bake", 0))

res <- resolve_corrections(base, corrections, decisions, key, "m")
out <- res$data
check("c01 applied", out$age[1] == 66)
check("c05 wins over c04 on the same cell", out$bmi[1] == 29.5)
check("c11 sets a value missing", is.na(out$surgeon[1]))
check("c03: a missing prior matches a missing base", out$age[4] == 61)
check("c02 not applied", out$bmi[3] == 22.8)
check("c06 rejected after accept, not applied", out$dt_dis[2] == as.Date("2020-02-09"))
check("c07 baked, not applied", out$surgeon[2] == "S2")
check("c12 belongs to another master", out$age[2] == 70.25)
check("c13 routes a full-precision double through the CAST", out$age[3] == 2 / 3)
stale <- res$stale[order(res$stale$correction_id), ]
check("stale ids", identical(stale$correction_id, c("c02", "c08", "c09", "c10")))
check("stale reasons", identical(stale$reason,
      c("prior_mismatch", "no_record", "prior_unknown", "no_variable")))

con <- DBI::dbConnect(duckdb::duckdb())
DBI::dbWriteTable(con, "base", base)
ddl <- corrections_ddl("corr", "dec",
                       key_types = c(id = "VARCHAR", dt_surg = "DATE"), dialect = "duckdb")
invisible(DBI::dbExecute(con, ddl[["corrections"]]))
invisible(DBI::dbExecute(con, ddl[["decisions"]]))
DBI::dbAppendTable(con, "corr", corrections)
DBI::dbAppendTable(con, "dec", decisions)

types <- c(id = "VARCHAR", dt_surg = "DATE", age = "DOUBLE", bmi = "DOUBLE",
           dt_dis = "DATE", surgeon = "VARCHAR")
corrected <- corrected_variables(con, "corr", "m", dialect = "duckdb")
check("corrected variables are the master's own",
      setequal(corrected, c("age", "bmi", "dt_dis", "surgeon", "height")))
invisible(DBI::dbExecute(con, corrections_view_sql("v", "base", "corr", "dec", "m", key,
                                         names(base), corrected, types, "duckdb")))
invisible(DBI::dbExecute(con, stale_view_sql("v_stale", "base", "corr", "dec", "m", key,
                                   names(base), corrected, types, "duckdb")))

sql_out <- DBI::dbGetQuery(con, "SELECT * FROM v ORDER BY id")
check("the SQL view agrees with the R reference",
      isTRUE(all.equal(sql_out, out[order(out$id), ], check.attributes = FALSE)))
sql_stale <- DBI::dbGetQuery(con, "SELECT * FROM v_stale ORDER BY correction_id")
check("the stale view agrees with the R reference",
      identical(sql_stale$correction_id, stale$correction_id) &&
        identical(sql_stale$reason, stale$reason))

# mssql string comparison: nvarchar/varchar/nchar/char get a binary-collation,
# length-checked comparison; other types keep plain equality. duckdb is
# unaffected (checked above; dialect gates the helper).
str_cols <- c("id", "dt_surg", "bmi")
str_view <- corrections_view_sql("v", "base", "corr", "dec", "m", key,
                                 str_cols, "bmi", c(bmi = "nvarchar(20)"), dialect = "mssql")
check("mssql nvarchar comparison uses BIN2 collation", grepl("Latin1_General_BIN2", str_view))
check("mssql nvarchar comparison checks DATALENGTH", grepl("DATALENGTH", str_view))

num_cols <- c("id", "dt_surg", "age")
num_view <- corrections_view_sql("v", "base", "corr", "dec", "m", key,
                                 num_cols, "age", c(age = "float"), dialect = "mssql")
check("mssql float comparison stays plain equality",
      !grepl("Latin1_General_BIN2|DATALENGTH", num_view))

str_stale <- stale_view_sql("v_stale", "base", "corr", "dec", "m", key,
                            str_cols, "bmi", c(bmi = "varchar(20)"), dialect = "mssql")
check("mssql stale view's varchar mismatch uses BIN2 collation",
      grepl("Latin1_General_BIN2", str_stale))
check("mssql stale view's varchar mismatch checks DATALENGTH", grepl("DATALENGTH", str_stale))

num_stale <- stale_view_sql("v_stale", "base", "corr", "dec", "m", key,
                            num_cols, "age", c(age = "float"), dialect = "mssql")
check("mssql stale view's float mismatch stays plain equality",
      !grepl("Latin1_General_BIN2|DATALENGTH", num_stale))

check_error("a duplicate correction_id is rejected by the primary key",
           DBI::dbAppendTable(con, "corr", corrections[corrections$correction_id == "c01", ]))
check_error("a duplicate decision_id is rejected by the primary key",
           DBI::dbAppendTable(con, "dec", decisions[decisions$decision_id == "dc01", ]))

DBI::dbDisconnect(con, shutdown = TRUE)
finish()
