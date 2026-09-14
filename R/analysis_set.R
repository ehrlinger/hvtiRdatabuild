# Analysis sets: a declared, checkpointed selection of the built dataset.
# Design doc reference, not commented code
# nolint next: commented_code_linter
# Design: dev/specs/2026-09-14-analysis-sets-design.md.

.set_keys <- c("id", "vars", "exclude", "expect")
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
  if (identical(name, tools::file_path_sans_ext(cfg$built)))
    stop(where, " has the same name as the built dataset, and its parquet would ",
         "overwrite the built dataset's cache. Rename the set.", call. = FALSE)
  unknown <- setdiff(names(raw), .set_keys)
  if (length(unknown))
    stop(where, " has unknown key(s): ", paste(unknown, collapse = ", "),
         ". Allowed: ", paste(.set_keys, collapse = ", "), ".", call. = FALSE)
  if (!is.character(raw$id) || length(raw$id) != 1L || !nzchar(raw$id))
    stop(where, ": `id` must name one patient-identifier column.", call. = FALSE)
  vars <- unlist(raw$vars, use.names = FALSE)
  if (!is.character(vars) || !length(vars) || anyNA(vars))
    stop(where, ": `vars` must list at least one column.", call. = FALSE)
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
  bad <- setdiff(names(expect), .expect_keys)
  if (length(bad))
    stop(where, ": `expect` has unknown count(s): ", paste(bad, collapse = ", "),
         ". Allowed: ", paste(.expect_keys, collapse = ", "), ".", call. = FALSE)
  list(id = raw$id, vars = vars, exclude = rules, expect = expect)
}

# Re-serialized, so comments and layout in _study.yml do not change the hash
# while any change to id, vars, the rules or their order does.
.declaration_sha <- function(raw) {
  digest::digest(yaml::as.yaml(raw), algo = "sha256", serialize = FALSE)
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
  v <- tryCatch(eval(expr, list2env(as.list(d), parent = baseenv())),
                error = function(e) stop(where, ": ", conditionMessage(e), call. = FALSE))
  if (!is.logical(v) || length(v) != nrow(d))
    stop(where, " must give one TRUE/FALSE per row (", nrow(d), "); it gave ",
         length(v), " value(s) of type ", typeof(v), ".", call. = FALSE)
  # SAS `if <missing> then delete` does not delete.
  !is.na(v) & v
}

.apply_exclusions <- function(d, block, name) {
  rules <- block$exclude
  empty <- data.frame(rule = integer(), reason = character(), n_before = integer(),
                      n_excluded = integer(), n_after = integer())
  if (!length(rules)) return(list(keep = rep(TRUE, nrow(d)), attrition = empty))
  if (!requireNamespace("hvtiPlotR", quietly = TRUE))
    stop("analysis set `", name, "` declares exclusions, which need hvtiPlotR. ",
         "Install it with pak::pak(\"ehrlinger/hvtiPlotR\").", call. = FALSE)

  flag_cols <- paste0(".hv_rule_", seq_along(rules))
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

.set_paths <- function(name, cfg) {
  list(
    parquet  = file.path(cfg$root, "datasets", paste0(name, ".parquet")),
    sidecar  = file.path(cfg$root, "datasets", paste0(name, ".set.yml")),
    manifest = file.path(cfg$root, "manifest.yaml")
  )
}
