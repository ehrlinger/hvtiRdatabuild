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
