# End-to-end: a parent master and a child master built on top of it, each lifted into
# the same warehouse connection, both views existing side by side. Invented data. No PHI.

test_that("a parent and a child master can both be lifted into the same warehouse", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("dplyr")
  skip_if_not_installed("withr")
  skip_if_not_installed("tidyselect")

  dir <- withr::local_tempdir()

  parent_d <- data.frame(ccfid = c("K1", "K2", "K3"), age = c(60, 61, 62),
                         stringsAsFactors = FALSE)
  parent_pq <- file.path(dir, "built_parent.parquet")
  arrow::write_parquet(parent_d, parent_pq)
  jsonlite::write_json(
    list(parquet_sha256 = digest::digest(parent_pq, algo = "sha256", file = TRUE),
         columns = list(list(variable = "ccfid", r_class = "character"),
                        list(variable = "age", r_class = "numeric"))),
    sub("\\.parquet$", ".meta.json", parent_pq), auto_unbox = TRUE
  )
  parent_cfg <- structure(list(
    name = "master_parent", key = "ccfid", alt_keys = list(), parent = NULL,
    parent_release = NULL, snapshots = dir, current = "built_parent.sas7bdat",
    history = NULL, build_program = file.path(dir, "bd_parent.sas"),
    file = file.path(dir, "master_parent.yml")
  ), class = "master_config")

  child_d <- data.frame(ccfid = c("K1", "K2", "K3"), valve = c("mitral", "aortic", "mitral"),
                        stringsAsFactors = FALSE)
  child_pq <- file.path(dir, "built_child.parquet")
  arrow::write_parquet(child_d, child_pq)
  jsonlite::write_json(
    list(parquet_sha256 = digest::digest(child_pq, algo = "sha256", file = TRUE),
         columns = list(list(variable = "ccfid", r_class = "character"),
                        list(variable = "valve", r_class = "character"))),
    sub("\\.parquet$", ".meta.json", child_pq), auto_unbox = TRUE
  )
  child_cfg <- structure(list(
    name = "master_child", key = "ccfid", alt_keys = list(),
    parent = list(master = "master_parent", libref = "master"), parent_release = NULL,
    snapshots = dir, current = "built_child.sas7bdat", history = NULL,
    build_program = file.path(dir, "bd_child.sas"), file = file.path(dir, "master_child.yml")
  ), class = "master_config")

  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  res_parent <- suppressMessages(lift_master(parent_cfg, con, parent_pq, dry_run = FALSE,
                                             dialect = "duckdb"))
  res_child <- suppressMessages(lift_master(child_cfg, con, child_pq, dry_run = FALSE,
                                            dialect = "duckdb"))
  expect_equal(res_parent$verdict, "pass")
  expect_equal(res_child$verdict, "pass")
  expect_true(DBI::dbExistsTable(con, "master_parent"))
  expect_true(DBI::dbExistsTable(con, "master_child"))
  expect_equal(nrow(DBI::dbGetQuery(con, "SELECT * FROM master_parent")), 3L)
  expect_equal(nrow(DBI::dbGetQuery(con, "SELECT * FROM master_child")), 3L)
})
