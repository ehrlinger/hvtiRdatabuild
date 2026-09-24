# The mitral master, lifted, and the master machinery promoted

**Date:** 2026-09-24
**Status:** design, approved in conversation 2026-09-24, section by section. Not yet planned.
**Extends:** `2026-09-23-cardiac-master-view-design.md`, whose decision 3 named the mitral
master as the second case and whose §4.1 promised promotion when a second master reused the
scripts.

> **Redacted for public release**, as the cardiac spec is. Internal paths are placeholders,
> individuals are named by role, and **no patient value or identifier appears here.** Counts
> are counts of code patterns and files, never of patients.

---

## 1. What this decides

Four decisions, each dated 2026-09-24 and made by the maintainer:

1. **The mitral master is lifted as cardiac was**: snapshot, load, parity, and a view with
   corrections. Porting its derivations comes later, in its own spec.
2. **The phase 0 to 2 scripts become exported functions now.** The package is 0.x, and the
   interface will iterate as the masters are built. This meets the cardiac spec's promotion
   gate: a second master exercises the same shape.
3. **Each master is described by a `master.yml` outside the repository**, read by
   `read_master_config()`. The repository is public and the paths are internal.
4. **Six exports.** `read_master_config()`, `snapshot_master()`,
   `lift_master(dry_run =)`, `backfill_corrections()`, `propose_correction()` and
   `decide_correction()`. The migration steps (DDL, load, parity, legacy parsing) stay
   internal. They are scaffolding that exists only until each master's build is ported, and
   exporting them would make plumbing permanent interface. View regeneration happens inside
   the phases.

## 2. The mitral master, as measured

Measured 2026-09-24 from the build folder on the share, counting statement patterns and
files. No dataset was opened.

- **The build program is `bd.data_all.sas`**: 1,647 lines, with 56 data steps, 16 `proc sql`
  blocks, 4 `merge` statements and 1 `update`.
- **It is a child of the cardiac master.** It reads `master.built_2026mar27`, the cardiac
  snapshot the cardiac spec lifts, and joins on **`ccfid` + `dtn_inst`**, not on the cardiac
  key.
- **It has sources the rollup does not**: REDCap, the STS submission file, echo read-ins, and
  dated follow-up, events, status and reoperation components, each with its own build program.
- **It reads six studies' `built` datasets back in, for cohort-membership flags only.** Each
  read keeps the key columns and a `flg_<study>` indicator, and nothing else.
- **21 patient-level inline fixes, some of which remap `ccfid` itself.** These are corrections
  to identity, not to a cell.
- **It is rebuilt often.** There are 11 builds of `built_all`: the current one and 2 dated
  ones beside it (7.0 to 7.4 GB each), and 8 more in the year folders. Program copies are dated
  through 2022, 2023, 2025 and 2026.
- ⚠️ **The program on disk is newer than the dataset.** `bd.data_all.sas` was edited on 22 Sep,
  after `built_all.sas7bdat` was built on 28 Aug. The log of the run that produced the dataset
  (`bd.data_all.log`, 28 Aug) records the parent it read as a SAS NOTE, which confirms
  `MASTER.BUILT_2026MAR27`. §4 turns this into a rule.

## 3. Configuration: `master.yml`

Validated on read. Paths live only on the share.

```yaml
name: master_mitral              # the view; table names derive from it
key: [ccfid, dtn_inst]           # exactly one; what corrections match and the view joins on
alt_keys:                        # zero or more, named
  epic: [emrn, encounter_date]
parent:                          # optional; master_cardiac has none
  master: master_cardiac
  libref: master                 # the libref the SAS build reads the parent through
snapshots: <share>/…/mitral/DATASETS
current: built_all.sas7bdat
history: "^built_all_.*\\.sas7bdat$"   # searched in snapshots/ and its immediate subfolders
build_program: <share>/…/mitral/DATASETS/bd.data_all.sas
```

**Keys.** There is **one primary key**. Two matching keys would mean two definitions of the
same row. **Alternate keys are bridges, not matching keys.** Each is checked unique where
non-null and reported by name. Its columns are carried, nullable, on every correction so that
a row can be found from another system. An STS alternate key is the likely second use, once
the field the build-layer capture found missing exists upstream.

**Validation** stops on:
- a missing `name`, `key`, `snapshots`, `current` or `build_program`;
- a `parent` without `libref`;
- a column named twice across `key` and `alt_keys`;
- a `history` pattern that does not compile.

**Cardiac gets a `master.yml` too**, and the cardiac spec's runbooks are replaced by the
exported calls.

## 4. Lineage between masters

`snapshot_master()` records the release of the parent master that a child build read, in the
snapshot's sidecar, with how it was established:

1. **From the log of the run that produced the dataset**, where one exists: a `.log` beside the
   build program whose timestamp brackets the dataset's. SAS writes each dataset read as a
   NOTE, and the parent is the member read through the parent's `libref`.
   `parent_source: log`.
2. Otherwise **from the build program**: its `set <libref>.<member>` statements.
   `parent_source: program`.
3. Otherwise, or when either finds more than one candidate, it **stops and asks for
   `parent_release:`** to be set in the config. `parent_source: declared`. For a historical
   build whose log and program are both gone, it records `unknown`.

The log outranks the program because the program can change after the run: mitral's did.
This is the lesson behind `log-verifiability-scan.R` applied to lineage: evidence of what ran
beats the source of what could run. Only `NOTE:` lines naming datasets are read, never data
lines.

## 5. Corrections

- **Per-master tables**, `<name>_corrections` and `<name>_correction_decisions`. The contract's
  `master` column would allow one shared table, but the key columns differ between masters, so
  a shared table cannot hold both.
- **Alternate-key columns** are the union across `alt_keys`, all nullable.
- **Legacy facts.** The 21 inline fixes are recorded as `bake`, except the **`ccfid` remaps**.
  Those change the key itself, so they are reported unresolved as `key_variable` with their line
  numbers and never recorded as cell corrections. **Identity corrections are designed in the
  mitral port spec**, where they are applied before cell corrections, because a remapped key
  changes which row every other correction points at.
- ⚠️ **A stated limit of the lifted state.** `master_mitral`'s base is a snapshot with cardiac
  values baked in at its build time. A correction made to `master_cardiac` afterwards **does not
  reach `master_mitral` until the mitral port**, when the mitral view is built over
  `master_cardiac` directly.

## 6. Promotion into the package

### 6.1 Exports

| Function | Does |
|---|---|
| `read_master_config(path)` | reads and validates `master.yml`; returns a `master_config` object |
| `snapshot_master(config, out_dir, which = c("current", "history"), chunk_rows =)` | snapshots via `snapshot_oracle()`, checks the key and alternate keys, records the parent release |
| `lift_master(config, con, parquet, dry_run = TRUE)` | DDL, key gate, load, parity (aggregates, sample, full), parity record, view. The dry run writes the DDL for a hand-off and touches nothing |
| `backfill_corrections(config, con, dry_run = TRUE)` | corrections tables, legacy facts as `bake`, view and stale-view regeneration |
| `propose_correction(config, con, ...)` / `decide_correction(config, con, ...)` | the everyday correction workflow |

A dry run is the default wherever a function writes to the warehouse. That keeps the default
the cardiac runbooks had.

### 6.2 Files

| File | Contents | Exported |
|---|---|---|
| `R/master_config.R` | `read_master_config()` and validation | yes |
| `R/master_snapshot.R` | `snapshot_master()`, history search, parent detection | yes |
| `R/master_lift.R` | `lift_master()` | yes |
| `R/master_corrections.R` | `backfill_corrections()`, `propose_correction()`, `decide_correction()` | yes |
| `R/corrections_sql.R` | resolver, view and stale SQL, `as_of`, `TRY_CAST` | internal |
| `R/master_steps.R` | DDL and preflight, load, parity, key verdicts | internal |
| `R/legacy_facts.R` | parser and `legacy_rows()` | internal |
| `R/sql_dialect.R` | quoting, types, `table_types()`, `run_step()` | internal |

`dev/masters/cardiac/` is deleted once its contents are in `R/` and its tests in testthat.

### 6.3 Dependencies

- `DBI`, `digest` and `haven` are already in Imports.
- `arrow`, `jsonlite`, `dplyr`, `odbc` and `withr` stay in Suggests. `duckdb` and `tidyselect`
  join them.
- Each export checks the Suggests it needs with `requireNamespace()` and a message naming the
  package.
- No new Imports.

### 6.4 Documentation

- Roxygen markdown on the exports, each with `@return` and `\donttest` examples that run on
  duckdb with synthetic data.
- A new vignette, `vignette("master-datasets")`, covers what a master is, the `master.yml`
  fields, the three phases, and the correction workflow. It uses the Quarto builder and
  synthetic data only.
- `_pkgdown.yml` gains a "Master datasets" reference section.
- One `NEWS.md` entry under the unreleased heading. No version bump in the PR.

## 7. Testing

**The script tests move into testthat** as `tests/testthat/test-master-*.R`, keeping their
synthetic fixtures and checks. The duckdb tests use `skip_if_not_installed("duckdb")`, so **CI
now runs them**. That closes the cardiac spec's "by hand, not in CI" gap.

New cases:
- **Config validation**, one test per stop listed in §3.
- **Parent detection:** from a synthetic log NOTE, from a program when there is no log, a stop
  when the candidate is ambiguous, and `parent_source` recorded each time.
- **History search** across subfolders.
- **A verdict per named alternate key.**
- **An end-to-end `lift_master()` on duckdb** from a parent config and a child config to both
  views, including the dry run touching nothing.
- **The `ccfid`-remap statement** reported as `key_variable`.

The SQL Server path stays behind the gated integration pattern, an environment variable like
`HVTI_ORACLE_DIR`, and **reruns the same assertions** against the warehouse. That is how the
cardiac spec's list of checks duckdb cannot reach gets closed.

**Definition of done:** `devtools::test()` passes; `devtools::check()` is 0/0/0 **including
the manual**, since new roxygen can bring Unicode into the Rd files and only the manual build
catches it; `lintr` is clean; no PHI in the diff.

## 8. Failure handling and PHI

Everything the cardiac spec established carries over:
- a dry run by default;
- the key gate before the DDL;
- the view created only after parity passes, and the parity record required before corrections
  are backfilled;
- `run_step()` withholding driver messages;
- output limited to verdicts, counts, line numbers and column names;
- identifiers read at run time and never transcribed.

Log parsing reads only the `NOTE:` lines that name datasets.

## 9. How this relates to the general `build.sas` path

**A master is a `build.sas` whose output other builds read.** `bd.data.master.sas` and
`bd.data_all.sas` are build programs like the study-level ones in the job catalog (`bd`,
1,094 studies). The general study build runs: cohort, join a master, cohort-specific
derivations, built dataset and EDA report. The master machinery supplies that path's
foundation:

| Master machinery | Its role in the general `bd` / `vars` path |
|---|---|
| Master views, `as_of`, the freeze record | **The input side of the `bd` template.** A study reads `master:` from a view pinned to a freeze point, not from a SAS file on the share |
| The corrections contract | **A home for corrections from the investigator's chart review**, which today are programmed into each study's `build.sas`. Recorded against the master, a fix found in one study is inherited by every later study that reads that master |
| The legacy-fix parser | **The same scan works on study builds**, whose inline patient fixes are how study-level corrections would reach the master instead of dying with each study |
| Snapshot, parity and the evidence ladder | **How a study's port is verified**, as in the vars-port design |
| `master.yml` and lineage | **The pattern for a study's config**: a declared parent master and release, and a declared key |

The masters come first because every study build reads from them. The `bd` template is then
thin by design. It composes the master read, cohort selection, derivations from the catalogue
the build-structure scan measured (7,009 step shapes), and the EDA report.

⚠️ **One dependency to carry into the `bd` spec:** the read side. A study's main interaction
with a master is reading it as of a freeze point, with lineage to the parent release. That
function belongs in the `bd` spec, not here, and is recorded so it is not lost.

## 10. Open questions

- [ ] **Who holds warehouse write rights.** The same question as cardiac, and it decides who
      runs `lift_master(dry_run = FALSE)`.
- [ ] **Whether each of the 10 historical mitral builds has a log** that brackets it, which
      decides how many get `parent_source: log`.
- [ ] **How common identity (`ccfid`) corrections are across masters**, which sizes the mitral
      port spec.
- [ ] **Whether cohort flags read from study `built` datasets are a master's concern** or belong
      to the `bd` template. A port-phase question.
- [ ] **The deferred items from the cardiac reviews.** Carried in the 2026-09-23 session log.
      The promotion is the natural moment to fix those that touch moved code, but none is in
      scope unless the plan takes it.

## 11. Out of scope

- Porting either master's derivations (phase 3), and identity corrections.
- The `bd` and `vars` templates, including the master read function (§9).
- Masters with no warehouse source, and REDCap-held registries.
