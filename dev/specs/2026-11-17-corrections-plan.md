# Source corrections: implementation plan (plan 2a of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Corrections name a cell of a warehouse source view. Generated views apply them
over every column with the G1 and G7 rules. Batch intake and decision functions record
them, and a helper turns a study's own fixes into candidate corrections.

**Architecture:**
- **Per-source tables.** Each source view declared in `master.yml` gets its own append-only
  `<source>_corrections` and `<source>_correction_decisions` tables. Key columns are typed
  per source.
- **Generated views.** One generated `checked` CTE gives every accepted correction a status.
  Four views read it: `<source>_corrected` (a single-join pivot over every column),
  `_corrections_applied`, `_corrections_stale` and `_corrections_conflicts`.
- **R reference.** `resolve_source_corrections()` is the R reference for the same rules.
  A test holds the reference and the SQL to identical output on one case matrix.
- **Intake.** `propose_corrections()` and `decide_corrections()` validate a whole batch,
  return a verdict per row, and write all of it in one transaction or nothing.
- **Study candidates.** `study_correction_candidates()` compares a study's data with its own
  frozen pull and writes a template for a human to review.

**Tech Stack:** R (>= 4.4.0), DBI, duckdb (tests), arrow (the frozen pull), yaml, digest,
testthat 3.

**Spec:** `dev/specs/2026-11-16-master-views-design.md` §3.1–§3.5 and the corrections bullets
of §8 and §9. **Not in this plan:** the parity gate (§7) is plan 2b,
`dev/specs/2026-11-17-parity-gate-plan.md`. The SQL model repository, deploying these views,
and the master-level `<master>_corrections_applied` rollup are plan 3. This plan tests on
duckdb only. The SQL Server rehearsal of the generated SQL belongs to plan 3.

## Global constraints

- Lines are **100 characters** (`.lintr`). Roxygen markdown is enabled.
- testthat **edition 3**. Test files are `test-*.R`, with a hyphen.
- **No PHI.** Every fixture is invented and says so ("No PHI: identifiers and values are
  invented.").
- **No values in output.** No identifier or data value appears in any error, warning, message
  or print. Output is counts, verdicts, column names, source names, correction ids and
  template row numbers.
- **Errors** use `.abort(condition, ...)` (`R/rubric.R:37`), which gives class
  `hvtiRdatabuild_<condition>`. Messages start with `fn():`.
- **DBI calls** are wrapped in `run_step(name, expr)` (`R/sql_dialect.R:94`), which withholds
  the driver's message.
- **Informational messages** go through `.hvti_inform()` (`R/rubric.R:19`), which respects
  `options(hvti.quiet = TRUE)`.
- **Dialects** are exactly `"mssql"` and `"duckdb"`. Quote identifiers with `quoter()`, and
  use `sql_types()`, `view_header()`, `table_types()` and `.string_eq_sql()` as they stand.
- **SQL stays in the shared subset:** CTEs, `CASE`, `LEFT JOIN`, `ROW_NUMBER() OVER`,
  `COUNT(DISTINCT ...)`, `TRY_CAST`, and bound `?` parameters.
- **Arrow and duckdb are Suggests.** Tests call `skip_if_not_installed()`.
- **The old master-level corrections code stays as it is:** `R/corrections_sql.R`,
  `R/master_corrections.R` and the three deprecated exports. This plan adds new files beside
  them. Its only edits there are two additive fixes in Task 2 Step 0: decimal scale in
  `table_types()`, and a `logical` branch in `parse_value()`.
- **Interim write tools.** Every new export's help says it is interim and superseded by the
  HVTR registry's intake (spec §3.4).
- **No version bump.** The implementation branch writes one news fragment (Task 8). This
  plan is under `dev/`, which `.Rbuildignore` excludes, so the plan's own PR needs none.
- **Done** means `devtools::document()` run and committed, `devtools::test()` passing, and
  `devtools::check()` at 0 errors, 0 warnings, 0 notes.

## Decisions this plan makes where the spec is silent

Task 8 records each of these as an amendment to the spec.

1. **Corrections tables are per source** (`<source>_corrections`,
   `<source>_correction_decisions`), not one shared pair. A source's key columns are typed,
   and the corrected view joins on them, so a shared table would need text-encoded keys and
   a cast in every join.
2. **`master.yml` declares the sources and the deciders.** It gains
   `sources: {<view>: {key: [...]}}` and `deciders: [...]`. The SQL repository's model
   metadata (plan 3) becomes the authority later, and the yml mirrors it until then.
3. **Intake stores a canonical text form.** Each value is parsed against the source column's
   type and written back with `value_text()`. Text agreement (G1) is then value agreement,
   so `"3.0"` and `"3"` corroborate.
4. **Intake verdicts.** The spec lists `appendable`, `unknown_key`, `ambiguous_key`,
   `does_not_cast`, `rule_not_fact` and `derived_variable`. This plan adds four more:
   - `unknown_source`: the row names a source `master.yml` does not declare.
   - `invalid_field`: a flag that is not 0 or 1, a flag that disagrees with its value, an
     unknown evidence type, or a blank evidence reference, asserter or variable.
   - `no_variable`: the source has no such column (§3.3), or it is a key column.
   - `prior_mismatch`: the spec names it in §3.5.

   `decide_corrections()` adds `repeated_correction`: one correction decided twice in one
   batch is refused, because the rows share a `decided_on` and their order would be
   arbitrary.

   **`rule_not_fact`** is a key or variable cell holding a pattern or comparison
   (`* % ? < > = , ;`) or the word `all` or `any`. It is a predicate, so it is a rule.
5. **Statuses, checked in this order:**
   1. `no_variable`
   2. `no_record`
   3. `ambiguous_record`: the key now matches several source rows, so none is changed.
      Intake refuses such a key (`ambiguous_key`), but a refresh can break uniqueness
      after a correction is accepted.
   4. `accepted_disagree` (G1)
   5. `prior_unknown`
   6. `does_not_cast`
   7. `filled_upstream_agrees` or `filled_upstream_disagrees` (G7)
   8. `prior_mismatch`
   9. `apply`

   The stale view lists `no_variable` through `prior_mismatch` plus `filled_upstream_agrees`.
   The conflicts view lists `accepted_disagree` and `filled_upstream_disagrees`.
6. **G7's automatic retirement** is `retire_filled_corrections()`. It records a `bake`
   decision by the reserved decider `"filled_upstream"` for every `filled_upstream_agrees`
   row. A view cannot write, so "automatic" means one call, which data management can
   schedule.
7. **Lineage is a contract with plan 3.**
   - `<master>_lineage` (`master_column`, `source`, `source_column`) lists exactly the master
     columns that pass a source column through by rename only.
   - A source's key columns carry the same names in the master, and therefore in a frozen
     pull.
8. **G2 covers every decision, not only `accept`.** A decider who asserted the correction is
   refused (`self_accepted`), and so is a decider not listed in `deciders` (`not_decider`).

## File structure

| File | Responsibility |
|---|---|
| `R/master_config.R` (modify) | `sources`, `deciders` fields |
| `R/source_corrections_sql.R` (new) | names, DDL, R reference resolver, generated views |
| `R/source_corrections.R` (new) | `generate_corrections_sql()`, `write_corrections_template()`, `propose_corrections()`, `decide_corrections()`, `retire_filled_corrections()` |
| `R/correction_candidates.R` (new) | `study_correction_candidates()` |
| `tests/testthat/helper-source-corrections.R` (new) | synthetic sources, master, config, deploy |
| `tests/testthat/test-master-config.R` (modify) | the two new fields |
| `tests/testthat/test-source-corrections-sql.R` (new) | DDL, R/SQL agreement, every-column coverage |
| `tests/testthat/test-propose-corrections.R` (new) | template, every verdict, whole-file refusal |
| `tests/testthat/test-decide-corrections.R` (new) | decisions, G2, G1 settled by supersede, G7 retirement |
| `tests/testthat/test-correction-candidates.R` (new) | candidates against the frozen pull |
| `_pkgdown.yml`, `news/`, the spec (modify) | Task 8 |

---

### Task 1: `master.yml` declares sources and deciders

**Files:**
- Modify: `R/master_config.R` (the body of `read_master_config()`, before the final
  `structure()`; the roxygen `@return`)
- Test: `tests/testthat/test-master-config.R`

**Interfaces:**
- Produces: `config$sources`, a named list (possibly empty). Each element is
  `list(key = <character>)`, and each name is a source view name matching
  `^[A-Za-z_][A-Za-z0-9_]*$`. Also `config$deciders`, a character vector or `NULL`.

- [ ] **Step 1: Write the failing tests** (append to `tests/testthat/test-master-config.R`)

```r
test_that("sources and deciders read, and default to empty", {
  cfg <- read_master_config(write_cfg(base_cfg))
  expect_identical(cfg$sources, list())
  expect_null(cfg$deciders)

  cfg <- read_master_config(write_cfg(c(base_cfg,
    "sources:",
    "  stg_echo: {key: [mrn, encounter_date]}",
    "  stg_patient: {key: [mrn]}",
    "deciders: [dm_one, dm_two]")))
  expect_identical(names(cfg$sources), c("stg_echo", "stg_patient"))
  expect_identical(cfg$sources$stg_patient$key, "mrn")
  expect_identical(cfg$deciders, c("dm_one", "dm_two"))
})

test_that("a source needs a key and a plain name", {
  expect_error(read_master_config(write_cfg(c(base_cfg, "sources:", "  stg_echo: {}"))),
               "must declare its key")
  expect_error(read_master_config(write_cfg(c(base_cfg, "sources:",
                                              "  \"stg echo\": {key: [mrn]}"))),
               "plain view name")
  expect_error(read_master_config(write_cfg(c(base_cfg, "deciders: []"))),
               "'deciders' must list")
})
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "master-config")'`
Expected: FAIL. `cfg$sources` is `NULL`, and no error is raised.

- [ ] **Step 3: Implement.** In `read_master_config()`, directly before
  `structure(list(`, insert:

```r
  sources <- raw[["sources"]]
  if (is.null(sources)) sources <- list()
  if (length(sources) && (is.null(names(sources)) || !all(nzchar(names(sources))))) {
    stop("'sources' must be a mapping of source view names to their keys.", call. = FALSE)
  }
  for (s in names(sources)) {
    if (!grepl("^[A-Za-z_][A-Za-z0-9_]*$", s)) {
      stop("Source '", s, "' must be a plain view name (letters, digits, underscores).",
           call. = FALSE)
    }
    k <- sources[[s]][["key"]]
    if (!is.character(k) || !length(k) || anyNA(k) || !all(nzchar(k))) {
      stop("Source '", s, "' must declare its key as one or more column names.",
           call. = FALSE)
    }
  }
  sources <- lapply(sources, function(s) list(key = as.character(s[["key"]])))

  deciders <- raw[["deciders"]]
  if (!is.null(deciders) &&
        (!is.character(deciders) || !length(deciders) || anyNA(deciders))) {
    stop("'deciders' must list who may decide corrections.", call. = FALSE)
  }
```

  Add `sources = sources, deciders = deciders,` to the `structure(list(...))` call, before
  `file = path`. In the roxygen `@return`, after `` `build_program`, `` add
  `` `sources` (a named list of `list(key = )`, possibly empty), `deciders` (`NULL` or a
  character vector), ``. Add one sentence to the description: "`sources` declares the
  warehouse source views whose cells may be corrected, each with its unique key, and
  `deciders` names who may decide a correction (see [propose_corrections()])."

  ⚠️ An empty yml sequence (`deciders: []`) reads as `list()`, which is not character, so it
  is refused as intended.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::test(filter = "master-config")'`
Expected: PASS. The existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add R/master_config.R tests/testthat/test-master-config.R man/read_master_config.Rd
git commit -m "feat: master.yml declares correctable sources and deciders"
```

---

### Task 2: per-source tables and the R reference resolver

**Files:**
- Create: `R/source_corrections_sql.R`
- Create: `tests/testthat/helper-source-corrections.R`
- Modify: `R/sql_dialect.R` (`table_types()`, line 115), `R/corrections_sql.R`
  (`parse_value()`, line 41): two additive fixes the generated casts depend on (Step 0)
- Test: `tests/testthat/test-source-corrections-sql.R`

**Interfaces:**
- Consumes: `quoter()`, `sql_types()`, `parse_value()` (`R/corrections_sql.R:41`) and
  `table_types()`.
- Produces:
  - `table_types()` now carries a SQL Server `decimal`/`numeric` column's precision and
    scale (`decimal(10,2)`, not `decimal`). duckdb already reports them in `DATA_TYPE`.
  - `parse_value()` gains a `logical` branch (`1`/`0`, `TRUE`/`FALSE`, `T`/`F`).
  - `.source_tables(source)`: a list with names `corrections`, `decisions`, `corrected`,
    `applied`, `stale` and `conflicts`.
  - `SOURCE_STALE` and `SOURCE_CONFLICT`: character constants of statuses.
  - `source_corrections_ddl(source, key_types, dialect)`: a named character vector of two
    `CREATE TABLE` statements, named `corrections` and `decisions`, with no trailing
    semicolon.
  - `resolve_source_corrections(base, corrections, decisions, key)`: a list.
    - `data`: `base`, corrected.
    - `applied`: `correction_id` and the key columns.
    - `stale`: `correction_id`, `variable`, `reason`.
    - `conflicts`: `correction_id`, `variable`, `reason`.

- [ ] **Step 0: Keep decimal scale, and read booleans.** Every generated cast uses
  `table_types()`. Today it drops a `decimal`'s precision and scale on SQL Server, and a
  bare `decimal` has scale 0, so a cast to it would round a fill-in of `12.5` to `13`.
  Separately, `parse_value()` has no `logical` branch, so a `BIT`/`BOOLEAN` column could
  never be corrected. Write the tests first, in `tests/testthat/test-source-corrections-sql.R`:

```r
test_that("table_types() keeps a decimal's precision and scale", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbExecute(con, "CREATE TABLE t_dec (a DECIMAL(10,2), b INTEGER)")
  expect_identical(unname(table_types(con, "t_dec")), c("DECIMAL(10,2)", "INTEGER"))
})

test_that("parse_value() reads logical text", {
  expect_identical(parse_value("1", "logical"), TRUE)
  expect_identical(parse_value("FALSE", "logical"), FALSE)
  expect_identical(parse_value("maybe", "logical"), NA)
  expect_identical(value_text(TRUE), "TRUE")
})
```

  Then implement. In `table_types()`, add `NUMERIC_PRECISION, NUMERIC_SCALE` to the
  `SELECT` and replace the `type <-` line with:

```r
  type <- ifelse(is.na(len), cols$DATA_TYPE,
                 sprintf("%s(%s)", cols$DATA_TYPE, ifelse(len == -1, "max", len)))
  # SQL Server reports a bare "decimal"; without its scale a cast would round (duckdb
  # already writes DECIMAL(p,s) into DATA_TYPE, which has a parenthesis and is left alone).
  dec <- tolower(cols$DATA_TYPE) %in% c("decimal", "numeric") &
    !grepl("(", cols$DATA_TYPE, fixed = TRUE)
  type[dec] <- sprintf("%s(%s,%s)", cols$DATA_TYPE[dec], cols$NUMERIC_PRECISION[dec],
                       cols$NUMERIC_SCALE[dec])
```

  In `parse_value()`, add a branch to the `switch()` before the `stop()` line:

```r
         logical = switch(toupper(text), "1" = , "TRUE" = , "T" = TRUE,
                          "0" = , "FALSE" = , "F" = FALSE, NA),
```

  and add `logical = NA,` to the missing-value `switch()` at the top. Add `"logical"` to
  the `@param r_class` list in its roxygen. These are the plan's only edits to existing
  corrections code. The global constraint's "stays as it is" means no behaviour change,
  and both edits are additive.

- [ ] **Step 1: Write the helper** `tests/testthat/helper-source-corrections.R`

```r
# No PHI: identifiers and values are invented.

# Two warehouse sources and the master built from them. stg_echo is encounter-level,
# stg_patient patient-level. master_demo2's mr_severe is derived, not a source column.
seed_sources <- function(con) {
  DBI::dbWriteTable(con, "stg_echo", data.frame(
    mrn = c("SYN201", "SYN202", "SYN203", "SYN204", "SYN205"),
    encounter_date = as.Date(c("2020-01-01", "2020-02-01", "2020-03-01", "2020-04-01",
                               "2020-05-01")),
    lvef = c(30, NA, 40, 50, 55),
    mr_grade = c("2", "3", "1", NA, "4"),
    seen_on = as.Date(c("2019-12-01", NA, "2020-02-01", "2020-03-01", "2020-04-01")),
    stringsAsFactors = FALSE
  ))
  DBI::dbWriteTable(con, "stg_patient", data.frame(
    mrn = c("SYN201", "SYN202", "SYN203", "SYN204", "SYN205"),
    sex = c("F", "M", "F", "M", "F"),
    stringsAsFactors = FALSE
  ))
  DBI::dbExecute(con, paste(
    "CREATE VIEW master_demo2 AS SELECT e.mrn, e.encounter_date, e.lvef, e.mr_grade,",
    "p.sex, CASE WHEN e.mr_grade IN ('3', '4') THEN 1 ELSE 0 END AS mr_severe",
    "FROM stg_echo e JOIN stg_patient p ON p.mrn = e.mrn"
  ))
  invisible(con)
}

# A master.yml for master_demo2, declaring both sources and two deciders.
corrections_config <- function(env = parent.frame()) {
  dir <- withr::local_tempdir("corrections-", .local_envir = env)
  path <- file.path(dir, "master.yml")
  writeLines(c("name: master_demo2", "key: [mrn, encounter_date]",
               paste0("snapshots: ", dir), "current: built.sas7bdat",
               paste0("build_program: ", file.path(dir, "bd.sas")),
               "sources:",
               "  stg_echo: {key: [mrn, encounter_date]}",
               "  stg_patient: {key: [mrn]}",
               "deciders: [dm_one, dm_two]"), path)
  read_master_config(path)
}

# A duckdb connection with the sources only (no correction objects yet).
local_sources_db <- function(env = parent.frame()) {
  testthat::skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
  seed_sources(con)
}

# One corrections-table row, for tests that write the table directly.
corr_row <- function(id, mrn, date, variable, prior, prior_missing, new, new_missing,
                     asserted_on = "2026-01-01", asserted_by = "tester") {
  data.frame(correction_id = id, source = "stg_echo", mrn = mrn,
             encounter_date = as.Date(date), variable = variable,
             expected_prior = as.character(prior),
             expected_prior_missing = as.integer(prior_missing),
             new_value = as.character(new), new_value_missing = as.integer(new_missing),
             evidence_type = "chart_review", evidence_ref = "invented",
             asserted_by = asserted_by,
             asserted_on = as.POSIXct(asserted_on, tz = "UTC"),
             stringsAsFactors = FALSE)
}

dec_row <- function(id, correction_id, decision = "accept", on = "2026-02-01",
                    by = "dm_one") {
  data.frame(decision_id = id, correction_id = correction_id, decision = decision,
             decided_by = by, decided_on = as.POSIXct(on, tz = "UTC"),
             reason = NA_character_, stringsAsFactors = FALSE)
}

# The case matrix shared by the R/SQL agreement test. One row per rule:
case_corrections <- function() {
  rbind(
    corr_row("c01", "SYN201", "2020-01-01", "lvef", "30", 0L, "35", 0L),     # apply
    corr_row("c02", "SYN202", "2020-02-01", "lvef", NA, 1L, "45", 0L),       # fill-in
    corr_row("c03", "SYN203", "2020-03-01", "lvef", "40", 0L, "41", 0L),     # G1 disagree
    corr_row("c04", "SYN203", "2020-03-01", "lvef", "40", 0L, "42", 0L),     # G1 disagree
    corr_row("c05", "SYN201", "2020-01-01", "mr_grade", "2", 0L, "3", 0L),   # agree
    corr_row("c06", "SYN201", "2020-01-01", "mr_grade", "2", 0L, "3", 0L),   # agree
    corr_row("c07", "SYN203", "2020-03-01", "mr_grade", NA, 1L, "1", 0L),    # G7 agrees
    corr_row("c08", "SYN205", "2020-05-01", "mr_grade", NA, 1L, "2", 0L),    # G7 disagrees
    corr_row("c09", "SYN204", "2020-04-01", "lvef", "49", 0L, "51", 0L),     # mismatch
    corr_row("c10", "SYN204", "2020-04-01", "nosuch", "1", 0L, "2", 0L),     # no_variable
    corr_row("c11", "SYN299", "2020-04-01", "lvef", "1", 0L, "2", 0L),       # no_record
    corr_row("c12", "SYN205", "2020-05-01", "lvef", NA, NA, "60", 0L),       # prior_unknown
    corr_row("c13", "SYN203", "2020-03-01", "seen_on", "2020-02-01", 0L, "notadate", 0L),
    corr_row("c14", "SYN204", "2020-04-01", "mr_grade", NA, 1L, NA, 1L),     # apply, NA
    corr_row("c15", "SYN205", "2020-05-01", "seen_on", "2020-04-01", 0L, NA, 1L),
    corr_row("c16", "SYN202", "2020-02-01", "mr_grade", "3", 0L, "4", 0L),   # rejected
    corr_row("c17", "SYN202", "2020-02-01", "seen_on", NA, 1L, "2020-01-15", 0L)
  )
}

# c13 does not cast; c15 sets a value missing; c16 is accepted then rejected; c17 is
# never decided.
case_decisions <- function() {
  rbind(do.call(rbind, lapply(1:16, function(i) {
    dec_row(sprintf("d%02d", i), sprintf("c%02d", i))
  })), dec_row("d99", "c16", "reject", on = "2026-03-01"))
}

# Create stg_echo's correction tables, fill them, and create its four views.
deploy_echo <- function(con, corrections = case_corrections(),
                        decisions = case_decisions()) {
  types <- table_types(con, "stg_echo")
  key <- c("mrn", "encounter_date")
  for (s in source_corrections_ddl("stg_echo", types[key], "duckdb")) DBI::dbExecute(con, s)
  if (nrow(corrections)) DBI::dbAppendTable(con, "stg_echo_corrections", corrections)
  if (nrow(decisions)) DBI::dbAppendTable(con, "stg_echo_correction_decisions", decisions)
  for (s in source_views_sql("stg_echo", key, types, "duckdb")) DBI::dbExecute(con, s)
  invisible(con)
}
```

  `deploy_echo()` calls `source_views_sql()`, which Task 3 defines. Task 2's tests do not
  call `deploy_echo()`.

- [ ] **Step 2: Write the failing tests** `tests/testthat/test-source-corrections-sql.R`

```r
# No PHI: identifiers and values are invented.

test_that("each source gets its own typed corrections and decisions tables", {
  con <- local_sources_db()
  types <- table_types(con, "stg_echo")
  ddl <- source_corrections_ddl("stg_echo", types[c("mrn", "encounter_date")], "duckdb")
  expect_named(ddl, c("corrections", "decisions"))
  for (s in ddl) DBI::dbExecute(con, s)
  got <- table_types(con, "stg_echo_corrections")
  expect_identical(unname(got[c("mrn", "encounter_date")]), unname(types[c("mrn",
                                                                           "encounter_date")]))
  expect_true(all(c("source", "variable", "expected_prior_missing") %in% names(got)))
  expect_true(DBI::dbExistsTable(con, "stg_echo_correction_decisions"))
})

test_that("the R reference applies each rule of the case matrix", {
  con <- local_sources_db()
  base <- DBI::dbGetQuery(con, "SELECT * FROM stg_echo ORDER BY mrn")
  ref <- resolve_source_corrections(base, case_corrections(), case_decisions(),
                                    c("mrn", "encounter_date"))
  expect_identical(ref$data$lvef, c(35, 45, 40, 50, 55))
  expect_identical(ref$data$mr_grade, c("3", "3", "1", NA, "4"))
  expect_identical(sort(ref$applied$correction_id), c("c01", "c02", "c05", "c06", "c14",
                                                       "c15"))
  stale <- stats::setNames(ref$stale$reason, ref$stale$correction_id)
  expect_identical(stale[sort(names(stale))],
                   c(c07 = "filled_upstream_agrees", c09 = "prior_mismatch",
                     c10 = "no_variable", c11 = "no_record", c12 = "prior_unknown",
                     c13 = "does_not_cast"))
  conf <- stats::setNames(ref$conflicts$reason, ref$conflicts$correction_id)
  expect_identical(conf[sort(names(conf))],
                   c(c03 = "accepted_disagree", c04 = "accepted_disagree",
                     c08 = "filled_upstream_disagrees"))
  expect_false(any(c("c16", "c17") %in% c(ref$applied$correction_id,
                                         ref$stale$correction_id,
                                         ref$conflicts$correction_id)))
})
```

- [ ] **Step 3: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "source-corrections-sql")'`
Expected: FAIL with `could not find function "source_corrections_ddl"`.

- [ ] **Step 4: Implement** `R/source_corrections_sql.R` (the generated views are added in
  Task 3)

```r
# source_corrections_sql.R
#
# Corrections to warehouse source views (spec §3): per-source append-only tables, an R
# reference for the resolution rules, and the generated views that implement the same
# rules. Nothing here prints a key or a value.

#' Object names for one source's corrections
#'
#' @param source Character. The source view's name.
#'
#' @return A list of table and view names.
#'
#' @keywords internal
#' @noRd
.source_tables <- function(source) {
  list(corrections = paste0(source, "_corrections"),
       decisions   = paste0(source, "_correction_decisions"),
       corrected   = paste0(source, "_corrected"),
       applied     = paste0(source, "_corrections_applied"),
       stale       = paste0(source, "_corrections_stale"),
       conflicts   = paste0(source, "_corrections_conflicts"))
}

# Statuses an accepted correction can take, besides "apply" (spec §3.3, G1, G7).
SOURCE_STALE <- c("no_variable", "no_record", "ambiguous_record", "prior_unknown", # nolint
                  "does_not_cast", "prior_mismatch", "filled_upstream_agrees")
SOURCE_CONFLICT <- c("accepted_disagree", "filled_upstream_disagrees") # nolint

#' DDL for one source's corrections and decisions tables
#'
#' @param source Character. The source view's name.
#' @param key_types A named character vector of the source's key columns' SQL types.
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#'
#' @return A named character vector (`corrections`, `decisions`) of `CREATE TABLE`
#'   statements.
#'
#' @keywords internal
#' @noRd
source_corrections_ddl <- function(source, key_types, dialect = "mssql") {
  q <- quoter(dialect)
  ty <- sql_types(dialect)
  tabs <- .source_tables(source)
  col <- function(name, type, null = TRUE) {
    sprintf("  %s %s %s", q(name), type, if (null) "NULL" else "NOT NULL")
  }
  key_cols <- unname(mapply(col, names(key_types), key_types, MoreArgs = list(null = FALSE)))
  corr <- c(col("correction_id", ty$id, FALSE), col("source", ty$id, FALSE), key_cols,
            col("variable", ty$id, FALSE),
            col("expected_prior", ty$text), col("expected_prior_missing", ty$flag),
            col("new_value", ty$text), col("new_value_missing", ty$flag, FALSE),
            col("evidence_type", ty$id, FALSE), col("evidence_ref", ty$text, FALSE),
            col("asserted_by", ty$id, FALSE), col("asserted_on", ty$ts, FALSE),
            sprintf("  PRIMARY KEY (%s)", q("correction_id")))
  dec <- c(col("decision_id", ty$id, FALSE), col("correction_id", ty$id, FALSE),
           col("decision", ty$id, FALSE), col("decided_by", ty$id, FALSE),
           col("decided_on", ty$ts, FALSE), col("reason", ty$text),
           sprintf("  PRIMARY KEY (%s)", q("decision_id")))
  c(corrections = sprintf("CREATE TABLE %s (\n%s\n)", q(tabs$corrections),
                          paste(corr, collapse = ",\n")),
    decisions   = sprintf("CREATE TABLE %s (\n%s\n)", q(tabs$decisions),
                          paste(dec, collapse = ",\n")))
}

#' Resolve one source's corrections in R
#'
#' The reference for the generated views. A correction counts when its latest decision
#' (by `decided_on`, then `decision_id`) is `"accept"`. Each accepted correction then takes
#' the first status that holds, in this order:
#'
#' 1. `no_variable`: its variable is not a non-key column.
#' 2. `no_record`: its key matches no row.
#' 3. `ambiguous_record`: its key matches several rows, so it changes none.
#' 4. `accepted_disagree`: accepted corrections to its cell disagree on the new value (G1).
#' 5. `prior_unknown`.
#' 6. `does_not_cast`.
#' 7. `filled_upstream_agrees` or `filled_upstream_disagrees`: it filled a missing value,
#'    and the source now holds one (G7).
#' 8. `prior_mismatch`.
#' 9. Otherwise, `apply`.
#'
#' @param base A data frame of the source's rows.
#' @param corrections A data frame of the corrections table's rows.
#' @param decisions A data frame of the decisions table's rows.
#' @param key Character. The source's key columns.
#'
#' @return A list: `data`, `applied`, `stale` and `conflicts`.
#'
#' @keywords internal
#' @noRd
resolve_source_corrections <- function(base, corrections, decisions, key) {
  dec <- decisions[order(decisions$correction_id, -xtfrm(decisions$decided_on),
                         -xtfrm(decisions$decision_id)), , drop = FALSE]
  latest <- dec[!duplicated(dec$correction_id), , drop = FALSE]
  acc <- corrections[corrections$correction_id %in%
                       latest$correction_id[latest$decision == "accept"], , drop = FALSE]
  cell_of <- function(d, cols) do.call(paste, c(lapply(d[cols], as.character), sep = "\r"))
  acc_cell <- cell_of(acc, c(key, "variable"))
  marker <- ifelse(acc$new_value_missing == 1L, "\001missing", acc$new_value)
  n_values <- tapply(marker, acc_cell, function(v) length(unique(v)))
  valid <- setdiff(names(base), key)
  base_id <- cell_of(base, key)
  row_of <- match(cell_of(acc, key), base_id)
  # A key that now matches several rows changes none of them (the source lost uniqueness).
  n_rows <- as.integer(table(base_id)[cell_of(acc, key)])
  status <- character(nrow(acc))
  for (i in seq_len(nrow(acc))) {
    a <- acc[i, ]
    v <- a$variable
    status[[i]] <- if (!v %in% valid) {
      "no_variable"
    } else if (is.na(row_of[[i]])) {
      "no_record"
    } else if (n_rows[[i]] > 1L) {
      "ambiguous_record"
    } else if (n_values[[acc_cell[[i]]]] > 1L) {
      "accepted_disagree"
    } else if (is.na(a$expected_prior_missing)) {
      "prior_unknown"
    } else {
      cls <- class(base[[v]])[[1]]
      cur <- base[[v]][[row_of[[i]]]]
      prior <- if (a$expected_prior_missing == 1L) NA else parse_value(a$expected_prior, cls)
      new <- if (a$new_value_missing == 1L) NA else parse_value(a$new_value, cls)
      if ((a$expected_prior_missing == 0L && is.na(prior)) ||
            (a$new_value_missing == 0L && is.na(new))) {
        "does_not_cast"
      } else if (a$expected_prior_missing == 1L && !is.na(cur)) {
        if (a$new_value_missing == 0L && isTRUE(cur == new)) {
          "filled_upstream_agrees"
        } else {
          "filled_upstream_disagrees"
        }
      } else if (a$expected_prior_missing == 0L && (is.na(cur) || !isTRUE(cur == prior))) {
        "prior_mismatch"
      } else {
        "apply"
      }
    }
  }
  data <- base
  for (i in which(status == "apply")) {
    v <- acc$variable[[i]]
    data[[v]][[row_of[[i]]]] <- if (acc$new_value_missing[[i]] == 1L) {
      NA
    } else {
      parse_value(acc$new_value[[i]], class(base[[v]])[[1]])
    }
  }
  pick <- function(keep, cols) {
    out <- acc[keep, c("correction_id", key, "variable"), drop = FALSE]
    out$reason <- status[keep]
    rownames(out) <- NULL
    out[cols]
  }
  list(data = data,
       applied = pick(status == "apply", c("correction_id", key)),
       stale = pick(status %in% SOURCE_STALE, c("correction_id", "variable", "reason")),
       conflicts = pick(status %in% SOURCE_CONFLICT,
                        c("correction_id", "variable", "reason")))
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::test(filter = "source-corrections-sql")'`
Expected: PASS, 4 tests.

- [ ] **Step 6: Commit**

```bash
git add R/source_corrections_sql.R tests/testthat/helper-source-corrections.R \
  tests/testthat/test-source-corrections-sql.R
git commit -m "feat: per-source corrections tables and the R reference resolver"
```

---

### Task 3: generated views over every column

**Files:**
- Modify: `R/source_corrections_sql.R` (append)
- Test: `tests/testthat/test-source-corrections-sql.R` (append)

**Interfaces:**
- Consumes: Task 2, plus `view_header()`, `sql_string()` and `.string_eq_sql()`
  (`R/corrections_sql.R:201`).
- Produces: `source_views_sql(source, key, types, dialect)`, a named character vector
  (`corrected`, `applied`, `stale`, `conflicts`) of `CREATE ... VIEW` statements with no
  trailing semicolon. `types` is the full `table_types()` of the source, keys included.

These views are why §3.3 says a first correction needs no deployment. The corrected view
covers every non-key column from the start, through one join to a pivot of the applied
corrections. A cell with no correction is a `LEFT JOIN` miss.

- [ ] **Step 1: Write the failing tests** (append)

```r
test_that("the generated views agree with the R reference on every rule", {
  con <- local_sources_db()
  deploy_echo(con)
  key <- c("mrn", "encounter_date")
  base <- DBI::dbGetQuery(con, "SELECT * FROM stg_echo ORDER BY mrn")
  ref <- resolve_source_corrections(base, case_corrections(), case_decisions(), key)
  srt <- function(d) {
    d <- d[do.call(order, unname(as.list(d))), , drop = FALSE]
    rownames(d) <- NULL
    d
  }
  expect_equal(DBI::dbGetQuery(con, "SELECT * FROM stg_echo_corrected ORDER BY mrn"),
               ref$data, ignore_attr = TRUE)
  expect_equal(srt(DBI::dbGetQuery(con, "SELECT * FROM stg_echo_corrections_applied")),
               srt(ref$applied), ignore_attr = TRUE)
  expect_equal(srt(DBI::dbGetQuery(con, "SELECT * FROM stg_echo_corrections_stale")),
               srt(ref$stale), ignore_attr = TRUE)
  expect_equal(srt(DBI::dbGetQuery(con, "SELECT * FROM stg_echo_corrections_conflicts")),
               srt(ref$conflicts), ignore_attr = TRUE)
})

test_that("a first correction to an untouched column is live with no redeployment", {
  con <- local_sources_db()
  deploy_echo(con, case_corrections()[0, ], case_decisions()[0, ])
  before <- DBI::dbGetQuery(con, "SELECT * FROM stg_echo_corrected ORDER BY mrn")
  expect_identical(before$seen_on, DBI::dbGetQuery(con, "SELECT seen_on FROM stg_echo
                                                     ORDER BY mrn")$seen_on)
  DBI::dbAppendTable(con, "stg_echo_corrections",
                     corr_row("c50", "SYN202", "2020-02-01", "seen_on", NA, 1L,
                              "2020-01-15", 0L))
  DBI::dbAppendTable(con, "stg_echo_correction_decisions", dec_row("d50", "c50"))
  after <- DBI::dbGetQuery(con, "SELECT seen_on FROM stg_echo_corrected ORDER BY mrn")
  expect_identical(after$seen_on[[2]], as.Date("2020-01-15"))
})

test_that("the corrected view keeps the source's columns, order and types", {
  con <- local_sources_db()
  deploy_echo(con)
  expect_identical(table_types(con, "stg_echo_corrected"), table_types(con, "stg_echo"))
})

test_that("a supersede decision settles a G1 conflict", {
  con <- local_sources_db()
  decisions <- rbind(case_decisions(),
                     dec_row("d70", "c04", "supersede", on = "2026-04-01"))
  deploy_echo(con, decisions = decisions)
  got <- DBI::dbGetQuery(con, "SELECT lvef FROM stg_echo_corrected WHERE mrn = 'SYN203'")
  expect_identical(got$lvef, 41)
  conflicts <- DBI::dbGetQuery(con, "SELECT correction_id FROM stg_echo_corrections_conflicts")
  expect_false(any(c("c03", "c04") %in% conflicts$correction_id))
})

test_that("a key duplicated after acceptance changes no row, in SQL and in R", {
  con <- local_sources_db()
  deploy_echo(con)
  DBI::dbExecute(con, paste("INSERT INTO stg_echo VALUES",
                            "('SYN201', DATE '2020-01-01', 30, '2', NULL)"))
  got <- DBI::dbGetQuery(con, "SELECT lvef, mr_grade FROM stg_echo_corrected
                               WHERE mrn = 'SYN201'")
  expect_identical(got$lvef, c(30, 30))           # c01 no longer applies to either row
  expect_identical(got$mr_grade, c("2", "2"))     # nor do c05 and c06
  expect_identical(nrow(DBI::dbGetQuery(con, "SELECT * FROM stg_echo_corrected")), 6L)
  stale <- DBI::dbGetQuery(con, "SELECT * FROM stg_echo_corrections_stale")
  expect_setequal(stale$correction_id[stale$reason == "ambiguous_record"],
                  c("c01", "c05", "c06"))
  ref <- resolve_source_corrections(DBI::dbGetQuery(con, "SELECT * FROM stg_echo"),
                                    case_corrections(), case_decisions(),
                                    c("mrn", "encounter_date"))
  expect_setequal(ref$stale$correction_id[ref$stale$reason == "ambiguous_record"],
                  c("c01", "c05", "c06"))
  expect_false(any(c("c01", "c05", "c06") %in% ref$applied$correction_id))
})
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "source-corrections-sql")'`
Expected: FAIL with `could not find function "source_views_sql"`.

- [ ] **Step 3: Implement** (append to `R/source_corrections_sql.R`)

```r
#' The `checked` CTE: every accepted correction with its status
#'
#' Shared by the four views, so they cannot disagree. The per-variable checks are one
#' `CASE` on the variable's name with a branch per non-key column, each casting through
#' that column's own SQL type.
#'
#' @param source Character. The source view's name.
#' @param key Character. Its key columns.
#' @param types A named character vector of all its columns' SQL types.
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#'
#' @return A length-one character: `WITH ... checked AS (...)`.
#'
#' @keywords internal
#' @noRd
.checked_cte <- function(source, key, types, dialect) {
  q <- quoter(dialect)
  tabs <- .source_tables(source)
  valid <- setdiff(names(types), key)
  # SQL Server's default collation would count "Yes" and "yes" as one value.
  distinct_value <- if (identical(dialect, "mssql")) {
    "new_value COLLATE Latin1_General_BIN2"
  } else {
    "new_value"
  }
  per_var <- vapply(valid, function(v) {
    b <- paste0("b.", q(v))
    prior <- sprintf("TRY_CAST(a.expected_prior AS %s)", types[[v]])
    new <- sprintf("TRY_CAST(a.new_value AS %s)", types[[v]])
    paste0(
      "WHEN ", sql_string(v), " THEN CASE",
      " WHEN (a.expected_prior_missing = 0 AND ", prior, " IS NULL)",
      " OR (a.new_value_missing = 0 AND ", new, " IS NULL) THEN 'does_not_cast'",
      " WHEN a.expected_prior_missing = 1 AND ", b, " IS NOT NULL THEN CASE",
      " WHEN a.new_value_missing = 0 AND ", .string_eq_sql(b, new, types[[v]], dialect),
      " THEN 'filled_upstream_agrees' ELSE 'filled_upstream_disagrees' END",
      " WHEN a.expected_prior_missing = 0 AND (", b, " IS NULL OR NOT (",
      .string_eq_sql(b, prior, types[[v]], dialect), ")) THEN 'prior_mismatch'",
      " ELSE 'apply' END"
    )
  }, character(1))
  on_b <- paste(sprintf("b.%s = a.%s", q(key), q(key)), collapse = " AND ")
  on_bc <- paste(sprintf("bc.%s = a.%s", q(key), q(key)), collapse = " AND ")
  on_k <- paste(c(sprintf("k.%s = a.%s", q(key), q(key)), "k.variable = a.variable"),
                collapse = " AND ")
  keys <- paste(q(key), collapse = ", ")
  paste0(
    "WITH latest AS (\n",
    "  SELECT correction_id, decision,\n",
    "         ROW_NUMBER() OVER (PARTITION BY correction_id\n",
    "                            ORDER BY decided_on DESC, decision_id DESC) AS rn\n",
    "  FROM ", q(tabs$decisions), "\n",
    "), accepted AS (\n",
    "  SELECT c.* FROM ", q(tabs$corrections), " c\n",
    "  JOIN latest l ON l.correction_id = c.correction_id\n",
    "  WHERE l.rn = 1 AND l.decision = 'accept'\n",
    "), cell AS (\n",
    "  SELECT ", keys, ", variable,\n",
    "         COUNT(DISTINCT CASE WHEN new_value_missing = 1 THEN NULL ELSE ",
    distinct_value, " END)\n",
    "         + MAX(new_value_missing) AS n_values\n",
    "  FROM accepted GROUP BY ", keys, ", variable\n",
    # Source rows per key now: a refresh can break uniqueness after a correction is accepted.
    "), bc AS (\n",
    "  SELECT ", keys, ", COUNT(*) AS n_rows FROM ", q(source), " GROUP BY ", keys, "\n",
    "), checked AS (\n",
    "  SELECT a.*, CASE\n",
    "    WHEN a.variable NOT IN (", paste(sql_string(valid), collapse = ", "),
    ") THEN 'no_variable'\n",
    "    WHEN bc.n_rows IS NULL THEN 'no_record'\n",
    "    WHEN bc.n_rows > 1 THEN 'ambiguous_record'\n",
    "    WHEN k.n_values > 1 THEN 'accepted_disagree'\n",
    "    WHEN a.expected_prior_missing IS NULL THEN 'prior_unknown'\n",
    "    ELSE CASE a.variable\n      ", paste(per_var, collapse = "\n      "),
    "\n    END END AS status\n",
    "  FROM accepted a\n",
    "  LEFT JOIN bc ON ", on_bc, "\n",
    # Joined only on a unique key, so a duplicated key never fans a correction out.
    "  LEFT JOIN ", q(source), " b ON ", on_b, " AND bc.n_rows = 1\n",
    "  JOIN cell k ON ", on_k, "\n",
    ")\n"
  )
}

#' The four generated views for one source
#'
#' `<source>_corrected` is the source with every applying correction in place. It covers
#' every non-key column, so a first correction to a column needs no redeployment (spec
#' §3.3). `_corrections_applied` lists `correction_id` and the key of each correction
#' applied, which plan 3 rolls up to the master. `_corrections_stale` and
#' `_corrections_conflicts` are for data management and are never read by a study build.
#'
#' @param source Character. The source view's name.
#' @param key Character. Its key columns.
#' @param types A named character vector of all its columns' SQL types, from
#'   `table_types()`.
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#'
#' @return A named character vector (`corrected`, `applied`, `stale`, `conflicts`).
#'
#' @keywords internal
#' @noRd
source_views_sql <- function(source, key, types, dialect = "mssql") {
  q <- quoter(dialect)
  tabs <- .source_tables(source)
  valid <- setdiff(names(types), key)
  stopifnot(all(key %in% names(types)), length(valid) > 0L)
  cte <- .checked_cte(source, key, types, dialect)
  keys <- paste(q(key), collapse = ", ")
  pivot <- unlist(lapply(seq_along(valid), function(i) {
    w <- sprintf("WHEN variable = %s THEN", sql_string(valid[[i]]))
    c(sprintf("MAX(CASE %s 1 END) AS h%d", w, i),
      sprintf("MAX(CASE %s new_value_missing END) AS m%d", w, i),
      sprintf("MAX(CASE %s new_value END) AS v%d", w, i))
  }))
  # Columns in the source's own order, keys included, so the view's shape is the source's.
  select <- vapply(names(types), function(v) {
    if (v %in% key) return(paste0("b.", q(v)))
    i <- match(v, valid)
    sprintf(paste("CASE WHEN p.h%1$d = 1 THEN CASE WHEN p.m%1$d = 1 THEN NULL",
                  "ELSE TRY_CAST(p.v%1$d AS %2$s) END ELSE b.%3$s END AS %3$s"),
            i, types[[v]], q(v))
  }, character(1))
  on_p <- paste(sprintf("p.%s = b.%s", q(key), q(key)), collapse = " AND ")
  corrected <- paste0(
    view_header(dialect), " ", q(tabs$corrected), " AS\n", cte,
    ", p AS (\n  SELECT ", keys, ",\n    ", paste(pivot, collapse = ",\n    "),
    "\n  FROM checked WHERE status = 'apply' GROUP BY ", keys, "\n)\n",
    "SELECT\n  ", paste(select, collapse = ",\n  "), "\n",
    "FROM ", q(source), " b\nLEFT JOIN p ON ", on_p
  )
  listed <- function(view, statuses, cols) {
    paste0(view_header(dialect), " ", q(view), " AS\n", cte,
           "SELECT ", cols, " FROM checked WHERE status IN (",
           paste(sql_string(statuses), collapse = ", "), ")")
  }
  c(corrected = corrected,
    applied = listed(tabs$applied, "apply", paste0("correction_id, ", keys)),
    stale = listed(tabs$stale, SOURCE_STALE, "correction_id, variable, status AS reason"),
    conflicts = listed(tabs$conflicts, SOURCE_CONFLICT,
                       "correction_id, variable, status AS reason"))
}
```

  The pivot holds at most one applying value per cell: agreeing corrections share one
  canonical `new_value` (decision 3), so `MAX` picks that value. Verified on duckdb 2.0.0
  while this plan was written. The case matrix's corrected data and its applied, stale and
  conflict lists all matched the R reference.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::test(filter = "source-corrections-sql")'`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add R/source_corrections_sql.R tests/testthat/test-source-corrections-sql.R
git commit -m "feat: generated corrected, applied, stale and conflicts views per source"
```

---

### Task 4: `generate_corrections_sql()` and `write_corrections_template()`

**Files:**
- Create: `R/source_corrections.R`
- Test: `tests/testthat/test-propose-corrections.R` (new; the template tests)

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
  - `.corrections_statements(config, con, dialect)`: a named list, one element per source,
    each `list(tables = <chr>, views = <chr>)`.
  - `generate_corrections_sql(config, con, dir, dialect = "mssql")` (exported): writes
    `<source>.tables.sql` and `<source>.views.sql` per source, with statements separated
    by `GO` lines. Returns the paths invisibly.
  - `.template_columns(config)`: the template's column names.
  - `write_corrections_template(config, path)` (exported): returns `path` invisibly.

- [ ] **Step 1: Write the failing tests** `tests/testthat/test-propose-corrections.R`

```r
# No PHI: identifiers and values are invented.

test_that("the generated SQL creates every object, with GO between statements", {
  con <- local_sources_db()
  cfg <- corrections_config()
  dir <- withr::local_tempdir()
  paths <- generate_corrections_sql(cfg, con, dir, dialect = "duckdb")
  expect_setequal(basename(paths), c("stg_echo.tables.sql", "stg_echo.views.sql",
                                     "stg_patient.tables.sql", "stg_patient.views.sql"))
  for (p in paths[grepl("tables", paths)]) {
    for (s in strsplit(paste(readLines(p), collapse = "\n"), "\nGO\n?")[[1]]) {
      DBI::dbExecute(con, s)
    }
  }
  for (p in paths[grepl("views", paths)]) {
    for (s in strsplit(paste(readLines(p), collapse = "\n"), "\nGO\n?")[[1]]) {
      DBI::dbExecute(con, s)
    }
  }
  expect_true(DBI::dbExistsTable(con, "stg_patient_corrected"))
  expect_identical(nrow(DBI::dbGetQuery(con, "SELECT * FROM stg_echo_corrections_stale")), 0L)
})

test_that("an undeclared or keyless source stops generation", {
  con <- local_sources_db()
  cfg <- corrections_config()
  cfg$sources$stg_missing <- list(key = "mrn")
  expect_error(generate_corrections_sql(cfg, con, withr::local_tempdir(), "duckdb"),
               class = "hvtiRdatabuild_unknown_source")
  cfg <- corrections_config()
  cfg$sources$stg_echo$key <- c("mrn", "no_such_column")
  expect_error(generate_corrections_sql(cfg, con, withr::local_tempdir(), "duckdb"),
               class = "hvtiRdatabuild_unknown_key_column")
})

test_that("the template has one column per declared key, and is never overwritten", {
  cfg <- corrections_config()
  path <- withr::local_tempfile(fileext = ".csv")
  write_corrections_template(cfg, path)
  expect_identical(names(utils::read.csv(path, check.names = FALSE)),
                   c("source", "mrn", "encounter_date", "variable", "expected_prior",
                     "expected_prior_missing", "new_value", "new_value_missing",
                     "evidence_type", "evidence_ref", "asserted_by"))
  expect_error(write_corrections_template(cfg, path), class = "hvtiRdatabuild_file_exists")
})
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "propose-corrections")'`
Expected: FAIL with `could not find function "generate_corrections_sql"`.

- [ ] **Step 3: Implement** `R/source_corrections.R`

```r
# source_corrections.R
#
# Interim correction intake (spec §3.4, §3.5): generating each source's correction
# objects, the submission template, batch proposal and decision, and retiring fill-ins
# that upstream has caught up with. Superseded by the HVTR registry's intake, which takes
# the template and the tables over unchanged. Output is counts, verdicts, column and
# source names, correction ids and template row numbers; never a key or a value.

# Who records a G7 retirement. Not a person, so it can never be in `deciders`.
FILLED_UPSTREAM_DECIDER <- "filled_upstream" # nolint: object_name_linter.

#' Each declared source's correction statements
#'
#' @param config A `master_config`.
#' @param con A DBI connection that can see the source views.
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#'
#' @return A named list, one element per source: `list(tables = , views = )`.
#'
#' @keywords internal
#' @noRd
.corrections_statements <- function(config, con, dialect) {
  if (!length(config$sources)) {
    .abort("no_sources", "generate_corrections_sql(): master.yml declares no sources.")
  }
  stats::setNames(lapply(names(config$sources), function(s) {
    types <- run_step("read source columns", table_types(con, s))
    if (!length(types)) {
      .abort("unknown_source", "generate_corrections_sql(): source ", s,
             " is not in the warehouse.")
    }
    key <- config$sources[[s]]$key
    if (!all(key %in% names(types))) {
      .abort("unknown_key_column", "generate_corrections_sql(): source ", s,
             " has no column(s) ", paste(setdiff(key, names(types)), collapse = ", "), ".")
    }
    list(tables = unname(source_corrections_ddl(s, types[key], dialect)),
         views = unname(source_views_sql(s, key, types, dialect)))
  }), names(config$sources))
}

#' Generate the correction tables and views for a master's sources
#'
#' Writes, for each source declared in `master.yml`, a `<source>.tables.sql` file that
#' creates its corrections and decisions tables once, and a `<source>.views.sql` file that
#' creates or replaces its four views:
#'
#' - `<source>_corrected`: the source with accepted corrections applied, covering every
#'   column, so a first correction to a column is live with no redeployment.
#' - `<source>_corrections_applied`: which correction applied to which row.
#' - `<source>_corrections_stale` and `<source>_corrections_conflicts`: for data
#'   management.
#'
#' Statements are separated by `GO` lines, as `sqlcmd` expects. Regenerate the views
#' whenever the source view's columns change. Data engineering deploys the files.
#'
#' **Interim.** Superseded by the HVTR registry, which takes over the tables unchanged.
#'
#' @param config A `master_config` from [read_master_config()], with `sources`.
#' @param con A DBI connection that can see the source views.
#' @param dir Character. An existing directory to write the files into.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return The written paths, invisibly.
#'
#' @seealso [propose_corrections()], [decide_corrections()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   con <- DBI::dbConnect(duckdb::duckdb())
#'   DBI::dbWriteTable(con, "stg_demo", data.frame(mrn = "SYN1", lvef = 30))
#'   cfg_path <- tempfile(fileext = ".yml")
#'   writeLines(c("name: master_demo", "key: [mrn]", "snapshots: .",
#'                "current: x.sas7bdat", "build_program: x.sas",
#'                "sources:", "  stg_demo: {key: [mrn]}"), cfg_path)
#'   generate_corrections_sql(read_master_config(cfg_path), con, tempdir(),
#'                            dialect = "duckdb")
#'   DBI::dbDisconnect(con, shutdown = TRUE)
#' }
#' }
#'
#' @export
generate_corrections_sql <- function(config, con, dir, dialect = "mssql") {
  if (!dir.exists(dir)) {
    .abort("no_directory", "generate_corrections_sql(): `dir` does not exist.")
  }
  st <- .corrections_statements(config, con, dialect)
  paths <- unlist(lapply(names(st), function(s) {
    p <- file.path(dir, paste0(s, c(".tables.sql", ".views.sql")))
    writeLines(paste(st[[s]]$tables, collapse = "\nGO\n"), p[[1]])
    writeLines(paste(st[[s]]$views, collapse = "\nGO\n"), p[[2]])
    p
  }))
  .hvti_inform("Wrote correction SQL for ", length(st), " source(s).")
  invisible(paths)
}

#' The submission template's columns
#'
#' @param config A `master_config` with `sources`.
#'
#' @return A character vector.
#'
#' @keywords internal
#' @noRd
.template_columns <- function(config) {
  keys <- unique(unlist(lapply(config$sources, `[[`, "key"), use.names = FALSE))
  c("source", keys, "variable", "expected_prior", "expected_prior_missing", "new_value",
    "new_value_missing", "evidence_type", "evidence_ref", "asserted_by")
}

#' Write an empty correction submission template
#'
#' One row per cell. `source` is a source view declared in `master.yml`. The key columns
#' are the union of every source's declared key. A row fills exactly its own source's key
#' and leaves the others blank: a patient-level source's rows carry no encounter date.
#' `expected_prior_missing` and `new_value_missing` are `0` or `1`, and a value column is
#' blank exactly when its flag is `1`.
#'
#' The filled template holds identifiers. Keep it under the same rules as study data, and
#' never commit it to a repository.
#'
#' **Interim.** Superseded by the HVTR registry, which takes over the template.
#'
#' @param config A `master_config` from [read_master_config()], with `sources`.
#' @param path Character. Where to write the CSV. An existing file is never overwritten.
#'
#' @return `path`, invisibly.
#'
#' @seealso [propose_corrections()]
#'
#' @examples
#' cfg_path <- tempfile(fileext = ".yml")
#' writeLines(c("name: master_demo", "key: [mrn]", "snapshots: .",
#'              "current: x.sas7bdat", "build_program: x.sas",
#'              "sources:", "  stg_demo: {key: [mrn]}"), cfg_path)
#' write_corrections_template(read_master_config(cfg_path), tempfile(fileext = ".csv"))
#'
#' @export
write_corrections_template <- function(config, path) {
  if (file.exists(path)) {
    .abort("file_exists", "write_corrections_template(): the file already exists.")
  }
  cols <- .template_columns(config)
  empty <- as.data.frame(stats::setNames(rep(list(character()), length(cols)), cols),
                         check.names = FALSE)
  utils::write.csv(empty, path, row.names = FALSE)
  invisible(path)
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "propose-corrections")'`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add R/source_corrections.R tests/testthat/test-propose-corrections.R NAMESPACE man/
git commit -m "feat: generate_corrections_sql() and the submission template"
```

---

### Task 5: `propose_corrections()`

**Files:**
- Modify: `R/source_corrections.R` (append)
- Test: `tests/testthat/test-propose-corrections.R` (append)
- Modify: `tests/testthat/helper-source-corrections.R` (append the deploy-all helper)

**Interfaces:**
- Consumes: Tasks 1–4, plus `value_text()`, `parse_value()`, `EVIDENCE_TYPES`
  (`R/master_corrections.R:8`) and `.with_snapshot_txn()` (`R/master_pull.R:10`).
- Produces: `propose_corrections(config, con, file, dry_run = TRUE, dialect = "mssql")`,
  which returns invisibly a list:
  - `verdicts`: a data frame of `row`, `source`, `verdict`.
  - `appended`: an integer.
  - `correction_ids`: a character vector.
  - `file_sha256`.

  The private helpers `.read_template(config, file)` and `.intake_temp(dialect, key_types)`
  are used only here.

The whole file is read once. Its SHA-256 and its rows both come from those same bytes, the
lesson of #114's review checksum. Verdicts are checked in this order:

1. `rule_not_fact`
2. `unknown_source`
3. `invalid_field`
4. `no_variable` or `derived_variable`
5. `unknown_key`
6. `ambiguous_key`
7. `does_not_cast`
8. `prior_mismatch`
9. `appendable`

The lookups and the append run in one snapshot transaction. A source value cannot change
between the prior check and the write.

- [ ] **Step 1: Write the helper** (append to `helper-source-corrections.R`)

```r
# Generate and deploy every declared source's correction objects.
deploy_sources <- function(con, cfg) {
  for (s in names(cfg$sources)) {
    st <- .corrections_statements(cfg, con, "duckdb")[[s]]
    for (x in c(st$tables, st$views)) DBI::dbExecute(con, x)
  }
  invisible(con)
}

# Write a filled template; `...` are its rows as named character vectors.
write_submission <- function(cfg, rows, env = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".csv", .local_envir = env)
  cols <- .template_columns(cfg)
  df <- do.call(rbind, lapply(rows, function(r) {
    out <- stats::setNames(as.list(rep(NA_character_, length(cols))), cols)
    out[names(r)] <- as.list(r)
    as.data.frame(out, check.names = FALSE, stringsAsFactors = FALSE)
  }))
  utils::write.csv(df, path, row.names = FALSE, na = "")
  path
}

good_row <- function(...) {
  r <- c(source = "stg_echo", mrn = "SYN201", encounter_date = "2020-01-01",
         variable = "lvef", expected_prior = "30", expected_prior_missing = "0",
         new_value = "35", new_value_missing = "0", evidence_type = "chart_review",
         evidence_ref = "invented note 1", asserted_by = "reviewer_a")
  over <- c(...)
  r[names(over)] <- over
  r
}
```

- [ ] **Step 2: Write the failing tests** (append to `test-propose-corrections.R`)

```r
propose_setup <- function(env = parent.frame()) {
  con <- local_sources_db(env)
  cfg <- corrections_config(env)
  deploy_sources(con, cfg)
  list(con = con, cfg = cfg)
}

test_that("a clean file is appendable on a dry run, and nothing is written", {
  s <- propose_setup()
  f <- write_submission(s$cfg, list(good_row(), good_row(
    source = "stg_patient", encounter_date = "", variable = "sex", expected_prior = "F",
    new_value = "M")))
  out <- propose_corrections(s$cfg, s$con, f, dialect = "duckdb")
  expect_identical(out$verdicts$verdict, c("appendable", "appendable"))
  expect_identical(out$appended, 0L)
  expect_identical(DBI::dbGetQuery(s$con, "SELECT COUNT(*) AS n FROM stg_echo_corrections")$n,
                   0)
  expect_match(out$file_sha256, "^[0-9a-f]{64}$")
})

test_that("every verdict is reached, and a bad row refuses the whole file", {
  s <- propose_setup()
  rows <- list(
    good_row(),                                                      # 1 appendable
    good_row(mrn = "SYN2*"),                                         # 2 rule_not_fact
    good_row(source = "stg_nowhere"),                                # 3 unknown_source
    good_row(evidence_type = "hunch"),                               # 4 invalid_field
    good_row(expected_prior_missing = "1"),                          # 5 invalid_field
    good_row(variable = "nosuch"),                                   # 6 no_variable
    good_row(variable = "mr_severe", expected_prior = "0", new_value = "1"),
                                                                     # 7 derived_variable
    good_row(mrn = "SYN299"),                                        # 8 unknown_key
    good_row(source = "stg_patient", variable = "sex", expected_prior = "F",
             new_value = "M"),                                       # 9 unknown_key
    good_row(variable = "seen_on", expected_prior = "2019-12-01",
             new_value = "not a date"),                              # 10 does_not_cast
    good_row(expected_prior = "31"),                                 # 11 prior_mismatch
    good_row(variable = "mrn", expected_prior = "SYN201", new_value = "SYN209")
                                                                     # 12 no_variable (key)
  )
  f <- write_submission(s$cfg, rows)
  out <- propose_corrections(s$cfg, s$con, f, dialect = "duckdb")
  expect_identical(out$verdicts$verdict, c(
    "appendable", "rule_not_fact", "unknown_source", "invalid_field", "invalid_field",
    "no_variable", "derived_variable", "unknown_key", "unknown_key", "does_not_cast",
    "prior_mismatch", "no_variable"))
  expect_error(propose_corrections(s$cfg, s$con, f, dry_run = FALSE, dialect = "duckdb"),
               class = "hvtiRdatabuild_corrections_refused")
  expect_identical(DBI::dbGetQuery(s$con, "SELECT COUNT(*) AS n FROM stg_echo_corrections")$n,
                   0)
})

test_that("an appended file is canonical text and live once accepted", {
  s <- propose_setup()
  f <- write_submission(s$cfg, list(good_row(expected_prior = "30.0", new_value = "35.00")))
  out <- propose_corrections(s$cfg, s$con, f, dry_run = FALSE, dialect = "duckdb")
  expect_identical(out$appended, 1L)
  row <- DBI::dbGetQuery(s$con, "SELECT * FROM stg_echo_corrections")
  expect_identical(c(row$expected_prior, row$new_value), c("30", "35"))
  expect_identical(row$asserted_by, "reviewer_a")
  DBI::dbAppendTable(s$con, "stg_echo_correction_decisions",
                     dec_row("d1", out$correction_ids[[1]]))
  got <- DBI::dbGetQuery(s$con, "SELECT lvef FROM stg_echo_corrected WHERE mrn = 'SYN201'")
  expect_identical(got$lvef, 35)
})

test_that("no value or key reaches a message", {
  s <- propose_setup()
  f <- write_submission(s$cfg, list(good_row(expected_prior = "31")))
  msgs <- testthat::capture_messages(
    try(propose_corrections(s$cfg, s$con, f, dry_run = FALSE, dialect = "duckdb"),
        silent = TRUE)
  )
  err <- tryCatch(propose_corrections(s$cfg, s$con, f, dry_run = FALSE, dialect = "duckdb"),
                  error = conditionMessage)
  for (text in c(msgs, err)) {
    expect_false(grepl("SYN201|2020-01-01|31|35", text))
  }
})

test_that("a value the column would round or overflow does not cast; booleans do", {
  s <- propose_setup()
  DBI::dbExecute(s$con, paste("CREATE TABLE stg_lab (mrn VARCHAR, encounter_date DATE,",
                              "potassium DECIMAL(4,1), on_pump BOOLEAN, n_grafts SMALLINT)"))
  DBI::dbExecute(s$con, "INSERT INTO stg_lab VALUES ('SYN201', DATE '2020-01-01', 4.1, TRUE, 3)")
  s$cfg$sources$stg_lab <- list(key = c("mrn", "encounter_date"))
  lab <- function(...) good_row(source = "stg_lab", ...)
  f <- write_submission(s$cfg, list(
    lab(variable = "potassium", expected_prior = "4.1", new_value = "4.25"),  # rounds
    lab(variable = "potassium", expected_prior = "4.1", new_value = "4.2"),
    lab(variable = "on_pump", expected_prior = "TRUE", new_value = "0"),
    lab(variable = "n_grafts", expected_prior = "3", new_value = "70000")    # overflows
  ))
  out <- propose_corrections(s$cfg, s$con, f, dialect = "duckdb")
  expect_identical(out$verdicts$verdict,
                   c("does_not_cast", "appendable", "appendable", "does_not_cast"))
})

test_that("keys and values are kept verbatim; only structural fields are trimmed", {
  s <- propose_setup()
  DBI::dbExecute(s$con, "UPDATE stg_echo SET mr_grade = ' 2' WHERE mrn = 'SYN201'")
  f <- write_submission(s$cfg, list(
    good_row(variable = " mr_grade ", expected_prior = " 2", new_value = "3"),
    good_row(variable = "mr_grade", expected_prior = "2", new_value = "3")))
  out <- propose_corrections(s$cfg, s$con, f, dialect = "duckdb")
  expect_identical(out$verdicts$verdict, c("appendable", "prior_mismatch"))
})

test_that("an empty string and significant spaces survive intake into the view", {
  s <- propose_setup()
  f <- write_submission(s$cfg, list(
    good_row(variable = "mr_grade", expected_prior = "2", new_value = ""),
    good_row(mrn = "SYN203", encounter_date = "2020-03-01", variable = "mr_grade",
             expected_prior = "1", new_value = "  3 ")))
  out <- propose_corrections(s$cfg, s$con, f, dry_run = FALSE, dialect = "duckdb")
  expect_identical(out$appended, 2L)
  stored <- DBI::dbGetQuery(s$con, paste("SELECT new_value, new_value_missing FROM",
                                         "stg_echo_corrections ORDER BY mrn"))
  expect_identical(stored$new_value, c("", "  3 "))
  expect_identical(stored$new_value_missing, c(0L, 0L))
  DBI::dbAppendTable(s$con, "stg_echo_correction_decisions",
                     rbind(dec_row("d1", out$correction_ids[[1]]),
                           dec_row("d2", out$correction_ids[[2]])))
  got <- DBI::dbGetQuery(s$con, paste("SELECT mr_grade FROM stg_echo_corrected",
                                      "WHERE mrn IN ('SYN201', 'SYN203') ORDER BY mrn"))
  expect_identical(got$mr_grade, c("", "  3 "))
})

test_that("a template with the wrong columns is refused before any row is read", {
  s <- propose_setup()
  f <- withr::local_tempfile(fileext = ".csv")
  writeLines("source,mrn,variable", f)
  expect_error(propose_corrections(s$cfg, s$con, f, dialect = "duckdb"),
               class = "hvtiRdatabuild_template_columns")
})
```

- [ ] **Step 3: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "propose-corrections")'`
Expected: FAIL with `could not find function "propose_corrections"`.

- [ ] **Step 4: Implement** (append to `R/source_corrections.R`)

```r
#' Read a submission file once: its rows and the SHA-256 of the same bytes
#'
#' @param config A `master_config` with `sources`.
#' @param file Character. The filled template.
#'
#' @return A list: `rows` (a character data frame, blanks as `NA`) and `sha256`.
#'
#' @keywords internal
#' @noRd
.read_template <- function(config, file) {
  if (!file.exists(file)) .abort("no_file", "propose_corrections(): `file` does not exist.")
  bytes <- readBin(file, "raw", file.size(file))
  sha <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
  # Nothing becomes NA on reading: the two value columns are kept exactly as written, and
  # their flags, not an empty cell, say whether a value is missing.
  rows <- utils::read.csv(text = rawToChar(bytes), colClasses = "character",
                          na.strings = character(), check.names = FALSE)
  if (!identical(names(rows), .template_columns(config))) {
    .abort("template_columns", "propose_corrections(): the file's columns are not the ",
           "template's. Start from write_corrections_template().")
  }
  # Trim only the structural fields. Keys and values stay verbatim: a prior of " A" is not
  # "A", and parse_value()/value_text() preserve character text. Outside the two value
  # columns an empty cell is missing; inside them an empty cell is an empty string unless
  # its flag says missing, so "" and "   " are both representable.
  structural <- c("source", "variable", "expected_prior_missing", "new_value_missing",
                  "evidence_type", "asserted_by")
  rows[structural] <- lapply(rows[structural], trimws)
  other <- setdiff(names(rows), c("expected_prior", "new_value"))
  rows[other] <- lapply(rows[other], function(x) {
    x[!nzchar(x)] <- NA_character_
    x
  })
  list(rows = rows, sha256 = sha)
}

#' The intake key temp table for one source
#'
#' @param dialect Character. `"mssql"` or `"duckdb"`.
#' @param key_types A named character vector of the source's key columns' SQL types.
#'
#' @return A list: `name` and `create`.
#'
#' @keywords internal
#' @noRd
.intake_temp <- function(dialect, key_types) {
  q <- quoter(dialect)
  cols <- paste0(", ", q(names(key_types)), " ", key_types, collapse = "")
  switch(dialect,
         mssql = list(name = "#correction_intake",
                      create = paste0("CREATE TABLE #correction_intake (row_id int NOT NULL",
                                      cols, ")")),
         duckdb = list(name = "correction_intake",
                       create = paste0("CREATE TEMP TABLE correction_intake (row_id INTEGER",
                                       " NOT NULL", cols, ")")))
}

#' Propose a batch of corrections from a filled template
#'
#' Validates every row of a submission made from [write_corrections_template()] and returns
#' a verdict per row:
#'
#' - `appendable`: the row passed every check below.
#' - `rule_not_fact`: a key or the variable holds a pattern, a comparison, or "all".
#' - `unknown_source`: the source is not declared in `master.yml`.
#' - `invalid_field`: a flag is not 0 or 1 or disagrees with its value, the evidence type
#'   is unknown, or a required field is blank.
#' - `no_variable`: the source has no such column, or the column is a key.
#' - `derived_variable`: the column is the master's, derived from sources; correct the
#'   sources or change the derivation.
#' - `unknown_key`: the key is incomplete, carries another source's key column, or matches
#'   no row.
#' - `ambiguous_key`: the key matches more than one row.
#' - `does_not_cast`: a value is not of the column's type, or the warehouse's cast to the
#'   column's SQL type would round, overflow or truncate it. This last check runs after
#'   the prior check.
#' - `prior_mismatch`: the source no longer holds `expected_prior`.
#'
#' With `dry_run = FALSE`, an all-`appendable` file is appended in one transaction, and a
#' file with any other verdict is refused whole, with nothing written. Values are stored in
#' a canonical text form, so `"30.0"` and `"30"` are the same assertion. A proposed
#' correction applies only once accepted with [decide_corrections()].
#'
#' Output is verdicts and counts, never a key or a value.
#'
#' **Interim.** Superseded by the HVTR registry's intake, which takes over the template
#' and the tables unchanged. Replaces the deprecated [propose_correction()].
#'
#' @param config A `master_config` from [read_master_config()], with `sources`.
#' @param con A DBI connection to the warehouse.
#' @param file Character. The filled template, as CSV.
#' @param dry_run If `TRUE`, the default, validate only.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return Invisibly, a list: `verdicts` (a data frame of `row`, `source`, `verdict`),
#'   `appended` (an integer), `correction_ids` and `file_sha256`.
#'
#' @seealso [write_corrections_template()], [decide_corrections()]
#'
#' @examples
#' # See the "Corrections" section of the package reference; the round trip needs a
#' # warehouse connection with the source views.
#'
#' @export
propose_corrections <- function(config, con, file, dry_run = TRUE, dialect = "mssql") {
  if (!requireNamespace("digest", quietly = TRUE)) {
    .abort("needs_digest", "propose_corrections(): needs the digest package.")
  }
  tpl <- .read_template(config, file)
  rows <- tpl$rows
  n <- nrow(rows)
  verdict <- rep(NA_character_, n)
  # Give rows `i` (logical, or integer positions) verdict `v` unless they already have one,
  # so each row keeps the first verdict it earns.
  set <- function(i, v) {
    if (!is.logical(i)) i <- seq_len(n) %in% i
    verdict[i & is.na(verdict)] <<- v
  }
  keys_all <- unique(unlist(lapply(config$sources, `[[`, "key"), use.names = FALSE))

  # Checks that need no database.
  pattern <- "[*%?<>=,;]|^(all|any)$"
  ruled <- Reduce(`|`, lapply(c(keys_all, "variable"), function(k) {
    !is.na(rows[[k]]) & grepl(pattern, rows[[k]], ignore.case = TRUE)
  }))
  set(ruled, "rule_not_fact")
  set(!rows$source %in% names(config$sources), "unknown_source")
  # A flag is 0 or 1, and a missing value (flag 1) leaves its cell empty. With flag 0 any
  # text is the value, the empty string included.
  flag_ok <- function(f, value) {
    f %in% c("0", "1") & (f %in% "0" | !nzchar(value))
  }
  bad <- is.na(rows$variable) | is.na(rows$evidence_ref) | is.na(rows$asserted_by) |
    !rows$evidence_type %in% setdiff(EVIDENCE_TYPES, "legacy_sas_inline") |
    !flag_ok(rows$expected_prior_missing, rows$expected_prior) |
    !flag_ok(rows$new_value_missing, rows$new_value)
  set(bad, "invalid_field")
  rows$expected_prior[rows$expected_prior_missing %in% "1"] <- NA_character_
  rows$new_value[rows$new_value_missing %in% "1"] <- NA_character_

  master_cols <- names(run_step("read master columns", table_types(con, config$name)))
  out_rows <- list()
  now <- Sys.time()
  write_all <- function() {
    for (s in intersect(names(config$sources), rows$source[is.na(verdict)])) {
      idx <- which(rows$source == s & is.na(verdict))
      key <- config$sources[[s]]$key
      types <- run_step("read source columns", table_types(con, s))
      proto <- run_step("read source types", DBI::dbGetQuery(
        con, paste("SELECT * FROM", quoter(dialect)(s), "WHERE 1 = 0")
      ))
      var <- rows$variable[idx]
      in_source <- var %in% setdiff(names(types), key)
      set(idx[!in_source & var %in% setdiff(master_cols, names(types))], "derived_variable")
      set(idx[!in_source], "no_variable")

      # The key: exactly this source's columns, each parsing to its column's type.
      other <- setdiff(keys_all, key)
      typed <- lapply(key, function(k) {
        cls <- class(proto[[k]])[[1]]
        vapply(rows[[k]][idx], function(x) {
          if (is.na(x)) return(NA_character_)
          # as.POSIXct() errors on text it cannot read; that is an unknown key, not a crash.
          tryCatch(value_text(parse_value(x, cls)), error = function(e) NA_character_)
        }, character(1), USE.NAMES = FALSE)
      })
      names(typed) <- key
      incomplete <- Reduce(`|`, lapply(typed, is.na)) |
        (if (length(other)) Reduce(`|`, lapply(other, function(k) !is.na(rows[[k]][idx])))
         else FALSE)
      set(idx[incomplete], "unknown_key")
      live <- idx[is.na(verdict[idx])]
      if (!length(live)) next

      tmp <- .intake_temp(dialect, types[key])
      run_step("create intake table", DBI::dbExecute(con, tmp$create))
      run_step("load intake keys", DBI::dbExecute(
        con, sprintf("INSERT INTO %s VALUES (%s)", tmp$name,
                     paste(rep("?", length(key) + 1L), collapse = ", ")),
        params = c(list(live), lapply(key, function(k) {
          parse_value_vec(typed[[k]][match(live, idx)], class(proto[[k]])[[1]])
        }))
      ))
      q <- quoter(dialect)
      wanted <- unique(rows$variable[live])
      found <- run_step("look up source rows", DBI::dbGetQuery(con, sprintf(
        "SELECT t.row_id, %s FROM %s t JOIN %s b ON %s",
        paste0("b.", q(wanted), collapse = ", "), tmp$name, q(s),
        paste(sprintf("b.%s = t.%s", q(key), q(key)), collapse = " AND ")
      )))
      run_step("drop intake table", DBI::dbExecute(con, paste("DROP TABLE", tmp$name)))
      hits <- tabulate(match(found$row_id, live), nbins = length(live))
      set(live[hits == 0L], "unknown_key")
      set(live[hits > 1L], "ambiguous_key")

      for (i in live[hits == 1L]) {
        v <- rows$variable[[i]]
        cls <- class(proto[[v]])[[1]]
        cur <- found[[v]][[match(i, found$row_id)]]
        parsed <- function(x) tryCatch(parse_value(x, cls), error = function(e) NA)
        prior <- if (rows$expected_prior_missing[[i]] == "1") NA else
          parsed(rows$expected_prior[[i]])
        new <- if (rows$new_value_missing[[i]] == "1") NA else parsed(rows$new_value[[i]])
        if ((rows$expected_prior_missing[[i]] == "0" && is.na(prior)) ||
              (rows$new_value_missing[[i]] == "0" && is.na(new))) {
          set(i, "does_not_cast")
          next
        }
        same <- if (is.na(prior)) is.na(cur) else
          !is.na(cur) && identical(value_text(cur), value_text(prior))
        if (!same) {
          set(i, "prior_mismatch")
          next
        }
        r <- data.frame(correction_id = NA_character_, source = s,
                        stringsAsFactors = FALSE)
        for (k in key) r[[k]] <- parse_value(typed[[k]][[match(i, idx)]],
                                             class(proto[[k]])[[1]])
        r$variable <- v
        r$expected_prior <- if (is.na(prior)) NA_character_ else value_text(prior)
        r$expected_prior_missing <- as.integer(rows$expected_prior_missing[[i]])
        r$new_value <- if (is.na(new)) NA_character_ else value_text(new)
        r$new_value_missing <- as.integer(rows$new_value_missing[[i]])
        r$evidence_type <- rows$evidence_type[[i]]
        r$evidence_ref <- rows$evidence_ref[[i]]
        r$asserted_by <- rows$asserted_by[[i]]
        r$asserted_on <- now
        r$correction_id <- paste0("c", substr(digest::digest(
          list(tpl$sha256, i, format(now, "%Y-%m-%d %H:%M:%OS6")), algo = "sha1"
        ), 1, 20))
        r$.row <- i
        out_rows[[length(out_rows) + 1L]] <<- r
      }

      # The warehouse's own cast decides, through the column's SQL type, so a value R
      # accepts but the column would round, overflow or truncate is refused here, not
      # discovered as a silently different value in the corrected view.
      mine <- out_rows[vapply(out_rows, `[[`, character(1), "source") == s]
      for (v in unique(vapply(mine, `[[`, character(1), "variable"))) {
        rv <- mine[vapply(mine, `[[`, character(1), "variable") == v]
        texts <- c(vapply(rv, `[[`, character(1), "expected_prior"),
                   vapply(rv, `[[`, character(1), "new_value"))
        rid <- rep(vapply(rv, `[[`, integer(1), ".row"), 2L)
        keep <- !is.na(texts)
        ok <- .casts_losslessly(con, texts[keep], types[[v]])
        set(unique(rid[keep][!ok]), "does_not_cast")
      }
      set(vapply(mine, `[[`, integer(1), ".row"), "appendable")
    }
    out_rows <<- out_rows[verdict[vapply(out_rows, `[[`, integer(1), ".row")] ==
                            "appendable"]
    out_rows <<- lapply(out_rows, function(r) r[setdiff(names(r), ".row")])
    stopifnot(!anyNA(verdict))
    if (dry_run || any(verdict != "appendable")) return(invisible(NULL))
    for (s in unique(vapply(out_rows, `[[`, character(1), "source"))) {
      batch <- do.call(rbind, out_rows[vapply(out_rows, `[[`, character(1), "source") == s])
      run_step("append corrections",
               DBI::dbAppendTable(con, .source_tables(s)$corrections, batch))
    }
    invisible(NULL)
  }
  .with_snapshot_txn(con, dialect, write_all())

  verdicts <- data.frame(row = seq_len(n), source = rows$source, verdict = verdict,
                         stringsAsFactors = FALSE)
  counts <- table(verdict)
  .hvti_inform("propose_corrections(): ",
               paste(sprintf("%s %d", names(counts), counts), collapse = ", "), ".")
  if (!dry_run && any(verdict != "appendable")) {
    .abort("corrections_refused", "propose_corrections(): the file was refused whole and ",
           "nothing was written: ", sum(verdict != "appendable"), " of ", n,
           " row(s) are not appendable. See the dry run's verdicts.")
  }
  ids <- vapply(out_rows, `[[`, character(1), "correction_id")
  invisible(list(verdicts = verdicts,
                 appended = if (dry_run) 0L else length(ids),
                 correction_ids = if (dry_run) character() else ids,
                 file_sha256 = tpl$sha256))
}

#' Which canonical texts the warehouse casts to a SQL type without loss
#'
#' Each text goes through `TRY_CAST(... AS type)` in the warehouse, the cast the generated
#' views use. A text passes when the cast succeeds and the result's canonical text is the
#' text itself: `1.239` into `decimal(10,2)` comes back `1.24` and fails, as does an
#' overflow (`NULL`) or a truncation. Batches of 500 keep under SQL Server's 2,100
#' parameters.
#'
#' @param con A DBI connection.
#' @param texts Character. Canonical texts, none missing.
#' @param type Character. The column's SQL type, from `table_types()`.
#'
#' @return A logical vector the length of `texts`.
#'
#' @keywords internal
#' @noRd
.casts_losslessly <- function(con, texts, type) {
  ok <- rep(FALSE, length(texts))
  for (start in seq(1L, length(texts), by = 500L)) {
    i <- start:min(start + 499L, length(texts))
    params <- vector("list", 2L * length(i))
    params[c(TRUE, FALSE)] <- as.list(i)
    params[c(FALSE, TRUE)] <- as.list(texts[i])
    got <- run_step("check casts", DBI::dbGetQuery(con, sprintf(
      "SELECT i, TRY_CAST(txt AS %s) AS x FROM (VALUES %s) AS t(i, txt)", type,
      paste(rep("(?, ?)", length(i)), collapse = ", ")
    ), params = params))
    x <- got$x[match(i, got$i)]
    ok[i] <- vapply(seq_along(i), function(j) {
      !is.na(x[[j]]) && identical(value_text(x[[j]]), texts[i][[j]])
    }, logical(1))
  }
  ok
}

#' Parse a vector of canonical texts to one class
#'
#' @param x Character. Canonical texts, possibly `NA`.
#' @param r_class Character. The target class.
#'
#' @return A vector of class `r_class`.
#'
#' @keywords internal
#' @noRd
parse_value_vec <- function(x, r_class) {
  out <- lapply(x, parse_value, r_class = r_class)
  do.call(c, out)
}
```

  ⚠️ Implementation notes for the executor:
  - **`parse_value_vec()` on dates and times.** Check it on `Date` and `POSIXct` vectors in
    a scratch session. `do.call(c, ...)` keeps the class, and keeps the time zone from R
    4.1 on, which this package's R 4.4 floor covers.
  - **Every row must end with a verdict.** Each row receives a verdict before the append,
    even when a source has no live rows. Rows of an undeclared source were set to
    `unknown_source` earlier. `stopifnot(!anyNA(verdict))` guards this.
  - **Temp tables under snapshot isolation.** On SQL Server, creating a `#` table inside a
    snapshot transaction needs rehearsing, as does plan 1's `#study_cohort`. That rehearsal
    is plan 3.
  - **Master columns from a view.** `table_types()` lists a view's columns on duckdb 2.0.0
    (verified while writing this plan). SQL Server's `INFORMATION_SCHEMA.COLUMNS` includes
    views too.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "propose-corrections")'`
Expected: PASS, 11 tests.

- [ ] **Step 6: Commit**

```bash
git add R/source_corrections.R tests/testthat/test-propose-corrections.R \
  tests/testthat/helper-source-corrections.R NAMESPACE man/
git commit -m "feat: propose_corrections() validates a whole submission, then appends it"
```

---

### Task 6: `decide_corrections()` and `retire_filled_corrections()`

**Files:**
- Modify: `R/source_corrections.R` (append)
- Test: `tests/testthat/test-decide-corrections.R` (new)

**Interfaces:**
- Consumes: Tasks 1–5, plus `DECISIONS` (`R/master_corrections.R:12`).
- Produces:
  - `decide_corrections(config, con, decisions, dry_run = TRUE, dialect = "mssql")`.
    `decisions` is a data frame with `source`, `correction_id`, `decision`, `decided_by`,
    and optionally `reason`. Returns invisibly a list: `verdicts` (a data frame of `row`,
    `verdict`) and `recorded`.
  - `retire_filled_corrections(config, con, source, dry_run = TRUE, dialect = "mssql")`.
    Returns invisibly a list: `correction_ids` and `recorded`.

- [ ] **Step 1: Write the failing tests** `tests/testthat/test-decide-corrections.R`

```r
# No PHI: identifiers and values are invented.

decide_setup <- function(env = parent.frame()) {
  con <- local_sources_db(env)
  cfg <- corrections_config(env)
  deploy_sources(con, cfg)
  DBI::dbAppendTable(con, "stg_echo_corrections", rbind(
    corr_row("c01", "SYN201", "2020-01-01", "lvef", "30", 0L, "35", 0L,
             asserted_by = "reviewer_a"),
    corr_row("c02", "SYN203", "2020-03-01", "lvef", "40", 0L, "41", 0L,
             asserted_by = "dm_two"),
    corr_row("c03", "SYN203", "2020-03-01", "mr_grade", NA, 1L, "1", 0L,
             asserted_by = "reviewer_a")
  ))
  list(con = con, cfg = cfg)
}

decisions_df <- function(...) {
  d <- data.frame(source = "stg_echo", correction_id = "c01", decision = "accept",
                  decided_by = "dm_one", reason = "chart confirms",
                  stringsAsFactors = FALSE)
  over <- list(...)
  d[names(over)] <- over
  d
}

test_that("an accept by a named decider is recorded, and applies", {
  s <- decide_setup()
  out <- decide_corrections(s$cfg, s$con, decisions_df(), dry_run = FALSE,
                            dialect = "duckdb")
  expect_identical(out$recorded, 1L)
  got <- DBI::dbGetQuery(s$con, "SELECT lvef FROM stg_echo_corrected WHERE mrn = 'SYN201'")
  expect_identical(got$lvef, 35)
})

test_that("each refusal has its verdict, and one refuses the whole batch", {
  s <- decide_setup()
  d <- rbind(decisions_df(),
             decisions_df(source = "stg_nowhere"),
             decisions_df(correction_id = "c99"),
             decisions_df(decision = "approve"),
             decisions_df(decided_by = "someone_else"),
             decisions_df(correction_id = "c02", decided_by = "dm_two"))
  out <- decide_corrections(s$cfg, s$con, d, dialect = "duckdb")
  expect_identical(out$verdicts$verdict, c("recordable", "unknown_source",
                                           "unknown_correction", "invalid_decision",
                                           "not_decider", "self_accepted"))
  expect_error(decide_corrections(s$cfg, s$con, d, dry_run = FALSE, dialect = "duckdb"),
               class = "hvtiRdatabuild_decisions_refused")
  expect_identical(
    DBI::dbGetQuery(s$con, "SELECT COUNT(*) AS n FROM stg_echo_correction_decisions")$n, 0)
})

test_that("a batch deciding one correction twice is refused, whatever the decisions", {
  s <- decide_setup()
  d <- rbind(decisions_df(), decisions_df(decision = "reject"))
  out <- decide_corrections(s$cfg, s$con, d, dialect = "duckdb")
  expect_identical(out$verdicts$verdict, c("repeated_correction", "repeated_correction"))
  expect_error(decide_corrections(s$cfg, s$con, d, dry_run = FALSE, dialect = "duckdb"),
               class = "hvtiRdatabuild_decisions_refused")
})

test_that("a master.yml with no deciders cannot decide", {
  s <- decide_setup()
  s$cfg$deciders <- NULL
  expect_error(decide_corrections(s$cfg, s$con, decisions_df(), dialect = "duckdb"),
               class = "hvtiRdatabuild_no_deciders")
})

test_that("a fill-in upstream has caught up with is retired with a bake decision", {
  s <- decide_setup()
  decide_corrections(s$cfg, s$con, decisions_df(correction_id = "c03"), dry_run = FALSE,
                     dialect = "duckdb")
  stale <- DBI::dbGetQuery(s$con, "SELECT * FROM stg_echo_corrections_stale")
  expect_identical(stale$reason, "filled_upstream_agrees")
  dry <- retire_filled_corrections(s$cfg, s$con, "stg_echo", dialect = "duckdb")
  expect_identical(dry$correction_ids, "c03")
  expect_identical(dry$recorded, 0L)
  out <- retire_filled_corrections(s$cfg, s$con, "stg_echo", dry_run = FALSE,
                                   dialect = "duckdb")
  expect_identical(out$recorded, 1L)
  expect_identical(nrow(DBI::dbGetQuery(s$con,
                                        "SELECT * FROM stg_echo_corrections_stale")), 0L)
  last <- DBI::dbGetQuery(s$con, paste("SELECT decision, decided_by FROM",
                                       "stg_echo_correction_decisions WHERE",
                                       "decided_by = 'filled_upstream'"))
  expect_identical(last$decision, "bake")
})
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "decide-corrections")'`
Expected: FAIL with `could not find function "decide_corrections"`.

- [ ] **Step 3: Implement** (append to `R/source_corrections.R`)

```r
#' Decide a batch of corrections
#'
#' Records `accept`, `reject`, `supersede` or `bake` for each row of `decisions`. A
#' correction applies while its latest decision is `accept`. When two accepted corrections
#' to a cell disagree, neither applies (G1): supersede the wrong one to settle the cell.
#'
#' Each row gets one of these verdicts:
#'
#' - `recordable`: the row passed every check below.
#' - `unknown_source`: the source is not declared in `master.yml`.
#' - `repeated_correction`: the batch decides the same correction more than once. Every row
#'   of a batch shares one `decided_on`, so their order would be arbitrary; decide it again
#'   in a later batch instead.
#' - `unknown_correction`: the source has no correction with that id.
#' - `invalid_decision`: the decision is not one of the four.
#' - `not_decider`: the decider is not listed in `master.yml`'s `deciders`.
#' - `self_accepted`: the decider asserted the correction (G2).
#'
#' With `dry_run = FALSE`, an all-`recordable` batch is recorded in one transaction, and a
#' batch with any other verdict is refused whole.
#'
#' **Interim.** Superseded by the HVTR registry. Replaces the deprecated
#' [decide_correction()].
#'
#' @param config A `master_config` from [read_master_config()], with `sources` and
#'   `deciders`.
#' @param con A DBI connection to the warehouse.
#' @param decisions A data frame with `source`, `correction_id`, `decision`, `decided_by`
#'   and optionally `reason`.
#' @param dry_run If `TRUE`, the default, validate only.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return Invisibly, a list: `verdicts` (a data frame of `row`, `verdict`) and
#'   `recorded` (an integer).
#'
#' @seealso [propose_corrections()], [retire_filled_corrections()]
#'
#' @examples
#' # See propose_corrections().
#'
#' @export
decide_corrections <- function(config, con, decisions, dry_run = TRUE, dialect = "mssql") {
  if (!length(config$deciders)) {
    .abort("no_deciders", "decide_corrections(): master.yml names no deciders.")
  }
  need <- c("source", "correction_id", "decision", "decided_by")
  if (!is.data.frame(decisions) || !all(need %in% names(decisions))) {
    .abort("decisions_columns", "decide_corrections(): `decisions` needs ",
           paste(need, collapse = ", "), ".")
  }
  if (!"reason" %in% names(decisions)) decisions$reason <- NA_character_
  n <- nrow(decisions)
  verdict <- rep(NA_character_, n)
  set <- function(i, v) {
    if (!is.logical(i)) i <- seq_len(n) %in% i
    verdict[i & is.na(verdict)] <<- v
  }
  set(!decisions$source %in% names(config$sources), "unknown_source")
  # One correction, one decision per batch: rows sharing a decided_on would be ordered by
  # their hash-derived decision_id, not by intent.
  dup <- paste(decisions$source, decisions$correction_id, sep = "\r")
  set(dup %in% dup[duplicated(dup)], "repeated_correction")
  q <- quoter(dialect)
  now <- Sys.time()
  record <- function() {
    for (s in intersect(names(config$sources), decisions$source)) {
      idx <- which(decisions$source == s)
      ids <- unique(decisions$correction_id[idx])
      known <- run_step("look up corrections", DBI::dbGetQuery(con, sprintf(
        "SELECT correction_id, asserted_by FROM %s WHERE correction_id IN (%s)",
        q(.source_tables(s)$corrections), paste(rep("?", length(ids)), collapse = ", ")
      ), params = as.list(ids)))
      asserter <- known$asserted_by[match(decisions$correction_id[idx], known$correction_id)]
      set(idx[is.na(asserter)], "unknown_correction")
      set(idx[!decisions$decision[idx] %in% DECISIONS], "invalid_decision")
      set(idx[!decisions$decided_by[idx] %in% config$deciders], "not_decider")
      set(idx[!is.na(asserter) & asserter == decisions$decided_by[idx]], "self_accepted")
      set(idx, "recordable")
    }
    if (dry_run || any(verdict != "recordable")) return(invisible(NULL))
    for (s in unique(decisions$source)) {
      idx <- which(decisions$source == s)
      rows <- data.frame(
        decision_id = vapply(idx, function(i) paste0("d", substr(digest::digest(
          list(decisions$correction_id[[i]], decisions$decision[[i]],
               decisions$decided_by[[i]], i, format(now, "%Y-%m-%d %H:%M:%OS6")),
          algo = "sha1"), 1, 20)), character(1)),
        correction_id = decisions$correction_id[idx], decision = decisions$decision[idx],
        decided_by = decisions$decided_by[idx], decided_on = now,
        reason = as.character(decisions$reason[idx]), stringsAsFactors = FALSE
      )
      run_step("append decisions",
               DBI::dbAppendTable(con, .source_tables(s)$decisions, rows))
    }
    invisible(NULL)
  }
  .with_snapshot_txn(con, dialect, record())
  counts <- table(verdict)
  .hvti_inform("decide_corrections(): ",
               paste(sprintf("%s %d", names(counts), counts), collapse = ", "), ".")
  if (!dry_run && any(verdict != "recordable")) {
    .abort("decisions_refused", "decide_corrections(): the batch was refused whole and ",
           "nothing was written: ", sum(verdict != "recordable"), " of ", n,
           " row(s) are not recordable.")
  }
  invisible(list(verdicts = data.frame(row = seq_len(n), verdict = verdict,
                                       stringsAsFactors = FALSE),
                 recorded = if (dry_run) 0L else n))
}

#' Retire fill-ins that upstream has caught up with
#'
#' A correction that filled a missing source value goes stale as `filled_upstream_agrees`
#' once the source holds that same value (G7). This records a `bake` decision for each
#' such correction, by the reserved decider `"filled_upstream"`, so it leaves the stale
#' view. Schedule it beside the data load. A fill-in where upstream holds a different
#' value is a conflict and is never retired here.
#'
#' **Interim.** Superseded by the HVTR registry.
#'
#' @param config A `master_config` from [read_master_config()], with `sources`.
#' @param con A DBI connection to the warehouse.
#' @param source Character. A declared source.
#' @param dry_run If `TRUE`, the default, list what would be retired.
#' @param dialect `"mssql"` or `"duckdb"`.
#'
#' @return Invisibly, a list: `correction_ids` and `recorded` (an integer).
#'
#' @seealso [decide_corrections()]
#'
#' @examples
#' # See propose_corrections().
#'
#' @export
retire_filled_corrections <- function(config, con, source, dry_run = TRUE,
                                      dialect = "mssql") {
  if (!source %in% names(config$sources)) {
    .abort("unknown_source", "retire_filled_corrections(): ", source,
           " is not declared in master.yml.")
  }
  tabs <- .source_tables(source)
  q <- quoter(dialect)
  now <- Sys.time()
  retire <- function() {
    ids <- run_step("read stale fill-ins", DBI::dbGetQuery(con, paste(
      "SELECT correction_id FROM", q(tabs$stale),
      "WHERE reason = 'filled_upstream_agrees'"
    )))$correction_id
    if (!dry_run && length(ids)) {
      rows <- data.frame(
        decision_id = vapply(ids, function(id) paste0("d", substr(digest::digest(
          list(id, "bake", FILLED_UPSTREAM_DECIDER, format(now, "%Y-%m-%d %H:%M:%OS6")),
          algo = "sha1"), 1, 20)), character(1)),
        correction_id = ids, decision = "bake", decided_by = FILLED_UPSTREAM_DECIDER,
        decided_on = now, reason = "The source now holds the corrected value.",
        stringsAsFactors = FALSE
      )
      run_step("append bake decisions", DBI::dbAppendTable(con, tabs$decisions, rows))
    }
    ids
  }
  ids <- .with_snapshot_txn(con, dialect, retire())
  .hvti_inform("retire_filled_corrections(): ", length(ids), " fill-in(s) ",
               if (dry_run) "would be retired." else "retired.")
  invisible(list(correction_ids = ids, recorded = if (dry_run) 0L else length(ids)))
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "decide-corrections")'`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add R/source_corrections.R tests/testthat/test-decide-corrections.R NAMESPACE man/
git commit -m "feat: decide_corrections() with G2, and retire_filled_corrections() for G7"
```

---

### Task 7: `study_correction_candidates()`

**Files:**
- Create: `R/correction_candidates.R`
- Test: `tests/testthat/test-correction-candidates.R`

**Interfaces:**
- Consumes:
  - `read_pull_provenance()`, `.read_deployment()` (`R/master_pull.R:57`), `value_text()`
    and `.template_columns()`.
  - The plan-1 test helpers `local_freeze_setup()`, `pull_demo()` and `demo_query()`.
- Produces: `study_correction_candidates(config, con, pull, data, path,
  key = c("mrn", "encounter_date"), dialect = "mssql")`. It writes `path` and
  `sub("\\.csv$", "-derived.csv", path)`, and returns invisibly a list:
  - `candidates`: an integer.
  - `inconsistent`: an integer.
  - `derived`: a data frame of `column`, `n_cells`.
  - `path` and `derived_path`.

**Contract with plan 3:** `<master>_lineage` (`master_column`, `source`, `source_column`)
lists exactly the pass-through columns. A source's key columns appear in the master, and so
in the pull, under the same names.

- [ ] **Step 1: Write the failing tests** `tests/testthat/test-correction-candidates.R`

```r
# No PHI: identifiers and values are invented.

candidates_setup <- function(env = parent.frame()) {
  f <- local_freeze_setup(env)
  DBI::dbWriteTable(f$con, "master_demo_lineage", data.frame(
    master_column = "age", source = "stg_demo", source_column = "age_years",
    stringsAsFactors = FALSE
  ))
  pull <- pull_demo(f$con, demo_query(), var_cols = c("proc", "age"))
  release <- freeze_study_pull(pull, f$config, f$dir, "st0000_pull",
                               extract_date = "2026-11-16")
  frozen <- file.path(f$dir, release$file)
  cfg_path <- withr::local_tempfile(fileext = ".yml", .local_envir = env)
  writeLines(c("name: master_demo", "key: [mrn, encounter_date]", "snapshots: .",
               "current: x.sas7bdat", "build_program: x.sas", "sources:",
               "  stg_demo: {key: [mrn, encounter_date]}"), cfg_path)
  list(con = f$con, cfg = read_master_config(cfg_path), frozen = frozen,
       data = as.data.frame(arrow::read_parquet(frozen)))
}

test_that("a pass-through fix becomes a template row; a derived fix is only counted", {
  s <- candidates_setup()
  data <- s$data
  data$age[data$mrn == "SYN103"] <- 56          # pass-through: a candidate
  data$proc[data$mrn == "SYN104"] <- "CABG+AVR"  # derived: counted only
  out_path <- withr::local_tempfile(fileext = ".csv")
  out <- study_correction_candidates(s$cfg, s$con, s$frozen, data, out_path,
                                     dialect = "duckdb")
  expect_identical(out$candidates, 1L)
  expect_identical(out$derived$column, "proc")
  expect_identical(out$derived$n_cells, 1L)
  rows <- utils::read.csv(out_path, colClasses = "character", na.strings = "")
  expect_identical(names(rows), .template_columns(s$cfg))
  expect_identical(rows$source, "stg_demo")
  expect_identical(rows$variable, "age_years")
  expect_identical(c(rows$expected_prior, rows$new_value), c("55", "56"))
  expect_true(is.na(rows$evidence_type))
  expect_true(is.na(rows$asserted_by))
})

test_that("a patient-level cell is a candidate only if every encounter agrees", {
  f <- local_freeze_setup()
  DBI::dbExecute(f$con, second_cabg)  # SYN103 gains a 2018 encounter
  DBI::dbWriteTable(f$con, "master_demo_lineage", data.frame(
    master_column = "proc", source = "stg_pat", source_column = "proc_group",
    stringsAsFactors = FALSE
  ))
  pull <- pull_demo(f$con, demo_query(index = "all"), var_cols = c("proc", "age"))
  release <- freeze_study_pull(pull, f$config, f$dir, "st0000_pull",
                               extract_date = "2026-11-16")
  frozen <- file.path(f$dir, release$file)
  cfg_path <- withr::local_tempfile(fileext = ".yml")
  writeLines(c("name: master_demo", "key: [mrn, encounter_date]", "snapshots: .",
               "current: x.sas7bdat", "build_program: x.sas", "sources:",
               "  stg_pat: {key: [mrn]}"), cfg_path)
  cfg <- read_master_config(cfg_path)
  data <- as.data.frame(arrow::read_parquet(frozen))
  later <- data$mrn == "SYN103" & data$encounter_date == as.Date("2018-02-02")
  data$proc[later] <- "OPCAB"           # one encounter changed, the other not
  one <- study_correction_candidates(cfg, f$con, frozen, data,
                                     withr::local_tempfile(fileext = ".csv"),
                                     dialect = "duckdb")
  expect_identical(c(one$candidates, one$inconsistent), c(0L, 1L))
  data$proc[data$mrn == "SYN103"] <- "OPCAB"   # both agree: one source cell
  both <- study_correction_candidates(cfg, f$con, frozen, data,
                                      withr::local_tempfile(fileext = ".csv"),
                                      dialect = "duckdb")
  expect_identical(c(both$candidates, both$inconsistent), c(1L, 0L))
})

test_that("candidates need the lineage the pull was made with", {
  s <- candidates_setup()
  DBI::dbExecute(s$con, "UPDATE master_demo_deployment SET sql_commit = 'def5678'")
  expect_error(study_correction_candidates(s$cfg, s$con, s$frozen, s$data,
                                           withr::local_tempfile(fileext = ".csv"),
                                           dialect = "duckdb"),
               class = "hvtiRdatabuild_lineage_moved")
})

test_that("a study row not in the pull stops, and no value is printed", {
  s <- candidates_setup()
  data <- s$data
  data$mrn[[1]] <- "SYN999"
  err <- tryCatch(study_correction_candidates(s$cfg, s$con, s$frozen, data,
                                              withr::local_tempfile(fileext = ".csv"),
                                              dialect = "duckdb"),
                  error = function(e) e)
  expect_s3_class(err, "hvtiRdatabuild_unknown_units")
  expect_false(grepl("SYN", conditionMessage(err)))
})
```

  ⚠️ Check the plan-1 fixture before relying on `55`. `master_demo`'s SYN103 2015-06-30 row
  has `age = 55` in `seed_master()`. Confirm two things:
  - `demo_query()` selects that encounter (SYN103's only CABG in the epoch) and SYN104's.
  - The frozen pull's columns include `mrn` and `encounter_date`.

  If the fixture differs, adjust the expected prior or the `key` argument, not the code.

- [ ] **Step 2: Run them and confirm they fail**

Run: `Rscript -e 'devtools::test(filter = "correction-candidates")'`
Expected: FAIL with `could not find function "study_correction_candidates"`.

- [ ] **Step 3: Implement** `R/correction_candidates.R`

```r
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
#'   cell, the candidates are dropped and counted as inconsistent.
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
      q(paste0(config$name, "_lineage"))
    )))
  ))
  if (!identical(read$commit, prov$sql_commit)) {
    .abort("lineage_moved", "study_correction_candidates(): the master was redeployed ",
           "since the pull, so its lineage may differ. Re-pull, then compare.")
  }
  lineage <- read$lineage
  base <- as.data.frame(arrow::read_parquet(pull))
  if (!all(key %in% names(base)) || !all(key %in% names(data))) {
    .abort("key_columns", "study_correction_candidates(): the pull and `data` must both ",
           "carry ", paste(key, collapse = ", "), ".")
  }
  unit <- function(d) do.call(paste, c(lapply(d[key], as.character), sep = "\r"))
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
    grp <- do.call(paste, c(lapply(s_key, function(k) as_text(base[[k]][m])), sep = "\r"))
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
    rows$evidence_ref <- paste0("study pull ", substr(digest::digest(
      pull, algo = "sha256", file = TRUE), 1, 12))
    cand[[length(cand) + 1L]] <- rows
  }
  cand <- if (length(cand)) do.call(rbind, cand) else
    as.data.frame(stats::setNames(rep(list(character()), length(tpl_cols)), tpl_cols),
                  check.names = FALSE)
  # Encounters that agree on a shared cell gave identical rows: keep one. Two master
  # columns read from one source column could still clash: drop and count those.
  cell <- do.call(paste, c(lapply(cand, function(x) x), sep = "\r"))
  cand <- cand[!duplicated(cell), , drop = FALSE]
  key_cols <- setdiff(tpl_cols, c("expected_prior", "expected_prior_missing", "new_value",
                                  "new_value_missing", "evidence_type", "evidence_ref",
                                  "asserted_by"))
  addr <- do.call(paste, c(lapply(cand[key_cols], function(x) x), sep = "\r"))
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
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "correction-candidates")'`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add R/correction_candidates.R tests/testthat/test-correction-candidates.R NAMESPACE man/
git commit -m "feat: study_correction_candidates() turns study fixes into a template"
```

---

### Task 8: reference group, spec amendments, news, the gate

**Files:**
- Modify: `_pkgdown.yml` (a new group before `Deprecated`)
- Modify: `dev/specs/2026-11-16-master-views-design.md` (§3.1, §3.3, §3.4, §3.5, §8)
- Create: `news/<branch with / as ->.md`

- [ ] **Step 1: Add the reference group** to `_pkgdown.yml`, directly before
  `- title: Deprecated`:

```yaml
- title: "Corrections to source views (interim)"
  desc: >
    Interim intake for corrections to warehouse source views, superseded by the HVTR
    registry, which takes over the template and the tables unchanged.
  contents:
  - generate_corrections_sql
  - write_corrections_template
  - propose_corrections
  - decide_corrections
  - retire_filled_corrections
  - study_correction_candidates
```

- [ ] **Step 2: Amend the spec.** Add a paragraph headed **Amended 2026-11-17 (plan 2a)** at
  the end of §3.1. It lists the plan's decisions 1, 2 and 7: per-source tables;
  `sources`/`deciders` in `master.yml`; the `<master>_lineage` contract and same-named
  source keys. Then make these edits:
  - §3.3: add the status order (decision 5) after the G7 bullet.
  - §3.4 step 3 and the verdict bullet in §8: list `unknown_source`, `invalid_field`,
    `no_variable` and `prior_mismatch` beside the original verdicts, and add the
    `rule_not_fact` definition (decision 4).
  - §3.4 step 5: name `retire_filled_corrections()` for G7, and note that G2 covers every
    decision (decision 8).

  Keep the spec's own line length and voice.

- [ ] **Step 3: Write the news fragment** `news/<branch>.md`, with no heading:

```markdown
* New interim tools for correcting warehouse source views, superseded by the HVTR
  registry: `generate_corrections_sql()` writes each declared source's corrections tables
  and its corrected, applied, stale and conflicts views, covering every column;
  `write_corrections_template()`, `propose_corrections()` and `decide_corrections()` take
  a whole submission and refuse it whole if any row fails, with a verdict per row and no
  values in any message; `retire_filled_corrections()` retires fill-ins upstream has
  caught up with; and `study_correction_candidates()` turns a study's own fixes into
  candidate corrections against its frozen pull. Accepted corrections to one cell that
  disagree no longer resolve to the latest: neither applies until one is superseded.
* `read_master_config()` reads `sources` (correctable source views and their keys) and
  `deciders` from `master.yml`.
```

- [ ] **Step 4: Run the full gate**

```bash
Rscript -e 'devtools::document()'
Rscript -e 'devtools::test()'
Rscript -e 'devtools::check(document = FALSE)'
Rscript -e 'lintr::lint_package()'
Rscript -e 'pkgdown::check_pkgdown()'
```

Expected: tests pass with no new skips, check at 0 errors, 0 warnings and 0 notes, no lints,
and pkgdown clean. If `check()` flags the examples, confirm that every example touching
duckdb sits inside `\donttest{}` and `if (requireNamespace(...))`.

- [ ] **Step 5: Commit**

```bash
git add _pkgdown.yml dev/specs/2026-11-16-master-views-design.md news/ man/ NAMESPACE
git commit -m "docs: corrections reference group, spec amendments and news"
```

---

## Self-review against the spec

| Spec | Covered by |
|---|---|
| §3.1 corrections tables, corrected views, stale/conflicts views | Tasks 2–4 |
| §3.2 corrections name a source cell; derived variable refused | Tasks 2, 5 (`derived_variable`) |
| §3.3 every column covered; first correction live with no deploy | Task 3 (test) |
| §3.3 G1 conflicts; supersede settles | Task 3 (tests) |
| §3.3 G7 fill-ins agree / disagree | Tasks 2–3, 6 (`retire_filled_corrections()`) |
| §3.3 `as_of` not a view parameter | Not generated (no `as_of` argument) |
| §3.4 template with the full declared key; patient-level rows carry no date | Tasks 4–5 |
| §3.4 dry run, verdicts, whole-file append, no values | Task 5 |
| §3.4 decisions; named deciding role; `self_accepted` | Tasks 1, 6 |
| §3.4 interim, marked superseded | Every export's help; Task 8 group |
| §3.5 candidates against the retained pull; derived listed separately; `prior_mismatch` | Tasks 5, 7 |
| §6.1 per-source `_corrections_applied` view | Task 3 (master rollup is plan 3) |
| §8 intake failures, no values | Tasks 5–6 tests |
| §9 R reference checked against generated SQL, incl. G1 and G7 | Task 3 |
| §9 intake against patient-level and encounter-level sources | Task 5 |
| §9 study candidates after upstream change (`prior_mismatch`) | Task 5 (verdict); Task 7 writes the prior |

**Not covered here, by design:**
- The legacy backfill re-expressed against source columns (§3.2) needs the SAS programs.
  It belongs with plan 3's port.
- Deploying the generated files and the master-level applied rollup are plan 3.
- The SQL Server rehearsal of the generated SQL, the `COLLATE` branch included, is plan 3.
- §10's corrected-view performance on the widest source is plan 3. It is measured there
  before the design is frozen.
