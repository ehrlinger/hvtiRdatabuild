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
#' @param pull A `master_pull` awaiting review.
#' @param path Character. The decisions file, as CSV.
#' @param reason_codes Character. The study's declared reason codes.
#'
#' @return The `master_pull`, with the review stages appended and `data` filtered.
#'
#' @seealso [review_list()], [review_criterion()]
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
  record <- .settle_routed(record, routed, sha)
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
.settle_routed <- function(record, routed, sha) {
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
  m <- m[is.na(at) | stage_order <= at, , drop = FALSE]
  n <- table(hit$criterion_id)
  i <- match(names(n), stages$stage_id)
  stages$provenance[i] <- sprintf("%s; %d excluded at chart review, decisions file sha256 %s",
                                  stages$provenance[i], as.integer(n), sha)
  new_cohort_record(m, stages[order(stages$order), , drop = FALSE],
                    patient_id_col = record$patient_id_col)
}

# Every byte of a file, as raw. A seam, so a test can change the file mid-read.
.read_file_bytes <- function(path) readBin(path, "raw", file.size(path))
