#!/usr/bin/env Rscript
# run-phase1.R: DDL, load, parity, and the master view.
#
#   Rscript run-phase1.R <parquet> <base_table> <view> <key> <server> <database> \
#     [dsn] [--execute]
#
# <key> is comma-separated, e.g. "ccfid,dt_surg". Without --execute it writes
# the DDL to <parquet>.ddl.sql for a hand-off and stops. With --execute it runs
# the DDL, loads, checks parity, and creates the view only if parity passes.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
for (f in c("ddl.R", "load.R", "sql-common.R", "parity.R", "key-verdict.R", "corrections.R")) {
  source(file.path(here, f))
}

args <- commandArgs(trailingOnly = TRUE)
execute <- "--execute" %in% args
args <- setdiff(args, "--execute")
if (length(args) < 6L) {
  stop("usage: run-phase1.R <parquet> <base> <view> <key> <server> <db>")
}
parquet <- args[[1]]
base <- args[[2]]
view <- args[[3]]
key <- strsplit(args[[4]], ",", fixed = TRUE)[[1]]

kv <- key_verdict(parquet, key)
message(format_key_verdict(kv))
if (kv$verdict != "unique") {
  stop("Key '", kv$key, "' is not unique in the parquet snapshot; fix the ",
       "snapshot before building.", call. = FALSE)
}

ddl <- master_ddl(parquet, base)
message("ddl  ", ddl$n_cols, " columns, fixed-width row ", ddl$row_bytes,
        " bytes")
if (!execute) {
  writeLines(ddl$sql, paste0(parquet, ".ddl.sql"))
  message("dry run: DDL written to ", paste0(parquet, ".ddl.sql"),
          "; rerun with --execute")
  quit(save = "no", status = 0)
}

con <- hvtiRdatabuild::dw_connect(server = args[[5]], database = args[[6]],
                                  dsn = if (length(args) >= 7L) args[[7]] else
                                    NULL)
on.exit(DBI::dbDisconnect(con), add = TRUE)
if (!DBI::dbExistsTable(con, base)) {
  run_step("create base table", invisible(DBI::dbExecute(con, ddl$sql)))
}

r <- run_step("load parquet", load_parquet(con, parquet, base))
message("load  ", r$loaded, " row groups loaded, ", r$skipped,
        " already present, of ", r$row_groups)

res <- parity_check(con, base, parquet, key)
message(parity_summary(res))
if (res$verdict != "pass") {
  message("mismatched columns: ",
          paste(res$columns$variable[res$columns$verdict == "mismatch"],
                collapse = ", "))
  stop("Parity failed; the view was not created.", call. = FALSE)
}

full <- run_step("full parity check", parity_full(con, base, parquet, key))
message(full_summary(full))
if (any(full$verdict == "mismatch")) {
  message("mismatched columns: ", paste(full$variable[full$verdict == "mismatch"],
                                        collapse = ", "))
  stop("Full parity failed; the view was not created.", call. = FALSE)
}

meta_json <- jsonlite::read_json(sub("\\.parquet$", ".meta.json", parquet),
                                 simplifyVector = TRUE)
meta <- meta_json$columns
q <- quoter("mssql")
run_step("write view metadata",
        DBI::dbWriteTable(con, paste0(view, "_meta"), meta, overwrite = TRUE))

parity_t <- paste0(view, "_parity")
ty <- sql_types("mssql")
if (!DBI::dbExistsTable(con, parity_t)) {
  run_step("create parity table", invisible(DBI::dbExecute(con, sprintf(
    paste("CREATE TABLE %s (base_table %s NOT NULL, parquet_sha256 %s NOT NULL,",
          "%s %s NOT NULL, %s %s NOT NULL);"),
    q(parity_t), ty$id, ty$id, q("verdict"), ty$id, q("checked_at"), ty$ts))))
}
run_step("record parity pass", DBI::dbAppendTable(con, parity_t, data.frame(
  base_table = base, parquet_sha256 = meta_json$parquet_sha256, verdict = "pass",
  checked_at = Sys.time(), stringsAsFactors = FALSE)))

corr_t <- paste0(view, "_corrections")
dec_t <- paste0(view, "_correction_decisions")
stale_v <- paste0(view, "_corrections_stale")
if (DBI::dbExistsTable(con, corr_t)) {
  types <- table_types(con, base)
  corrected <- corrected_variables(con, corr_t, view)
  run_step("regenerate corrections view", invisible(DBI::dbExecute(con,
          corrections_view_sql(view, base, corr_t, dec_t, view, key,
                               names(types), corrected, types))))
  run_step("regenerate stale corrections view", invisible(DBI::dbExecute(con,
          stale_view_sql(stale_v, base, corr_t, dec_t, view, key,
                         names(types), corrected, types))))
  message("view  ", view, " -> ", base, " (regenerated over corrections)")
} else {
  run_step("create master view",
          invisible(DBI::dbExecute(con, sprintf("CREATE OR ALTER VIEW %s AS SELECT * FROM %s;",
                                                q(view), q(base)))))
  message("view  ", view, " -> ", base)
}
