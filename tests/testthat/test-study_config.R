.write_config <- function(..., .extra = NULL) {
  cfg <- utils::modifyList(
    list(
      study        = "st1234",
      cohort_table = "<DW-DB>.<SCHEMA>.st1234_cohort",
      warehouse    = "<WAREHOUSE>",
      view_schema  = "dbo",
      pull_date    = "2026-08-04",
      modules      = list("base", "fup"),
      varsets      = list("core"),
      derive       = list(missing = TRUE, transform = TRUE, propensity = FALSE)
    ),
    list(...)
  )
  if (!is.null(.extra)) cfg <- c(cfg, .extra)
  path <- withr::local_tempfile(fileext = ".yaml", .local_envir = parent.frame())
  yaml::write_yaml(cfg, path)
  path
}

test_that("a well-formed study.yaml loads with the documented types", {
  cfg <- read_study_config(.write_config())

  expect_s3_class(cfg, "study_config")
  expect_identical(cfg$study, "st1234")
  expect_identical(cfg$modules, c("base", "fup"))
  expect_s3_class(cfg$pull_date, "Date")
  expect_identical(cfg$derive[["propensity"]], FALSE)
})

test_that("an unknown key is an error, not a silent no-op", {
  path <- .write_config(.extra = list(modulez = list("base")))

  expect_error(read_study_config(path), "Unknown key.*modulez")
})

test_that("a missing required key names the key", {
  cfg  <- list(study = "st1234")
  path <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(cfg, path)

  expect_error(read_study_config(path), "cohort_table")
})

test_that("an unparseable pull_date is an error", {
  path <- .write_config(pull_date = "04/08/2026")

  expect_error(read_study_config(path), "pull_date.*YYYY-MM-DD")
})

test_that("a non-logical derive flag is an error", {
  path <- .write_config(derive = list(missing = "yes"))

  expect_error(read_study_config(path), "derive.*missing.*logical")
})

test_that("a missing file names the path", {
  expect_error(read_study_config("/nonexistent/study.yaml"), "does not exist")
})

test_that("an empty modules list is an error, not a silent zero-pull", {
  # utils::modifyList() recurses into list-valued keys, so an empty override
  # list() is a no-op against .write_config()'s default modules -- the YAML
  # is built directly here to actually produce `modules: []`.
  cfg <- list(
    study        = "st1234",
    cohort_table = "<DW-DB>.<SCHEMA>.st1234_cohort",
    warehouse    = "<WAREHOUSE>",
    view_schema  = "dbo",
    pull_date    = "2026-08-04",
    modules      = list()
  )
  path <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(cfg, path)

  expect_error(read_study_config(path), "modules")
})

test_that("a bare modules key is an error, not a silent zero-pull", {
  cfg <- list(
    study        = "st1234",
    cohort_table = "<DW-DB>.<SCHEMA>.st1234_cohort",
    warehouse    = "<WAREHOUSE>",
    view_schema  = "dbo",
    pull_date    = "2026-08-04",
    modules      = NULL
  )
  path <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(cfg, path)

  expect_error(read_study_config(path), "modules")
})

test_that("a mapping where modules must be a sequence is an error", {
  cfg <- list(
    study        = "st1234",
    cohort_table = "<DW-DB>.<SCHEMA>.st1234_cohort",
    warehouse    = "<WAREHOUSE>",
    view_schema  = "dbo",
    pull_date    = "2026-08-04",
    modules      = list(base = "alpha", fup = "beta")
  )
  path <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(cfg, path)

  expect_error(read_study_config(path), "modules")
})
