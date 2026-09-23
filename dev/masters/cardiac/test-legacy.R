#!/usr/bin/env Rscript
# test-legacy.R: parsing inline SAS fixes, and recording them as 'bake'.
# The SAS below is invented; the ids are not anyone's. NO PHI.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "test-harness.R"))
skip_unless(c("duckdb", "DBI", "digest"))
for (f in c("sql-common.R", "value-text.R", "corrections.R", "legacy.R")) {
  source(file.path(here, f))
}

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
check("six facts parsed", nrow(f) == 6L)
check("the compound condition is reported unparsed", identical(p$unparsed, 10L))
check("line numbers survive the comment", identical(f$line, c(3L, 4L, 5L, 5L, 9L, 9L)))
check("a SAS date literal becomes ISO", f$value_text[f$variable == "dt_dis"] == "2020-01-15")
check("'.' is a missing value", f$value_missing[f$variable == "bmi"] == 1L)
check("a quoted value is unquoted", f$value_text[f$variable == "surgeon"] == "Jones")
check("an IN list gives one fact per key", setequal(f$key_value[f$line == 9L],
                                                    c("1004", "1005")))

p2 <- parse_legacy_facts(c(
  "if ccfid = 2001 then age = 66;",              # 1  fact
  "else age = 70;",                              # 2  else after a key-if: unparsed
  "if age > 1 then x = 1;",                      # 3  a rule with no key: no fact
  "else if ccfid = 2002 then age = 71;",         # 4  else mentions the key: unparsed
  "if ccfid = 2003 then note = 'a;b';"))         # 5  fact; ';' inside quotes
f2 <- p2$facts
check("the 2001 fact parses", "2001" %in% f2$key_value)
check("line 2 is unparsed (else after a key-if)", 2L %in% p2$unparsed)
check("line 4 is unparsed (else mentions the key)", 4L %in% p2$unparsed)
check("the 2003 fact parses with a literal semicolon",
      f2$value_text[f2$variable == "note"] == "a;b")
check("line 3 is not unparsed", !3L %in% p2$unparsed)
check("line 3 yields no fact", !3L %in% f2$line)

base_keys <- data.frame(ccfid = c(1001, 1002, 1003, 1004, 1004),
                        dt_surg = as.Date("2020-01-01") + 0:4)
meta <- data.frame(variable = c("ccfid", "dt_surg", "age", "surgeon", "bmi", "dt_dis"),
                   r_class = c("numeric", "Date", "numeric", "character", "numeric", "Date"))
at <- as.POSIXct("2026-09-23 12:00:00", tz = "UTC")
rows <- legacy_rows(f, base_keys, c("ccfid", "dt_surg"), "m", meta, "bd.data.master.sas", at)
check("four facts resolve to one record", nrow(rows$corrections) == 4L)
check("the surgery date is filled from the base",
      rows$corrections$dt_surg[rows$corrections$variable == "age"] == as.Date("2020-01-01"))
check("two surgeries make a fact ambiguous", "ambiguous" %in% rows$unresolved$reason)
check("an absent key is no_record", "no_record" %in% rows$unresolved$reason)
check("the prior is unknown on every legacy row",
      all(is.na(rows$corrections$expected_prior_missing)))
check("every legacy row is baked", all(rows$decisions$decision == "bake"))
check("evidence points at the file and line",
      all(grepl("^bd\\.data\\.master\\.sas:[0-9]+$", rows$corrections$evidence_ref)))

con <- DBI::dbConnect(duckdb::duckdb())
ddl <- corrections_ddl("corr", "dec", c(ccfid = "DOUBLE", dt_surg = "DATE"),
                       dialect = "duckdb")
invisible(DBI::dbExecute(con, ddl[["corrections"]]))
invisible(DBI::dbExecute(con, ddl[["decisions"]]))
r1 <- record_legacy_facts(con, rows, "corr", "dec", dialect = "duckdb")
r2 <- record_legacy_facts(con, rows, "corr", "dec", dialect = "duckdb")
check("first run appends four", r1$appended == 4L)
check("a rerun appends nothing", r2$appended == 0L && r2$already_present == 4L)
DBI::dbDisconnect(con, shutdown = TRUE)
finish()
