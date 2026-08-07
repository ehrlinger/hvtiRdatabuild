test_that("connection arguments carry TrustServerCertificate by default", {
  # HOME is faked so .resolve_credentials()'s mode-check of ~/.Renviron
  # inspects an empty directory rather than whatever the real developer or
  # CI machine happens to have at that path.
  withr::local_envvar(c(
    HVI_DW_UID = "someone", HVI_DW_PWD = "hunter2",
    HOME = withr::local_tempdir()
  ))

  args <- .build_connection_args(
    server = "<DW-SERVER>", database = "<DW-DB>", port = 1433L
  )

  expect_identical(args$TrustServerCertificate, "Yes")
  expect_identical(args$Encrypt, "yes")
})

test_that("trust_certificate = FALSE is honoured", {
  withr::local_envvar(c(
    HVI_DW_UID = "someone", HVI_DW_PWD = "hunter2",
    HOME = withr::local_tempdir()
  ))

  args <- .build_connection_args(
    server = "<DW-SERVER>", database = "<DW-DB>",
    trust_certificate = FALSE
  )

  expect_identical(args$TrustServerCertificate, "No")
})

test_that("a DSN connection carries no uid or pwd argument", {
  withr::local_envvar(c(HOME = withr::local_tempdir()))

  args <- .build_connection_args(
    server = "<DW-SERVER>", database = "<DW-DB>", dsn = "HVI_DW"
  )

  expect_identical(args$dsn, "HVI_DW")
  expect_null(args$uid)
  expect_null(args$pwd)
})

test_that("printing the argument list never reveals the password", {
  withr::local_envvar(c(
    HVI_DW_UID = "someone", HVI_DW_PWD = "hunter2",
    HOME = withr::local_tempdir()
  ))

  args <- .build_connection_args(server = "<DW-SERVER>", database = "<DW-DB>")
  shown <- paste(utils::capture.output(print(.redact(args))), collapse = "\n")

  expect_false(grepl("hunter2", shown, fixed = TRUE))
  expect_true(grepl("<redacted>", shown, fixed = TRUE))
})

test_that("dw_connect() errors without odbc rather than failing obscurely", {
  skip_if(requireNamespace("odbc", quietly = TRUE), "odbc is installed.")

  expect_error(
    dw_connect(server = "<DW-SERVER>", database = "<DW-DB>", dsn = "HVI_DW"),
    "odbc"
  )
})

test_that("dw_connect() passes assembled arguments to DBI::dbConnect", {
  skip_if_not_installed("odbc")
  withr::local_envvar(c(HOME = withr::local_tempdir()))
  seen <- NULL
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) {
      seen <<- list(...)
      structure(list(), class = "FakeConnection")
    },
    .package = "DBI"
  )

  conn <- dw_connect(server = "<DW-SERVER>", database = "<DW-DB>",
                     dsn = "HVI_DW")

  expect_s3_class(conn, "FakeConnection")
  expect_identical(seen$TrustServerCertificate, "Yes")
})

test_that("a failed connection message never contains the password", {
  skip_if_not_installed("odbc")
  withr::local_envvar(c(
    HVI_DW_UID = "someone", HVI_DW_PWD = "hunter2",
    HOME = withr::local_tempdir()
  ))
  # A real ODBC driver error commonly quotes the connection string back at
  # the caller. Echo it here so the test actually discriminates: it only
  # passes if dw_connect()'s tryCatch wrapper replaces the driver's message
  # rather than passing it through.
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) {
      seen <- list(...)
      stop(sprintf(
        "[ODBC Driver 18 for SQL Server]Login failed. Connection string: UID=%s;PWD=%s;",
        seen$uid, seen$pwd
      ))
    },
    .package = "DBI"
  )

  result <- tryCatch(
    dw_connect(server = "<DW-SERVER>", database = "<DW-DB>"),
    error = function(e) e
  )

  expect_false(grepl("hunter2", conditionMessage(result), fixed = TRUE))
  # call. = FALSE means the replacement error carries no call component, so
  # the driver's original call (which could itself embed the credential
  # through matched arguments) cannot leak through conditionCall() either.
  expect_null(conditionCall(result))
})
