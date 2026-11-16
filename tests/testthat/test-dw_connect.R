test_that("connection arguments verify the server certificate by default", {
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

  expect_identical(args$TrustServerCertificate, "No")
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
  expect_identical(seen$TrustServerCertificate, "No")
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

test_that("a connection warning never reveals the password", {
  skip_if_not_installed("odbc")
  withr::local_envvar(c(
    HVI_DW_UID = "someone", HVI_DW_PWD = "hunter2",
    HOME = withr::local_tempdir()
  ))
  # dw_connect() builds its DBI::dbConnect() call with
  # do.call(DBI::dbConnect, c(list(odbc::odbc()), args, list(...))), so the
  # constructed call object holds the *evaluated* uid/pwd values. A warning
  # signalled inside dbConnect() gets that call as its default
  # conditionCall() -- unrelated to what the driver puts in the message.
  # This mock reproduces that exact mechanism instead of guessing at driver
  # text.
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) warning("fallback"),
    .package = "DBI"
  )

  result <- tryCatch(
    dw_connect(server = "<DW-SERVER>", database = "<DW-DB>"),
    warning = function(w) w
  )

  shown <- paste(deparse(result), collapse = "\n")

  expect_false(grepl("hunter2", conditionMessage(result), fixed = TRUE))
  expect_null(conditionCall(result))
  expect_false(grepl("hunter2", shown, fixed = TRUE))
})

test_that("a failed connection that verified the certificate says what to try", {
  skip_if_not_installed("odbc")
  withr::local_envvar(c(HOME = withr::local_tempdir()))
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) stop("SSL Provider: certificate verify failed"),
    .package = "DBI"
  )
  msg <- tryCatch(dw_connect(server = "<DW-SERVER>", database = "<DW-DB>", dsn = "HVI_DW"),
                  error = conditionMessage)
  expect_match(msg, "^dw_connect\\(\\): ")
  expect_match(msg, "trust_certificate = TRUE")
  expect_match(msg, "CA")
  trusting <- tryCatch(
    dw_connect(server = "<DW-SERVER>", database = "<DW-DB>", dsn = "HVI_DW",
               trust_certificate = TRUE),
    error = conditionMessage
  )
  expect_false(grepl("trust_certificate = TRUE", trusting, fixed = TRUE),
               label = "the certificate advice appears only when the certificate was checked")
})

test_that("a failed connection says whether the network, TLS, login or driver failed", {
  skip_if_not_installed("odbc")
  withr::local_envvar(c(HOME = withr::local_tempdir()))
  # Driver messages modelled on ODBC Driver 18 and unixODBC, each carrying an
  # invented secret that must never reach the error.
  cases <- list(
    network = paste("[Microsoft][ODBC Driver 18 for SQL Server]TCP Provider: Error code",
                    "0x2AF9 s3cret; Login timeout expired; A network-related or",
                    "instance-specific error has occurred"),
    tls = paste("[Microsoft][ODBC Driver 18 for SQL Server]SSL Provider:",
                "[error:0A000086:SSL routines::certificate verify failed] s3cret"),
    login = "[Microsoft][ODBC Driver 18 for SQL Server][SQL Server]Login failed for user 's3cret'.",
    driver = paste("[unixODBC][Driver Manager]Can't open lib",
                   "'/opt/s3cret/libmsodbcsql.so' : file not found"),
    unknown = "something else entirely s3cret"
  )
  for (kind in names(cases)) {
    driver_msg <- cases[[kind]]
    testthat::local_mocked_bindings(
      dbConnect = function(drv, ...) stop(driver_msg),
      .package = "DBI"
    )
    e <- tryCatch(dw_connect(server = "<DW-SERVER>", database = "<DW-DB>", dsn = "HVI_DW"),
                  error = identity)
    expect_s3_class(e, "hvtiRdatabuild_connection_failed")
    expect_identical(e$kind, kind, label = paste("kind for", kind))
    msg <- conditionMessage(e)
    expect_false(grepl("s3cret", msg, fixed = TRUE), label = paste("no driver text for", kind))
    expect_identical(grepl("trust_certificate = TRUE", msg, fixed = TRUE),
                     kind %in% c("tls", "unknown"),
                     label = paste("certificate advice only where it can apply, for", kind))
  }
})
