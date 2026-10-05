# All identifiers and values below are invented. No PHI.

.derive_build_fixture <- function() {
  path <- withr::local_tempfile(fileext = ".yaml", .local_envir = parent.frame())
  yaml::write_yaml(list(
    study = "synthetic",
    cohort_table = "synthetic.cohort",
    warehouse = "synthetic_warehouse",
    view_schema = "dbo",
    pull_date = "2026-10-01",
    modules = list("base")
  ), path)
  config <- read_study_config(path)
  base <- data.frame(
    masterid = c("SYN101", "SYN102"), value = c(2, 4),
    eligible = c(TRUE, FALSE),
    clinical_value = c("SYNTHETIC-CLINICAL-A", "SYNTHETIC-CLINICAL-B"),
    stringsAsFactors = FALSE
  )
  raw <- structure(list(
    tables = list(bdbase = base),
    manifest = data.frame(
      module = "base", output = "bdbase", n_rows = 2L, n_cols = 4L,
      pulled_at = as.POSIXct("2026-10-01", tz = "UTC")
    )
  ), class = "pull_result")
  cohort <- new_cohort_record(
    members = data.frame(
      patient_id = base$masterid, stage_id = "selected", included = TRUE,
      reason = NA_character_, stringsAsFactors = FALSE
    ),
    stages = data.frame(
      stage_id = "selected", order = 1L, label = "Selected",
      source = "upstream", provenance = "synthetic selection",
      stringsAsFactors = FALSE
    ),
    patient_id_col = "masterid"
  )
  list(config = config, build = build_dataset(raw, config, cohort))
}

.derive_stage <- function(cohort, ids, included, reason) {
  stage <- data.frame(
    stage_id = "study_eligibility",
    order = max(cohort$stages$order) + 1L,
    label = "Study eligibility",
    source = "derive",
    provenance = "synthetic study rule",
    stringsAsFactors = FALSE
  )
  outcomes <- data.frame(
    patient_id = ids,
    included = included,
    reason = reason,
    stringsAsFactors = FALSE
  )
  append_cohort_stage(cohort, stage, outcomes)
}

test_that("study-specific code can derive a variable", {
  fixture <- .derive_build_fixture()
  callback <- function(data, cohort, config) {
    data$double_value <- data$value * 2
    list(data = data, cohort = cohort)
  }
  result <- derive_vars(fixture$build, fixture$config, callback)

  expect_s3_class(result, "derive_result")
  expect_identical(result$data$double_value, c(4, 8))
  expect_identical(result$tables, fixture$build$tables)
})

test_that("study exclusions append to the cohort history in order", {
  fixture <- .derive_build_fixture()
  callback <- function(data, cohort, config) {
    ids <- data$masterid
    included <- data$eligible
    reason <- ifelse(included, NA_character_, "synthetic ineligibility")
    reason[is.na(included)] <- NA_character_
    updated <- .derive_stage(cohort, ids, included, reason)
    list(data = data[included %in% TRUE, , drop = FALSE], cohort = updated)
  }
  result <- derive_vars(fixture$build, fixture$config, callback)

  expect_identical(result$data$masterid, "SYN101")
  expect_identical(result$cohort$stages$source, c("upstream", "build", "derive"))
  expect_identical(tail(cohort_summary(result$cohort)$stages$n_excluded, 1L), 1L)
})

test_that("missing predicate values are explicitly resolved by study code", {
  fixture <- .derive_build_fixture()
  fixture$build$data$eligible[2] <- NA
  callback <- function(data, cohort, config) {
    predicate <- data$eligible
    included <- !is.na(predicate) & predicate
    reason <- rep(NA_character_, length(included))
    reason[!included] <- "missing or ineligible"
    updated <- .derive_stage(cohort, data$masterid, included, reason)
    list(data = data[included, , drop = FALSE], cohort = updated)
  }
  result <- derive_vars(fixture$build, fixture$config, callback)

  expect_identical(result$data$masterid, "SYN101")
  expect_identical(tail(result$cohort$members$included, 2L), c(TRUE, FALSE))
})

test_that("a no-op study derivation preserves the built data and history", {
  fixture <- .derive_build_fixture()
  callback <- function(data, cohort, config) list(data = data, cohort = cohort)
  result <- derive_vars(fixture$build, fixture$config, callback)

  expect_identical(result$data, fixture$build$data)
  expect_identical(result$cohort, fixture$build$cohort)
})

test_that("malformed study callback results fail safely", {
  fixture <- .derive_build_fixture()
  callback <- function(data, cohort, config) list(data = data)

  expect_error(derive_vars(fixture$build, fixture$config, callback),
               "named data and cohort")
})

test_that("study output identifiers must match the final cohort", {
  fixture <- .derive_build_fixture()
  callback <- function(data, cohort, config) {
    list(data = data[-1, , drop = FALSE], cohort = cohort)
  }
  err <- tryCatch(
    derive_vars(fixture$build, fixture$config, callback),
    error = identity
  )

  expect_s3_class(err, "error")
  expect_match(conditionMessage(err), "data identifiers.*cohort")
  expect_false(grepl("SYN", conditionMessage(err), fixed = TRUE))
})

test_that("callback failures are reported without patient values", {
  fixture <- .derive_build_fixture()
  callback <- function(data, cohort, config) stop("failed at SYN101")
  err <- tryCatch(
    derive_vars(fixture$build, fixture$config, callback),
    error = identity
  )

  expect_s3_class(err, "error")
  expect_match(conditionMessage(err), "callback failed")
  expect_false(grepl("SYN101", conditionMessage(err), fixed = TRUE))
})

test_that("duplicate patient rows from study code are rejected", {
  fixture <- .derive_build_fixture()
  callback <- function(data, cohort, config) {
    list(data = rbind(data, data[1, ]), cohort = cohort)
  }

  expect_error(
    derive_vars(fixture$build, fixture$config, callback),
    "unique, non-missing patient identifiers"
  )
})

test_that("study code cannot rewrite upstream or build history", {
  fixture <- .derive_build_fixture()
  callback <- function(data, cohort, config) {
    shortened <- cohort$members[cohort$members$patient_id == "SYN101", ]
    changed <- new_cohort_record(
      shortened, cohort$stages, cohort$patient_id_col
    )
    list(data = data[1, , drop = FALSE], cohort = changed)
  }

  expect_error(
    derive_vars(fixture$build, fixture$config, callback),
    "may append history but may not rewrite"
  )
})

test_that("derived results print shape and counts without patient values", {
  fixture <- .derive_build_fixture()
  callback <- function(data, cohort, config) list(data = data, cohort = cohort)
  result <- derive_vars(fixture$build, fixture$config, callback)
  printed <- paste(capture.output(print(result)), collapse = "\n")

  expect_match(printed, "Derived dataset: 2 row")
  expect_false(grepl("SYN10", printed, fixed = TRUE))
})

test_that("str on derive results omits patient and clinical values", {
  fixture <- .derive_build_fixture()
  callback <- function(data, cohort, config) list(data = data, cohort = cohort)
  result <- derive_vars(fixture$build, fixture$config, callback)
  printed <- paste(capture.output(utils::str(result)), collapse = "\n")

  expect_match(printed, "derive_result")
  expect_false(grepl("SYN101|SYNTHETIC-CLINICAL", printed))
})

test_that("callback warning and message text is redacted on success", {
  fixture <- .derive_build_fixture()
  warnings <- character()
  messages <- character()
  callback <- function(data, cohort, config) {
    warning("warning contains SYN101", call. = FALSE)
    message("message contains SYN101")
    list(data = data, cohort = cohort)
  }
  withCallingHandlers(
    derive_vars(fixture$build, fixture$config, callback),
    warning = function(condition) {
      warnings <<- c(warnings, conditionMessage(condition))
      invokeRestart("muffleWarning")
    },
    message = function(condition) {
      messages <<- c(messages, conditionMessage(condition))
      invokeRestart("muffleMessage")
    }
  )

  expect_match(warnings, "callback warning.*suppressed")
  expect_match(messages, "callback message.*suppressed")
  expect_false(grepl("SYN101", paste(warnings, messages), fixed = TRUE))
})

test_that("callback warning and message text is redacted on failure", {
  fixture <- .derive_build_fixture()
  warnings <- character()
  messages <- character()
  callback <- function(data, cohort, config) {
    warning("warning contains SYN101", call. = FALSE)
    message("message contains SYN101")
    stop("error contains SYN101")
  }
  err <- withCallingHandlers(
    tryCatch(derive_vars(fixture$build, fixture$config, callback), error = identity),
    warning = function(condition) {
      warnings <<- c(warnings, conditionMessage(condition))
      invokeRestart("muffleWarning")
    },
    message = function(condition) {
      messages <<- c(messages, conditionMessage(condition))
      invokeRestart("muffleMessage")
    }
  )

  expect_match(conditionMessage(err), "callback failed")
  expect_match(warnings, "callback warning.*suppressed")
  expect_match(messages, "callback message.*suppressed")
  expect_false(grepl("SYN101", paste(conditionMessage(err), warnings, messages),
                     fixed = TRUE))
})
