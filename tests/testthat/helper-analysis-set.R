local_study <- function(sets = list(), env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  suppressMessages(invisible(hvtiRutilities::study_setup(
    root,
    study = "Test",
    study_tracker_id = 1L,
    adopt = TRUE
  )))
  n <- 20L
  d <- data.frame(
    ccfid   = seq_len(n),
    age     = c(10, 15, seq(40, by = 2, length.out = n - 2L)),
    aggrc   = c(NA, seq_len(n - 1L)),
    dead    = rep(c(0L, 1L), length.out = n),
    iv_dead = seq_len(n) / 2,
    junk    = 1
  )
  utils::write.csv(
    d,
    file.path(hvtiRutilities::study_dir("datasets", root), "built.csv"),
    row.names = FALSE
  )
  suppressMessages(invisible(hvtiRutilities::register_data(
    root,
    built = "built.csv",
    event = "dead",
    time = "iv_dead"
  )))
  if (length(sets)) {
    yml <- file.path(root, "_study.yml")
    y <- yaml::read_yaml(yml)
    y$analysis_sets <- sets
    yaml::write_yaml(y, yml)
  }
  hvtiRutilities::study_config(root)
}

eda_set <- function(...) {
  b <- list(
    id = "ccfid",
    vars = c("age", "aggrc", "dead", "iv_dead"),
    exclude = list(
      list(reason = "No aggrecan", when = "is.na(aggrc)"),
      list(reason = "Under 18", when = "age < 18")
    )
  )
  args <- list(...)
  # Top-level replacement, not utils::modifyList(): modifyList merges nested
  # lists and ignores unnamed elements, so a replacement `exclude` never took.
  # b[names(args)] <- args keeps an explicit NULL (eda_set(id = NULL)) as a
  # NULL-valued entry, which is what the "missing id" test needs.
  b[names(args)] <- args
  b
}
