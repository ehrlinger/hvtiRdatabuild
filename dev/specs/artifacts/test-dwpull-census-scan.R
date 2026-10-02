#!/usr/bin/env Rscript
# test-dwpull-census-scan.R
#
# Checks `dwpull-census-scan.R` against synthetic warehouse pulls whose edits
# from the template are known by construction.
#
#   Rscript test-dwpull-census-scan.R
#
# NO PHI. Every study name, library, dataset and variable here is invented. The
# identifiers in WHERE clauses (`SYN0001` and kin) and the server name are canaries:
# they exist so the test can assert they never reach the output.

self <- sub(
  "^--file=", "",
  grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
)
here <- if (length(self)) dirname(self[[1]]) else "."
scan_script <- file.path(here, "dwpull-census-scan.R")
stopifnot(file.exists(scan_script))

if (!requireNamespace("hvtiRutilities", quietly = TRUE)) {
  message(
    "SKIP: hvtiRutilities could not be loaded, so the scan cannot run.\n",
    "  This R:   ", R.version.string, "\n",
    "  libPaths: ", paste(.libPaths(), collapse = "\n            ")
  )
  quit(save = "no", status = 0)
}

root <- file.path(tempdir(), paste0("dwpull-fixture-", Sys.getpid()))
folder <- unique(hvtiRutilities::hvti_taxonomy()$folder)[[1]]
put <- function(study, file, lines) {
  d <- file.path(root, study, folder)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, file.path(d, file))
}

# ---- the template -------------------------------------------------------------
# Seven blocks, shaped like tp.stXXXX_dwpull.sas: five module pulls, the coronary
# ad hoc pull, and the cohort upload. ⚠️ The `*` comment carries an apostrophe,
# which a regex-only string masker would read as an opening quote.
pull <- function(ds, select, from, where = NULL) {
  c(
    paste0("  create table dat.", ds, " as select * from connection to wh ("),
    paste0("    select ", select),
    paste0("    from HVI_DM.ST.stXXXX_cohort c"),
    paste0("    ", from), if (!is.null(where)) paste0("    where ", where), "  );"
  )
}
dd_echo <- paste(
  "(datediff(day, e.dtn_echo, c.dtn_inst) <= 180",
  "or datediff(day, c.dtn_inst, e.dtn_echo) >= 0)"
)
dd_cath <- paste(
  "(datediff(day, k.dt_cath, c.dtn_inst) <= 60",
  "or datediff(day, c.dtn_inst, k.dt_cath) >= 0)"
)
upload <- c(
  paste0(
    "libname libsql odbc noprompt=\"driver=SQL Server;server=SYNSERVER01;",
    "database=HVI_DM;uid=&dbuid;pwd=&dbpwd\" schema=ST;"
  ),
  "data libsql.stXXXX_cohort; set dat.cohort; run;"
)
template <- function(extra_pulls = NULL, echo_where = dd_echo, cath_where = dd_cath,
                     valve_join = "inner", with_upload = TRUE) {
  c(
    "/* tp.stXXXX_dwpull.sas -- invented for the fixture */",
    "%include '/invented/secret/dbcreds.sas';",
    "libname dat '/invented/study/datasets';",
    "* pull the cohort's records from the warehouse, and don't edit below;",
    "proc sql;",
    paste0(
      "  connect to odbc as wh (noprompt=\"driver=SQL Server;server=SYNSERVER01;",
      "database=warehouse;uid=&dbuid;pwd=&dbpwd\");"
    ),
    pull(
      "bdbase", "c.*, s.*, v.*, w.*",
      c(
        "inner join warehouse.dbo.vw_CardSurg_Base s on c.masterid = s.masterid",
        paste0(
          "    ", valve_join,
          " join warehouse.dbo.vw_CardSurg_Valve v on c.masterid = v.masterid"
        ),
        "    inner join warehouse.dbo.vw_CardSurg_Cabg w on c.masterid = w.masterid"
      )
    ),
    pull(
      "bdstat", "c.masterid, s.patid, s.masterid, s.dtn_inst, s.dt_vstat, s.vit_stat",
      "inner join warehouse.dbo.vw_CardSurg_Base s on c.masterid = s.masterid"
    ),
    pull(
      "echo", "c.patid, c.dtn_inst, c.mrn, e.*",
      "inner join warehouse.dbo.vw_Echo_Base e on e.patid = c.patid",
      paste(echo_where, "order by c.mrn, c.dtn_inst")
    ),
    pull(
      "fup", "c.patid, c.masterid, c.mrn, c.dtn_surg dtn_inst, s.*",
      "inner join warehouse.dbo.vw_FUP_Base s on c.patid = s.patid"
    ),
    pull(
      "bdevents", "c.mrn, c.dtn_inst, c.patid, s.dtn_inst dtn_evst, s.sp_cabg rp_cabg",
      paste(
        "inner join warehouse.dbo.vw_CardSurg_Base s",
        "on c.patid = s.patid and c.dtn_inst < s.dtn_inst"
      )
    ),
    "  * ad hoc example: coronary cath near surgery;",
    pull(
      "cath", "c.patid, c.dtn_inst, k.dt_cath, k.cath_lm",
      "inner join warehouse.dbo.Event_CardSurg_Coronary k on k.patid = c.patid",
      cath_where
    ),
    extra_pulls,
    "  disconnect from wh;", "quit;",
    if (with_upload) upload
  )
}
as_study <- function(lines, id) gsub("stXXXX", id, lines, fixed = TRUE)
extra <- pull(
  "extra", "c.patid, x.newcol_common, x.dt_extra",
  "left join warehouse.dbo.vw_Sts_Extra x on x.patid = c.patid"
)
drifted <- template(echo_where = sub("180", "365", dd_echo), with_upload = FALSE)

# ---- the corpus ---------------------------------------------------------------
# Template copies: three canonical, one drifted.
for (s in c("cardiac/u1", "cardiac/u2", "cardiac/lj")) {
  put(
    s, "tp.stXXXX_dwpull.sas",
    template()
  )
}
put("cardiac/d1", "tp.stXXXX_dwpull.sas", drifted)

# u1: the template, byte for byte. u2: only the study number filled in.
put("cardiac/u1", "st0100_dwpull.sas", template())
put("cardiac/u2", "st0102_dwpull.sas", as_study(template(), "st0102"))

# nv1-3 add a pull from a new view, above the floor of 3 studies. nv1 also adds a
# view and a column that ONE study uses: below the floor, never to be named.
put("cardiac/nv1", "st0201_dwpull.sas", as_study(template(c(
  extra, pull(
    "rare", "c.patid, r.zz_rarecol",
    "inner join warehouse.dbo.vw_Rare_Thing r on r.patid = c.patid"
  )
)), "st0201"))
put("cardiac/nv2", "st0202_dwpull.sas", as_study(template(extra), "st0202"))
put("thoracic/nv3", "st0203_dwpull.sas", as_study(template(extra), "st0203"))

# lj: the inner join to Valve becomes a left join.
put("cardiac/lj", "st0300_dwpull.sas", as_study(template(valve_join = "left"), "st0300"))

# fixwin: both lopsided ORs closed into ANDs, and the echo window narrowed to 90.
put("cardiac/fixwin", "st0400_dwpull.sas", as_study(template(
  echo_where = sub(" or ", " and ", sub("180", "90", dd_echo)),
  cath_where = sub(" or ", " and ", dd_cath)
), "st0400"))

# adhoc: a pull from an event view the template never reads, with a BETWEEN window.
put("cardiac/adhoc", "st0500_dwpull.sas", as_study(template(pull(
  "valveev", "c.patid, ev.dt_event",
  "inner join warehouse.dbo.Event_CardSurg_Valve ev on ev.patid = c.patid",
  "datediff(day, c.dtn_inst, ev.dt_event) between 0 and 30"
)), "st0500"))

# noup: the cohort upload removed.
put("cardiac/noup", "st0600_dwpull.sas", as_study(template(with_upload = FALSE), "st0600"))

# 🔴 lit: literal identifiers in WHERE clauses, in the pass-through and in SAS.
put("cardiac/lit", "st0700_dwpull.sas", c(
  as_study(template(
    echo_where = paste(
      dd_echo, "and c.mrn not in ('SYN0001', 'SYN0002')",
      "and c.patid <> 99887766"
    )
  ), "st0700"),
  "data dat.keep; set dat.echo; where mrn in ('SYN0003'); run;"
))

# drift: a study instance made from the drifted template copy.
put("cardiac/d1", "st0900_dwpull.sas", as_study(drifted, "st0900"))

# 🔴 The %include target, inside the root, under a name the pattern does not
# match. If the scan ever opened it, its canary would reach the output.
put(
  "cardiac/u1", "dbcreds.sas",
  c(
    "%let dbpwd = CANARYPWD;",
    "proc sql; create table x as select * from warehouse.dbo.vw_Canary_View;"
  )
)

# ---- run ----------------------------------------------------------------------
outfile <- file.path(root, "out.json")
rscript <- file.path(R.home("bin"), "Rscript")
res <- system2(rscript, c(
  shQuote(normalizePath(scan_script)),
  "--root", shQuote(root), "--out", shQuote(outfile)
),
stdout = TRUE, stderr = TRUE
)
if (!file.exists(outfile)) {
  cat(res, sep = "\n")
  stop("scan produced no output")
}
raw <- readLines(outfile)
j <- paste(raw, collapse = " ")
console <- paste(res, collapse = "\n")
num <- function(field) {
  m <- regmatches(j, regexpr(paste0("\"", field, "\": *-?[0-9]+"), j))
  if (!length(m)) stop("field not found: ", field)
  as.integer(sub(".*: *", "", m))
}

expected <- list(
  study_instance_files = 11L,
  template_files = 4L,
  studies = 11L,
  # ⭐ u1 is byte-identical; u2 differs only in the study number.
  studies_byte_identical_to_canonical = 1L,
  studies_structurally_identical_to_canonical = 2L,
  byte_variants = 2L,
  canonical_files = 3L,
  # vw_sts_extra, vw_rare_thing and event_cardsurg_valve
  beyond_template_distinct = 3L,
  studies_left_join_valve_or_cabg = 1L,
  # every instance but fixwin keeps at least one lopsided OR
  studies_lopsided = 10L,
  # nv1, nv2, nv3, adhoc
  studies_with_pull_beyond_template = 4L,
  # every instance but noup and drift
  studies_writing_via_odbc_libref = 9L,
  # drift sits nearest the drifted template copy
  instances_nearest_drifted = 1L,
  studies_with_include = 11L,
  unparsed_datediff = 0L
)

fail <- 0L
for (nm in names(expected)) {
  got <- num(nm)
  ok <- identical(got, expected[[nm]])
  if (!ok) fail <- fail + 1L
  message(sprintf(
    "%-44s expected %2d  got %2d  %s", nm, expected[[nm]], got,
    if (ok) "ok" else "FAIL"
  ))
}
check <- function(label, cond) {
  if (!isTRUE(cond)) {
    message("FAIL  ", label)
    fail <<- fail + 1L
  } else {
    message(sprintf("%-44s ok", label))
  }
}

# ⭐ What the scan is for: names above the floor are reported.
check("view above the floor is named", grepl("warehouse.dbo.vw_sts_extra", j, fixed = TRUE))
check("column above the floor is named", grepl("\"newcol_common\"", j, fixed = TRUE))
check("sp_ -> rp_ rename pattern reported", grepl("sp_* -> rp_*", j, fixed = TRUE))
check("lopsided canonical flagged", grepl("\"canonical_is_lopsided\": true", j, fixed = TRUE))
check("narrowed window signature reported", grepl("\"before <= 90\": 1", j, fixed = TRUE))
check("between window parsed", grepl("after between 0..30", j, fixed = TRUE))
check("upload db reduced to hvi_dm", grepl("\"hvi_dm\": 9", j, fixed = TRUE))
check("connect db reduced to warehouse", grepl("\"warehouse\": 11", j, fixed = TRUE))
check("left join counted by type", grepl("\"left\": 4", j, fixed = TRUE))
# The drifted variant's diff names the window it changed, and the upload it lost.
check("variant diff shows the widened window", grepl("win:before <= 365", j, fixed = TRUE))
check(
  "variant diff shows the lost upload",
  grepl("\"removed\": \\{ *\"named\": \\[[^]]*\"upload\"", j)
)

# ⚠️ The floor. One study each: counted, never named.
for (x in c("vw_rare_thing", "zz_rarecol", "event_cardsurg_valve")) {
  check(paste("below-floor name withheld:", x), !grepl(x, j, fixed = TRUE))
}

# 🔴 THE PRIVACY ASSERTIONS. Case-insensitive, because the scan lowercases.
lj <- tolower(j)
lc <- tolower(console)
canaries <- c(
  "syn0001", "syn0002", "syn0003", "99887766", "synserver01",
  "dbcreds", "invented/secret", "invented/study", "canary", "dbpwd",
  "cardiac", "thoracic", "nv1", "fixwin", "st0100", "st0201", "st0700"
)
for (x in canaries) {
  check(paste("absent from JSON:", x), !grepl(x, lj, fixed = TRUE))
  check(paste("absent from console:", x), !grepl(x, lc, fixed = TRUE))
}
# No path of any kind reaches the JSON.
check("no fixture path in JSON", !grepl(tolower(root), lj, fixed = TRUE))

# --count-only reads nothing and writes nothing.
o2 <- file.path(root, "count.json")
system2(rscript, c(
  shQuote(normalizePath(scan_script)), "--root", shQuote(root),
  "--out", shQuote(o2), "--count-only"
),
stdout = FALSE, stderr = FALSE
)
check("--count-only writes nothing", !file.exists(o2))

want_fp <- if (requireNamespace("digest", quietly = TRUE)) {
  "md5"
} else {
  "weighted-sums (COLLISION-PRONE)"
}
check("reports its fingerprint", grepl(paste0('"fingerprint": "', want_fp, '"'), j,
  fixed = TRUE
))

# ⚠️ An empty census must fail, not report zero. The first real run met an
# unmounted share and printed "candidate files: 0" with exit status 0.
exit_of <- function(r) {
  s <- suppressWarnings(system2(rscript, c(scan_script, "--root", r, "--count-only"),
    stdout = FALSE, stderr = FALSE
  ))
  if (is.null(s)) 0L else as.integer(s)
}
empty_root <- file.path(tempdir(), paste0("dwpull-empty-", Sys.getpid()))
dir.create(empty_root)
check("missing root exits nonzero", exit_of(file.path(empty_root, "absent")) != 0L)
check("root with no dwpull programs exits nonzero", exit_of(empty_root) != 0L)
unlink(empty_root, recursive = TRUE)

# ⚠️ A subquery in FROM leaves the reader no table alias. The first real run
# stopped on exactly this with `startsWith(unlist(alias), ...)`: unlist() of an
# empty list is NULL. It must complete, and report no parse error.
subq_root <- file.path(tempdir(), paste0("dwpull-subq-", Sys.getpid()))
d <- file.path(subq_root, "cardiac", "synth", folder)
dir.create(d, recursive = TRUE)
writeLines(c(
  "proc sql;",
  "  connect to odbc (noprompt=\"driver=x; database=HVI_DM; uid=&dbuid; pwd=&dbpwd;\");",
  "  create table work.a as select * from connection to odbc",
  "    (select x.* from (select b.masterid from warehouse.dbo.vw_CardSurg_Base b) x);",
  "  disconnect from odbc;",
  "quit;"
), file.path(d, "st0001_dwpull.sas"))
subq_out <- file.path(subq_root, "out.json")
subq_status <- suppressWarnings(system2(rscript, c(
  scan_script, "--root", subq_root, "--out", subq_out
), stdout = FALSE, stderr = FALSE))
check("subquery in FROM does not halt the scan", is.null(subq_status) || subq_status == 0L)
subq_json <- if (file.exists(subq_out)) paste(readLines(subq_out), collapse = "\n") else ""
check("subquery in FROM is not a parse error",
      grepl("\"files_parse_error\": 0", subq_json, fixed = TRUE))
unlink(subq_root, recursive = TRUE)

unlink(root, recursive = TRUE)
if (fail) {
  message("\n", fail, " failure(s)")
  quit(save = "no", status = 1)
}
message("\nall checks passed")
