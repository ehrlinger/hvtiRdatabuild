# No PHI: identifiers and values are invented.

test_that("the SQL combination agrees with R on every flag pattern", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  vals <- c(1L, 0L, NA)
  grid <- expand.grid(crit_1 = vals, crit_2 = vals, crit_3 = vals)
  DBI::dbWriteTable(con, "flags", grid)
  leaf <- function(k) list(type = "leaf", col = paste0("crit_", k))
  nodes <- list(
    list(type = "any", parts = list(leaf(1), leaf(2), leaf(3))),
    list(type = "all", parts = list(leaf(1), leaf(2), leaf(3))),
    list(type = "any", parts = list(leaf(1),
                                    list(type = "all", parts = list(leaf(2), leaf(3)))))
  )
  for (node in nodes) {
    got <- DBI::dbGetQuery(con, paste("SELECT", .node_sql(node), "AS s FROM flags"))$s
    expect_identical(as.integer(got), .eval_node(node, grid))
  }
})

test_that("deactivation keeps exactly the units R keeps", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  for (role in c("include", "exclude")) {
    for (und in c("exclude", "keep", "review")) {
      DBI::dbWriteTable(con, "t", data.frame(active = 1L, crit_1 = c(1L, 0L, NA)),
                        overwrite = TRUE)
      stage <- list(role = role, undetermined = und,
                    node = list(type = "leaf", col = "crit_1"))
      DBI::dbExecute(con, .deactivate_sql("t", stage))
      got <- DBI::dbGetQuery(con, "SELECT active FROM t")$active == 1L
      expect_identical(got, .stage_outcome(role, und, c(1L, 0L, NA), "L")$included,
                       info = paste(role, und))
    }
  }
})

lvef <- function(pick, window = c(-30, 0), condition = "lvef <= 25") {
  view_rows("echo_demo", "measured_on", window, pick, condition)
}

test_that("pick any, all and nearest judge the rows in the window", {
  con <- local_master_db()
  seed_criteria_views(con)
  flag_table(con, c("SYN101", "SYN103", "SYN104"),
             c("2010-03-01", "2015-06-30", "2020-01-10"))
  # SYN101: 22 in window, 50 outside. SYN103: 30 and 20 tied nearest. SYN104: none.
  expect_identical(leaf_flags(con, lvef("any")),
                   c(SYN101 = 1L, SYN103 = 1L, SYN104 = NA))
  expect_identical(leaf_flags(con, lvef("all")),
                   c(SYN101 = 1L, SYN103 = 0L, SYN104 = NA))
  expect_identical(leaf_flags(con, lvef("nearest")),
                   c(SYN101 = 1L, SYN103 = NA, SYN104 = NA))
})

test_that("window edges are inclusive and outside rows are ignored", {
  con <- local_master_db()
  seed_criteria_views(con)
  flag_table(con, "SYN101", "2010-03-01")
  # The 22 is 9 days before.
  expect_identical(leaf_flags(con, lvef("any", c(-9, 0))), c(SYN101 = 1L))
  expect_identical(leaf_flags(con, lvef("any", c(-8, 0))), c(SYN101 = NA_integer_))
  # The 50 is 59 days before.
  expect_identical(leaf_flags(con, lvef("any", c(-59, -59))), c(SYN101 = 0L))
})

test_that("an unknown condition makes the test undetermined, not unmet", {
  con <- local_master_db()
  seed_criteria_views(con)
  DBI::dbExecute(con, "INSERT INTO echo_demo VALUES ('SYN104', DATE '2020-01-09', NULL)")
  flag_table(con, "SYN104", "2020-01-10")
  expect_identical(leaf_flags(con, lvef("nearest")), c(SYN104 = NA_integer_))
  expect_identical(leaf_flags(con, lvef("any")), c(SYN104 = NA_integer_))
})

test_that("nearest takes the closer side and a timestamp is cast to its date", {
  con <- local_master_db()
  seed_criteria_views(con)
  DBI::dbExecute(con, "INSERT INTO echo_demo VALUES ('SYN104', DATE '2020-01-12', 60)")
  DBI::dbExecute(con, "INSERT INTO echo_demo VALUES ('SYN104', DATE '2020-01-05', 20)")
  flag_table(con, "SYN104", "2020-01-10")
  expect_identical(leaf_flags(con, lvef("nearest", c(-30, 30))), c(SYN104 = 0L))
  inotrope <- view_rows("med_demo", "given_at", c(-3, 0), "any",
                        "drug_class = 'inotrope'")
  flag_table(con, c("SYN101", "SYN104"), c("2010-03-01", "2020-01-10"))
  expect_identical(leaf_flags(con, inotrope), c(SYN101 = 1L, SYN104 = NA))
})

test_that("a master_row test reads the encounter's own row", {
  con <- local_master_db()
  flag_table(con, c("SYN101", "SYN104"), c("2010-03-01", "2020-01-10"))
  expect_identical(leaf_flags(con, master_row("age >= 65")),
                   c(SYN101 = 0L, SYN104 = 1L))
})

test_that("inactive units are not evaluated", {
  con <- local_master_db()
  flag_table(con, c("SYN101", "SYN104"), c("2010-03-01", "2020-01-10"))
  DBI::dbExecute(con, "UPDATE study_cohort SET active = 0 WHERE mrn = 'SYN104'")
  expect_identical(leaf_flags(con, master_row("age >= 65")),
                   c(SYN101 = 0L, SYN104 = NA))
})
