# Build and derive implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement
> this plan task by task.

**Goal:** Implement patient-level dataset assembly, a package-owned cohort record, and an
optional study-specific R derivation step that preserves ordered inclusion, exclusion, and
attrition history.

**Architecture:** `hvtiRdatabuild` owns a `cohort_record` made of ordered stage metadata and
patient-by-stage outcomes. `build_dataset()` returns the assembled patient data with that
record. `derive_vars()` calls study-specific R code and validates the updated data and record.
The package does not depend on `hvtiPlotR`; a plotting adapter can consume the result later.

**Tech Stack:** R, testthat edition 3, roxygen2, dplyr, yaml.

**Spec:** `dev/specs/2026-10-05-upstream-cohort-build-handoff-design.md`

**Scope boundary:** This plan implements the package-side record and pipeline contract using
synthetic inputs. It does not connect to an upstream producer; none is present in the local
repositories, and its transfer format remains a separate decision.

## Global Constraints

- No real data or patient value enters the repository, a fixture, or a test message.
- New fixtures are invented and labeled synthetic.
- Patient identifiers remain runtime data and are never printed in errors or summaries.
- Preserve exclusion order; a patient excluded earlier is not counted again later.
- A change to package code earns an unreleased `NEWS.md` entry.
- Run `devtools::document()` and commit generated `man/` and `NAMESPACE` with source changes.

## Review Focus

- Duplicate or missing patient identifiers within a stage must fail without echoing values.
- A patient excluded at one stage must not appear in a later stage or count as a later exclusion.
- Missing or unknown stage metadata must fail instead of being interpreted as an empty history.
- One-to-many source modules must not silently duplicate the primary built cohort.
- Missing values in study exclusion predicates must follow an explicit rule and be tested.

---

## Proposed interfaces

These signatures make the conceptual contract executable and are review points for this plan.

- `new_cohort_record(members, stages, patient_id_col)` returns class `cohort_record`.
- `append_cohort_stage(cohort, stage, outcomes)` appends one ordered stage. `stage` is a
  one-row table with the `stages` schema; `outcomes` has `patient_id`, `included`, and `reason`.
- `members` has columns `patient_id`, `stage_id`, `included`, and `reason`. `patient_id` is
  character and may contain PHI; it is never included in printed output. `patient_id_col`
  names the corresponding identifier column in the patient-level dataset.
- `stages` has columns `stage_id`, `order`, `label`, `source`, and `provenance`. `source` is
  one of `upstream`, `build`, or `derive`; `provenance` is character and contains no patient
  values. Counts are computed from `members`.
- `build_dataset(raw, config, cohort)` returns class `build_result`, with `$data`, `$cohort`,
  and unjoined supporting module tables in `$tables`.
- `derive_vars(build, config, study_derive)` returns class `derive_result`, with `$data`,
  `$cohort`, and unchanged supporting `$tables`. `study_derive(data, cohort, config)` returns a
  list with named `data` and `cohort` elements. Study-specific predicates and variable formulas
  live in committed R code, not executable YAML.
- `cohort_summary(cohort)` returns `$stages` (`stage_id`, `label`, `n_in`, `n_excluded`,
  `n_remaining`) and `$reasons` (`stage_id`, `reason`, `n_excluded`) tables. It never returns
  patient identifiers.
- Printed record and result objects show dimensions and cohort counts only.

## File structure

- `R/cohort_record.R`: constructor, validation, stage append helper, summary, and safe print.
- `R/build_dataset.R`: primary patient-level module assembly and `build_result` creation.
- `R/derive_vars.R`: validated study-code runner and `derive_result` creation.
- `R/study_config.R`: no executable expressions; existing `derive` flags select named shared
  steps, while study-specific code is supplied as an R function.
- `tests/testthat/test-cohort-record.R`: schema, order, summary, and privacy behavior.
- `tests/testthat/test-build-dataset.R`: synthetic module joins and cohort preservation.
- `tests/testthat/test-derive-vars.R`: callback execution, contract validation, and attrition.
- `man/`, `NAMESPACE`, and `NEWS.md`: generated documentation and user-facing change note.
- `DESCRIPTION`: promote `dplyr` from `Suggests` to `Imports` for module joins.

### Task 1: Define the cohort record

**Files:**
- Create: `R/cohort_record.R`
- Create: `tests/testthat/test-cohort-record.R`
- Modify: `NAMESPACE`, generated Rd files, and `NEWS.md`

**Interfaces:**
- Produces: `new_cohort_record(members, stages, patient_id_col)` and
  `append_cohort_stage(cohort, stage, outcomes)`, `cohort_summary(cohort)`, and a safe
  `print.cohort_record()` method.
- `members` contains one row for each patient entering each stage. An excluded patient has no
  row for later stages. `included` is logical; `reason` is `NA_character_` when included and
  a non-empty string when excluded. Outcomes with `NA` are invalid and must be resolved in
  study-specific R code.
- `stages$order` is unique, positive, and strictly increasing; stage identifiers are unique.
  A cohort history contains at least one initial stage, even when it has no members.
- `append_cohort_stage()` accepts outcomes only for patients active at the preceding stage.
- Summary counts are derived from the member outcomes and do not contain patient identifiers.
- Printing a `cohort_record` shows only stage and count summaries.

- [x] **Step 1: Write synthetic constructor and validation tests**

Test valid multi-stage records, invalid types, unknown stage references, duplicate patient
and stage rows, empty histories, bad order, included rows with reasons, excluded rows without
reasons, patients reappearing after exclusion, and summary/print output with no identifiers. Use
invented IDs only.

- [x] **Step 2: Run the focused test file and confirm the new tests fail**

Run: `Rscript -e 'devtools::test(filter = "cohort-record")'`
Expected: failures report missing constructor/summary behavior and contain no patient values.

- [x] **Step 3: Implement `new_cohort_record()` and validation**

Store only the public `members`, `stages`, and identifier-column name in the classed list.
Keep identifiers in memory; make `print.cohort_record()` show counts only.

- [x] **Step 4: Implement `append_cohort_stage()`**

Require exactly one outcome for every patient active at the preceding stage and no outcomes
for inactive or unknown patients. The first stage is supplied to `new_cohort_record()` as the
initial history. Append the metadata row and outcome rows without changing prior stages.

- [x] **Step 5: Implement `cohort_summary()`**

Derive `n_in`, `n_excluded`, and `n_remaining` from outcomes. Return a stage summary table and
a stage-by-reason table without expanding or printing patient-level rows.

- [x] **Step 6: Run the focused tests and document exports**

Run: `Rscript -e 'devtools::test(filter = "cohort-record")'`
Expected: all cohort-record tests pass. Run `devtools::document()` and review generated Rd and
`NAMESPACE` changes.

### Task 2: Assemble a built dataset with its cohort record

**Files:**
- Create: `R/build_dataset.R`
- Create: `tests/testthat/test-build-dataset.R`
- Modify: `NAMESPACE`, generated Rd files, and `NEWS.md`

**Interfaces:**
- Consumes: `raw` as a `pull_result`, `config` as a `study_config`, and `cohort` as a
  `cohort_record`.
- Produces: `build_dataset(raw, config, cohort)`, a `build_result` list with `$data`,
  `$cohort`, and `$tables` containing unjoined supporting module tables.
- The `data` member is the patient-level dataset supplied to downstream derivation and
  comparison. The cohort record preserves the membership decisions that produced it.

- [x] **Step 1: Write synthetic assembly tests**

Cover primary-table preservation, joins by declared module keys, missing-key errors,
one-to-many event tables remaining separate from the one-row-per-patient built data, and
ID-set disagreement with the cohort record. Assert only synthetic shapes, counts, and verdicts.

- [x] **Step 2: Run the focused test file and confirm failures**

Run: `Rscript -e 'devtools::test(filter = "build-dataset")'`
Expected: failures identify the missing builder and the unhandled join contracts.

- [x] **Step 3: Implement `build_dataset(raw, config, cohort)`**

Use `base` (`bdbase`) as the required patient-level anchor and join `vitalstatus` (`bdstat`)
by their declared `masterid` key when configured. The existing S1 design identifies `echo`,
`fup`, and `bdevents` as repeated-event tables; keep them in `build_result$tables` rather than
joining them into patient-level data. Validate key uniqueness, cohort identifiers, and row
preservation without including identifier values in errors.
Append the build stage to the cohort record and return `build_result`.

- [x] **Step 4: Run focused tests and document the export**

Run: `Rscript -e 'devtools::test(filter = "build-dataset")'`
Expected: all builder tests pass. Run `devtools::document()` and review generated Rd and
`NAMESPACE` changes.

### Task 3: Run study-specific derivation code and preserve attrition

**Files:**
- Create: `R/derive_vars.R`
- Create: `tests/testthat/test-derive-vars.R`
- Modify: `NAMESPACE`, `man/derive_vars.Rd`, `NEWS.md`

**Interfaces:**
- Consumes: a `build_result`, `study_config`, and a study-specific function with signature
  `study_derive(data, cohort, config)`.
- Produces: `derive_vars(build, config, study_derive)`, a `derive_result` list with `$data`,
  `$cohort`, and the unchanged supporting `$tables` from `build`.
- The study function returns a list with named `data` and `cohort` members. The package
  validates their classes, required columns, unique IDs, stage ordering, and record consistency.
- The study-specific function uses `config$derive` to select named shared steps and supplies
  cohort-specific predicates and variable formulas in committed R code.

- [x] **Step 1: Write callback contract tests using synthetic functions**

Cover successful derived columns, ordered local exclusions, explicit handling of missing
predicate values, empty/no-op derivation, malformed return values, dropped IDs, duplicated
IDs, and error messages that do not reveal test IDs.

- [x] **Step 2: Run the focused test file and confirm failures**

Run: `Rscript -e 'devtools::test(filter = "derive-vars")'`
Expected: failures identify missing runner behavior and invalid callback handling.

- [x] **Step 3: Implement `derive_vars()`**

Call the study-specific function with patient data, cohort record, and config. Validate its
returned pair and preserve ordered upstream and local stages. Do not source code paths from
`study.yaml` or print patient identifiers.

- [x] **Step 4: Run focused tests and document the export**

Run: `Rscript -e 'devtools::test(filter = "derive-vars")'`
Expected: all derivation tests pass. Run `devtools::document()` and review generated Rd and
`NAMESPACE` changes.

### Task 4: Verify the complete pipeline and package gates

**Files:**
- Create: `tests/testthat/test-cohort-pipeline.R`
- Modify: `vignettes/` with a synthetic example and migration guidance
- Modify: `NEWS.md`

**Interfaces:**
- Consumes: the `cohort_record`, `build_result`, and `derive_result` contracts from Tasks 1–3.

- [x] **Step 1: Add an end-to-end synthetic pipeline example**

Construct a cohort record, build from mocked module tables, run a study-specific derivation
function, and verify ordered summary counts and the final data shape.

- [x] **Step 2: Run the full package tests**

Run: `Rscript -e 'devtools::test()'`
Expected: all tests pass; the real-study integration test skips unless its external data
directory is explicitly configured.

- [x] **Step 3: Run package checks**

Run: `Rscript -e 'devtools::check()'`
Expected: 0 errors, 0 warnings, 0 notes; inspect testthat skip counts as well as the check
summary.

- [ ] **Step 4: Review the final diff**

Review only the files in this plan and keep existing unrelated worktree changes untouched.
