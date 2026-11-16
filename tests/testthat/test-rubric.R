# The hvtiR API rubric: quiet mode, condition classes, the provenance record
# and one-release deprecations. Synthetic data only; no PHI.

# ---------------------------------------------------------------------------
# Quiet mode
# ---------------------------------------------------------------------------

test_that("hvti.quiet silences informational messages and nothing else", {
  expect_message(.hvti_inform("hello"), "hello")
  withr::local_options(hvti.quiet = TRUE)
  expect_no_message(.hvti_inform("hello"))
  expect_warning(.deprecate("f", "quiet-check", "a warning still shows."), "still shows")
  rm(list = "f:quiet-check", envir = .deprecation_seen)
})

test_that("snapshot_master() is silent in quiet mode", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("tidyselect")
  dir <- withr::local_tempdir()
  file.copy(system.file("extdata", "oracle_small.sas7bdat", package = "hvtiRdatabuild"),
            file.path(dir, "built.sas7bdat"))
  writeLines("data m; run;", file.path(dir, "bd.data.sas"))
  cfg_path <- file.path(dir, "master.yml")
  writeLines(c("name: master_q", "key: [ccfidu]", paste0("snapshots: ", dir),
               "current: built.sas7bdat",
               paste0("build_program: ", file.path(dir, "bd.data.sas"))), cfg_path)
  withr::local_options(hvti.quiet = TRUE)
  expect_no_message(snapshot_master(read_master_config(cfg_path), withr::local_tempdir(),
                                    which = "current"))
})

# ---------------------------------------------------------------------------
# Provenance record
# ---------------------------------------------------------------------------

test_that("the provenance record has the seven fields with their types", {
  expect_provenance_record(.provenance_record("test"))
  expect_identical(.provenance_record("test")$package, "hvtiRdatabuild")
})

test_that("a master pull carries the record in $meta and keeps $provenance", {
  con <- local_master_db()
  res <- pull_demo(con, demo_query())
  expect_provenance_record(res$meta)
  expect_identical(res$meta$method, "pull_master")
  expect_identical(res$meta$sql_commit, "abc1234")
  expect_identical(res$provenance$sql_commit, "abc1234")
  expect_null(res$provenance$package)
})

test_that("the analysis-set sidecar carries the record and a POSIXct-readable time", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set()))
  side <- write_analysis_set("eda", cfg)
  expect_provenance_record(side$provenance)
  on_disk <- yaml::read_yaml(.set_paths("eda", cfg)$sidecar)
  for (x in c(on_disk$written, on_disk$provenance$time)) {
    t <- as.POSIXct(x, tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ")
    expect_false(is.na(t))
  }
  expect_length(on_disk$provenance$rng_kind, 3L)
})

# ---------------------------------------------------------------------------
# Condition classes
# ---------------------------------------------------------------------------

test_that("catchable errors carry hvtiRdatabuild_<condition>", {
  dir <- local_publication_dir()
  draft <- write_synthetic_draft(dir)
  first <- publish_dataset(draft, "cohort", dir, "2026-09-21")
  withdraw_dataset_release("cohort", first$release_id, dir, "Synthetic correction")
  err <- tryCatch(publish_dataset(draft, "cohort", dir, "2026-09-21"), error = identity)
  expect_s3_class(err, "hvtiRdatabuild_withdrawn_release")
  expect_s3_class(err, "hvtiRdatabuild_error")
  expect_null(conditionCall(err))
})

test_that("a stale set's message carries the new class first, the old one second", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("hvtiPlotR")
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "")
  cfg <- stale_by_new_parent()
  m <- tryCatch(read_analysis_set("eda", cfg), message = identity)
  expect_identical(class(m)[1:2], c("hvtiRdatabuild_stale_analysis_set",
                                    "hvtiRutilities_stale_analysis_set"))
  withr::local_envvar(HVTI_TEMPLATE_STRICT = "1")
  err <- tryCatch(read_analysis_set("eda", cfg), error = identity)
  expect_s3_class(err, "hvtiRdatabuild_stale_analysis_set")
  expect_match(conditionMessage(err), "^read_analysis_set\\(\\): ")
})

# ---------------------------------------------------------------------------
# Renamed arguments
# ---------------------------------------------------------------------------

test_that("compare_built(): id is renamed id_col, and id_col has no default", {
  fresh_deprecations()
  o <- data.frame(ccfidu = c("A1", "A2"), age = c(65, 70))
  expect_warning(res <- compare_built(o, o, id = "ccfidu"), class = "hvtiRdatabuild_deprecated")
  expect_equal(attr(res, "rows")$n_common, 2L)
  expect_no_warning(compare_built(o, o, id = "ccfidu"))
  expect_error(compare_built(o, o, id_col = "ccfidu", id = "ccfidu"),
               "compare_built\\(\\): give `id_col` only; `id` is its old name",
               class = "hvtiRdatabuild_both_names")
  expect_warning(compare_built(o, o), "`id_col` has no default",
                 class = "hvtiRdatabuild_deprecated")
  expect_no_warning(compare_built(o, o, "ccfidu"))
})

test_that("parse_legacy_facts(): key_var is renamed key_col, with no default", {
  fresh_deprecations()
  lines <- c("if ccfid = 'K1' then age = 70;")
  new <- parse_legacy_facts(lines, key_col = "ccfid")
  expect_warning(old <- parse_legacy_facts(lines, key_var = "ccfid"),
                 class = "hvtiRdatabuild_deprecated")
  expect_identical(old, new)
  expect_warning(parse_legacy_facts(lines), class = "hvtiRdatabuild_deprecated")
  expect_error(parse_legacy_facts(lines, key_col = "a", key_var = "b"),
               class = "hvtiRdatabuild_both_names")
})

test_that("pull_master(): columns and study_config are renamed var_cols and path", {
  fresh_deprecations()
  con <- local_master_db()
  new <- pull_demo(con, demo_query())
  expect_warning(
    expect_warning(
      old <- pull_master(con, "master_demo", demo_query(), columns = "age",
                         study_config = demo_config, dialect = "duckdb"),
      class = "hvtiRdatabuild_deprecated"
    ),
    class = "hvtiRdatabuild_deprecated"
  )
  expect_identical(old$data, new$data)
  expect_error(pull_master(con, "master_demo", demo_query(), var_cols = "age",
                           columns = "age"),
               "give `var_cols` only; `columns`", class = "hvtiRdatabuild_both_names")
  expect_error(pull_master(con, "master_demo", demo_query(), "age", demo_config,
                           study_config = demo_config),
               "give `path` only; `study_config`", class = "hvtiRdatabuild_both_names")
})

test_that("propose_correction(): variable is renamed var_col", {
  fresh_deprecations()
  expect_error(
    propose_correction(NULL, NULL, list(), var_col = "a", variable = "a"),
    "give `var_col` only; `variable`", class = "hvtiRdatabuild_both_names"
  )
  expect_warning(try(propose_correction(NULL, NULL, list(), variable = "a"), silent = TRUE),
                 class = "hvtiRdatabuild_deprecated")
})

test_that("out_dir and datasets_dir are renamed dir", {
  fresh_deprecations()
  expect_error(snapshot_master(NULL, dir = "a", out_dir = "a"),
               "snapshot_master\\(\\): give `dir` only; `out_dir`",
               class = "hvtiRdatabuild_both_names")
  expect_error(publish_dataset("x", "d", dir = "a", datasets_dir = "a"),
               "publish_dataset\\(\\): give `dir` only; `datasets_dir`",
               class = "hvtiRdatabuild_both_names")
  expect_error(withdraw_dataset_release("d", "r", dir = "a", reason = "x", datasets_dir = "a"),
               "withdraw_dataset_release\\(\\): give `dir` only",
               class = "hvtiRdatabuild_both_names")
  expect_error(freeze_study_pull(NULL, dir = "a", datasets_dir = "a"),
               "freeze_study_pull\\(\\): give `dir` only", class = "hvtiRdatabuild_both_names")
  expect_error(freeze_study_pull(NULL, path = "a", study_config = "a"),
               "freeze_study_pull\\(\\): give `path` only", class = "hvtiRdatabuild_both_names")

  dir <- local_publication_dir()
  draft <- write_synthetic_draft(dir)
  expect_warning(rel <- publish_dataset(draft, "cohort", datasets_dir = dir,
                                        extract_date = "2026-09-21"),
                 class = "hvtiRdatabuild_deprecated")
  expect_identical(rel$status, "published")
  expect_warning(withdraw_dataset_release("cohort", rel$release_id, datasets_dir = dir,
                                          reason = "Synthetic"),
                 class = "hvtiRdatabuild_deprecated")
})

test_that("snapshot_oracle(): sas_path and out_path are renamed path and file", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  fresh_deprecations()
  src <- system.file("extdata", "oracle_small.sas7bdat", package = "hvtiRdatabuild")
  out <- file.path(withr::local_tempdir(), "o.parquet")
  expect_warning(
    expect_warning(snapshot_oracle(sas_path = src, out_path = out),
                   class = "hvtiRdatabuild_deprecated"),
    class = "hvtiRdatabuild_deprecated"
  )
  expect_true(file.exists(out))
  expect_error(snapshot_oracle(path = src, sas_path = src),
               "give `path` only; `sas_path`", class = "hvtiRdatabuild_both_names")
  expect_error(snapshot_oracle(src, file = out, out_path = out),
               "give `file` only; `out_path`", class = "hvtiRdatabuild_both_names")
  # A positional call binds as before.
  out2 <- file.path(withr::local_tempdir(), "p.parquet")
  expect_no_warning(snapshot_oracle(src, out2))
  expect_true(file.exists(out2))
})

test_that("dw_pull(): conn is renamed con", {
  fresh_deprecations()
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      data.frame(masterid = 1:2, patid = 3:4, value = c(1.5, 2.5))
    },
    .package = "DBI"
  )
  cfg <- structure(list(
    study = "st1234", cohort_table = "db.sch.st1234_cohort", warehouse = "wh",
    view_schema = "dbo", pull_date = as.Date("2026-08-04"), modules = "base",
    varsets = character(0), derive = stats::setNames(logical(0), character(0))
  ), class = "study_config")
  fake <- structure(list(), class = "FakeConnection")
  expect_warning(dw_pull(cfg, conn = fake), class = "hvtiRdatabuild_deprecated")
  expect_no_warning(dw_pull(cfg, con = fake))
  expect_error(dw_pull(cfg, con = fake, conn = fake), "give `con` only",
               class = "hvtiRdatabuild_both_names")
})
