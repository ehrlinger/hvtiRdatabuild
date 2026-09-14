# Analysis sets Implementation Plan (hvtiRdatabuild)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `write_analysis_set()` and `read_analysis_set()` as specified in
`dev/specs/2026-09-14-analysis-sets-design.md`.

**Architecture:** One new source file, `R/analysis_set.R`, holding two exports and
small internal helpers: declaration reading and validation, exclusion evaluation,
parent-state capture, atomic write. Exclusions are evaluated here in a restricted
environment and handed to `hvtiPlotR::hv_consort_exclude()` as precomputed logical
columns, because `hv_consort_exclude()` evaluates formula left-hand sides with
`rlang::eval_tidy()` in a data mask whose enclosure reaches the search path, so a
predicate naming a global variable would silently succeed there. Precomputing keeps
the spec's "no global environment" rule and still uses the tracker.

**Tech Stack:** R, yaml, digest (Imports); arrow, hvtiPlotR, withr (Suggests); testthat 3e.

## Global Constraints

- Spec: `dev/specs/2026-09-14-analysis-sets-design.md`. Select-only; no derived variables.
- Declared under `analysis_sets:` in `_study.yml`; keys `id`, `vars` (required), `exclude`, `expect` (optional). Any other key is an error.
- Exclusions: `str2lang()`, evaluated with the data as environment and `baseenv()` as parent. `NA` means not excluded. First match wins.
- Files: `datasets/<name>.parquet`, `datasets/<name>.set.yml`, and a `manifest.yaml` entry via `hvtiRutilities::update_manifest()`.
- No identifier value is ever written to the sidecar or the manifest.
- No change to hvtiRutilities; no `:::` calls into it.
- Imports unchanged. `hvtiPlotR` added to Suggests (and `Remotes: ehrlinger/hvtiPlotR`); `arrow` already there.
- No chatty output in function bodies (CRAN cookbook): the attrition table is returned, not printed.
- Roxygen markdown is on. Line length 100 (`.lintr`).
- Branch: rename `spec/analysis-sets` to `feat/analysis-sets`; PR; no `Version:` bump in the PR; NEWS entry under `# hvtiRdatabuild (unreleased)`, added if absent.

**One deliberate addition to the spec, applied in Task 4:** the parent check also
compares `built`'s size and mtime (a stat, not a read) with values recorded in the
sidecar. The manifest's `sha256` for `built` is refreshed only when something calls
`read_built()`; a `built` rewritten since then would otherwise pass the parent check.

---

### Task 0: Branch and plan

- [ ] `cd ~/Documents/GitHub/hvtiRdatabuild-analysis-sets && git branch -m feat/analysis-sets`
- [ ] Commit this file: `git add dev/specs/2026-09-14-analysis-sets-plan.md && git commit -m "docs: plan analysis sets"`

### Task 1: Declaration reading, validation and hash

**Files:**
- Create: `R/analysis_set.R`
- Create: `tests/testthat/helper-analysis-set.R`
- Test: `tests/testthat/test-analysis_set.R`

**Interfaces:**
- Produces (internal): `.set_raw(name, cfg)` returning the block exactly as `yaml::read_yaml()` gave it; `.set_validate(raw, name, cfg)` returning a normalized list `id` (chr1), `vars` (chr), `exclude` (list of `list(reason, when)`), `expect` (named list, possibly empty); `.declaration_sha(raw)` returning a 64-hex string; `.set_paths(name, cfg)` returning `list(parquet, sidecar, manifest)`.
- Produces (test helper): `local_study(sets, env = parent.frame())` returning a `study_config()` list for a temporary study with a 20-row CSV `built` (columns `ccfid, age, aggrc, dead, iv_dead, junk`).

- [ ] **Step 1: Test helper**

```r
# tests/testthat/helper-analysis-set.R
local_study <- function(sets = list(), env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(root, "datasets"))
  n <- 20L
  d <- data.frame(
    ccfid   = seq_len(n),
    age     = c(10, 15, seq(40, by = 2, length.out = n - 2L)),
    aggrc   = c(NA, seq_len(n - 1L)),
    dead    = rep(c(0L, 1L), length.out = n),
    iv_dead = seq_len(n) / 2,
    junk    = 1
  )
  utils::write.csv(d, file.path(root, "datasets", "built.csv"), row.names = FALSE)
  suppressMessages(invisible(hvtiRutilities::study_init(
    root, study = "Test", built = "built.csv", event = "dead", time = "iv_dead"
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
```

- [ ] **Step 2: Failing tests**

```r
test_that("an unknown set name lists the declared ones", {
  cfg <- local_study(list(eda = eda_set()))
  expect_error(.set_raw("nope", cfg), "No analysis set `nope`.*Declared: eda")
})

test_that("a study with no analysis_sets says so", {
  cfg <- local_study()
  expect_error(.set_raw("eda", cfg), "Declared: none")
})

test_that("validation rejects unknown keys, missing id/vars, bad rules", {
  cfg <- local_study(list(eda = eda_set()))
  v <- function(b) .set_validate(b, "eda", cfg)
  expect_error(v(eda_set(derive = "x")), "unknown key.*derive")
  expect_error(v(eda_set(id = NULL)), "`id`")
  expect_error(v(eda_set(vars = NULL)), "`vars`")
  expect_error(v(eda_set(exclude = list(list(reason = "x")))), "rule 1.*`when`")
  expect_error(v(eda_set(exclude = list(list(reason = "a", when = "age > 1"),
                                        list(reason = "a", when = "age > 2")))),
               "duplicate reason")
  expect_error(v(eda_set(expect = list(rows = 3))), "`expect`.*rows")
})

test_that("a set may not be named like the built dataset", {
  cfg <- local_study(list(built = eda_set()))
  expect_error(.set_validate(.set_raw("built", cfg), "built", cfg), "same name")
})

test_that("validation normalizes vars to a character vector", {
  cfg <- local_study(list(eda = eda_set()))
  b <- .set_validate(.set_raw("eda", cfg), "eda", cfg)
  expect_type(b$vars, "character")
  expect_equal(b$expect, list())
})

test_that("the declaration hash ignores formatting and tracks content", {
  a <- eda_set()
  expect_identical(.declaration_sha(a), .declaration_sha(eda_set()))
  b <- eda_set(exclude = rev(eda_set()$exclude))
  expect_false(identical(.declaration_sha(a), .declaration_sha(b)))
  expect_match(.declaration_sha(a), "^[0-9a-f]{64}$")
})
```

- [ ] **Step 3: Run** `Rscript -e 'devtools::test(filter = "analysis_set")'`. Expected: FAIL, `could not find function ".set_raw"`.

- [ ] **Step 4: Implement** the start of `R/analysis_set.R`:

```r
# Analysis sets: a declared, checkpointed selection of the built dataset.
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
      if (!is.character(r[[f]]) || length(r[[f]]) != 1L || !nzchar(r[[f]]))
        stop(where, ", rule ", k, ": `", f, "` must be a single string.", call. = FALSE)
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

`%||%` <- function(x, y) if (is.null(x)) y else x
```

  Before adding `%||%`, run `grep -rn "%||%" R/`: `R/study_config.R` already defines one (its roxygen names a "Null-coalescing helper"). If it exists, do NOT redefine it; delete the last line above.

- [ ] **Step 5: Run** the focused tests. Expected: PASS.
- [ ] **Step 6: Commit** `feat: read and validate analysis-set declarations`

### Task 2: Exclusions

**Files:** Modify `R/analysis_set.R`; test in `tests/testthat/test-analysis_set.R`.

**Interfaces:**
- Consumes: `.set_validate()` output.
- Produces: `.apply_exclusions(d, block, name)` returning `list(keep = logical(nrow(d)), attrition = data.frame(rule, reason, n_before, n_excluded, n_after))`.

- [ ] **Step 1: Failing tests**

```r
exclusion_data <- function() {
  data.frame(ccfid = 1:6, age = c(10, 15, 40, NA, 50, 60),
             aggrc = c(NA, 1, NA, 2, 3, 4))
}
rule_block <- function(rules) list(id = "ccfid", vars = "age", exclude = rules,
                                   expect = list())

test_that("first match wins and attrition counts each rule once", {
  skip_if_not_installed("hvtiPlotR")
  b <- rule_block(list(list(reason = "No aggrecan", when = "is.na(aggrc)"),
                       list(reason = "Under 18", when = "age < 18")))
  ex <- .apply_exclusions(exclusion_data(), b, "eda")
  # row 1 matches both rules: counted under rule 1 only
  expect_equal(ex$attrition$n_excluded, c(2L, 1L))
  expect_equal(ex$attrition$n_before, c(6L, 4L))
  expect_equal(ex$attrition$n_after, c(4L, 3L))
  expect_equal(ex$keep, c(FALSE, FALSE, FALSE, TRUE, TRUE, TRUE))
})

test_that("NA in a predicate excludes nothing", {
  skip_if_not_installed("hvtiPlotR")
  b <- rule_block(list(list(reason = "Under 18", when = "age < 18")))
  ex <- .apply_exclusions(exclusion_data(), b, "eda")
  expect_true(ex$keep[4])  # age is NA
})

test_that("a predicate cannot see the global environment", {
  skip_if_not_installed("hvtiPlotR")
  assign("hv_test_cutoff", 18, envir = globalenv())
  withr::defer(rm("hv_test_cutoff", envir = globalenv()))
  b <- rule_block(list(list(reason = "Young", when = "age < hv_test_cutoff")))
  expect_error(.apply_exclusions(exclusion_data(), b, "eda"),
               "analysis set `eda`, rule 1.*hv_test_cutoff")
})

test_that("bad predicates are named", {
  skip_if_not_installed("hvtiPlotR")
  d <- exclusion_data()
  expect_error(.apply_exclusions(d, rule_block(list(list(reason = "x", when = "age <"))),
                                 "eda"), "rule 1.*does not parse")
  expect_error(.apply_exclusions(d, rule_block(list(list(reason = "x", when = "age"))),
                                 "eda"), "rule 1.*one TRUE/FALSE per row")
})

test_that("no rules keeps every row and needs no hvtiPlotR", {
  ex <- .apply_exclusions(exclusion_data(), rule_block(list()), "eda")
  expect_true(all(ex$keep))
  expect_equal(nrow(ex$attrition), 0L)
})
```

- [ ] **Step 2: Run** the focused tests. Expected: FAIL, `could not find function ".apply_exclusions"`.
- [ ] **Step 3: Implement** in `R/analysis_set.R`:

```r
# Evaluate one rule with the data as its environment and base R as the parent,
# so a predicate sees the columns and base functions and nothing else. A
# predicate naming a global variable is an error here rather than a silent
# lookup, which is why rules are not handed to hv_consort_exclude() as-is: its
# data mask encloses the search path.
.eval_rule <- function(d, rule, name, k) {
  where <- paste0("analysis set `", name, "`, rule ", k, " (`", rule$when, "`)")
  expr <- tryCatch(str2lang(rule$when), error = function(e)
    stop(where, ": `when` does not parse: ", conditionMessage(e), call. = FALSE))
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
  formulas <- lapply(seq_along(rules), function(k)
    eval(call("~", as.name(flag_cols[k]), rules[[k]]$reason), baseenv()))
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
```

- [ ] **Step 4: Run** the focused tests. Expected: PASS. **Step 5: Commit** `feat: evaluate analysis-set exclusions through the consort tracker`

### Task 3: `write_analysis_set()`

**Files:** Modify `R/analysis_set.R`; tests in `tests/testthat/test-analysis_set.R`.

**Interfaces:**
- Consumes: `.set_raw()`, `.set_validate()`, `.declaration_sha()`, `.set_paths()`, `.apply_exclusions()`; `hvtiRutilities::read_built(cfg)`, `hvtiRutilities::built_path(cfg)`, `hvtiRutilities::update_manifest(file, manifest_path, n_rows, n_cols, source)`.
- Produces: exported `write_analysis_set(name, cfg = hvtiRutilities::study_config())` returning the sidecar list invisibly; internal `.built_state(cfg)` returning `list(file, sha256, size, mtime)` (size and mtime as strings); `.atomic_write(target, write_fn)`.

- [ ] **Step 1: Failing tests**

```r
test_that("write produces parquet, sidecar and manifest entry", {
  skip_if_not_installed("arrow"); skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set()))
  side <- write_analysis_set("eda", cfg)
  p <- .set_paths("eda", cfg)
  expect_true(file.exists(p$parquet)); expect_true(file.exists(p$sidecar))
  out <- arrow::read_parquet(p$parquet)
  expect_equal(names(out), c("age", "aggrc", "dead", "iv_dead"))
  expect_equal(nrow(out), 17L)  # 20 rows, 1 with NA aggrc, then 2 under 18
  expect_equal(side$counts$n, 17L)
  expect_equal(side$counts$n_events + side$counts$n_censored, 17L)
  m <- yaml::read_yaml(p$manifest)
  expect_true("eda.parquet" %in% vapply(m$datasets, function(e) e$file, character(1)))
})

test_that("the sidecar and manifest carry no identifier value", {
  skip_if_not_installed("arrow"); skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set()))
  write_analysis_set("eda", cfg)
  p <- .set_paths("eda", cfg)
  side_txt <- readLines(p$sidecar)
  expect_false(any(grepl("ccfid", side_txt)))
  expect_false("ccfid" %in% names(arrow::read_parquet(p$parquet)))
})

test_that("an expect mismatch writes nothing", {
  skip_if_not_installed("arrow"); skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(eda = eda_set(expect = list(n = 99))))
  expect_error(write_analysis_set("eda", cfg), "expected n = 99, got 17")
  p <- .set_paths("eda", cfg)
  expect_false(file.exists(p$parquet)); expect_false(file.exists(p$sidecar))
  m <- yaml::read_yaml(p$manifest)
  expect_false("eda.parquet" %in% vapply(m$datasets, function(e) e$file, character(1)))
})

test_that("missing columns and a non-unique id are errors", {
  skip_if_not_installed("arrow"); skip_if_not_installed("hvtiPlotR")
  cfg <- local_study(list(a = eda_set(vars = c("age", "nope")),
                          b = eda_set(id = "junk")))
  expect_error(write_analysis_set("a", cfg), "not in the built dataset: nope")
  expect_error(write_analysis_set("b", cfg), "`junk` is not unique")
})
```

- [ ] **Step 2: Run** the focused tests. Expected: FAIL, `could not find function "write_analysis_set"`.
- [ ] **Step 3: Implement**

```r
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
         "hvtiRutilities::study_init() or read_built() first.", call. = FALSE)
  p <- hvtiRutilities::built_path(cfg)
  info <- file.info(p)
  list(file = cfg$built, sha256 = e[[1L]]$sha256,
       size = if (file.exists(p)) format(info$size, scientific = FALSE) else NA_character_,
       mtime = if (file.exists(p)) format(info$mtime, "%Y-%m-%d %H:%M:%OS3") else NA_character_)
}

#' Write an analysis set
#'
#' @description
#' Cuts the analysis set `name`, declared under `analysis_sets:` in the study's
#' `_study.yml`, from the built dataset: keeps its `vars`, applies its `exclude`
#' rules in order (first match wins), checks any `expect` counts, and writes
#' `datasets/<name>.parquet`, a `datasets/<name>.set.yml` sidecar recording the
#' parent dataset and the attrition, and a `manifest.yaml` entry.
#'
#' @details
#' Nothing is written unless every check passes. Each `when` is R code evaluated
#' against the data with only base R visible; a missing value counts as not
#' excluded, as SAS `if <missing> then delete` does. The identifier column named
#' by `id` is used to track exclusions and is never written to the sidecar or
#' the manifest.
#'
#' @param name Character(1). The set's name in `_study.yml`.
#' @param cfg List. A study manifest from [hvtiRutilities::study_config()].
#'
#' @return The sidecar contents, invisibly: a list with `set`, `parent`,
#'   `declaration_sha256`, `written`, `counts`, `n_cols`, `attrition` and
#'   `packages`.
#'
#' @seealso [read_analysis_set()]
#' @export
write_analysis_set <- function(name, cfg = hvtiRutilities::study_config()) {
  if (!requireNamespace("arrow", quietly = TRUE))
    stop("write_analysis_set() needs arrow. Install it with ",
         "install.packages(\"arrow\").", call. = FALSE)
  raw <- .set_raw(name, cfg)
  b <- .set_validate(raw, name, cfg)
  d <- hvtiRutilities::read_built(cfg)

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
  ev <- cfg$cohort$event
  if (ev %in% b$vars) {
    counts$n_events <- as.integer(sum(out[[ev]] == 1, na.rm = TRUE))
    counts$n_censored <- counts$n - counts$n_events
  }
  for (k in names(b$expect)) {
    if (is.null(counts[[k]]))
      stop("analysis set `", name, "`: cannot check `expect: ", k, "` because ",
           "the event column `", ev, "` is not in `vars`.", call. = FALSE)
    if (!identical(as.integer(counts[[k]]), as.integer(b$expect[[k]])))
      stop("analysis set `", name, "`: expected ", k, " = ", b$expect[[k]], ", got ",
           counts[[k]], ". Nothing was written.", call. = FALSE)
  }

  p <- .set_paths(name, cfg)
  side <- list(
    set = name,
    parent = .built_state(cfg),
    declaration_sha256 = .declaration_sha(raw),
    written = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    counts = counts,
    n_cols = ncol(out),
    attrition = ex$attrition,
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
```

- [ ] **Step 4: Run** the focused tests; PASS. **Step 5: Commit** `feat: write_analysis_set()`

### Task 4: `read_analysis_set()` and the spec addition

**Files:** Modify `R/analysis_set.R`, `tests/testthat/test-analysis_set.R`, `dev/specs/2026-09-14-analysis-sets-design.md` (sections 5, 6).

- [ ] **Step 1: Failing tests**

```r
written_study <- function(env = parent.frame()) {
  cfg <- local_study(list(eda = eda_set()), env = env)
  write_analysis_set("eda", cfg)
  cfg
}

test_that("read round-trips the written set with its attrition", {
  skip_if_not_installed("arrow"); skip_if_not_installed("hvtiPlotR")
  cfg <- written_study()
  d <- read_analysis_set("eda", cfg)
  expect_equal(nrow(d), 17L)
  expect_equal(attr(d, "attrition")$n_excluded, c(1L, 2L))
})

test_that("an unwritten set says how to write it", {
  skip_if_not_installed("arrow")
  cfg <- local_study(list(eda = eda_set()))
  expect_error(read_analysis_set("eda", cfg), 'write_analysis_set\\("eda"\\)')
})

test_that("a rewritten built dataset makes the set stale", {
  skip_if_not_installed("arrow"); skip_if_not_installed("hvtiPlotR")
  cfg <- written_study()
  f <- hvtiRutilities::built_path(cfg)
  cat("21,70,5,0,3,1\n", file = f, append = TRUE)
  expect_error(read_analysis_set("eda", cfg), "built dataset has changed")
})

test_that("an edited rule makes the set stale; key order in YAML does not", {
  skip_if_not_installed("arrow"); skip_if_not_installed("hvtiPlotR")
  cfg <- written_study()
  y <- yaml::read_yaml(cfg$file)
  y$analysis_sets$eda$exclude[[2]]$when <- "age < 21"
  yaml::write_yaml(y, cfg$file)
  expect_error(read_analysis_set("eda", cfg), "declaration .* has changed")
})

test_that("a corrupted parquet fails the integrity check", {
  skip_if_not_installed("arrow"); skip_if_not_installed("hvtiPlotR")
  cfg <- written_study()
  p <- .set_paths("eda", cfg)
  con <- file(p$parquet, "ab"); writeBin(as.raw(0), con); close(con)
  expect_error(read_analysis_set("eda", cfg), "does not match its manifest")
})
```

- [ ] **Step 2: Run** focused tests; FAIL on `read_analysis_set` not found.
- [ ] **Step 3: Implement**

```r
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
  if (!same(side$parent$sha256, now$sha256) || !same(side$parent$size, now$size) ||
        !same(side$parent$mtime, now$mtime))
    stop("analysis set `", name, "`: the built dataset has changed since the set ",
         "was written. ", fix, call. = FALSE)
  if (!same(side$declaration_sha256, .declaration_sha(raw)))
    stop("analysis set `", name, "`: its declaration in _study.yml has changed ",
         "since the set was written. ", fix, call. = FALSE)
  m <- yaml::read_yaml(p$manifest)
  e <- Filter(function(x) identical(x$file, basename(p$parquet)), m$datasets)
  if (!length(e) || !same(e[[1L]]$sha256,
                          digest::digest(p$parquet, algo = "sha256", file = TRUE)))
    stop("analysis set `", name, "`: ", basename(p$parquet), " does not match its ",
         "manifest entry. ", fix, call. = FALSE)

  d <- as.data.frame(arrow::read_parquet(p$parquet))
  attr(d, "attrition") <- do.call(rbind, lapply(side$attrition, as.data.frame))
  d
}
```

  Note: `yaml::write_yaml()` of a data frame writes it column-wise, so `side$attrition` reads back as a named list of columns, not a list of rows. Write the attrition as rows in Task 3 (`attrition = lapply(split(ex$attrition, seq_len(nrow(ex$attrition))), as.list)`, unnamed) if the round-trip test shows the columnar shape, and keep both functions consistent. Decide by running the test, not by assumption.

- [ ] **Step 4: Update the spec.** In `dev/specs/2026-09-14-analysis-sets-design.md` section 5's check table, add to the parent row: "or `built`'s size or mtime differs from the sidecar's"; in section 6, add `size` and `mtime` under `parent:`; in section 5 step 8, change "with the attrition table printed" to "the attrition table is in the returned sidecar; nothing is printed (no chatty output in function bodies)".
- [ ] **Step 5: Run** focused tests; PASS. **Step 6: Commit** `feat: read_analysis_set() with parent, declaration and integrity checks`

### Task 5: Package wiring, docs, PR

- [ ] `DESCRIPTION`: add `hvtiPlotR` to Suggests and `ehrlinger/hvtiPlotR` to Remotes.
- [ ] `Rscript -e 'devtools::document()'`; confirm `export(write_analysis_set)` and `export(read_analysis_set)`.
- [ ] `_pkgdown.yml`: if it has a `reference:` index, add both functions under a new title "Analysis sets"; if pkgdown's `check_pkgdown()` fails, fix the index it names.
- [ ] `NEWS.md`: add `# hvtiRdatabuild (unreleased)` above `# hvtiRdatabuild 0.2.0` if absent, with:

```markdown
* **New `write_analysis_set()` and `read_analysis_set()`.** An analysis set
  is a declared, checkpointed selection of the built dataset: the columns a
  job reads and the rows it excludes, declared under `analysis_sets:` in
  `_study.yml`, written once to `datasets/<name>.parquet` with a sidecar
  recording its parent and per-rule attrition, and read by every job that
  needs it. Reading stops, rather than rebuilding, when the built dataset or
  the declaration has changed.
```

- [ ] Definition of done: `devtools::test()` all pass; `devtools::check()` 0/0/0; `lintr::lint_package()` clean.
- [ ] Push `feat/analysis-sets`, `gh pr create` (body ends with the Claude Code attribution line). The maintainer merges. After merge, a separate commit names `0.2.1`.
