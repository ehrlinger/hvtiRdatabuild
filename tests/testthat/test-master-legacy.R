test_that("parse_legacy_facts reads inline if/then fixes, and flags what it cannot", {
  sas <- c(
           "data master; set base;",                        # 1
           "/* invented fixes */",                          # 2
           "if ccfid = 1001 then age = 66;",                # 3  fact
           "if ccfid eq '1002' then surgeon = 'Jones';",    # 4  fact
           "if ccfid = 1003 then do;",                      # 5  block: two facts
           "  bmi = .;",                                    # 6
           "  dt_dis = '15JAN2020'd;",                      # 7
           "end;",                                          # 8
           "if ccfid in (1004, 1005) then age = 70;",       # 9  two facts
           "if ccfid = 1006 and age > 90 then age = .;",    # 10 unparsed: compound
           "* if ccfid = 1007 then age = 1;",               # 11 comment statement
           "if age < 0 then age = .;",                      # 12 a rule, not a fact
           "run;")                                          # 13

  p <- parse_legacy_facts(sas)
  f <- p$facts
  expect_true(nrow(f) == 6L, label = "six facts parsed")
  expect_true(identical(p$unparsed, 10L),
              label = "the compound condition is reported unparsed")
  expect_true(identical(f$line, c(3L, 4L, 5L, 5L, 9L, 9L)),
              label = "line numbers survive the comment")
  expect_true(f$value_text[f$variable == "dt_dis"] == "2020-01-15",
              label = "a SAS date literal becomes ISO")
  expect_true(f$value_missing[f$variable == "bmi"] == 1L,
              label = "'.' is a missing value")
  expect_true(f$value_text[f$variable == "surgeon"] == "Jones",
              label = "a quoted value is unquoted")
  expect_true(setequal(f$key_value[f$line == 9L], c("1004", "1005")),
              label = "an IN list gives one fact per key")
})

test_that("parse_legacy_facts distinguishes a key-if's else from an unrelated rule", {
  p2 <- parse_legacy_facts(c(
    "if ccfid = 2001 then age = 66;",              # 1  fact
    "else age = 70;",                              # 2  else after a key-if: unparsed
    "if age > 1 then x = 1;",                      # 3  a rule with no key: no fact
    "else if ccfid = 2002 then age = 71;",         # 4  else mentions the key: unparsed
    "if ccfid = 2003 then note = 'a;b';"           # 5  fact; ';' inside quotes
  ))
  f2 <- p2$facts
  expect_true("2001" %in% f2$key_value, label = "the 2001 fact parses")
  expect_true(2L %in% p2$unparsed, label = "line 2 is unparsed (else after a key-if)")
  expect_true(4L %in% p2$unparsed, label = "line 4 is unparsed (else mentions the key)")
  expect_true(f2$value_text[f2$variable == "note"] == "a;b",
              label = "the 2003 fact parses with a literal semicolon")
  expect_true(!3L %in% p2$unparsed, label = "line 3 is not unparsed")
  expect_true(!3L %in% f2$line, label = "line 3 yields no fact")
})

test_that("legacy_rows resolves facts to corrections, baked, with no known prior", {
  skip_if_not_installed("digest")
  sas <- c(
           "if ccfid = 1001 then age = 66;",
           "if ccfid eq '1002' then surgeon = 'Jones';",
           "if ccfid = 1003 then do;",
           "  bmi = .;",
           "  dt_dis = '15JAN2020'd;",
           "end;",
           "if ccfid in (1004, 1005) then age = 70;")
  f <- parse_legacy_facts(sas)$facts

  base_keys <- data.frame(
    ccfid = c(1001, 1002, 1003, 1004, 1004),
    dt_surg = as.Date("2020-01-01") + 0:4
  )
  meta <- data.frame(
    variable = c("ccfid", "dt_surg", "age", "surgeon", "bmi", "dt_dis"),
    r_class = c("numeric", "Date", "numeric", "character", "numeric", "Date")
  )
  at <- as.POSIXct("2026-09-23 12:00:00", tz = "UTC")
  rows <- legacy_rows(f, base_keys, c("ccfid", "dt_surg"), "m", meta, "bd.data.master.sas", at)
  expect_true(nrow(rows$corrections) == 4L, label = "four facts resolve to one record")
  expect_true(rows$corrections$dt_surg[rows$corrections$variable == "age"] ==
                as.Date("2020-01-01"),
              label = "the surgery date is filled from the base")
  expect_true("ambiguous" %in% rows$unresolved$reason,
              label = "two surgeries make a fact ambiguous")
  expect_true("no_record" %in% rows$unresolved$reason,
              label = "an absent key is no_record")
  expect_true(all(is.na(rows$corrections$expected_prior_missing)),
              label = "the prior is unknown on every legacy row")
  expect_true(all(rows$decisions$decision == "bake"), label = "every legacy row is baked")
  expect_true(all(grepl("^bd\\.data\\.master\\.sas:[0-9]+$", rows$corrections$evidence_ref)),
              label = "evidence points at the file and line")

  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  ddl <- corrections_ddl("corr", "dec", c(ccfid = "DOUBLE", dt_surg = "DATE"),
                         dialect = "duckdb")
  DBI::dbExecute(con, ddl[["corrections"]])
  DBI::dbExecute(con, ddl[["decisions"]])
  r1 <- record_legacy_facts(con, rows, "corr", "dec", dialect = "duckdb")
  r2 <- record_legacy_facts(con, rows, "corr", "dec", dialect = "duckdb")
  expect_true(r1$appended == 4L, label = "first run appends four")
  expect_true(r2$appended == 0L && r2$already_present == 4L,
              label = "a rerun appends nothing")
})
