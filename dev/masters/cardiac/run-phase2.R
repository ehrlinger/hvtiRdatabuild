#!/usr/bin/env Rscript
# run-phase2.R: corrections tables, legacy facts as 'bake', corrections view.
#
#   Rscript run-phase2.R <meta_json> <base_table> <view> <key> <build_sas> \
#     <server> <database> [dsn] [--execute]
#
# The legacy facts are read from <build_sas> here and written only to the
# warehouse, so this step needs write access and has no file hand-off. Without
# --execute it parses and resolves, prints counts, and writes nothing.

self <- sub("^--file=", "",
            grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
here <- if (length(self)) dirname(self[[1]]) else "."
for (f in c("sql-common.R", "value-text.R", "corrections.R", "legacy.R")) {
  source(file.path(here, f))
}

args <- commandArgs(trailingOnly = TRUE)
execute <- "--execute" %in% args
args <- setdiff(args, "--execute")
if (length(args) < 7L) {
  stop("usage: run-phase2.R <meta> <base> <view> <key> <sas> <server> <db>")
}
meta <- jsonlite::read_json(args[[1]], simplifyVector = TRUE)$columns
base <- args[[2]]
view <- args[[3]]
key <- strsplit(args[[4]], ",", fixed = TRUE)[[1]]
corr_t <- paste0(view, "_corrections")
dec_t <- paste0(view, "_correction_decisions")
stale_v <- paste0(view, "_corrections_stale")

con <- hvtiRdatabuild::dw_connect(server = args[[6]], database = args[[7]],
                                  dsn = if (length(args) >= 8L) args[[8]] else
                                    NULL)
on.exit(DBI::dbDisconnect(con), add = TRUE)
q <- quoter("mssql")
types <- table_types(con, base)

parsed <- parse_legacy_facts(readLines(args[[5]], warn = FALSE), key_var = key[[1]])
base_keys <- DBI::dbGetQuery(con, sprintf("SELECT %s FROM %s",
                                          paste(q(key), collapse = ", "),
                                          q(base)))
rows <- legacy_rows(parsed$facts, base_keys, key, view, meta,
                    basename(args[[5]]))
message("legacy  ", nrow(parsed$facts), " facts parsed; ",
        NROW(rows$corrections), " resolved; ", nrow(rows$unresolved),
        " unresolved")
if (nrow(rows$unresolved)) {
  tab <- table(rows$unresolved$reason)
  message("  unresolved by reason: ",
          paste(names(tab), tab, sep = " ", collapse = ", "))
  message("  at lines: ", paste(sort(unique(rows$unresolved$line)),
                                collapse = ", "))
}
if (length(parsed$unparsed)) {
  message("  unparsed statements at lines: ",
          paste(parsed$unparsed, collapse = ", "))
}
if (!execute) {
  message("dry run: nothing written; rerun with --execute")
  quit(save = "no", status = 0)
}

if (!DBI::dbExistsTable(con, corr_t)) {
  ddl <- corrections_ddl(corr_t, dec_t, key_types = types[key])
  invisible(DBI::dbExecute(con, ddl[["corrections"]]))
  invisible(DBI::dbExecute(con, ddl[["decisions"]]))
}
r <- record_legacy_facts(con, rows, corr_t, dec_t)
message("record  ", r$appended, " appended, ", r$already_present,
        " already present")

corrected <- corrected_variables(con, corr_t, view)
invisible(DBI::dbExecute(con, corrections_view_sql(view, base, corr_t, dec_t,
                                                   view, key, names(types),
                                                   corrected, types)))
invisible(DBI::dbExecute(con, stale_view_sql(stale_v, base, corr_t, dec_t,
                                             view, key, names(types),
                                             corrected, types)))
n_stale <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s",
                                        q(stale_v)))$n
message("views   ", view, " regenerated over ", length(corrected),
        " corrected variables; ", n_stale, " stale corrections")
