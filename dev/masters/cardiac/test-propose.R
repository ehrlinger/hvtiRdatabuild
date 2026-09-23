#!/usr/bin/env Rscript
# test-propose.R: propose_correction() and decide_correction(). NO PHI.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
source(file.path(here, "test-harness.R"))
skip_unless(c("duckdb", "DBI", "digest"))
for (f in c("sql-common.R", "value-text.R", "corrections.R", "propose.R")) {
  source(file.path(here, f))
}

con <- DBI::dbConnect(duckdb::duckdb())
DBI::dbWriteTable(con, "base", data.frame(
  id = c("K1", "K2"), dt_surg = as.Date(c("2020-01-01", "2020-02-01")),
  age = c(65.5, NA), stringsAsFactors = FALSE))
ddl <- corrections_ddl("corr", "dec", c(id = "VARCHAR", dt_surg = "DATE"),
                       dialect = "duckdb")
invisible(DBI::dbExecute(con, ddl[["corrections"]]))
invisible(DBI::dbExecute(con, ddl[["decisions"]]))
meta <- data.frame(variable = c("id", "dt_surg", "age"),
                   r_class = c("character", "Date", "numeric"))
k1 <- list(id = "K1", dt_surg = as.Date("2020-01-01"))

propose <- function(...) {
  args <- utils::modifyList(list(
    con = con, master = "m", base_table = "base", corrections_table = "corr",
    key_values = k1, variable = "age", expected_prior = 65.5, new_value = 66,
    evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester",
    meta = meta, dialect = "duckdb"), list(...))
  suppressMessages(do.call(propose_correction, args))
}

r <- propose()
check("a valid correction is appended", r$verdict == "appended")
check("the first correction to a variable asks for a regenerated view", isTRUE(r$new_variable))
check("second one does not", !isTRUE(propose(new_value = 67)$new_variable))
check("two rows stored", DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM corr")$n == 2)
row <- DBI::dbGetQuery(con, sprintf("SELECT * FROM corr WHERE correction_id = '%s'",
                                    r$correction_id))
check("the prior is stored as exact text", row$expected_prior == "65.5")

Sys.time <- function() as.POSIXct("2026-01-01 00:00:00", tz = "UTC")
suppressMessages(propose(new_value = 99))
check_error("a colliding id is refused", propose(new_value = 99), "collides")
rm(Sys.time)

r_na <- propose(key_values = list(id = "K2", dt_surg = as.Date("2020-02-01")),
                expected_prior = NA)
check("a missing prior is flagged", r_na$verdict == "appended")
row_na <- DBI::dbGetQuery(con, sprintf("SELECT * FROM corr WHERE correction_id = '%s'",
                                       r_na$correction_id))
check("missing prior is stored with flag", row_na$expected_prior_missing == 1L)

check_error("an unknown variable is an error", propose(variable = "height"), "metadata")
check_error("a key column cannot be corrected", propose(variable = "id"), "key column")
check_error("an unknown evidence type is an error", propose(evidence_type = "hunch"),
            "evidence")
msg <- check_error("a key that matches no row is an error",
                   propose(key_values = list(id = "K9", dt_surg = as.Date("2020-01-01"))),
                   "matched 0 rows")
check("and its message carries no key value", !grepl("K9", msg))
check_error("a value that does not cast is an error", propose(new_value = "abc"),
            "does not cast")
check_error("a factor value is refused", propose(new_value = factor("66")),
            "does not cast")

meta_chr <- rbind(meta, data.frame(variable = "surgeon", r_class = "character"))
propose_chr <- function(...) {
  args <- utils::modifyList(list(
    con = con, master = "m", base_table = "base", corrections_table = "corr",
    key_values = k1, variable = "surgeon", expected_prior = NA, new_value = "way too long",
    evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester",
    meta = meta_chr, dialect = "duckdb"), list(...), keep.null = TRUE)
  args$meta <- meta_chr
  suppressMessages(do.call(propose_correction, args))
}
msg_wide <- check_error("an over-width character value is rejected",
                        propose_chr(widths = c(surgeon = 5L)),
                        "longer than the column allows")
check("the over-width message carries no value", !grepl("way too long", msg_wide))
check("no widths means no width check", propose_chr()$verdict == "appended")

d <- suppressMessages(decide_correction(con, "dec", "corr", r$correction_id, "accept",
                                        "tester", dialect = "duckdb"))
check("a decision is recorded", d$verdict == "recorded")
check_error("an unknown decision is an error",
            decide_correction(con, "dec", "corr", r$correction_id, "maybe", "tester",
                              dialect = "duckdb"), "decision")
check_error("a decision on an unknown correction is an error",
            decide_correction(con, "dec", "corr", "cnope", "accept", "tester",
                              dialect = "duckdb"), "no correction")

DBI::dbDisconnect(con, shutdown = TRUE)
finish()
