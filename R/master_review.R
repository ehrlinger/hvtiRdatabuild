# master_review.R
#
# Chart review of a master pull: the units and criteria that need a person, and the
# decisions file that settles them. Spec: dev/specs/2026-11-16-cohort-criteria-addendum.md
# §3.5.

#' List what a pull needs decided at chart review
#'
#' Every unit a criterion routed to review (`undetermined = "review"`), and every unit
#' still in the cohort for each [review_criterion()]. The list holds unit identifiers. Keep
#' it with the study's other restricted files, and never print it to a shared log.
#'
#' @param pull A `master_pull` from [pull_master()].
#'
#' @return A data frame with `cohort_unit` and `criterion_id`.
#'
#' @seealso [apply_review()]
#'
#' @inherit apply_review examples
#'
#' @export
review_list <- function(pull) {
  if (!inherits(pull, "master_pull")) {
    .abort("review", "review_list(): `pull` must be a master_pull from pull_master().")
  }
  rv <- pull$review
  if (is.null(rv)) {
    return(data.frame(cohort_unit = character(), criterion_id = character(),
                      stringsAsFactors = FALSE))
  }
  review_ids <- rv$criteria$criterion_id[rv$criteria$kind == "review"]
  active <- .active_units(pull$cohort)
  rbind(
    rv$queue,
    data.frame(cohort_unit = rep(active, times = length(review_ids)),
               criterion_id = rep(review_ids, each = length(active)),
               stringsAsFactors = FALSE)
  )
}

#' Record chart-review decisions on a pull
#'
#' Reads a decisions file with one row per entry of [review_list()]: `cohort_unit`,
#' `criterion_id`, `outcome` (`"met"` or `"not_met"`) and `reason_code`. An outcome that
#' excludes the unit (not met on an include criterion, or met on an exclude criterion)
#' needs a code from `reason_codes`. Codes, never free text: chart notes are PHI.
#'
#' A routed unit is settled at the criterion that routed it, so the stage counts stay
#' sequential: if review excludes it, the exclusion is recorded at that criterion and no
#' later stage counts the unit, whether or not a later criterion also excluded it; if
#' review keeps it, every later outcome stands. The criterion's provenance records how
#' many were excluded at review and the decisions file's checksum. Each review criterion
#' is then its own stage, with source `review`. The file's SHA-256 is recorded in the
#' pull's metadata, and the pull is then complete.
#'
#' Each later criterion's tally of met, not met and undetermined units is rebuilt from
#' the units that reached it, using the outcomes [pull_master()] keeps in
#' `review$outcomes`. A pull saved before that field existed has none, so decisions that
#' would change a counted stage are refused with an error of class
#' `hvtiRdatabuild_review_outcomes_missing`: pull again with [pull_master()] and apply
#' the decisions to the new pull. Decisions that change no counted stage are applied as
#' usual.
#'
#' @param pull A `master_pull` awaiting review.
#' @param path Character. The decisions file, as CSV.
#' @param reason_codes Character. The study's declared reason codes.
#'
#' @return The `master_pull`, with the review stages appended and `data` filtered.
#'
#' @seealso [review_list()], [review_criterion()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   # Synthetic data; no PHI.
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   DBI::dbWriteTable(con, "master_demo", data.frame(
#'     mrn = c("SYN101", "SYN102"),
#'     encounter_date = as.Date(c("2010-03-01", "2012-07-15")),
#'     proc = c("CABG", "CABG"), age = c(62, 70)
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
#'   strategy <- review_criterion("strategy", "Planned alternative support", role = "exclude")
#'   q <- cohort_query("proc = 'CABG'", as.Date(c("2000-01-01", "2024-07-31")),
#'                     criteria = list(strategy), index_on = "qualifying")
#'   pull <- pull_master(con, "master_demo", q, var_cols = "age", path = config,
#'                       dialect = "duckdb")
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#'
#'   # One decision per row of the review list, with a declared code for each exclusion.
#'   decisions <- review_list(pull)
#'   decisions$outcome <- c("not_met", "met")
#'   decisions$reason_code <- c(NA, "PLANNED")
#'   f <- tempfile(fileext = ".csv")
#'   utils::write.csv(decisions, f, row.names = FALSE, na = "")
#'   reviewed <- apply_review(pull, f, reason_codes = "PLANNED")
#'   reviewed$meta$status
#' }
#' }
#'
#' @export
apply_review <- function(pull, path, reason_codes) {
  if (!inherits(pull, "master_pull")) {
    .abort("review", "apply_review(): `pull` must be a master_pull from pull_master().")
  }
  if (!identical(.pull_meta(pull)$status, "awaiting review")) {
    .abort("review", "apply_review(): this pull is not awaiting review.")
  }
  if (!.one_string(path) || !file.exists(path)) {
    .abort("review", "apply_review(): `path` must be an existing decisions file.")
  }
  if (!is.character(reason_codes) || !length(reason_codes) || anyNA(reason_codes)) {
    .abort("review", "apply_review(): `reason_codes` must name the study's codes.")
  }
  # Read once, then hash and parse those bytes: the checksum certifies what was applied.
  bytes <- .read_file_bytes(path)
  sha <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
  dec <- utils::read.csv(text = rawToChar(bytes), colClasses = "character",
                         na.strings = "")
  if (!all(c("cohort_unit", "criterion_id", "outcome", "reason_code") %in% names(dec))) {
    .abort("review", "apply_review(): the decisions file needs cohort_unit, ",
           "criterion_id, outcome and reason_code.")
  }
  wanted <- review_list(pull)
  key <- paste(dec$cohort_unit, dec$criterion_id, sep = "\r")
  want_key <- paste(wanted$cohort_unit, wanted$criterion_id, sep = "\r")
  if (anyDuplicated(key)) {
    .abort("review", "apply_review(): ", sum(duplicated(key)), " duplicate decision(s).")
  }
  if (!setequal(key, want_key)) {
    .abort("review", "apply_review(): ", length(setdiff(want_key, key)),
           " decision(s) missing and ", length(setdiff(key, want_key)),
           " not asked for.")
  }
  if (any(!dec$outcome %in% c("met", "not_met"))) {
    .abort("review", "apply_review(): every outcome must be \"met\" or \"not_met\".")
  }
  crit <- pull$review$criteria
  role <- crit$role[match(dec$criterion_id, crit$criterion_id)]
  excludes <- (role == "include" & dec$outcome == "not_met") |
    (role == "exclude" & dec$outcome == "met")
  if (any(excludes & is.na(dec$reason_code))) {
    .abort("review", "apply_review(): ", sum(excludes & is.na(dec$reason_code)),
           " decision(s) exclude a unit without a code; an exclusion needs a reason code.")
  }
  if (any(!is.na(dec$reason_code) & !dec$reason_code %in% reason_codes)) {
    .abort("review", "apply_review(): ",
           sum(!is.na(dec$reason_code) & !dec$reason_code %in% reason_codes),
           " decision(s) use a reason code not in `reason_codes`.")
  }
  label <- crit$label[match(dec$criterion_id, crit$criterion_id)]
  dec$reason <- rep(NA_character_, nrow(dec))
  dec$reason[excludes] <- paste0(label[excludes], " at review: ",
                                 dec$reason_code[excludes])
  review_stage <- function(record, id, stage_label, rows) {
    active <- .active_units(record)
    hit <- rows[rows$cohort_unit %in% active & !is.na(rows$reason), , drop = FALSE]
    hit <- hit[!duplicated(hit$cohort_unit), , drop = FALSE]
    out <- !active %in% hit$cohort_unit
    reason <- rep(NA_character_, length(active))
    reason[!out] <- hit$reason[match(active[!out], hit$cohort_unit)]
    append_cohort_stage(
      record,
      data.frame(stage_id = id, order = max(record$stages$order) + 1L,
                 label = stage_label, source = "review",
                 provenance = sprintf("decisions file sha256 %s; %d decided", sha,
                                      nrow(rows)),
                 stringsAsFactors = FALSE),
      data.frame(patient_id = active, included = out, reason = reason,
                 stringsAsFactors = FALSE)
    )
  }
  record <- pull$cohort
  routed <- dec[dec$criterion_id %in% pull$review$queue$criterion_id &
                  key %in% paste(pull$review$queue$cohort_unit,
                                 pull$review$queue$criterion_id, sep = "\r"), ]
  counted <- crit$criterion_id[crit$kind %in% c("warehouse", "local")]
  record <- .settle_routed(record, routed, sha, pull$review$outcomes, counted)
  for (i in which(crit$kind == "review")) {
    rows <- dec[dec$criterion_id == crit$criterion_id[[i]], , drop = FALSE]
    record <- review_stage(record, crit$criterion_id[[i]], crit$label[[i]], rows)
  }
  # With index_on = "eligible", the first eligible encounter is chosen only now, once
  # review has ruled on every candidate.
  definition <- .pull_meta(pull)$cohort_definition
  if (is.list(definition) && identical(definition$index_on, "eligible")) {
    record <- .index_eligible_stage(record)
  }
  pull$cohort <- record
  pull$data <- pull$data[pull$data$cohort_unit %in% .active_units(record), , drop = FALSE]
  row.names(pull$data) <- NULL
  for (el in c("meta", "provenance")) {
    if (!is.null(pull[[el]])) {
      pull[[el]]$status <- "complete"
      pull[[el]]$review_decisions_sha256 <- sha
    }
  }
  pull
}

# Settle each unit routed to review at the criterion that routed it. If review excludes
# it, that criterion removed it first: the exclusion is recorded there and its rows at
# later stages go. If review keeps it, every later outcome stands.
.settle_routed <- function(record, routed, sha, outcomes, counted) {
  hit <- routed[!is.na(routed$reason), , drop = FALSE]
  if (!nrow(hit)) return(record)
  stages <- record$stages
  hit$order <- stages$order[match(hit$criterion_id, stages$stage_id)]
  hit <- hit[order(hit$order), , drop = FALSE]
  hit <- hit[!duplicated(hit$cohort_unit), , drop = FALSE]
  m <- record$members
  at <- hit$order[match(m$patient_id, hit$cohort_unit)]
  stage_order <- stages$order[match(m$stage_id, stages$stage_id)]
  here <- !is.na(at) & stage_order == at
  m$included[here] <- FALSE
  m$reason[here] <- hit$reason[match(m$patient_id[here], hit$cohort_unit)]
  dropped <- !is.na(at) & stage_order > at
  # A pull made before per-criterion outcomes were kept cannot recount its stages.
  if (is.null(outcomes) && any(m$stage_id[dropped] %in% counted)) {
    .abort("review_outcomes_missing",
           "apply_review(): this pull predates the per-criterion outcomes needed to ",
           "recount the criteria stages these decisions change. Pull again with ",
           "pull_master() and apply the decisions to the new pull.")
  }
  m <- m[!dropped, , drop = FALSE]
  stages <- .recount_stages(stages, m, outcomes)
  n <- table(hit$criterion_id)
  i <- match(names(n), stages$stage_id)
  stages$provenance[i] <- sprintf("%s; %d excluded at chart review, decisions file sha256 %s",
                                  stages$provenance[i], as.integer(n), sha)
  new_cohort_record(m, stages[order(stages$order), , drop = FALSE],
                    patient_id_col = record$patient_id_col)
}

# Rebuild a criterion's tally from the units that reached it once review has settled
# them. Where that differs from what was evaluated at the pull (in the warehouse, or in
# R for a local criterion), those figures are kept beside it, labelled.
.recount_stages <- function(stages, members, outcomes) {
  if (is.null(outcomes) || !nrow(outcomes)) return(stages)
  pattern <- "^(.*)met [0-9]+, not met [0-9]+, undetermined [0-9]+"
  for (i in which(stages$stage_id %in% outcomes$criterion_id)) {
    id <- stages$stage_id[[i]]
    rows <- outcomes[outcomes$criterion_id == id, , drop = FALSE]
    entrants <- members$patient_id[members$stage_id == id]
    now <- .count_text(rows$outcome[rows$cohort_unit %in% entrants])
    before <- .count_text(rows$outcome)
    if (identical(now, before) || !grepl(pattern, stages$provenance[[i]])) next
    where <- if (identical(stages$source[[i]], "build")) "in R" else "in the warehouse"
    stages$provenance[[i]] <- paste0(
      sub(pattern, paste0("\\1", now), stages$provenance[[i]]),
      "; as evaluated ", where, " before review: ", before
    )
  }
  stages
}

# Every byte of a file, as raw. A seam, so a test can change the file mid-read.
.read_file_bytes <- function(path) readBin(path, "raw", file.size(path))
