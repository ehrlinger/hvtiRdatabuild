.test_config <- function(modules = c("base", "fup")) {
  structure(list(
    study = "st1234", cohort_table = "db.sch.st1234_cohort",
    warehouse = "wh", view_schema = "dbo",
    pull_date = as.Date("2026-08-04"), modules = modules,
    varsets = character(0), derive = stats::setNames(logical(0), character(0))
  ), class = "study_config")
}

test_that("every shipped module file parses and declares the required fields", {
  mods <- dw_modules()

  expect_true(nrow(mods) >= 5L)
  expect_setequal(
    names(mods), c("module", "output", "join_key", "optional")
  )
  expect_true(all(nzchar(mods$module)))
  expect_type(mods$optional, "logical")
  expect_false(anyDuplicated(mods$module) > 0)
})

test_that("the five dwpull modules are present", {
  expect_true(all(c("base", "vitalstatus", "echo", "fup", "events") %in%
                    dw_modules()$module))
})

test_that("SQL interpolation replaces every placeholder", {
  sql <- .module_sql("base", .test_config())

  expect_false(grepl("\\{", sql))
  expect_true(grepl("db.sch.st1234_cohort", sql, fixed = TRUE))
  expect_true(grepl("wh.dbo.vw_CardSurg_Base", sql, fixed = TRUE))
})

test_that("no shipped module file carries a site-specific identifier", {
  # The repository is public. Real host, port, database, and schema names
  # arrive from study.yaml at runtime and must never be committed.
  files <- list.files(
    system.file("extdata", "modules", package = "hvtiRdatabuild"),
    full.names = TRUE
  )
  text <- paste(unlist(lapply(files, readLines)), collapse = "\n")

  expect_false(grepl("\\.cchs\\.net|ESQLPROD|ESQLPLDAG|HVI_DM", text))
})

test_that("an unknown module name is an error naming the known ones", {
  expect_error(.module_sql("nonsuch", .test_config()), "base")
})

test_that(".module_sql() errors on a leftover placeholder, naming it", {
  # A genuinely uninterpolated placeholder, exercised through the real
  # dw_modules()/.module_sql() code path rather than a unit-level shortcut,
  # because .read_module_specs() always reads from the package's shipped
  # module directory. The shipped module files are not touched: a temporary
  # fixture is written into that directory and removed when the test ends.
  dir <- system.file("extdata", "modules", package = "hvtiRdatabuild")
  fixture <- file.path(dir, "zzz_leftover_placeholder.yaml")
  writeLines(c(
    "module: zzz_leftover_placeholder",
    "output: zzz_leftover_placeholder",
    "join_key: patid",
    "optional: true",
    "sql: >",
    "  select * from {cohort} where {not_a_real_placeholder} = 1"
  ), fixture)
  withr::defer(unlink(fixture))

  expect_error(
    .module_sql("zzz_leftover_placeholder", .test_config()),
    "not_a_real_placeholder",
    fixed = TRUE
  )
})

test_that("the echo module records the SAS window as a known divergence", {
  path <- system.file("extdata", "modules", "echo.yaml",
                      package = "hvtiRdatabuild")
  spec <- yaml::read_yaml(path)

  expect_true(nzchar(spec$divergence))
})
