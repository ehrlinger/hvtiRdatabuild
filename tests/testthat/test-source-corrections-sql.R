# No PHI: identifiers and values are invented.

test_that("table_types() keeps a decimal's precision and scale", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbExecute(con, "CREATE TABLE t_dec (a DECIMAL(10,2), b INTEGER)")
  expect_identical(unname(table_types(con, "t_dec")), c("DECIMAL(10,2)", "INTEGER"))
})

test_that("parse_value() reads logical text", {
  expect_identical(parse_value("1", "logical"), TRUE)
  expect_identical(parse_value("FALSE", "logical"), FALSE)
  expect_identical(parse_value("maybe", "logical"), NA)
  expect_identical(value_text(TRUE), "TRUE")
})

test_that("each source gets its own typed corrections and decisions tables", {
  con <- local_sources_db()
  types <- table_types(con, "stg_echo")
  ddl <- source_corrections_ddl("stg_echo", types[c("mrn", "encounter_date")], "duckdb")
  expect_named(ddl, c("corrections", "decisions"))
  for (s in ddl) DBI::dbExecute(con, s)
  got <- table_types(con, "stg_echo_corrections")
  expect_identical(unname(got[c("mrn", "encounter_date")]), unname(types[c("mrn",
                                                                           "encounter_date")]))
  expect_true(all(c("source", "variable", "expected_prior_missing") %in% names(got)))
  expect_true(DBI::dbExistsTable(con, "stg_echo_correction_decisions"))
})

test_that("the R reference applies each rule of the case matrix", {
  con <- local_sources_db()
  base <- DBI::dbGetQuery(con, "SELECT * FROM stg_echo ORDER BY mrn")
  ref <- resolve_source_corrections(base, case_corrections(), case_decisions(),
                                    c("mrn", "encounter_date"))
  expect_identical(ref$data$lvef, c(35, 45, 40, 50, 55))
  expect_identical(ref$data$mr_grade, c("3", "3", "1", NA, "4"))
  expect_identical(sort(ref$applied$correction_id),
                   c("c01", "c02", "c05", "c06", "c14", "c15"))
  stale <- stats::setNames(ref$stale$reason, ref$stale$correction_id)
  expect_identical(stale[sort(names(stale))],
                   c(c07 = "filled_upstream_agrees", c09 = "prior_mismatch",
                     c10 = "no_variable", c11 = "no_record", c12 = "prior_unknown",
                     c13 = "does_not_cast"))
  conf <- stats::setNames(ref$conflicts$reason, ref$conflicts$correction_id)
  expect_identical(conf[sort(names(conf))],
                   c(c03 = "accepted_disagree", c04 = "accepted_disagree",
                     c08 = "filled_upstream_disagrees"))
  expect_false(any(c("c16", "c17") %in% c(ref$applied$correction_id,
                                          ref$stale$correction_id,
                                          ref$conflicts$correction_id)))
})

test_that("the generated views agree with the R reference on every rule", {
  con <- local_sources_db()
  deploy_echo(con)
  key <- c("mrn", "encounter_date")
  base <- DBI::dbGetQuery(con, "SELECT * FROM stg_echo ORDER BY mrn")
  ref <- resolve_source_corrections(base, case_corrections(), case_decisions(), key)
  srt <- function(d) {
    d <- d[do.call(order, unname(as.list(d))), , drop = FALSE]
    rownames(d) <- NULL
    d
  }
  expect_equal(DBI::dbGetQuery(con, "SELECT * FROM stg_echo_corrected ORDER BY mrn"),
               ref$data, ignore_attr = TRUE)
  expect_equal(srt(DBI::dbGetQuery(con, "SELECT * FROM stg_echo_corrections_applied")),
               srt(ref$applied), ignore_attr = TRUE)
  expect_equal(srt(DBI::dbGetQuery(con, "SELECT * FROM stg_echo_corrections_stale")),
               srt(ref$stale), ignore_attr = TRUE)
  expect_equal(srt(DBI::dbGetQuery(con, "SELECT * FROM stg_echo_corrections_conflicts")),
               srt(ref$conflicts), ignore_attr = TRUE)
})

test_that("a first correction to an untouched column is live with no redeployment", {
  con <- local_sources_db()
  deploy_echo(con, case_corrections()[0, ], case_decisions()[0, ])
  before <- DBI::dbGetQuery(con, "SELECT * FROM stg_echo_corrected ORDER BY mrn")
  expect_identical(before$seen_on, DBI::dbGetQuery(con, "SELECT seen_on FROM stg_echo
                                                     ORDER BY mrn")$seen_on)
  DBI::dbAppendTable(con, "stg_echo_corrections",
                     corr_row("c50", "SYN202", "2020-02-01", "seen_on", NA, 1L,
                              "2020-01-15", 0L))
  DBI::dbAppendTable(con, "stg_echo_correction_decisions", dec_row("d50", "c50"))
  after <- DBI::dbGetQuery(con, "SELECT seen_on FROM stg_echo_corrected ORDER BY mrn")
  expect_identical(after$seen_on[[2]], as.Date("2020-01-15"))
})

test_that("the corrected view keeps the source's columns, order and types", {
  con <- local_sources_db()
  deploy_echo(con)
  expect_identical(table_types(con, "stg_echo_corrected"), table_types(con, "stg_echo"))
})

test_that("a supersede decision settles a G1 conflict", {
  con <- local_sources_db()
  decisions <- rbind(case_decisions(),
                     dec_row("d70", "c04", "supersede", on = "2026-04-01"))
  deploy_echo(con, decisions = decisions)
  got <- DBI::dbGetQuery(con, "SELECT lvef FROM stg_echo_corrected WHERE mrn = 'SYN203'")
  expect_identical(got$lvef, 41)
  conflicts <- DBI::dbGetQuery(con, "SELECT correction_id FROM stg_echo_corrections_conflicts")
  expect_false(any(c("c03", "c04") %in% conflicts$correction_id))
})

test_that("a key duplicated after acceptance changes no row, in SQL and in R", {
  con <- local_sources_db()
  deploy_echo(con)
  DBI::dbExecute(con, paste("INSERT INTO stg_echo VALUES",
                            "('SYN201', DATE '2020-01-01', 30, '2', NULL)"))
  got <- DBI::dbGetQuery(con, "SELECT lvef, mr_grade FROM stg_echo_corrected
                               WHERE mrn = 'SYN201'")
  expect_identical(got$lvef, c(30, 30))           # c01 no longer applies to either row
  expect_identical(got$mr_grade, c("2", "2"))     # nor do c05 and c06
  expect_identical(nrow(DBI::dbGetQuery(con, "SELECT * FROM stg_echo_corrected")), 6L)
  stale <- DBI::dbGetQuery(con, "SELECT * FROM stg_echo_corrections_stale")
  expect_setequal(stale$correction_id[stale$reason == "ambiguous_record"],
                  c("c01", "c05", "c06"))
  ref <- resolve_source_corrections(DBI::dbGetQuery(con, "SELECT * FROM stg_echo"),
                                    case_corrections(), case_decisions(),
                                    c("mrn", "encounter_date"))
  expect_setequal(ref$stale$correction_id[ref$stale$reason == "ambiguous_record"],
                  c("c01", "c05", "c06"))
  expect_false(any(c("c01", "c05", "c06") %in% ref$applied$correction_id))
})

test_that("the mssql views compare names, character keys and counted values exactly", {
  types <- c(mrn = "varchar(20)", visit_no = "int", lvef = "float", grade = "varchar(5)")
  v <- source_views_sql("stg_x", c("mrn", "visit_no"), types, "mssql")
  bin2 <- "COLLATE Latin1_General_BIN2"
  for (view in v) {
    expect_match(view, paste0("a.variable ", bin2, " = N'lvef' ", bin2), fixed = TRUE)
    expect_match(view, "DATALENGTH(a.variable) = DATALENGTH(N'lvef')", fixed = TRUE)
    expect_match(view, paste0("b.[mrn] ", bin2, " = a.[mrn] ", bin2), fixed = TRUE)
    expect_match(view, paste0("k.variable ", bin2, " = a.variable ", bin2), fixed = TRUE)
    expect_match(view, "CONCAT(DATALENGTH(new_value), '|', new_value COLLATE", fixed = TRUE)
    expect_no_match(view, "NOT IN", fixed = TRUE)
    # The numeric key is joined plainly, never collated.
    expect_match(view, "b.[visit_no] = a.[visit_no]", fixed = TRUE)
    expect_no_match(view, "[visit_no] COLLATE", fixed = TRUE)
  }
  expect_match(v[["corrected"]], paste0("variable ", bin2, " = N'grade' ", bin2), fixed = TRUE)
  expect_match(v[["corrected"]], paste0("p.[mrn] ", bin2, " = b.[mrn] ", bin2), fixed = TRUE)
  expect_match(v[["corrected"]], "p.[visit_no] = b.[visit_no]", fixed = TRUE)
  # Each of cell, bc and p groups the character key exactly and the numeric key plainly.
  corrected <- v[["corrected"]]
  groups <- regmatches(corrected, gregexpr("GROUP BY [^\n]*", corrected))[[1]]
  expect_length(groups, 3L)
  for (g in groups) {
    expect_match(g, paste0("[mrn] ", bin2, ", DATALENGTH([mrn])"), fixed = TRUE)
    expect_match(g, "[visit_no]", fixed = TRUE)
    expect_no_match(g, "[visit_no] COLLATE", fixed = TRUE)
    expect_no_match(g, "DATALENGTH([visit_no])", fixed = TRUE)
  }
  expect_match(groups[[1]], paste0("[variable] ", bin2, ", DATALENGTH([variable])"), fixed = TRUE)
  expect_match(corrected, paste0("[mrn] ", bin2, " AS [mrn]"), fixed = TRUE)
})

test_that("source_views_sql() refuses a key outside the columns and a keys-only source", {
  expect_error(source_views_sql("s", "nope", c(a = "int", b = "int"), "duckdb"),
               class = "hvtiRdatabuild_source_views_key")
  expect_error(source_views_sql("s", "a", c(a = "int"), "duckdb"),
               class = "hvtiRdatabuild_source_views_no_columns")
})
