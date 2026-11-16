.pull_metadata_key <- "hvtiRdatabuild.pull"

#' Freeze a study's pull from a master view
#'
#' Sources are not time-travelable, so the release, not the warehouse, is the record of
#' what a study read. `freeze_study_pull()` publishes the pull as an immutable parquet
#' release with [publish_dataset()], with its provenance written **into the file's own
#' metadata**: the SQL model commit, the ids of the corrections applied, when the pull
#' read, the parity verdict it passed, the cohort definition and stage counts, and the
#' study configuration's checksum as recorded when the pull ran.
#' Because the provenance is part of the bytes, the release's SHA-256 covers it, and a
#' release can never exist without it. Read it back with [read_pull_provenance()].
#'
#' The configuration must be unchanged since the pull: if its checksum no longer matches
#' the one [pull_master()] recorded, nothing is published.
#'
#' Retrying the same pull returns the same release. A distinct pull with identical data
#' carries different provenance, so it becomes its own release.
#'
#' The retained pull holds patient values. It belongs in the study's data folder under
#' the same rules as the built dataset, never in a repository.
#'
#' @param pull A `master_pull` from [pull_master()].
#' @param study_config Character. Path to the study configuration file given to
#'   [pull_master()]; it must be unchanged since the pull.
#' @param datasets_dir,dataset_id,extract_date As for [publish_dataset()].
#'
#' @return Invisibly, the release, as returned by [publish_dataset()].
#'
#' @seealso [read_pull_provenance()], [pull_master()], [publish_dataset()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE) &&
#'       requireNamespace("arrow", quietly = TRUE)) {
#'   # Synthetic data; no PHI.
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   DBI::dbWriteTable(con, "master_demo", data.frame(
#'     mrn = "SYN101", encounter_date = as.Date("2010-03-01"), proc = "CABG", age = 62
#'   ))
#'   DBI::dbWriteTable(con, "master_demo_corrections_applied", data.frame(
#'     correction_id = character(), mrn = character(), encounter_date = as.Date(character())
#'   ))
#'   DBI::dbWriteTable(con, "master_demo_deployment", data.frame(sql_commit = "abc1234"))
#'   DBI::dbWriteTable(con, "master_demo_parity", data.frame(
#'     sql_commit = "abc1234", verdict = "pass", verified_at = Sys.time()
#'   ))
#'   config <- tempfile(fileext = ".yaml")
#'   writeLines("study: st0000", config)
#'   q <- cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")))
#'   pull <- pull_master(con, "master_demo", q, columns = "age", study_config = config,
#'                       dialect = "duckdb")
#'   published <- tempfile("published-")
#'   dir.create(published)
#'   release <- freeze_study_pull(pull, config, published, "st0000_pull")
#'   read_pull_provenance(file.path(published, release$file))$sql_commit
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#'   unlink(c(config, published), recursive = TRUE)
#' }
#' }
#'
#' @export
freeze_study_pull <- function(pull, study_config, datasets_dir, dataset_id,
                              extract_date = Sys.Date()) {
  if (!inherits(pull, "master_pull")) {
    stop("'pull' must be a master_pull from pull_master().", call. = FALSE)
  }
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("Freezing a pull writes parquet and needs the arrow package.", call. = FALSE)
  }
  if (!is.character(study_config) || length(study_config) != 1L ||
        !file.exists(study_config)) {
    stop("'study_config' must be the path of an existing study configuration file.",
         call. = FALSE)
  }
  if (!identical(digest::digest(study_config, algo = "sha256", file = TRUE),
                 pull$provenance$study_config_sha256)) {
    stop("The study configuration has changed since the pull. Pull again with the ",
         "current configuration. Nothing was published.", call. = FALSE)
  }

  stages <- cohort_summary(pull$cohort)$stages
  prov <- c(
    list(schema = 1L),
    pull$provenance,
    list(cohort_stages = as.list(stages[c("stage_id", "n_in", "n_excluded", "n_remaining")]))
  )
  table <- arrow::arrow_table(pull$data)
  metadata <- table$metadata
  metadata[[.pull_metadata_key]] <- yaml::as.yaml(prov)
  table$metadata <- metadata

  draft <- tempfile(fileext = ".parquet")
  on.exit(unlink(draft), add = TRUE)
  arrow::write_parquet(table, draft)

  release <- publish_dataset(
    draft, dataset_id, datasets_dir, extract_date = extract_date,
    source = sprintf("pull_master() from %s at SQL commit %s",
                     pull$provenance$master, pull$provenance$sql_commit)
  )
  invisible(release)
}

#' Read the provenance a frozen pull carries
#'
#' @param path Character. A parquet file written by [freeze_study_pull()].
#'
#' @return A list: `schema`, `master`, `sql_commit`, `applied_correction_ids`,
#'   `corrections_in_effect`, `parity_verified_at`, `read_at`, `columns`,
#'   `cohort_definition`, `study_config_sha256`, `n_cohort`, `n_matched`, `n_unmatched`
#'   and `cohort_stages`.
#'
#' @seealso [freeze_study_pull()]
#'
#' @examples
#' # See freeze_study_pull().
#'
#' @export
read_pull_provenance <- function(path) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("Reading pull provenance needs the arrow package.", call. = FALSE)
  }
  # The footer holds the schema and its metadata; no column data is read.
  schema <- arrow::ParquetFileReader$create(path)$GetSchema()
  text <- schema$metadata[[.pull_metadata_key]]
  if (is.null(text)) {
    stop("This file carries no pull provenance.", call. = FALSE)
  }
  yaml::yaml.load(text, eval.expr = FALSE)
}
