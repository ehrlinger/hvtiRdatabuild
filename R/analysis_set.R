# Analysis sets: a declared, checkpointed selection of the built dataset.
# Design doc reference, not commented code
# nolint next: commented_code_linter
# Design: dev/specs/2026-09-14-analysis-sets-design.md.

.set_keys <- c("id", "vars", "event", "exclude", "expect")
.expect_keys <- c("n", "n_events", "n_censored")

# The set's block exactly as yaml::read_yaml() returns it. The declaration hash
# is taken over this, before any normalization, so the hash describes what the
# author wrote rather than what this package made of it.
.set_raw <- function(name, cfg) {
  if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name))
    stop("`name` must be a single non-empty string.", call. = FALSE)
  sets <- yaml::read_yaml(cfg$file)$analysis_sets
  if (is.null(sets[[name]])) {
    declared <- if (length(sets)) paste(names(sets), collapse = ", ") else "none"
    stop("No analysis set `", name, "` in ", cfg$file, ". Declared: ", declared, ".",
         call. = FALSE)
  }
  sets[[name]]
}

.set_validate <- function(raw, name, cfg) {
  where <- paste0("analysis set `", name, "`")
  if (!grepl("^[a-z][a-z0-9_]*$", name))
    stop(where, ": a set name is lower-case letters, digits and underscores, ",
         "starting with a letter.", call. = FALSE)
  additional <- vapply(
    cfg$additional_datasets %||% list(),
    function(dataset) dataset$built,
    character(1)
  )
  registered <- tools::file_path_sans_ext(c(cfg$built, additional))
  if (name %in% registered)
    stop(where, " has the same name as a registered dataset, and its parquet ",
         "would overwrite that dataset or its cache. Rename the set.",
         call. = FALSE)
  unknown <- setdiff(names(raw), .set_keys)
  if (length(unknown))
    stop(where, " has unknown key(s): ", paste(unknown, collapse = ", "),
         ". Allowed: ", paste(.set_keys, collapse = ", "), ".", call. = FALSE)
  if (!is.character(raw$id) || length(raw$id) != 1L || !nzchar(raw$id))
    stop(where, ": `id` must name one patient-identifier column.", call. = FALSE)
  vars <- unlist(raw$vars, use.names = FALSE)
  if (!is.character(vars) || !length(vars) || anyNA(vars))
    stop(where, ": `vars` must list at least one column.", call. = FALSE)
  if (anyDuplicated(vars))
    stop(where, ": duplicate variable `", vars[anyDuplicated(vars)], "` in `vars`.",
         call. = FALSE)
  event <- raw$event
  if (!is.null(event)) {
    if (!is.character(event) || length(event) != 1L || is.na(event) || !nzchar(event))
      stop(where, ": `event` must name one column.", call. = FALSE)
    if (!event %in% vars)
      stop(where, ": the event column `", event, "` is not in `vars`.", call. = FALSE)
  }
  rules <- raw$exclude %||% list()
  for (k in seq_along(rules)) {
    r <- rules[[k]]
    for (f in c("reason", "when")) {
      val <- r[[f]]
      if (is.null(val) || !is.character(val) || length(val) != 1L) {
        stop(where, ", rule ", k, ": `", f, "` must be a single string.",
             call. = FALSE)
      }
      if (is.na(val) || !nzchar(val)) {
        stop(where, ", rule ", k, ": `", f, "` must be a single string.",
             call. = FALSE)
      }
    }
  }
  reasons <- vapply(rules, function(r) r$reason, character(1))
  if (anyDuplicated(reasons))
    stop(where, ": duplicate reason `", reasons[anyDuplicated(reasons)], "`. Each ",
         "rule needs its own reason, because attrition is counted by reason.",
         call. = FALSE)
  expect <- raw$expect %||% list()
  valid_names <- !length(expect) || (!is.null(names(expect)) && all(nzchar(names(expect))) &&
                                       !anyDuplicated(names(expect)))
  if (!is.list(expect) || !valid_names) {
    stop(where, ": `expect` must be a named list of counts.", call. = FALSE)
  }
  bad <- setdiff(names(expect), .expect_keys)
  if (length(bad))
    stop(where, ": `expect` has unknown count(s): ", paste(bad, collapse = ", "),
         ". Allowed: ", paste(.expect_keys, collapse = ", "), ".", call. = FALSE)
  for (k in names(expect)) {
    value <- expect[[k]]
    if (!is.numeric(value) || length(value) != 1L)
      stop(where, ": `expect: ", k, "` must be a single non-negative whole number.",
           call. = FALSE)
    if (is.na(value) || !is.finite(value) || value < 0 || value != floor(value))
      stop(where, ": `expect: ", k, "` must be a non-negative whole number.",
           call. = FALSE)
  }
  needs_event <- intersect(names(expect), c("n_events", "n_censored"))
  if (length(needs_event) && is.null(event))
    stop(where, ": `expect: ", needs_event[1L], "` needs an `event` column. ",
         "Name it with `event:` in the set.", call. = FALSE)
  list(id = raw$id, vars = vars, event = event, exclude = rules, expect = expect)
}

# Re-serialized, so comments and layout in _study.yml do not change the hash
# while any change to id, vars, the rules or their order does.
.canonical_mapping <- function(x) {
  if (!is.list(x)) return(x)
  if (!is.null(names(x))) x <- x[order(names(x))]
  lapply(x, .canonical_mapping)
}

.declaration_sha <- function(raw) {
  canonical <- .canonical_mapping(raw)
  digest::digest(yaml::as.yaml(canonical), algo = "sha256", serialize = FALSE)
}

# Evaluate one rule with the data as its environment and base R as the parent,
# so a predicate sees the columns and base functions and nothing else. A
# predicate naming a global variable is an error here rather than a silent
# lookup, which is why rules are not handed to hv_consort_exclude() as-is: its
# data mask encloses the search path.
.eval_rule <- function(d, rule, name, k) {
  where <- paste0("analysis set `", name, "`, rule ", k, " (`", rule$when, "`)")
  expr <- tryCatch(str2lang(rule$when), error = function(e) {
    stop(where, ": `when` does not parse: ", conditionMessage(e), call. = FALSE)
  })
  v <- tryCatch(
    eval(expr, list2env(as.list(d), parent = baseenv())),
    error = function(e) {
      stop(where, ": evaluation failed; details are suppressed because they may ",
           "contain row-level data.", call. = FALSE)
    }
  )
  if (!is.logical(v) || length(v) != nrow(d))
    stop(where, " must give one TRUE/FALSE per row (", nrow(d), "); it gave ",
         length(v), " value(s) of type ", typeof(v), ".", call. = FALSE)
  # SAS `if <missing> then delete` does not delete.
  !is.na(v) & v
}

.apply_exclusions <- function(d, block, name) {
  rules <- block$exclude
  if (!length(rules)) {
    return(list(keep = rep(TRUE, nrow(d)), attrition = .empty_attrition()))
  }
  if (!requireNamespace("hvtiPlotR", quietly = TRUE))
    stop("analysis set `", name, "` declares exclusions, which need hvtiPlotR. ",
         "Install it with pak::pak(\"ehrlinger/hvtiPlotR\").", call. = FALSE)

  flag_cols <- paste0(".hv_rule_", seq_along(rules))
  scratch_cols <- c(flag_cols, ".hv_start", ".hv_reason", ".hv_keep")
  collisions <- intersect(scratch_cols, names(d))
  if (length(collisions)) {
    stop("analysis set `", name, "`: reserved scratch column(s) already exist: ",
         paste(collisions, collapse = ", "), ".", call. = FALSE)
  }
  work <- d
  for (k in seq_along(rules)) work[[flag_cols[k]]] <- .eval_rule(d, rules[[k]], name, k)

  tracker <- do.call(hvtiPlotR::hv_consort_start,
                     list(work, as.name(block$id), pass_col = ".hv_start"))
  formulas <- lapply(seq_along(rules), function(k) {
    eval(call("~", as.name(flag_cols[k]), rules[[k]]$reason), baseenv())
  })
  tracker <- do.call(hvtiPlotR::hv_consort_exclude,
                     c(list(tracker, label = "Analysis set", col = ".hv_reason",
                            pass_col = ".hv_keep"), formulas))

  reason <- tracker$data$.hv_reason
  # Per-rule counts are tabulated here because hv_consort_summary() counts per
  # stage, not per reason (hvtiPlotR#129). Remove this when #129 ships.
  n_excl <- vapply(rules, function(r) sum(reason == r$reason, na.rm = TRUE), integer(1))
  n_after <- nrow(d) - cumsum(n_excl)
  list(
    keep = tracker$data$.hv_keep,
    attrition = data.frame(
      rule = seq_along(rules),
      reason = vapply(rules, function(r) r$reason, character(1)),
      n_before = as.integer(c(nrow(d), utils::head(n_after, -1L))),
      n_excluded = as.integer(n_excl),
      n_after = as.integer(n_after)
    )
  )
}

.empty_attrition <- function() {
  data.frame(
    rule = integer(), reason = character(), n_before = integer(),
    n_excluded = integer(), n_after = integer()
  )
}

.set_paths <- function(name, cfg) {
  datasets <- hvtiRutilities::study_dir("datasets", cfg$root)
  list(
    parquet  = file.path(datasets, paste0(name, ".parquet")),
    sidecar  = file.path(datasets, paste0(name, ".set.yml")),
    manifest = file.path(cfg$root, "manifest.yaml")
  )
}

# Write to a temporary name in the destination directory, then rename: a rename
# within one filesystem is atomic where a half-written file is not.
.atomic_write <- function(target, write_fn) {
  tmp <- tempfile(tmpdir = dirname(target), fileext = ".tmp")
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  write_fn(tmp)
  if (!file.rename(tmp, target)) stop("Could not write ", target, call. = FALSE)
  invisible(target)
}

# The built dataset's identity: its sha256 as the manifest records it (kept
# current by read_built()'s cache, so it is never re-hashed here), plus a stat,
# which catches a rewrite that no read_built() call has recorded yet.
.built_state <- function(cfg) {
  m <- yaml::read_yaml(file.path(cfg$root, "manifest.yaml"))
  e <- Filter(function(x) identical(x$file, cfg$built), m$datasets)
  if (!length(e) || is.null(e[[1L]]$sha256))
    stop("manifest.yaml has no sha256 for ", cfg$built, ". Run ",
         "hvtiRutilities::register_data() or read_built() first.",
         call. = FALSE)
  p <- hvtiRutilities::built_path(cfg)
  info <- file.info(p)
  list(file = cfg$built, sha256 = e[[1L]]$sha256,
       size = if (file.exists(p)) format(info$size, scientific = FALSE) else NA_character_,
       mtime = if (file.exists(p)) {
         format(info$mtime, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
       } else {
         NA_character_
       })
}

.same_built_state <- function(a, b) {
  fields <- c("file", "sha256", "size", "mtime")
  all(vapply(fields, function(field) {
    identical(as.character(a[[field]]), as.character(b[[field]]))
  }, logical(1)))
}

#' Write an analysis set
#'
#' @description
#' Cuts the analysis set `name`, declared under `analysis_sets:` in the study's
#' `_study.yml`, from the built dataset: keeps its `vars`, applies its `exclude`
#' rules in order (first match wins), checks any `expect` counts, and writes
#' `<name>.parquet` and a `<name>.set.yml` sidecar in the study's logical
#' datasets directory, plus a `manifest.yaml` entry. The sidecar records the
#' parent dataset and the attrition.
#'
#' @details
#' Nothing is written unless every check passes. Each `when` is R code evaluated
#' against the data with only base R visible; a missing value counts as not
#' excluded, as SAS `if <missing> then delete` does. The identifier column named
#' by `id` is used to track exclusions and is never written to the sidecar or
#' the manifest. A set that names an `event` column, one of its `vars`, also
#' counts `n_events` (rows where it equals 1) and `n_censored`; an `expect` on
#' either count needs that `event` key.
#'
#' @param name Character(1). The set's name in `_study.yml`.
#' @param cfg List. A study manifest from [hvtiRutilities::study_config()].
#'
#' @return The sidecar contents, invisibly: a list with `set`, `parent`,
#'   `declaration_sha256`, `written`, `counts`, `n_cols`, `attrition` and
#'   `packages`.
#'
#' @export
write_analysis_set <- function(name, cfg = hvtiRutilities::study_config()) {
  if (!requireNamespace("arrow", quietly = TRUE))
    stop("write_analysis_set() needs arrow. Install it with ",
         "install.packages(\"arrow\").", call. = FALSE)
  raw <- .set_raw(name, cfg)
  b <- .set_validate(raw, name, cfg)
  parent_before <- .built_state(cfg)
  d <- hvtiRutilities::read_built(cfg)
  parent_after <- .built_state(cfg)
  if (!.same_built_state(parent_before, parent_after)) {
    stop("analysis set `", name, "`: the built dataset changed while it was being read. ",
         "Nothing was written; run write_analysis_set(\"", name, "\") again.",
         call. = FALSE)
  }

  absent <- setdiff(c(b$id, b$vars), names(d))
  if (length(absent))
    stop("analysis set `", name, "` names column(s) not in the built dataset: ",
         paste(absent, collapse = ", "), ".", call. = FALSE)
  if (anyDuplicated(d[[b$id]]))
    stop("analysis set `", name, "`: `", b$id, "` is not unique in the built ",
         "dataset, so it cannot identify patients.", call. = FALSE)

  ex <- .apply_exclusions(d, b, name)
  out <- d[ex$keep, b$vars, drop = FALSE]
  rownames(out) <- NULL

  counts <- list(n = nrow(out))
  if (!is.null(b$event)) {
    counts$n_events <- as.integer(sum(out[[b$event]] == 1, na.rm = TRUE))
    counts$n_censored <- counts$n - counts$n_events
  }
  for (k in names(b$expect)) {
    if (!isTRUE(counts[[k]] == b$expect[[k]]))
      stop("analysis set `", name, "`: expected ", k, " = ", b$expect[[k]], ", got ",
           counts[[k]], ". Nothing was written.", call. = FALSE)
  }

  p <- .set_paths(name, cfg)
  # One YAML entry per rule, not the attrition data frame itself:
  # yaml::write_yaml() writes a data frame column-wise, which would scramble
  # rule/reason/count alignment. An empty attrition writes `attrition: []`.
  attrition <- unname(lapply(seq_len(nrow(ex$attrition)), function(i) as.list(ex$attrition[i, ])))
  side <- list(
    set = name,
    parent = parent_after,
    declaration_sha256 = .declaration_sha(raw),
    written = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    counts = counts,
    n_cols = ncol(out),
    attrition = attrition,
    packages = list(
      hvtiRdatabuild = as.character(utils::packageVersion("hvtiRdatabuild")),
      hvtiRutilities = as.character(utils::packageVersion("hvtiRutilities")),
      arrow = as.character(utils::packageVersion("arrow"))
    )
  )
  .atomic_write(p$parquet, function(tmp) arrow::write_parquet(out, tmp))
  .atomic_write(p$sidecar, function(tmp) yaml::write_yaml(side, tmp))
  hvtiRutilities::update_manifest(
    file = p$parquet, manifest_path = p$manifest, n_rows = nrow(out),
    n_cols = ncol(out), source = paste0("analysis set ", name, " of ", cfg$built)
  )
  invisible(side)
}

#' Read an analysis set
#'
#' @description
#' Reads the analysis set `name` written by [write_analysis_set()], after
#' checking that it is current. It stops, naming the `write_analysis_set()` call
#' that fixes it, when the built dataset has changed since the set was written,
#' when the set's declaration in `_study.yml` has changed, or when the parquet no
#' longer matches its manifest entry. A stale set is never rebuilt silently:
#' its exclusions are decisions, and a changed attrition should be looked at.
#'
#' @param name Character(1). The set's name in `_study.yml`.
#' @param cfg List. A study manifest from [hvtiRutilities::study_config()].
#'
#' @return A data frame of the set's columns and rows, with the per-rule
#'   attrition table attached as `attr(x, "attrition")`.
#'
#' @seealso [write_analysis_set()]
#' @export
read_analysis_set <- function(name, cfg = hvtiRutilities::study_config()) {
  if (!requireNamespace("arrow", quietly = TRUE))
    stop("read_analysis_set() needs arrow. Install it with ",
         "install.packages(\"arrow\").", call. = FALSE)
  raw <- .set_raw(name, cfg)
  p <- .set_paths(name, cfg)
  fix <- paste0('Run write_analysis_set("', name, '").')
  if (!file.exists(p$parquet) || !file.exists(p$sidecar))
    stop("analysis set `", name, "` has not been written. ", fix, call. = FALSE)
  side <- yaml::read_yaml(p$sidecar)

  now <- .built_state(cfg)
  same <- function(a, b) identical(as.character(a), as.character(b))
  if (!same(side$parent$sha256, now$sha256) ||
        !same(side$parent$size, now$size) ||
        !same(side$parent$mtime, now$mtime)) {
    stop("analysis set `", name, "`: the built dataset has changed since the set ",
         "was written. ", fix, call. = FALSE)
  }
  if (!same(side$declaration_sha256, .declaration_sha(raw))) {
    stop("analysis set `", name, "`: its declaration in _study.yml has changed ",
         "since the set was written. ", fix, call. = FALSE)
  }
  m <- yaml::read_yaml(p$manifest)
  e <- Filter(function(x) identical(x$file, basename(p$parquet)), m$datasets)
  actual_sha <- digest::digest(p$parquet, algo = "sha256", file = TRUE)
  if (!length(e) || !same(e[[1L]]$sha256, actual_sha)) {
    stop("analysis set `", name, "`: ", basename(p$parquet), " does not match its ",
         "manifest entry. ", fix, call. = FALSE)
  }

  d <- as.data.frame(arrow::read_parquet(p$parquet))
  attrition <- if (length(side$attrition)) {
    do.call(rbind, lapply(side$attrition, as.data.frame))
  } else {
    .empty_attrition()
  }
  attr(d, "attrition") <- attrition
  d
}
