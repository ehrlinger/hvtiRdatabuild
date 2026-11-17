#' Turn a study's own data fixes into candidate corrections
#'
#' A fix made in study code leaves the study out of step with the master and every other
#' study (G5). This compares the study's corrected data with **the study's own frozen
#' pull**, never the live view: sources are not time-travelable, so a later read would
#' mistake upstream change for a study fix (spec §3.5).
#'
#' - **Pass-through columns.** A differing cell in a column that `<master>_lineage` lists
#'   becomes a row of the correction template at `path`. The row is keyed by the source's
#'   declared key, and `expected_prior` comes from the pull. `evidence_type` and
#'   `asserted_by` are left blank, so [propose_corrections()] refuses the file until a
#'   person has reviewed it and filled them in.
#' - **Derived columns.** A differing cell in any other column is a candidate derivation,
#'   not a correction. It is counted per column in the `-derived.csv` file beside `path`.
#' - **Patient-level sources.** When encounters of one patient disagree on such a source's
#'   cell, the candidates are dropped and counted as inconsistent. Agreement is checked
#'   over the encounters present in `data`; an encounter dropped from `data` carries no
#'   study value, so it cannot contradict a candidate, and intake rechecks
#'   `expected_prior` against the source.
#' - **Undeclared sources.** A lineage source not declared in `master.yml` is counted as
#'   derived, because this intake cannot correct it.
#'
#' If the source has changed since the pull, intake refuses the row as `prior_mismatch`.
#' Nothing is appended here, and only counts are printed. The files hold identifiers and
#' belong in the study's data folder.
#'
#' **Interim.** Superseded by the HVTR registry.
#'
#' @param config A `master_config` from [read_master_config()], with `sources`.
#' @param con A DBI connection to the warehouse, to read the master's lineage.
#' @param pull Character. The study's frozen pull, from [freeze_study_pull()].
#' @param data A data frame: the study's corrected data, keyed as the pull is.
#' @param path Character. The candidate template to write, ending `.csv`. Never
#'   overwritten.
#' @param key Character. The cohort unit's key columns in the pull and in `data`.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return Invisibly, a list: `candidates`, `inconsistent`, `derived` (a data frame of
#'   `column`, `n_cells`), `path` and `derived_path`.
#'
#' @seealso [propose_corrections()], [freeze_study_pull()]
#'
#' @examples
#' # Needs a frozen pull and the warehouse; see freeze_study_pull().
#'
#' @export
study_correction_candidates <- function(config, con, pull, data, path,
                                        key = c("mrn", "encounter_date"),
                                        dialect = "mssql") {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    .abort("needs_arrow", "study_correction_candidates(): needs the arrow package.")
  }
  if (!grepl("\\.csv$", path)) {
    .abort("bad_path", "study_correction_candidates(): `path` must end in .csv.")
  }
  derived_path <- sub("\\.csv$", "-derived.csv", path)
  if (file.exists(path) || file.exists(derived_path)) {
    .abort("file_exists", "study_correction_candidates(): an output file already exists.")
  }
  prov <- read_pull_provenance(pull)
  if (!identical(prov$master, config$name)) {
    .abort("wrong_master", "study_correction_candidates(): the pull is not from ",
           config$name, ".")
  }
  q <- quoter(dialect)
  # One snapshot for both reads, so a redeployment between them cannot pair the pull's
  # commit with a newer lineage.
  read <- .with_snapshot_txn(con, dialect, list(
    commit = .read_deployment(con, paste0(config$name, "_deployment"), dialect),
    lineage = run_step("read lineage", DBI::dbGetQuery(con, paste(
      "SELECT master_column, source, source_column FROM",
      q(paste0(config$name, "_lineage")),
      "ORDER BY master_column, source, source_column"
    )))
  ))
  if (!identical(read$commit, prov$sql_commit)) {
    .abort("lineage_moved", "study_correction_candidates(): the master was redeployed ",
           "since the pull, so its lineage may differ. Re-pull, then compare.")
  }
  lineage <- read$lineage
  pairs <- unique(lineage[c("master_column", "source", "source_column")])
  if (anyDuplicated(pairs$master_column)) {
    .abort("ambiguous_lineage", "study_correction_candidates(): a master column ",
           "has more than one lineage source, e.g. `",
           pairs$master_column[anyDuplicated(pairs$master_column)], "`.")
  }
  base <- as.data.frame(arrow::read_parquet(pull))
  if (!all(key %in% names(base)) || !all(key %in% names(data))) {
    .abort("key_columns", "study_correction_candidates(): the pull and `data` must both ",
           "carry ", paste(key, collapse = ", "), ".")
  }
  if (anyNA(base[key]) || anyNA(data[key])) {
    .abort("missing_key", "study_correction_candidates(): ",
           sum(!stats::complete.cases(data[key])), " row(s) of `data` and ",
           sum(!stats::complete.cases(base[key])), " of the pull have a missing key.")
  }
  unit <- function(d) .composite_key(lapply(d[key], as.character))
  if (anyDuplicated(unit(base)) || anyDuplicated(unit(data))) {
    .abort("duplicate_units", "study_correction_candidates(): a unit appears twice.")
  }
  m <- match(unit(data), unit(base))
  if (anyNA(m)) {
    .abort("unknown_units", "study_correction_candidates(): ", sum(is.na(m)),
           " row(s) of `data` are not in the pull.")
  }
  as_text <- function(x) {
    if (is.factor(x)) x <- as.character(x)
    vapply(seq_along(x), function(i) value_text(x[i]), character(1))
  }
  pull_sha <- substr(digest::digest(pull, algo = "sha256", file = TRUE), 1, 12)
  cols <- setdiff(intersect(names(data), names(base)), key)
  tpl_cols <- .template_columns(config)
  cand <- list()
  inconsistent <- 0L
  derived <- data.frame(column = character(), n_cells = integer(), stringsAsFactors = FALSE)
  for (col in cols) {
    before <- as_text(base[[col]][m])
    after <- as_text(data[[col]])
    differ <- xor(is.na(before), is.na(after)) |
      (!is.na(before) & !is.na(after) & before != after)
    if (!any(differ)) next
    lin <- lineage[lineage$master_column == col, , drop = FALSE]
    if (!nrow(lin) || !lin$source[[1]] %in% names(config$sources)) {
      derived[nrow(derived) + 1L, ] <- list(col, sum(differ))
      next
    }
    s <- lin$source[[1]]
    s_key <- config$sources[[s]]$key
    if (!all(s_key %in% names(base))) {
      .abort("source_key_missing", "study_correction_candidates(): the pull lacks ",
             "source ", s, "'s key column(s).")
    }
    # A source cell shared by several encounters (a patient-level source) is a candidate
    # only when every one of those encounters in `data` agrees on it, changed or not.
    grp <- .composite_key(lapply(s_key, function(k) as_text(base[[k]][m])))
    n_vals <- tapply(ifelse(is.na(after), "\001missing", after), grp,
                     function(x) length(unique(x)))
    split <- grp %in% names(n_vals)[n_vals > 1L]
    inconsistent <- inconsistent + length(unique(grp[differ & split]))
    i <- which(differ & !split)
    if (!length(i)) next
    rows <- as.data.frame(stats::setNames(rep(list(rep(NA_character_, length(i))),
                                              length(tpl_cols)), tpl_cols),
                          check.names = FALSE, stringsAsFactors = FALSE)
    rows$source <- s
    for (k in s_key) rows[[k]] <- as_text(base[[k]][m[i]])
    rows$variable <- lin$source_column[[1]]
    rows$expected_prior <- before[i]
    rows$expected_prior_missing <- as.character(as.integer(is.na(before[i])))
    rows$new_value <- after[i]
    rows$new_value_missing <- as.character(as.integer(is.na(after[i])))
    rows$evidence_ref <- paste0("study pull ", pull_sha)
    cand[[length(cand) + 1L]] <- rows
  }
  cand <- if (length(cand)) {
    do.call(rbind, cand)
  } else {
    as.data.frame(stats::setNames(rep(list(character()), length(tpl_cols)), tpl_cols),
                  check.names = FALSE)
  }
  # Encounters that agree on a shared cell gave identical rows: keep one. Two master
  # columns read from one source column could still clash: drop and count those.
  cell <- .composite_key(as.list(cand))
  cand <- cand[!duplicated(cell), , drop = FALSE]
  key_cols <- setdiff(tpl_cols, c("expected_prior", "expected_prior_missing", "new_value",
                                  "new_value_missing", "evidence_type", "evidence_ref",
                                  "asserted_by"))
  addr <- .composite_key(as.list(cand[key_cols]))
  clash <- addr %in% addr[duplicated(addr)]
  inconsistent <- inconsistent + length(unique(addr[clash]))
  cand <- cand[!clash, , drop = FALSE]
  utils::write.csv(cand, path, row.names = FALSE, na = "")
  utils::write.csv(derived, derived_path, row.names = FALSE)
  .hvti_inform("study_correction_candidates(): ", nrow(cand), " candidate correction(s), ",
               inconsistent, " inconsistent cell(s), ", sum(derived$n_cells),
               " derived-column difference(s) in ", nrow(derived), " column(s).")
  invisible(list(candidates = nrow(cand), inconsistent = inconsistent, derived = derived,
                 path = path, derived_path = derived_path))
}

#' One text per row from several key columns, without collisions
#'
#' Each part is written as its length in characters, a colon and the text, or as `N` when
#' it is missing, so a missing part never matches the text `"NA"` and no separator inside
#' a value can make two different rows read alike.
#'
#' @param parts List of character vectors of equal length.
#'
#' @return A character vector, one element per row.
#'
#' @keywords internal
#' @noRd
.composite_key <- function(parts) {
  enc <- lapply(parts, function(x) ifelse(is.na(x), "N", paste0(nchar(x), ":", x)))
  do.call(paste, c(enc, sep = "|"))
}
