.pull_config <- function(modules = c("base", "fup")) {
  structure(list(
    study = "st1234", cohort_table = "db.sch.st1234_cohort",
    warehouse = "wh", view_schema = "dbo",
    pull_date = as.Date("2026-08-04"), modules = modules,
    varsets = character(0), derive = stats::setNames(logical(0), character(0))
  ), class = "study_config")
}

.fake_conn <- function() structure(list(), class = "FakeConnection")

# Synthetic, no PHI: two identifier-shaped columns and one measurement.
.fake_rows <- function(n = 3L) {
  data.frame(
    masterid = seq_len(n),
    patid    = seq_len(n) + 100L,
    value    = seq_len(n) * 1.5
  )
}

test_that("dw_pull() returns one table per enabled module, named by output", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) .fake_rows(),
    .package = "DBI"
  )

  res <- dw_pull(.pull_config(), .fake_conn())

  expect_s3_class(res, "pull_result")
  expect_setequal(names(res$tables), c("bdbase", "fup"))
  expect_identical(nrow(res$tables$bdbase), 3L)
})

test_that("the manifest records shape for every module pulled", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) .fake_rows(),
    .package = "DBI"
  )

  res <- dw_pull(.pull_config(), .fake_conn())

  expect_setequal(
    names(res$manifest),
    c("module", "output", "n_rows", "n_cols", "pulled_at")
  )
  expect_identical(nrow(res$manifest), 2L)
  expect_true(all(res$manifest$n_rows == 3L))
})

test_that("a required module returning zero rows is an error", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) .fake_rows(0L),
    .package = "DBI"
  )

  expect_error(dw_pull(.pull_config("base"), .fake_conn()),
               "zero rows")
})

test_that("an optional module returning zero rows is kept, not an error", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) .fake_rows(0L),
    .package = "DBI"
  )

  res <- dw_pull(.pull_config("echo"), .fake_conn())

  expect_identical(nrow(res$tables$echo), 0L)
  expect_identical(res$manifest$n_rows, 0L)
})

test_that("an unknown module in the config is an error before any query runs", {
  queried <- FALSE
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      queried <<- TRUE
      .fake_rows()
    },
    .package = "DBI"
  )

  expect_error(dw_pull(.pull_config("nonsuch"), .fake_conn()), "nonsuch")
  expect_false(queried)
})

test_that("dw_pull() issues only SELECT statements", {
  seen <- character(0)
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      seen <<- c(seen, statement)
      .fake_rows()
    },
    .package = "DBI"
  )

  dw_pull(.pull_config(c("base", "vitalstatus", "fup")), .fake_conn())

  expect_true(all(grepl("^select", trimws(seen), ignore.case = TRUE)))
  expect_false(any(grepl("insert|update|delete|drop|create",
                         seen, ignore.case = TRUE)))
})

.colliding_specs <- function() {
  list(
    one = list(module = "one", output = "same", join_key = "masterid",
               sql = "select 1 as masterid"),
    two = list(module = "two", output = "same", join_key = "masterid",
               sql = "select 1 as masterid")
  )
}

test_that("two modules sharing an output name is an error before any query runs", {
  queried <- FALSE
  testthat::local_mocked_bindings(
    .read_module_specs = .colliding_specs
  )
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      queried <<- TRUE
      .fake_rows()
    },
    .package = "DBI"
  )

  err <- tryCatch(
    dw_pull(.pull_config(c("one", "two")), .fake_conn()),
    error = function(e) e
  )

  expect_s3_class(err, "error")
  expect_match(conditionMessage(err), "same")
  expect_match(conditionMessage(err), "one")
  expect_match(conditionMessage(err), "two")
  expect_false(queried)
})

test_that("dw_pull() never calls a DBI write entry point", {
  called <- character(0)
  # Each mock records that it fired and returns a harmless value rather than
  # erroring on a missing S4 method. That way a real write shows up as a
  # failed assertion below, not as unrelated dispatch noise.
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) .fake_rows(),
    dbExecute = function(conn, statement, ...) {
      called <<- c(called, "dbExecute")
      0L
    },
    dbSendStatement = function(conn, statement, ...) {
      called <<- c(called, "dbSendStatement")
      structure(list(), class = "FakeResult")
    },
    dbWriteTable = function(conn, name, value, ...) {
      called <<- c(called, "dbWriteTable")
      TRUE
    },
    .package = "DBI"
  )

  dw_pull(.pull_config(c("base", "vitalstatus", "fup")), .fake_conn())

  expect_identical(called, character(0))
})

test_that("a query failure names the module and not the SQL", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) stop("driver exploded"),
    .package = "DBI"
  )

  msg <- tryCatch(dw_pull(.pull_config("base"), .fake_conn()),
                  error = conditionMessage)

  expect_match(msg, "base")
  expect_false(grepl("vw_CardSurg", msg, fixed = TRUE))
})
