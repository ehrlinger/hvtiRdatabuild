#!/usr/bin/env Rscript
# test-ddl.R: DDL generation and the row-size preflight. NO PHI.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "test-harness.R"))
skip_unless(c("arrow", "tidyselect"))
source(file.path(here, "ddl.R"))

pq <- tempfile(fileext = ".parquet")
sex <- c("M", "Foo")
attr(sex, "format.sas") <- "$20."
arrow::write_parquet(data.frame(
  id      = c("K1", "K22"),
  age     = c(60.5, NA),
  n       = c(1L, 2L),
  flag    = c(TRUE, FALSE),
  dt_surg = as.Date(c("2020-01-01", "2021-02-03")),
  note    = c(NA_character_, NA_character_),
  sex     = sex,
  stringsAsFactors = FALSE
), pq)

d <- master_ddl(pq, "master_cardiac_base_test")
check("table is schema-qualified and quoted",
      grepl("CREATE TABLE [dbo].[master_cardiac_base_test]", d$sql, fixed = TRUE))
check("character width is measured", d$types[["id"]] == "nvarchar(3)")
check("an all-missing character column gets width 255", d$types[["note"]] == "nvarchar(255)")
check("a SAS-declared width wider than the data wins", d$types[["sex"]] == "nvarchar(20)")
check("double maps to float", d$types[["age"]] == "float")
check("integer maps to int", d$types[["n"]] == "int")
check("logical maps to bit", d$types[["flag"]] == "bit")
check("date maps to date", d$types[["dt_surg"]] == "date")
check("every column is nullable", lengths(regmatches(d$sql, gregexpr(" NULL", d$sql))) == 7L)

check_error("an unknown arrow type is an error", mssql_type("list<item: int32>"), "No SQL")
check("a very long string becomes nvarchar(max)",
      mssql_type("string", 5000L)$sql == "nvarchar(max)")

wide <- rep(list(mssql_type("double")), 1000L)
p <- ddl_preflight(wide)
check("1,000 float columns exceed the 8,060-byte row", !p$ok && p$row_bytes > 8060)
check("the message names the limit", grepl("8060", p$message))

many <- rep(list(mssql_type("bool")), 1100L)
p <- ddl_preflight(many)
check("1,100 columns exceed the column limit", !p$ok && grepl("1024", p$message))

check("a narrow table passes", ddl_preflight(rep(list(mssql_type("double")), 10L))$ok)

finish()
