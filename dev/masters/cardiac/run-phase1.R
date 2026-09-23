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
for (f in c("ddl.R", "load.R", "sql-common.R", "parity.R")) {
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
  invisible(DBI::dbExecute(con, ddl$sql))
}

r <- load_parquet(con, parquet, base)
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

meta <- jsonlite::read_json(sub("\\.parquet$", ".meta.json", parquet),
                            simplifyVector = TRUE)$columns
DBI::dbWriteTable(con, paste0(view, "_meta"), meta, overwrite = TRUE)
q <- quoter("mssql")
invisible(DBI::dbExecute(con, sprintf("CREATE OR ALTER VIEW %s AS SELECT * FROM %s;",
                                      q(view), q(base))))
message("view  ", view, " -> ", base)
