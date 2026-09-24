# Tests for backfill_corrections(), propose_correction() and decide_correction().
# Every id and value is invented. No PHI.

corr_fixture <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  d <- data.frame(
    ccfid = c("K1", "K2", "K3"), dt_surg = as.Date("2020-01-01") + 0:2,
    emrn = c("E1", NA, "E3"), age = c(65.5, NA, 70),
    surgeon = c("S1", "S2", "S3"), stringsAsFactors = FALSE
  )
  pq <- file.path(dir, "built_t.parquet")
  arrow::write_parquet(d, pq)
  jsonlite::write_json(
    list(parquet_sha256 = digest::digest(pq, algo = "sha256", file = TRUE), columns = list(
      list(variable = "ccfid", r_class = "character"),
      list(variable = "dt_surg", r_class = "Date"),
      list(variable = "emrn", r_class = "character"),
      list(variable = "age", r_class = "numeric"),
      list(variable = "surgeon", r_class = "character")
    )),
    file.path(dir, "built_t.meta.json"),
    auto_unbox = TRUE
  )
  writeLines(c(
    "data m; set base;",
    "if ccfid = 'K1' then age = 66;",
    "if ccfid = 'K2' then ccfid = 'K9';",
    "run;"
  ), file.path(dir, "bd.sas"))
  cfg <- structure(list(
    name = "master_c", key = c("ccfid", "dt_surg"),
    alt_keys = list(epic = "emrn"), parent = NULL,
    parent_release = NULL, snapshots = dir, current = "built_t.sas7bdat",
    history = NULL, build_program = file.path(dir, "bd.sas"),
    file = file.path(dir, "master.yml")
  ), class = "master_config")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
  suppressMessages(lift_master(cfg, con, pq, dry_run = FALSE, dialect = "duckdb"))
  list(cfg = cfg, con = con)
}

skip_corr <- function() {
  for (p in c("arrow", "duckdb", "jsonlite", "dplyr", "withr", "tidyselect", "digest")) {
    testthat::skip_if_not_installed(p)
  }
}

test_that("the backfill dry run counts and writes nothing", {
  skip_corr()
  f <- corr_fixture()
  r <- suppressMessages(backfill_corrections(f$cfg, f$con, dialect = "duckdb"))
  expect_true(r$dry_run)
  expect_equal(r$resolved, 1L)
  expect_false(DBI::dbExistsTable(f$con, "master_c_corrections"))
})

test_that("an executed backfill records baked facts, remaps the key, regenerates the view", {
  skip_corr()
  f <- corr_fixture()
  r <- suppressMessages(backfill_corrections(f$cfg, f$con,
    dry_run = FALSE,
    dialect = "duckdb"
  ))
  expect_equal(r$appended, 1L)
  expect_equal(r$unresolved, 1L)
  dec <- DBI::dbGetQuery(f$con, "SELECT decision FROM master_c_correction_decisions")
  expect_equal(dec$decision, "bake")
  v <- DBI::dbGetQuery(f$con, "SELECT age FROM master_c WHERE ccfid = 'K1'")
  expect_equal(v$age, 65.5)
  expect_true(DBI::dbExistsTable(f$con, "master_c_corrections_stale"))
})

test_that("a backfilled legacy row also stores the base row's alternate-key columns", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  row <- DBI::dbGetQuery(f$con,
    "SELECT emrn FROM master_c_corrections WHERE evidence_type = 'legacy_sas_inline'"
  )
  expect_equal(row$emrn, "E1")
})

test_that("a proposal found by alternate key is stored against the primary key", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  r <- suppressMessages(propose_correction(
    f$cfg, f$con,
    key_values = list(emrn = "E3"), alt_key = "epic", variable = "age",
    expected_prior = 70, new_value = 71, evidence_type = "chart_review",
    evidence_ref = "invented", asserted_by = "tester", dialect = "duckdb"
  ))
  row <- DBI::dbGetQuery(f$con, sprintf(
    "SELECT ccfid, emrn FROM master_c_corrections WHERE correction_id = '%s'",
    r$correction_id
  ))
  expect_equal(row$ccfid, "K3")
  expect_equal(row$emrn, "E3")
})

test_that("a primary-key proposal also carries the base row's alternate-key columns", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  r <- suppressMessages(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K3", dt_surg = as.Date("2020-01-03")),
    variable = "age", expected_prior = 70, new_value = 72, evidence_type = "chart_review",
    evidence_ref = "invented", asserted_by = "tester", dialect = "duckdb"
  ))
  row <- DBI::dbGetQuery(f$con, sprintf(
    "SELECT emrn FROM master_c_corrections WHERE correction_id = '%s'", r$correction_id
  ))
  expect_equal(row$emrn, "E3")
})

test_that("a primary-key proposal must name exactly the key columns, each one value", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  expect_error(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K1"), variable = "age", expected_prior = 65.5, new_value = 66,
    evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester",
    dialect = "duckdb"
  ), "primary key columns")
  expect_error(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K1", dt_surg = NA), variable = "age", expected_prior = 65.5,
    new_value = 66, evidence_type = "chart_review", evidence_ref = "invented",
    asserted_by = "tester", dialect = "duckdb"
  ), "primary key columns")
})

test_that("an alternate-key column cannot be corrected through the primary-key path", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  expect_error(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K1", dt_surg = as.Date("2020-01-01")),
    variable = "emrn", expected_prior = "E1", new_value = "E9",
    evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester",
    dialect = "duckdb"
  ), "key column")
})

test_that("a failing warehouse call during propose is reported by step, without a value", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  testthat::local_mocked_bindings(
    table_types = function(con, table) stop("mock failure quoting SECRET_VALUE"),
    .package = "hvtiRdatabuild"
  )
  msg <- tryCatch(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K1", dt_surg = as.Date("2020-01-01")),
    variable = "age", expected_prior = 65.5, new_value = 66, evidence_type = "chart_review",
    evidence_ref = "invented", asserted_by = "tester", dialect = "duckdb"
  ), error = conditionMessage)
  expect_match(msg, "Step 'read column types' failed")
  expect_false(grepl("SECRET_VALUE", msg))
})

test_that("a failing warehouse call during decide is reported by step, without a value", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  r <- suppressMessages(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K1", dt_surg = as.Date("2020-01-01")),
    variable = "surgeon", expected_prior = "S1", new_value = "S9",
    evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester",
    dialect = "duckdb"
  ))
  testthat::local_mocked_bindings(
    quoter = function(dialect) function(x) paste0("BOGUS_TOKEN(", x, ")"),
    .package = "hvtiRdatabuild"
  )
  msg <- tryCatch(
    decide_correction(f$cfg, f$con, r$correction_id, "accept", "tester", dialect = "duckdb"),
    error = conditionMessage
  )
  expect_match(msg, "Step '.*' failed")
  expect_false(grepl("BOGUS_TOKEN", msg))
})

test_that("an alternate key with a null part or no match stops without a value", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  msg <- tryCatch(
    propose_correction(
      f$cfg, f$con,
      key_values = list(emrn = "E404"), alt_key = "epic", variable = "age",
      expected_prior = 70, new_value = 71, evidence_type = "chart_review",
      evidence_ref = "invented", asserted_by = "tester", dialect = "duckdb"
    ),
    error = conditionMessage
  )
  expect_match(msg, "matched 0 rows")
  expect_false(grepl("E404", msg))
  expect_error(propose_correction(
    f$cfg, f$con,
    key_values = list(emrn = NA), alt_key = "epic", variable = "age",
    expected_prior = 70, new_value = 71, evidence_type = "chart_review",
    evidence_ref = "invented", asserted_by = "tester", dialect = "duckdb"
  ), "null")
})

test_that("writer dry runs return the row and leave both tables unchanged", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  n0 <- DBI::dbGetQuery(f$con, "SELECT COUNT(*) AS n FROM master_c_corrections")$n
  r <- propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K3", dt_surg = as.Date("2020-01-03")),
    variable = "age", expected_prior = 70, new_value = 71, evidence_type = "chart_review",
    evidence_ref = "invented", asserted_by = "tester", dry_run = TRUE, dialect = "duckdb"
  )
  expect_equal(r$verdict, "validated")
  expect_equal(nrow(r$row), 1L)
  expect_equal(
    DBI::dbGetQuery(f$con, "SELECT COUNT(*) AS n FROM master_c_corrections")$n,
    n0
  )
  d <- decide_correction(f$cfg, f$con, DBI::dbGetQuery(
    f$con, "SELECT correction_id FROM master_c_corrections"
  )$correction_id[[1]],
  "accept", "tester",
  dry_run = TRUE, dialect = "duckdb"
  )
  expect_equal(d$verdict, "validated")
})

# --- Remaining checks carried from .superpowers/sdd/legacy-test-propose.R ------------------

test_that("a valid correction is appended, flags the first correction, stores the prior text", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  propose <- function(...) {
    args <- utils::modifyList(list(
      config = f$cfg, con = f$con, key_values = list(
        ccfid = "K1",
        dt_surg = as.Date("2020-01-01")
      ),
      variable = "surgeon", expected_prior = "S1", new_value = "S9",
      evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester",
      dialect = "duckdb"
    ), list(...))
    suppressMessages(do.call(propose_correction, args))
  }
  r <- propose()
  expect_equal(r$verdict, "appended")
  expect_true(r$new_variable)
  r2 <- propose(
    key_values = list(ccfid = "K2", dt_surg = as.Date("2020-01-02")),
    expected_prior = "S2"
  )
  expect_false(r2$new_variable)
  n <- DBI::dbGetQuery(
    f$con,
    "SELECT COUNT(*) AS n FROM master_c_corrections WHERE variable = 'surgeon'"
  )$n
  expect_equal(n, 2L)
  row <- DBI::dbGetQuery(f$con, sprintf(
    "SELECT expected_prior FROM master_c_corrections WHERE correction_id = '%s'",
    r$correction_id
  ))
  expect_equal(row$expected_prior, "S1")
})

test_that("a missing prior is flagged in the verdict and stored with the flag", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  r <- suppressMessages(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K2", dt_surg = as.Date("2020-01-02")),
    variable = "age", expected_prior = NA, new_value = 71, evidence_type = "chart_review",
    evidence_ref = "invented", asserted_by = "tester", dialect = "duckdb"
  ))
  expect_equal(r$verdict, "appended")
  row <- DBI::dbGetQuery(f$con, sprintf(
    "SELECT expected_prior_missing FROM master_c_corrections WHERE correction_id = '%s'",
    r$correction_id
  ))
  expect_equal(row$expected_prior_missing, 1L)
})

test_that("a colliding correction id is refused", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  testthat::local_mocked_bindings(
    Sys.time = function() as.POSIXct("2026-01-01 00:00:00", tz = "UTC"),
    .package = "base"
  )
  args <- list(
    config = f$cfg, con = f$con,
    key_values = list(ccfid = "K1", dt_surg = as.Date("2020-01-01")),
    variable = "surgeon", expected_prior = "S1", new_value = "S9",
    evidence_type = "chart_review", evidence_ref = "invented",
    asserted_by = "tester", dialect = "duckdb"
  )
  suppressMessages(do.call(propose_correction, args))
  expect_error(do.call(propose_correction, args), "collides")
})

test_that("an unknown variable is an error", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  expect_error(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K1", dt_surg = as.Date("2020-01-01")),
    variable = "height", expected_prior = 1, new_value = 2, evidence_type = "chart_review",
    evidence_ref = "invented", asserted_by = "tester", dialect = "duckdb"
  ), "metadata")
})

test_that("a key column cannot be corrected through this path", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  expect_error(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K1", dt_surg = as.Date("2020-01-01")),
    variable = "ccfid", expected_prior = "K1", new_value = "K9",
    evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester",
    dialect = "duckdb"
  ), "key column")
})

test_that("an unknown evidence type is an error", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  expect_error(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K1", dt_surg = as.Date("2020-01-01")),
    variable = "age", expected_prior = 65.5, new_value = 66, evidence_type = "hunch",
    evidence_ref = "invented", asserted_by = "tester", dialect = "duckdb"
  ), "evidence")
})

test_that("a primary key matching 0 rows is an error, with no value in the message", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  msg <- tryCatch(
    propose_correction(
      f$cfg, f$con,
      key_values = list(ccfid = "K9", dt_surg = as.Date("2020-01-01")),
      variable = "age", expected_prior = 1, new_value = 2, evidence_type = "chart_review",
      evidence_ref = "invented", asserted_by = "tester", dialect = "duckdb"
    ),
    error = conditionMessage
  )
  expect_match(msg, "matched 0 rows")
  expect_false(grepl("K9", msg))
})

test_that("a value that does not cast is an error", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  expect_error(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K1", dt_surg = as.Date("2020-01-01")),
    variable = "age", expected_prior = 65.5, new_value = "abc",
    evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester",
    dialect = "duckdb"
  ), "does not cast")
})

test_that("a factor value is refused", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  expect_error(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K1", dt_surg = as.Date("2020-01-01")),
    variable = "age", expected_prior = 65.5, new_value = factor("66"),
    evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester",
    dialect = "duckdb"
  ), "does not cast")
})

test_that("an over-width value is rejected, and a factor still fails the cast check first", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  testthat::local_mocked_bindings(
    table_types = function(con, table) c(surgeon = "nvarchar(5)"),
    .package = "hvtiRdatabuild"
  )
  msg_wide <- tryCatch(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K1", dt_surg = as.Date("2020-01-01")),
    variable = "surgeon", expected_prior = "S1", new_value = "way too long",
    evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester",
    dialect = "duckdb"
  ), error = conditionMessage)
  expect_match(msg_wide, "longer than the column allows")
  expect_false(grepl("way too long", msg_wide))
  expect_error(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K1", dt_surg = as.Date("2020-01-01")),
    variable = "surgeon", expected_prior = "S1", new_value = factor("x"),
    evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester",
    dialect = "duckdb"
  ), "does not cast")
})

test_that("no widths means no width check", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  r <- suppressMessages(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K1", dt_surg = as.Date("2020-01-01")),
    variable = "surgeon", expected_prior = "S1", new_value = "a very long surgeon name indeed",
    evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester",
    dialect = "duckdb"
  ))
  expect_equal(r$verdict, "appended")
})

test_that("a decision is recorded", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  r <- suppressMessages(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K1", dt_surg = as.Date("2020-01-01")),
    variable = "surgeon", expected_prior = "S1", new_value = "S9",
    evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester",
    dialect = "duckdb"
  ))
  d <- suppressMessages(decide_correction(f$cfg, f$con, r$correction_id, "accept", "tester",
    dialect = "duckdb"
  ))
  expect_equal(d$verdict, "recorded")
})

test_that("an unknown decision is an error", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  r <- suppressMessages(propose_correction(
    f$cfg, f$con,
    key_values = list(ccfid = "K1", dt_surg = as.Date("2020-01-01")),
    variable = "surgeon", expected_prior = "S1", new_value = "S9",
    evidence_type = "chart_review", evidence_ref = "invented", asserted_by = "tester",
    dialect = "duckdb"
  ))
  expect_error(decide_correction(f$cfg, f$con, r$correction_id, "maybe", "tester",
                 dialect = "duckdb"
               ), "decision")
})

test_that("a decision on an unknown correction is an error", {
  skip_corr()
  f <- corr_fixture()
  suppressMessages(backfill_corrections(f$cfg, f$con, dry_run = FALSE, dialect = "duckdb"))
  expect_error(
    decide_correction(f$cfg, f$con, "cnope", "accept", "tester", dialect = "duckdb"),
    "no correction"
  )
})
