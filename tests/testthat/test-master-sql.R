test_that("run_step withholds the driver's own error message", {
  msg <- tryCatch(run_step("x", stop("secret K9")), error = conditionMessage)
  expect_match(msg, "Step 'x'", label = "run_step withholds the driver's message")
  expect_false(grepl("K9", msg),
               label = "run_step's message does not leak the driver's text")
})

test_that("dialect quoting and parity aggregate SQL are correct per dialect", {
  expect_true(quoter("mssql")("a]b") == "[a]]b]",
              label = "mssql quoting doubles a closing bracket")
  expect_true(quoter("duckdb")("a\"b") == "\"a\"\"b\"",
              label = "duckdb quoting doubles a quote")
  expect_true(sql_string("O'Neil") == "'O''Neil'",
              label = "string literals double a single quote")
  expect_true(grepl("HASHBYTES", parity_sql("t", "s", FALSE, TRUE, "mssql")),
              label = "mssql distinct on text uses a hash")
  expect_true(grepl("SUM", parity_sql("t", "x", TRUE, FALSE, "duckdb")),
              label = "numeric columns get a sum")
})

test_that("value_text and parse_value round-trip a double, a date, and missing", {
  expect_true(parse_value(value_text(0.1), "numeric") == 0.1,
              label = "a double round-trips through text")
  expect_true(value_text(as.Date("2020-01-15")) == "2020-01-15",
              label = "a date is written ISO")
  expect_true(is.na(value_text(NA_real_)), label = "missing is NA text")
})

test_that("resolve_corrections applies the winning correction and flags every stale reason", {
  key <- c("id", "dt_surg")
  base <- data.frame(
    id      = c("K1", "K2", "K3", "K4"),
    dt_surg = as.Date(c("2020-01-01", "2020-02-01", "2020-03-01", "2020-04-01")),
    age     = c(65.5, 70.25, 1 / 3, NA),
    bmi     = c(31.2, NA, 22.8, 27.4),
    dt_dis  = as.Date(c("2020-01-09", "2020-02-09", "2020-03-09", "2020-04-09")),
    surgeon = c("S1", "S2", "S1", NA),
    stringsAsFactors = FALSE
  )
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
         value_text(2 / 3), 0L, 13), # full-precision double through CAST
    corr("c14", "K2", "2020-02-01", "age",     "70.25", 0L, "not-a-number", 0L, 14) # does_not_cast
  )
  corrections$master[corrections$correction_id == "c12"] <- "other"
  decision <- function(did, cid, what, decided_at) {
    data.frame(decision_id = did, correction_id = cid, decision = what, decided_by = "tester",
               decided_on = t0 + decided_at, reason = NA_character_, stringsAsFactors = FALSE)
  }
  # Decided shortly after asserted, like a real review, so as_of can freeze at a
  # point between two corrections and still find their decisions already made.
  corr_at <- c(c01 = 1, c02 = 2, c03 = 3, c04 = 4, c05 = 5, c06 = 6, c07 = 7, c08 = 8,
               c09 = 9, c10 = 10, c11 = 11, c12 = 12, c13 = 13, c14 = 14)
  decisions <- rbind(
    do.call(rbind, lapply(sprintf("c%02d", c(1:5, 8:14)), function(cid) {
      decision(paste0("d", cid), cid, "accept", corr_at[[cid]] + 0.5)
    })),
    decision("d06a", "c06", "accept", corr_at[["c06"]] + 0.5),
    decision("d06b", "c06", "reject", corr_at[["c06"]] + 1),
    decision("d07", "c07", "bake", corr_at[["c07"]] + 0.5)
  )

  res <- resolve_corrections(base, corrections, decisions, key, "m")
  out <- res$data
  expect_true(out$age[1] == 66, label = "c01 applied")
  expect_true(out$bmi[1] == 29.5, label = "c05 wins over c04 on the same cell")
  expect_true(is.na(out$surgeon[1]), label = "c11 sets a value missing")
  expect_true(out$age[4] == 61, label = "c03: a missing prior matches a missing base")
  expect_true(out$bmi[3] == 22.8, label = "c02 not applied")
  expect_true(out$dt_dis[2] == as.Date("2020-02-09"),
              label = "c06 rejected after accept, not applied")
  expect_true(out$surgeon[2] == "S2", label = "c07 baked, not applied")
  expect_true(out$age[2] == 70.25, label = "c12 belongs to another master")
  expect_true(out$age[3] == 2 / 3,
              label = "c13 routes a full-precision double through the CAST")
  expect_true(out$age[2] == 70.25,
              label = "c14's new_value does not cast; K2 age is untouched")
  stale <- res$stale[order(res$stale$correction_id), ]
  expect_true(identical(stale$correction_id, c("c02", "c08", "c09", "c10", "c14")),
              label = "stale ids")
  expect_true(identical(stale$reason,
                        c("prior_mismatch", "no_record", "prior_unknown", "no_variable",
                          "does_not_cast")),
              label = "stale reasons")

  # C1: as_of freezes the correction state at a point in time.
  as_of <- t0 + 4.5
  res_asof <- resolve_corrections(base, corrections, decisions, key, "m", as_of = as_of)
  expect_true(res_asof$data$bmi[1] == 30,
              label = "as_of between c04 and c05: K1 bmi takes c04's value")
  expect_true(
              isTRUE(all.equal(resolve_corrections(base, corrections, decisions, key, "m")$data,
                               out, check.attributes = FALSE)),
              label = "as_of = NULL leaves resolve_corrections unchanged")

  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbWriteTable(con, "base", base)
  ddl <- corrections_ddl("corr", "dec",
                         key_types = c(id = "VARCHAR", dt_surg = "DATE"), dialect = "duckdb")
  DBI::dbExecute(con, ddl[["corrections"]])
  DBI::dbExecute(con, ddl[["decisions"]])
  DBI::dbAppendTable(con, "corr", corrections)
  DBI::dbAppendTable(con, "dec", decisions)

  types <- c(id = "VARCHAR", dt_surg = "DATE", age = "DOUBLE", bmi = "DOUBLE",
             dt_dis = "DATE", surgeon = "VARCHAR")
  corrected <- corrected_variables(con, "corr", "m", dialect = "duckdb")
  expect_true(setequal(corrected, c("age", "bmi", "dt_dis", "surgeon", "height")),
              label = "corrected variables are the master's own")
  DBI::dbExecute(con, corrections_view_sql("v", "base", "corr", "dec", "m", key,
                                           names(base), corrected, types, "duckdb"))
  DBI::dbExecute(con, stale_view_sql("v_stale", "base", "corr", "dec", "m", key,
                                     names(base), corrected, types, "duckdb"))

  sql_out <- DBI::dbGetQuery(con, "SELECT * FROM v ORDER BY id")
  expect_true(isTRUE(all.equal(sql_out, out[order(out$id), ], check.attributes = FALSE)),
              label = "the SQL view agrees with the R reference")
  sql_stale <- DBI::dbGetQuery(con, "SELECT * FROM v_stale ORDER BY correction_id")
  expect_true(identical(sql_stale$correction_id, stale$correction_id) &&
                identical(sql_stale$reason, stale$reason),
              label = "the stale view agrees with the R reference")

  DBI::dbExecute(con, corrections_view_sql("v_asof", "base", "corr", "dec", "m", key,
                                           names(base), corrected, types, "duckdb",
                                           as_of = as_of))
  sql_asof <- DBI::dbGetQuery(con, "SELECT * FROM v_asof ORDER BY id")
  expect_true(isTRUE(all.equal(sql_asof, res_asof$data[order(res_asof$data$id), ],
                               check.attributes = FALSE)),
              label = "the as_of SQL view agrees with the R reference")

  expect_error(DBI::dbAppendTable(con, "corr", corrections[corrections$correction_id == "c01", ]))
  expect_error(DBI::dbAppendTable(con, "dec", decisions[decisions$decision_id == "dc01", ]))
})

test_that("mssql identifiers get collation-safe comparisons for character types, not numeric", {
  key <- c("id", "dt_surg")

  # mssql string comparison: nvarchar/varchar/nchar/char get a binary-collation,
  # length-checked comparison; other types keep plain equality. duckdb is
  # unaffected (checked above; dialect gates the helper).
  str_cols <- c("id", "dt_surg", "bmi")
  str_view <- corrections_view_sql("v", "base", "corr", "dec", "m", key,
                                   str_cols, "bmi", c(bmi = "nvarchar(20)"), dialect = "mssql")
  expect_true(grepl("Latin1_General_BIN2", str_view),
              label = "mssql nvarchar comparison uses BIN2 collation")
  expect_true(grepl("DATALENGTH", str_view),
              label = "mssql nvarchar comparison checks DATALENGTH")

  num_cols <- c("id", "dt_surg", "age")
  num_view <- corrections_view_sql("v", "base", "corr", "dec", "m", key,
                                   num_cols, "age", c(age = "float"), dialect = "mssql")
  expect_true(!grepl("Latin1_General_BIN2|DATALENGTH", num_view),
              label = "mssql float comparison stays plain equality")

  str_stale <- stale_view_sql("v_stale", "base", "corr", "dec", "m", key,
                              str_cols, "bmi", c(bmi = "varchar(20)"), dialect = "mssql")
  expect_true(grepl("Latin1_General_BIN2", str_stale),
              label = "mssql stale view's varchar mismatch uses BIN2 collation")
  expect_true(grepl("DATALENGTH", str_stale),
              label = "mssql stale view's varchar mismatch checks DATALENGTH")

  num_stale <- stale_view_sql("v_stale", "base", "corr", "dec", "m", key,
                              num_cols, "age", c(age = "float"), dialect = "mssql")
  expect_true(!grepl("Latin1_General_BIN2|DATALENGTH", num_stale),
              label = "mssql stale view's float mismatch stays plain equality")
})
