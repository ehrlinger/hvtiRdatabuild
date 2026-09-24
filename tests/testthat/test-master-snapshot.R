# Tests for snapshot_master(). The SAS fixture is the package's synthetic
# oracle_small.sas7bdat; logs and programs are invented text. No PHI.

make_master <- function(env = parent.frame(), log_member = "built_2026mar27",
                        prog_member = "built_2026mar27", with_log = TRUE) {
  dir <- withr::local_tempdir(.local_envir = env)
  src <- system.file("extdata", "oracle_small.sas7bdat", package = "hvtiRdatabuild")
  file.copy(src, file.path(dir, "built.sas7bdat"))
  dir.create(file.path(dir, "2023"))
  file.copy(src, file.path(dir, "2023", "built_2023jan.sas7bdat"))
  # An old build: no log is written within hours of it.
  Sys.setFileTime(file.path(dir, "2023", "built_2023jan.sas7bdat"),
                  Sys.time() - 30 * 86400)
  writeLines(c("data m;", paste0("  set master.", prog_member, ";"), "run;"),
             file.path(dir, "bd.data.sas"))
  if (with_log) {
    log <- file.path(dir, "bd.data.log")
    writeLines(c("NOTE: invented log.",
                 paste0("NOTE: There were 4 observations read from the data set MASTER.",
                        toupper(log_member), ".")), log)
    t <- file.mtime(file.path(dir, "built.sas7bdat")) + 60
    Sys.setFileTime(log, t)
  }
  cfg_path <- file.path(dir, "master.yml")
  writeLines(c("name: master_x", "key: [ccfidu]", "alt_keys:", "  bridge: [surgeon]",
               "parent:", "  master: master_parent", "  libref: master",
               paste0("snapshots: ", dir), "current: built.sas7bdat",
               "history: \"^built_.*\\\\.sas7bdat$\"",
               paste0("build_program: ", file.path(dir, "bd.data.sas"))), cfg_path)
  list(dir = dir, cfg = read_master_config(cfg_path))
}

test_that("the current snapshot records the parent release from the log", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  m <- make_master()
  out <- withr::local_tempdir()
  res <- snapshot_master(m$cfg, out, which = "current")
  expect_equal(res$status, "written")
  expect_equal(res$parent_release, "built_2026mar27")
  expect_equal(res$parent_source, "log")
  expect_equal(res$key_verdict, "unique")
  meta <- jsonlite::read_json(file.path(out, "built.meta.json"), simplifyVector = TRUE)
  expect_equal(meta$lineage$parent_release, "built_2026mar27")
  expect_equal(meta$keys$bridge, "not unique")
})

test_that("the log beats a program that names a different parent release", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  m <- make_master(log_member = "built_2026mar27", prog_member = "built_2025mar31")
  res <- snapshot_master(m$cfg, withr::local_tempdir(), which = "current")
  expect_equal(res$parent_release, "built_2026mar27")
  expect_equal(res$parent_source, "log")
})

test_that("without a bracketing log the program decides", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  m <- make_master(with_log = FALSE)
  res <- snapshot_master(m$cfg, withr::local_tempdir(), which = "current")
  expect_equal(res$parent_source, "program")
})

test_that("an ambiguous parent stops unless parent_release is declared", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  m <- make_master(with_log = FALSE)
  writeLines(c("set master.built_a;", "set master.built_b;"), m$cfg$build_program)
  expect_error(snapshot_master(m$cfg, withr::local_tempdir(), which = "current"),
               "parent_release")
  m$cfg$parent_release <- "built_a"
  res <- snapshot_master(m$cfg, withr::local_tempdir(), which = "current")
  expect_equal(res$parent_source, "declared")
})

test_that("history is found in subfolders, and its unknown parent does not stop", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  m <- make_master()
  expect_equal(basename(.find_history(m$cfg)), "built_2023jan.sas7bdat")
  res <- snapshot_master(m$cfg, withr::local_tempdir(), which = "history")
  expect_equal(res$status, "written")
  expect_equal(res$parent_source, "unknown")
})

test_that("a second run skips what is already written", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  m <- make_master()
  out <- withr::local_tempdir()
  snapshot_master(m$cfg, out, which = "current")
  res <- snapshot_master(m$cfg, out, which = "current")
  expect_equal(res$status, "skipped")
})

test_that("a master with no parent records no lineage", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  m <- make_master()
  m$cfg$parent <- NULL
  res <- snapshot_master(m$cfg, withr::local_tempdir(), which = "current")
  expect_true(is.na(res$parent_release))
  expect_equal(res$parent_source, "none")
})
