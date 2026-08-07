test_that("a credential file more permissive than 600 is an error", {
  path <- withr::local_tempfile()
  writeLines("HVI_DW_UID=someone", path)
  Sys.chmod(path, "644")
  skip_if(file.mode(path) != as.octmode("644"), "Filesystem ignored chmod.")

  expect_error(.check_file_mode(path), "600")
})

test_that("a credential file at 600 passes", {
  path <- withr::local_tempfile()
  writeLines("HVI_DW_UID=someone", path)
  Sys.chmod(path, "600")

  expect_silent(.check_file_mode(path))
})

test_that("the error for a loose file never shows the file's contents", {
  path <- withr::local_tempfile()
  writeLines("HVI_DW_PWD=hunter2", path)
  Sys.chmod(path, "644")
  skip_if(file.mode(path) != as.octmode("644"), "Filesystem ignored chmod.")

  msg <- tryCatch(.check_file_mode(path), error = conditionMessage)
  expect_false(grepl("hunter2", msg, fixed = TRUE))
})

test_that("a named DSN outranks .Renviron and carries no secret", {
  # HOME is faked so .resolve_credentials()'s mode-check of ~/.odbc.ini
  # inspects an empty directory rather than whatever the real developer or
  # CI machine happens to have at that path.
  withr::local_envvar(c(
    HVI_DW_UID = "someone", HVI_DW_PWD = "hunter2",
    HOME = withr::local_tempdir(), HVI_DW_KERBEROS = NA
  ))

  res <- .resolve_credentials(dsn = "HVI_DW", interactive_ok = FALSE)

  expect_identical(res$method, "dsn")
  expect_null(res$pwd)
})

test_that(".Renviron variables are used when no DSN is given", {
  # HOME is faked so .resolve_credentials()'s mode-check of ~/.Renviron
  # inspects an empty directory rather than whatever the real developer or
  # CI machine happens to have at that path.
  withr::local_envvar(c(
    HVI_DW_UID = "someone", HVI_DW_PWD = "hunter2",
    HOME = withr::local_tempdir(), HVI_DW_KERBEROS = NA
  ))

  res <- .resolve_credentials(dsn = NULL, interactive_ok = FALSE)

  expect_identical(res$method, "renviron")
  expect_identical(res$uid, "someone")
})

test_that("no resolvable source in a non-interactive session is an error", {
  withr::local_envvar(c(HVI_DW_UID = NA, HVI_DW_PWD = NA, HVI_DW_KERBEROS = NA))

  expect_error(
    .resolve_credentials(dsn = NULL, interactive_ok = FALSE),
    "No credential source"
  )
})

test_that("a project-level .Renviron shadowing the user one warns with both paths", {
  proj <- withr::local_tempdir()
  writeLines("HVI_DW_UID=someone", file.path(proj, ".Renviron"))
  withr::local_dir(proj)

  expect_warning(.warn_renviron_shadow(home = "/home/someone"),
                 "shadow")
})

test_that("no shadow warning fires when there is no project .Renviron", {
  proj <- withr::local_tempdir()
  withr::local_dir(proj)

  expect_silent(.warn_renviron_shadow(home = "/home/someone"))
})
