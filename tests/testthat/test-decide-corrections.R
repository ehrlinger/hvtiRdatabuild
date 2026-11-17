# No PHI: identifiers and values are invented.

decide_setup <- function(env = parent.frame()) {
  con <- local_sources_db(env)
  cfg <- corrections_config(env)
  deploy_sources(con, cfg)
  DBI::dbAppendTable(con, "stg_echo_corrections", rbind(
    corr_row("c01", "SYN201", "2020-01-01", "lvef", "30", 0L, "35", 0L,
             asserted_by = "reviewer_a"),
    corr_row("c02", "SYN203", "2020-03-01", "lvef", "40", 0L, "41", 0L,
             asserted_by = "dm_two"),
    corr_row("c03", "SYN203", "2020-03-01", "mr_grade", NA, 1L, "1", 0L,
             asserted_by = "reviewer_a"),
    corr_row("c04", "SYN204", "2020-04-01", "lvef", "50", 0L, "51", 0L,
             asserted_by = "reviewer_a")
  ))
  list(con = con, cfg = cfg)
}

decisions_df <- function(...) {
  d <- data.frame(source = "stg_echo", correction_id = "c01", decision = "accept",
                  decided_by = "dm_one", reason = "chart confirms",
                  stringsAsFactors = FALSE)
  over <- list(...)
  d[names(over)] <- over
  d
}

test_that("an accept by a named decider is recorded, and applies", {
  s <- decide_setup()
  out <- decide_corrections(s$cfg, s$con, decisions_df(), dry_run = FALSE,
                            dialect = "duckdb")
  expect_identical(out$recorded, 1L)
  got <- DBI::dbGetQuery(s$con, "SELECT lvef FROM stg_echo_corrected WHERE mrn = 'SYN201'")
  expect_identical(got$lvef, 35)
})

test_that("each refusal has its verdict, and one refuses the whole batch", {
  s <- decide_setup()
  d <- rbind(decisions_df(),
             decisions_df(source = "stg_nowhere"),
             decisions_df(correction_id = "c99"),
             decisions_df(correction_id = "c03", decision = "approve"),
             decisions_df(correction_id = "c04", decided_by = "someone_else"),
             decisions_df(correction_id = "c02", decided_by = "dm_two"))
  out <- decide_corrections(s$cfg, s$con, d, dialect = "duckdb")
  expect_identical(out$verdicts$verdict, c("recordable", "unknown_source",
                                           "unknown_correction", "invalid_decision",
                                           "not_decider", "self_accepted"))
  expect_error(decide_corrections(s$cfg, s$con, d, dry_run = FALSE, dialect = "duckdb"),
               class = "hvtiRdatabuild_decisions_refused")
  n <- DBI::dbGetQuery(s$con, "SELECT COUNT(*) AS n FROM stg_echo_correction_decisions")$n
  expect_identical(n, 0)
})

test_that("a batch deciding one correction twice is refused, whatever the decisions", {
  s <- decide_setup()
  d <- rbind(decisions_df(), decisions_df(decision = "reject"))
  out <- decide_corrections(s$cfg, s$con, d, dialect = "duckdb")
  expect_identical(out$verdicts$verdict, c("repeated_correction", "repeated_correction"))
  expect_error(decide_corrections(s$cfg, s$con, d, dry_run = FALSE, dialect = "duckdb"),
               class = "hvtiRdatabuild_decisions_refused")
})

test_that("a master.yml with no deciders cannot decide", {
  s <- decide_setup()
  s$cfg$deciders <- NULL
  expect_error(decide_corrections(s$cfg, s$con, decisions_df(), dialect = "duckdb"),
               class = "hvtiRdatabuild_no_deciders")
})

test_that("a fill-in upstream has caught up with is retired with a bake decision", {
  s <- decide_setup()
  decide_corrections(s$cfg, s$con, decisions_df(correction_id = "c03"), dry_run = FALSE,
                     dialect = "duckdb")
  stale <- DBI::dbGetQuery(s$con, "SELECT * FROM stg_echo_corrections_stale")
  expect_identical(stale$reason, "filled_upstream_agrees")
  dry <- retire_filled_corrections(s$cfg, s$con, "stg_echo", dialect = "duckdb")
  expect_identical(dry$correction_ids, "c03")
  expect_identical(dry$recorded, 0L)
  out <- retire_filled_corrections(s$cfg, s$con, "stg_echo", dry_run = FALSE,
                                   dialect = "duckdb")
  expect_identical(out$recorded, 1L)
  expect_identical(nrow(DBI::dbGetQuery(s$con,
                                        "SELECT * FROM stg_echo_corrections_stale")), 0L)
  last <- DBI::dbGetQuery(s$con, paste("SELECT decision, decided_by FROM",
                                       "stg_echo_correction_decisions WHERE",
                                       "decided_by = 'filled_upstream'"))
  expect_identical(last$decision, "bake")
})
