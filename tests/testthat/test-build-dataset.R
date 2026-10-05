# All identifiers and values below are invented. No PHI.

.build_fixture <- function(modules = c("base", "vitalstatus", "echo", "fup", "events")) {
  path <- withr::local_tempfile(fileext = ".yaml", .local_envir = parent.frame())
  yaml::write_yaml(list(
    study = "synthetic",
    cohort_table = "synthetic.cohort",
    warehouse = "synthetic_warehouse",
    view_schema = "dbo",
    pull_date = "2026-10-01",
    modules = as.list(modules)
  ), path)
  config <- read_study_config(path)
  base <- data.frame(
    masterid = c("M001", "M002"),
    patid = c("P001", "P002"),
    base_value = c(10L, 20L),
    stringsAsFactors = FALSE
  )
  status <- data.frame(
    masterid = c("M001", "M002"),
    status_value = c("alive", "deceased"),
    stringsAsFactors = FALSE
  )
  tables <- list(
    bdbase = base,
    bdstat = status,
    echo = data.frame(
      patid = c("P001", "P001", "P002"), echo_value = 1:3
    ),
    fup = data.frame(patid = c("P001", "P002", "P002"), fup_value = 4:6),
    bdevents = data.frame(
      patid = c("P001", "P001"), event_value = c("A", "B")
    )
  )
  outputs <- vapply(config$modules, function(module) {
    dw_modules()$output[match(module, dw_modules()$module)]
  }, character(1))
  tables <- tables[outputs]
  manifest <- data.frame(
    module = config$modules,
    output = outputs,
    n_rows = vapply(tables, nrow, integer(1)),
    n_cols = vapply(tables, ncol, integer(1)),
    pulled_at = as.POSIXct(rep("2026-10-01", length(outputs)), tz = "UTC"),
    stringsAsFactors = FALSE
  )
  raw <- structure(list(tables = tables, manifest = manifest), class = "pull_result")
  list(raw = raw, config = config, base = base)
}

.build_cohort <- function(ids = c("M001", "M002")) {
  members <- data.frame(
    patient_id = ids,
    stage_id = "selected",
    included = TRUE,
    reason = NA_character_,
    stringsAsFactors = FALSE
  )
  stages <- data.frame(
    stage_id = "selected", order = 1L, label = "Selected",
    source = "upstream", provenance = "synthetic selection",
    stringsAsFactors = FALSE
  )
  new_cohort_record(members, stages, "masterid")
}

test_that("build joins patient-level modules and preserves event tables", {
  fixture <- .build_fixture()
  result <- build_dataset(fixture$raw, fixture$config, .build_cohort())

  expect_s3_class(result, "build_result")
  expect_equal(nrow(result$data), 2L)
  expect_identical(result$data$masterid, c("M001", "M002"))
  expect_identical(result$data$status_value, c("alive", "deceased"))
  expect_named(result$tables, c("echo", "fup", "bdevents"))
  expect_equal(nrow(result$tables$echo), 3L)
  expect_equal(nrow(result$tables$fup), 3L)
  expect_equal(nrow(result$tables$bdevents), 2L)
  expect_identical(tail(result$cohort$stages$source, 1L), "build")
})

test_that("the base module must have its declared join key", {
  fixture <- .build_fixture()
  fixture$raw$tables$bdbase$masterid <- NULL

  err <- tryCatch(
    build_dataset(fixture$raw, fixture$config, .build_cohort()),
    error = identity
  )
  expect_s3_class(err, "error")
  expect_match(conditionMessage(err), "base.*join key")
  expect_false(grepl("M001", conditionMessage(err), fixed = TRUE))
})

test_that("one-to-one module joins must preserve unique patient keys", {
  fixture <- .build_fixture()
  fixture$raw$tables$bdstat$masterid[2] <- "M001"

  expect_error(
    build_dataset(fixture$raw, fixture$config, .build_cohort()),
    "vitalstatus.*unique"
  )
})

test_that("the cohort membership must match the assembled patient rows", {
  fixture <- .build_fixture()
  cohort <- .build_cohort(c("M001", "M003"))

  err <- tryCatch(
    build_dataset(fixture$raw, fixture$config, cohort),
    error = identity
  )
  expect_s3_class(err, "error")
  expect_match(conditionMessage(err), "cohort membership")
  expect_false(grepl("M003", conditionMessage(err), fixed = TRUE))
})

test_that("the base module cannot duplicate a patient row", {
  fixture <- .build_fixture()
  fixture$raw$tables$bdbase$masterid[2] <- "M001"

  expect_error(
    build_dataset(fixture$raw, fixture$config, .build_cohort()),
    "base.*unique"
  )
})

test_that("a missing vital-status patient is a build integrity error", {
  fixture <- .build_fixture()
  fixture$raw$tables$bdstat <- fixture$raw$tables$bdstat[1, , drop = FALSE]

  expect_error(
    build_dataset(fixture$raw, fixture$config, .build_cohort()),
    "vitalstatus.*cover the base patient keys"
  )
})

test_that("repeated-event tables must retain their declared join key", {
  fixture <- .build_fixture()
  fixture$raw$tables$echo$patid <- NULL

  expect_error(
    build_dataset(fixture$raw, fixture$config, .build_cohort()),
    "echo.*declared join key"
  )
})

test_that("build results print shape and counts without patient values", {
  fixture <- .build_fixture()
  result <- build_dataset(fixture$raw, fixture$config, .build_cohort())
  printed <- paste(capture.output(print(result)), collapse = "\n")

  expect_match(printed, "Built dataset: 2 row")
  expect_match(printed, "Supporting module tables: 3")
  expect_false(grepl("M001|P001", printed))
})

test_that("a base-only build returns no supporting event tables", {
  fixture <- .build_fixture("base")
  result <- build_dataset(fixture$raw, fixture$config, .build_cohort())

  expect_equal(nrow(result$data), 2L)
  expect_length(result$tables, 0L)
})
