# Synthetic publication fixtures. No PHI: identifiers and values are invented.
local_publication_dir <- function(env = parent.frame()) {
  withr::local_tempdir(.local_envir = env)
}

write_synthetic_draft <- function(dir, name = "draft.csv", n = 3L) {
  path <- file.path(dir, name)
  d <- data.frame(
    synthetic_id = sprintf("SYN%03d", seq_len(n)),
    value = seq_len(n),
    group = rep(c("A", "B"), length.out = n)
  )
  utils::write.csv(d, path, row.names = FALSE)
  path
}

local_catalog_fixture <- function(env = parent.frame()) {
  dir <- local_publication_dir(env)
  path <- file.path(dir, "dataset-catalog.yml")
  source <- testthat::test_path("fixtures", "dataset-catalog-v1.yml")
  stopifnot(file.copy(source, path))
  path
}

rewrite_catalog <- function(path, change) {
  catalog <- yaml::read_yaml(path)
  yaml::write_yaml(change(catalog), path)
  path
}
