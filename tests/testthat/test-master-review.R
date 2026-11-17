# No PHI: identifiers, values and decisions are invented.


write_decisions <- function(rows) {
  f <- withr::local_tempfile(fileext = ".csv", .local_envir = parent.frame())
  utils::write.csv(rows, f, row.names = FALSE, na = "")
  f
}

test_that("the review list holds routed units and every unit for review criteria", {
  pull <- review_pull()
  rl <- review_list(pull)
  expect_identical(nrow(rl), 5L)
  expect_identical(sum(rl$criterion_id == "lvef"), 2L)
  expect_identical(sum(rl$criterion_id == "strategy"), 3L)
})

test_that("a pull awaiting review cannot be built or frozen", {
  pull <- review_pull()
  expect_error(build_from_master(pull), class = "hvtiRdatabuild_awaiting_review")
  expect_error(freeze_study_pull(pull, demo_config, tempdir(), "x", Sys.Date()),
               class = "hvtiRdatabuild_awaiting_review")
})

test_that("decisions are applied as review stages, with the file checksum", {
  pull <- review_pull()
  rl <- review_list(pull)
  rl$outcome <- "not_met"
  rl$reason_code <- NA_character_
  # SYN103's tied echoes: the reviewer finds LVEF 20 is the valid study.
  rl$outcome[rl$criterion_id == "lvef" & grepl("^SYN103", rl$cohort_unit)] <- "met"
  rl$reason_code[rl$criterion_id == "lvef" & grepl("^SYN104", rl$cohort_unit)] <- "NO_ECHO"
  f <- write_decisions(rl)
  out <- apply_review(pull, f, reason_codes = c("NO_ECHO", "PLANNED"))
  expect_identical(out$meta$status, "complete")
  expect_identical(out$meta$review_decisions_sha256,
                   digest::digest(f, algo = "sha256", file = TRUE))
  s <- out$cohort$stages
  expect_identical(utils::tail(s$stage_id, 1L), "strategy")
  expect_identical(utils::tail(s$source, 1L), "review")
  expect_false("review_undetermined" %in% s$stage_id)
  expect_setequal(out$data$cohort_unit, c("SYN101|2010-03-01", "SYN103|2015-06-30"))
  expect_s3_class(build_from_master(out), "build_result")
})

test_that("decisions must answer exactly the review list, with declared reasons", {
  pull <- review_pull()
  rl <- review_list(pull)
  rl$outcome <- "not_met"
  rl$reason_code <- NA_character_
  expect_error(apply_review(pull, write_decisions(rl[-1, ]), "X"),
               class = "hvtiRdatabuild_review", regexp = "1 decision\\(s\\) missing")
  rl$reason_code[rl$criterion_id == "lvef"] <- "MADE_UP"
  expect_error(apply_review(pull, write_decisions(rl), "NO_ECHO"),
               "reason code not in `reason_codes`")
  rl$reason_code <- NA_character_
  expect_error(apply_review(pull, write_decisions(rl), "NO_ECHO"),
               "an exclusion needs a reason code")
})

decide_all <- function(pull, met_units = character(), code = "PLANNED") {
  rl <- review_list(pull)
  rl$outcome <- ifelse(rl$cohort_unit %in% met_units, "met", "not_met")
  crit <- pull$review$criteria
  role <- crit$role[match(rl$criterion_id, crit$criterion_id)]
  excludes <- (role == "include" & rl$outcome == "not_met") |
    (role == "exclude" & rl$outcome == "met")
  rl$reason_code <- replace(rep(NA_character_, nrow(rl)), excludes, code)
  rl
}

test_that("a later encounter is the index when review excludes the first", {
  con <- local_master_db()
  seed_criteria_views(con)
  DBI::dbExecute(con, second_cabg)
  strategy <- review_criterion("strategy", "Planned alternative support", "exclude")
  pull <- pull_demo(con, demo_query(criteria = list(strategy), index_on = "eligible"))
  expect_identical(nrow(review_list(pull)), 4L)
  rl <- decide_all(pull, met_units = "SYN103|2015-06-30")
  out <- apply_review(pull, write_decisions(rl), reason_codes = "PLANNED")
  expect_setequal(out$data$cohort_unit,
                  c("SYN101|2010-03-01", "SYN103|2018-02-02", "SYN104|2020-01-10"))
  expect_identical(utils::tail(out$cohort$stages$stage_id, 2L),
                   c("strategy", "index_eligible"))
})

test_that("a later encounter is the index when a routed first is excluded at review", {
  con <- local_master_db()
  seed_criteria_views(con)
  DBI::dbExecute(con, second_cabg)
  routed <- criterion("lvef", "LVEF 25% or less", "include",
                      view_rows("echo_demo", "measured_on", c(-30, 0), "nearest",
                                "lvef <= 25"),
                      undetermined = "review")
  pull <- pull_demo(con, demo_query(criteria = list(routed), index_on = "eligible"))
  # SYN103 2015 (tied echoes) and SYN104 (no echo) are routed; SYN103 2018 met.
  expect_setequal(pull$review$queue$cohort_unit,
                  c("SYN103|2015-06-30", "SYN104|2020-01-10"))
  out <- apply_review(pull, write_decisions(decide_all(pull, code = "NO_ECHO")),
                      reason_codes = "NO_ECHO")
  expect_setequal(out$data$cohort_unit, c("SYN101|2010-03-01", "SYN103|2018-02-02"))
})

test_that("an empty cohort before a review criterion needs no review", {
  con <- local_master_db()
  seed_criteria_views(con)
  nobody <- criterion("nobody", "Nobody", "include", master_row("age > 200"), "exclude")
  res <- pull_demo(con, demo_query(
    criteria = list(nobody, review_criterion("strategy", "Strategy", "exclude")),
    index_on = "qualifying"
  ))
  expect_identical(res$meta$status, "complete")
  expect_identical(nrow(review_list(res)), 0L)
  expect_s3_class(build_from_master(res), "build_result")
})

stage_excluded <- function(cohort) {
  s <- cohort_summary(cohort)$stages
  stats::setNames(s$n_excluded, s$stage_id)
}

test_that("a routed unit a later criterion excludes still waits for review", {
  pull <- routed_then_age()
  expect_identical(pull$meta$status, "awaiting review")
  expect_setequal(review_list(pull)$cohort_unit, c("SYN103|2015-06-30", "SYN104|2020-01-10"))
})

test_that("a routed unit excluded at review is attributed to the routing criterion", {
  pull <- routed_then_age()
  out <- apply_review(pull, write_decisions(decide_all(pull, "SYN104|2020-01-10", "NO_ECHO")),
                      reason_codes = "NO_ECHO")
  n <- stage_excluded(out$cohort)
  expect_identical(n[["lvef"]], 1L)
  expect_identical(n[["age"]], 0L)
  reasons <- cohort_summary(out$cohort)$reasons
  expect_identical(reasons$reason[reasons$stage_id == "lvef"],
                   "LVEF 25% or less at review: NO_ECHO")
  expect_setequal(out$data$cohort_unit, c("SYN101|2010-03-01", "SYN104|2020-01-10"))
})

test_that("a routed unit kept at review stays excluded by the later criterion", {
  pull <- routed_then_age()
  met <- c("SYN103|2015-06-30", "SYN104|2020-01-10")
  out <- apply_review(pull, write_decisions(decide_all(pull, met, "NO_ECHO")),
                      reason_codes = "NO_ECHO")
  n <- stage_excluded(out$cohort)
  expect_identical(n[["lvef"]], 0L)
  expect_identical(n[["age"]], 1L)
  expect_setequal(out$data$cohort_unit, c("SYN101|2010-03-01", "SYN104|2020-01-10"))
})

test_that("the recorded checksum is of the decisions that were applied", {
  pull <- review_pull()
  # Applied: every routed unit meets lvef and none is a planned alternative, so all stay.
  rl <- review_list(pull)
  rl$outcome <- ifelse(rl$criterion_id == "lvef", "met", "not_met")
  rl$reason_code <- NA_character_
  f <- write_decisions(rl)
  original <- digest::digest(f, algo = "sha256", file = TRUE)
  swap <- decide_all(pull, code = "NO_ECHO")
  read_bytes <- .read_file_bytes
  # The file is replaced the moment it has been read.
  local_mocked_bindings(.read_file_bytes = function(path) {
    bytes <- read_bytes(path)
    utils::write.csv(swap, path, row.names = FALSE, na = "")
    bytes
  })
  out <- apply_review(pull, f, reason_codes = c("NO_ECHO", "PLANNED"))
  expect_identical(out$meta$review_decisions_sha256, original)
  expect_identical(nrow(out$data), 3L)
})

test_that("a routed unit that passes later criteria is excluded at the routing criterion", {
  con <- criteria_db()
  routed <- criterion("lvef", "LVEF 25% or less", "include",
                      view_rows("echo_demo", "measured_on", c(-30, 0), "nearest",
                                "lvef <= 25"),
                      undetermined = "review")
  # Every candidate passes this one, so the routed units reach the end active.
  adult <- criterion("adult", "Age 50 or over", "include", master_row("age >= 50"), "exclude")
  pull <- pull_demo(con, demo_query(criteria = list(routed, adult), index_on = "qualifying"))
  out <- apply_review(pull, write_decisions(decide_all(pull, code = "NO_ECHO")),
                      reason_codes = "NO_ECHO")
  s <- cohort_summary(out$cohort)$stages
  expect_identical(s$n_excluded[s$stage_id == "lvef"], 2L)
  expect_identical(s$n_in[s$stage_id == "adult"], 1L)
  expect_identical(s$n_excluded[s$stage_id == "adult"], 0L)
  expect_false("review_undetermined" %in% s$stage_id)
  prov <- out$cohort$stages$provenance[out$cohort$stages$stage_id == "lvef"]
  expect_match(prov, "2 excluded at chart review", fixed = TRUE)
  expect_identical(out$data$cohort_unit, "SYN101|2010-03-01")
})

stage_prov <- function(cohort, id) cohort$stages$provenance[cohort$stages$stage_id == id]

test_that("a unit moved back by review leaves every later stage's counts", {
  con <- criteria_db()
  routed <- criterion("lvef", "LVEF 25% or less", "include",
                      view_rows("echo_demo", "measured_on", c(-30, 0), "nearest",
                                "lvef <= 25"),
                      undetermined = "review")
  adult <- criterion("adult", "Age 50 or over", "include", master_row("age >= 50"), "exclude")
  pull <- pull_demo(con, demo_query(criteria = list(routed, adult), index_on = "qualifying"))
  expect_match(stage_prov(pull$cohort, "adult"), "met 3, not met 0, undetermined 0",
               fixed = TRUE)
  out <- apply_review(pull, write_decisions(decide_all(pull, code = "NO_ECHO")),
                      reason_codes = "NO_ECHO")
  prov <- stage_prov(out$cohort, "adult")
  # The counts describe the stage's one remaining entrant ...
  expect_match(prov, "; met 1, not met 0, undetermined 0;", fixed = TRUE)
  # ... and the warehouse's own figures are kept, labelled as such.
  expect_match(prov, "as evaluated in the warehouse before review: met 3, not met 0, ",
               fixed = TRUE)
  # The routing stage keeps its counts: every routed unit entered it.
  expect_match(stage_prov(out$cohort, "lvef"), "met 1, not met 0, undetermined 2",
               fixed = TRUE)
})

test_that("a later stage's not-met count drops a unit review moved back", {
  pull <- routed_then_age()
  out <- apply_review(pull, write_decisions(decide_all(pull, "SYN104|2020-01-10", "NO_ECHO")),
                      reason_codes = "NO_ECHO")
  expect_match(stage_prov(out$cohort, "age"), "; met 2, not met 0, undetermined 0;",
               fixed = TRUE)
})

test_that("a stage review did not change keeps its text", {
  pull <- routed_then_age()
  met <- c("SYN103|2015-06-30", "SYN104|2020-01-10")
  out <- apply_review(pull, write_decisions(decide_all(pull, met, "NO_ECHO")),
                      reason_codes = "NO_ECHO")
  expect_identical(stage_prov(out$cohort, "age"), stage_prov(pull$cohort, "age"))
})
