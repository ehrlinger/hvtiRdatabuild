# Tests for read_master_config(). Every config here is synthetic. No PHI.

write_cfg <- function(lines) {
  p <- withr::local_tempfile(fileext = ".yml", .local_envir = parent.frame())
  writeLines(lines, p)
  p
}

base_cfg <- c(
  "name: master_x",
  "key: [ccfid, dt_surg]",
  "snapshots: /tmp/x",
  "current: built.sas7bdat",
  "build_program: /tmp/x/bd.sas"
)

test_that("a minimal config reads, with empty alt_keys and no parent", {
  cfg <- read_master_config(write_cfg(base_cfg))
  expect_s3_class(cfg, "master_config")
  expect_equal(cfg$key, c("ccfid", "dt_surg"))
  expect_equal(length(cfg$alt_keys), 0L)
  expect_null(cfg$parent)
  expect_null(cfg$parent_release)
})

test_that("the example config reads, with a named alternate key and a parent", {
  cfg <- read_master_config(system.file("extdata", "master-example.yml",
                                        package = "hvtiRdatabuild"))
  expect_equal(cfg$alt_keys$epic, c("emrn", "encounter_date"))
  expect_equal(cfg$parent$libref, "master")
})

test_that("each required field is required", {
  for (f in c("name", "key", "snapshots", "current", "build_program")) {
    lines <- base_cfg[!startsWith(base_cfg, paste0(f, ":"))]
    expect_error(read_master_config(write_cfg(lines)), f)
  }
})

test_that("a parent needs both master and libref", {
  expect_error(read_master_config(write_cfg(c(base_cfg, "parent:", "  master: p"))),
               "libref")
  expect_error(read_master_config(write_cfg(c(base_cfg, "parent:", "  libref: m"))),
               "master")
})

test_that("parent_release must be one string and needs a parent", {
  expect_error(read_master_config(write_cfg(c(base_cfg, "parent_release: r1"))),
               "parent")
  expect_error(read_master_config(write_cfg(c(base_cfg, "parent:", "  master: p",
                                              "  libref: m",
                                              "parent_release: [a, b]"))),
               "single string")
})

test_that("a column named twice across key and alt_keys is refused", {
  expect_error(read_master_config(write_cfg(c(base_cfg, "alt_keys:",
                                              "  epic: [ccfid, encounter_date]"))),
               "more than once")
})

test_that("a history pattern that does not compile is refused", {
  expect_error(read_master_config(write_cfg(c(base_cfg, "history: \"[unclosed\""))),
               "history")
})

test_that(".master_tables derives every table name from the master's name", {
  cfg <- read_master_config(write_cfg(base_cfg))
  t <- .master_tables(cfg)
  expect_equal(t$corrections, "master_x_corrections")
  expect_equal(t$decisions, "master_x_correction_decisions")
  expect_equal(t$stale, "master_x_corrections_stale")
  expect_equal(t$parity, "master_x_parity")
  expect_equal(t$meta, "master_x_meta")
})

test_that("a parent that is not a mapping is refused", {
  expect_error(read_master_config(write_cfg(c(base_cfg, "parent: master_parent"))),
               "master and libref")
})

test_that("an empty key is refused", {
  expect_error(read_master_config(write_cfg(c(base_cfg[!startsWith(base_cfg, "key:")],
                                              "key: []"))),
               "at least one")
})

test_that("an alternate key with zero columns or an empty column name is refused", {
  expect_error(read_master_config(write_cfg(c(base_cfg, "alt_keys:", "  epic: []"))),
               "Alternate key 'epic' must name at least one column")
  expect_error(read_master_config(write_cfg(c(base_cfg, "alt_keys:",
                                              "  epic: [emrn, \"\"]"))),
               "Alternate key 'epic' must name at least one column")
})

test_that("an unnamed alt_keys sequence is refused", {
  expect_error(read_master_config(write_cfg(c(base_cfg, "alt_keys: [a, b]"))),
               "mapping of names")
})

test_that("non-character key or alt_keys values are refused", {
  expect_error(read_master_config(write_cfg(c(base_cfg[!startsWith(base_cfg, "key:")],
                                              "key: 123"))),
               "not numbers")
  expect_error(read_master_config(write_cfg(c(base_cfg, "alt_keys:", "  epic: 456"))),
               "not numbers")
})
