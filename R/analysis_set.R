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

.set_paths <- function(name, cfg) {
  list(
    parquet  = file.path(cfg$root, "datasets", paste0(name, ".parquet")),
    sidecar  = file.path(cfg$root, "datasets", paste0(name, ".set.yml")),
    manifest = file.path(cfg$root, "manifest.yaml")
  )
}
