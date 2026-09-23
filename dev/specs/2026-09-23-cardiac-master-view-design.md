# The cardiac-surgery master: from SAS dataset to warehouse view

**Date:** 2026-09-23
**Status:** design, approved in conversation 2026-09-23, section by section. Not yet planned.
**Extends:** `2026-08-24-build-layer-design-capture.md` (Fork 3, "Four topologies, one
name", and the amendment's corrections sections) and
`2026-09-02-vars-port-and-attrition-design.md`.
**Reads alongside:** `2026-09-21-dataset-publication-plan.md`, whose release catalog this
proposes to reuse (§4.4).

> **Redacted for public release**, following the build-layer capture. Internal paths are
> placeholders, individuals are named by role, and **no patient value or identifier
> appears here.** Counts below are counts of code patterns, never of patients.

---

## 1. What this decides

This is the first spec of the `build.sas` / `vars.sas` replacement path, and it starts one
level below either of them: with the master dataset a study build reads.

Five decisions, each dated 2026-09-23 and made by the maintainer:

1. **The build language is R.** The build-layer capture required this settled before S2.
   The lean had moved toward R at the 2026-09-17 stat-programmer check-in; it is now a
   decision, not a lean.
2. **Forward path first, migration second.** The replacement templates define the shape
   that ported studies land in. Porting before that shape exists means porting twice.
3. **One master end to end before generalising.** The cardiac-surgery rollup first, the
   mitral master second. This is the same gate `hvtiRtemplates` applies to a template and
   the vars-port design applies to `vars.R`: build it once for real, extract it when a
   second case has exercised it.
4. **Masters become views in the current SQL Server warehouse**, reached through a parquet
   snapshot. They move before HVTR lands, not with it.
5. **This package designs the corrections model.** 🔴 **This reverses the build-layer
   capture's amendment**, which concluded that `hvtiRdatabuild` should consume HVTR's
   corrections layer rather than implement one. That was right while the masters were
   going to wait for HVTR. They are not waiting, and a master in a warehouse view needs
   somewhere to put a correction on the day it moves. The model is written to be
   independent of storage (§5) so HVTR can take over the contract and replace the
   implementation.

## 2. Where this sits

The replacement path decomposes into five specs:

| # | Spec | Depends on |
|---|---|---|
| 1 | Corrections model | nothing |
| 2 | Master to warehouse view, one master at a time | 1 |
| 3 | `bd` forward template: cohort, `master:` (`file:` or `modules:`), derivations, built dataset and EDA report | 1 for the freeze record |
| 4 | `vars` template: the opt-in overlay, exclusions through the CONSORT tracker | 3 |
| 5 | Migration of existing studies, verified up the evidence ladder | 3, 4 |

**This spec is 1 and 2 together, on one master.** Designing the corrections model in the
abstract would skip the gate in decision 3; designing it against a real master gives it a
case to fail on.

Spec 3's `master:` block accepts both `file:` and `modules:`. That was chosen because the
masters are moving into the warehouse: a study reads `file:` until its master lands, then
flips to `modules:`. This spec is what makes the flip possible for the first master.

## 3. The master, as measured

Measured 2026-09-23 from the build folder on the share (`<share>/…/Data_Wpull/`),
counting statement patterns only. No dataset was opened.

- **The build program** is `bd.data.master.sas`: 2,453 lines, last run 8 May 2026,
  with its `.log` and `.lst` beside it. It holds 48 data steps and 16 `proc sql` blocks,
  and no `merge` or `update` against a corrections file.
- **The frozen builds** are in `snapshots/`: **12 dated builds**, November 2021 to March
  2026, 11 to 36 GB each, about 350 GB together. A thirteenth file, an undated
  `built.sas7bdat`, is byte-for-byte the size of the April 2024 build and is probably a
  copy; phase 0's source checksum settles it. One of the twelve is a follow-up refresh of an
  earlier build (`built_2023may15_fup08162023`), which is the off-cadence partial refresh
  the build-layer amendment described, sitting in the version history.
- **Patient-level corrections are inline, and there are few.** 18 statements of the form
  `if ccfid = … then …`. 65 conditional assignments overall, which are mostly derivations,
  and 2 rule-style fixes that set a value missing. One external CSV is read in, and
  whether it is a source or a corrections file is open (§9).

⚠️ **The rollup is a thin test of the corrections model.** Eighteen facts in a master of
700 to 800 variables says the adjudication weight the authors described lives in the child
masters and the study builds, not here. That is why the mitral master is the second case:
it proves the model under load that the rollup cannot supply.

⚠️ The build `%include`s a SAS file holding warehouse credentials. It was not opened. It is
the SAS counterpart of the `.Renviron` rung of `dw_connect()`'s ladder, and a master that
is a warehouse view no longer needs it.

## 4. Phases

| Phase | Output | Verified against | Here |
|---|---|---|---|
| 0. Snapshot | parquet of `built_2026mar27`, then the other 11, each with a SHA-256 and a metadata sidecar | the build log's shape, via `expect` | fully designed |
| 1. Lift | a base table and the `master_cardiac` view in SQL Server | the parquet: counts, aggregates and a sampled value compare | fully designed |
| 2. Corrections | the corrections contract; the view becomes base plus corrections | compare-and-swap on the prior value | fully designed (§5) |
| 3. Port | `bd.data.master.sas` re-expressed from warehouse sources | the loaded snapshot, inside the database | interface and acceptance only (§7) |

**Success:** a biostatistician reads `master_cardiac` in place of
`built_2026mar27.sas7bdat` and gets an identical dataset, proved rather than assumed; and
a new correction lands in a table with its evidence, not in a SAS file.

Until phase 3 lands the view is frozen at March 2026, and the next rebuild still needs
SAS. That is acceptable while the licence runs to 2027, and it is why phase 3 is not
optional.

### 4.1 Where the code lives

**Generic fixes go into the package now. Master-specific machinery starts as scripts**
under `dev/masters/cardiac/` and is promoted to exports only when the mitral master reuses
it. Chunked reading (§4.2) is the one piece that is plainly generic, so it goes straight
into `snapshot_oracle()`.

### 4.2 Phase 0: snapshot

Parquet is the intermediate for a reason beyond the SQL load: it **confines `haven` to one
audited step**, which this package already requires. After conversion nothing downstream
reads a `sas7bdat` again. The same rule carries its caveat: a misread is preserved
faithfully in the parquet, so each conversion is validated with `expect`, not trusted
because it round-tripped.

`snapshot_oracle()` gains three things:

1. **`chunk_rows =`**, default `NULL` for today's behaviour. When set, it reads with
   `haven::read_sas(skip =, n_max =)` and appends row groups through
   `arrow::ParquetFileWriter`, so the output stays **one file with one SHA-256**. A chunk
   whose schema differs from the first chunk's is an error. A 36 GB file cannot be read
   whole, which is the reason this exists.
2. **A source checksum** beside the parquet one. Hashing 36 GB takes minutes, and it is the
   only thing that pins which `sas7bdat` was read. Both go to the manifest.
3. **A metadata sidecar**, `<name>.meta.json`: variable, label, SAS format, SAS type and R
   class. Arrow keeps labels for R readers; SQL Server and the other eleven builds need
   them written down somewhere language-neutral.

`expect` takes the shape from `bd.data.master.log`. That log and `built_2026mar27` carry
matching timestamps from the 8 May run, so it is the right log. The shape is supplied by
hand, not parsed.

**Order:** `built_2026mar27` first, which unblocks phase 1. The other eleven follow as a
background batch from a resumable `dev/` script; `snapshot_oracle()` already refuses to
overwrite, which makes the resume free. It should run on the scan host, not over SMB from
a laptop.

The spec commits to converting **all twelve**. The history is evidence: consecutive
builds separate upstream warehouse drift (many cells, no code change) from corrections (few
cells, tied to a code change), which a single diff cannot. Arrow and duckdb read only the
columns a question needs, which is what makes comparing twelve 30 GB builds feasible.

**Keys.** Phase 0 asserts both candidate keys against the parquet and reports a verdict
only, "unique" or "N duplicates":

- **primary:** `ccfid` plus surgery date. It spans the whole snapshot history back to 2021.
- **alternate:** eMRN plus encounter date, asserted unique where non-null. It is the bridge
  to Epic-era sources.

Neither rests on `masterid`, which the build-layer capture records as unstable since
April 2023. `print_built_comparison()` already documents a `ccfidu` column concatenating
a medical record number with a surgery date; if the master carries it, it is the primary
key in one column, and phase 0 checks it too.

### 4.3 Phase 1: lift

Scripts, under `dev/masters/cardiac/`:

- **DDL generator.** Arrow schema plus sidecar gives `CREATE TABLE`: doubles to `float`,
  dates to `date`, character to `nvarchar(n)` with `n` measured from the data. A
  **preflight fails loudly** past SQL Server's 8,060-byte fixed-width row limit or its
  1,024-column limit. 800 `float` columns is already 6,400 bytes, so this is a live risk.
  If it trips, the fix is two tables joined by the view.
- **Base table named for its release**, `master_cardiac_base_<release>`. The view
  `master_cardiac` selects from it. A later rebuild loads alongside, and the view is
  repointed in one statement. **That repoint is the phase 1 freeze record**: a study citing
  the base-table name and the parquet SHA-256 has pinned its master exactly. A partial
  refresh becomes its own base table, so "which build of the master" is answered by the
  view definition at a moment in time rather than by a date.
- **Load.** Arrow reads the parquet row group by row group into `DBI::dbAppendTable()`,
  with a load-log table so a failure resumes rather than restarts. Throughput is measured on
  the first row group; `bcp` is the fallback only if that is too slow.
- **Labels table**, `master_cardiac_meta`, loaded from the sidecar.
- **Parity check**, on both sides: row count; per column, non-null count, distinct count
  and numeric sum; **and a full value compare on a random sample of rows joined on the
  key.** Aggregates alone pass with compensating errors: `sum` cannot see two cells swap,
  `distinct` cannot see a consistent shift. This is the same argument the vars-port design
  makes for per-rule attrition over one aggregate count. **Output is verdicts**, match or
  mismatch per column, never a minimum, maximum or value.

**Who runs the DDL is open (§9), and the design does not depend on the answer.** The R side
produces the parquet, the DDL and the load step. If we hold the rights we run them; if not,
they are a clean hand-off to data engineering.

### 4.4 The release catalog

`publish_dataset()` (0.2.3) already publishes immutable, dated releases of a logical
dataset into `dataset-catalog.yml`, with checksum and shape. The twelve dated snapshots are
exactly that: releases of one logical dataset, one per extract date, with the follow-up
refresh as a second revision on its date.

**Proposed:** register the snapshots as releases of `master_cardiac`, and derive each base
table's name from its `release_id`. That gives the masters one version history instead of a
second scheme invented beside the first. Two things stand in the way and are open (§9):
publication copies bytes, which is roughly 350 GB duplicated for twelve builds already
sitting immutable on the share; and parquet is not among the formats `publish_dataset()`
accepts.

## 5. The corrections model

### 5.1 The contract is two append-only tables

The SQL view in §5.3 is one implementation. The contract is the two tables, and it is what
HVTR takes over.

**`corrections`**, one row per assertion, never updated:

| field | purpose |
|---|---|
| `correction_id` | identity |
| `master`, `ccfid`, `surgery_date`, and `emrn`, `encounter_date` where known | which record |
| `variable` | **exactly one cell** |
| `expected_prior` | the value the corrector saw |
| `new_value` | text, cast through the type in the metadata table; missing is an explicit flag, not an empty string |
| `evidence_type`, `evidence_ref` | chart review, source document or investigator return, and a pointer to it |
| `asserted_by`, `asserted_on` | provenance |

**`correction_decisions`**: accept, reject or supersede, with who, when and why.

A correction's status is **derived at query time** from the two tables. Nothing is edited in
place, and a losing assertion is retained.

### 5.2 Rules and facts, enforced by the schema

The build-layer capture separates a **rule** (systematic, reproducible, belongs in code) from
a **fact** (a one-off, known only from evidence, can only be stored). A correction names one
record and one variable. **A correction that needs a predicate is a rule**, and it goes into
the derivations, not this table. The schema cannot express a rule, which is the point.

### 5.3 How the view applies corrections

- The latest accepted correction for a cell applies **while the base still holds
  `expected_prior`**. `NA` matches `NULL`.
- If the base holds something else, the correction is **stale**: not applied, and listed in
  `master_cardiac_corrections_stale` for re-adjudication. That is the case where upstream
  fixed the value, or broke it differently, after the correction was made. This is
  compare-and-swap, and it is the argument `snapshot_oracle()` makes about a SAS dataset on a
  shared volume, applied one level down.
- Corrections are long, one row per cell; the master is wide, 700 to 800 columns. So **the
  view is generated**. Only variables with at least one correction get a join and a `CASE`,
  and the view is regenerated when a variable gets its first. Keeping the pivot out of human
  hands is the 2026-08-24 constraint, that nothing built should be so clever only its authors
  can maintain it, applied to SQL.

### 5.4 Backfill of the legacy facts

**The rollup is backfilled, not abandoned.** Its eighteen inline facts are recorded, but in
phases 1 and 2 the base already contains them, because they are baked into the snapshot. So
they go in with evidence "legacy SAS inline" and the file and line, provenance unknown, and
status **`baked`**: recorded, not applied.

**Phase 3 activates them.** When the base becomes the rules-only port, each legacy row's
`expected_prior` is filled from the port's output and it applies like any other correction.
A legacy correction whose prior does not match the port is a port defect or a correction
overtaken upstream, and either way it surfaces.

Parsing and diffing cross-check each other here. A correction found by the parse and not by
the diff was overtaken. A difference found by the diff and not by the parse is an unwritten
fix or a port defect. That four-way split is how backfill completeness is shown rather than
assumed.

### 5.5 Writing a correction

`propose_correction()`, a script until the mitral master needs it, checks the key exists,
the variable exists and the value casts, then appends a row. It prints a verdict, never a
value.

## 6. Failure handling

- A preflight failure (row size, column count, key not unique) **stops before the DDL
  runs**.
- The load resumes from its load log. **The view is created only after parity passes**, so
  a half-loaded or mismatched table is never readable through `master_cardiac`.
- A stale correction is **surfaced, not raised**. It is an expected state, not a fault.

## 7. Phase 3: interface and acceptance, fixed now

- **Input:** the warehouse source views.
- **Output:** a rules-only base table, loaded alongside the snapshot's and swapped in by
  repointing the view.
- **Acceptance:** equal to the loaded snapshot base table **except exactly where activated
  legacy corrections explain it**.

The acceptance test is fixed before the implementation so the port cannot quietly redefine
what correct means once it starts. Phase 3 gets its own spec once phases 0 to 2 exist.

## 8. Testing and PHI

**Tests:**

- **Chunked `snapshot_oracle()`** on the synthetic `oracle_small.sas7bdat` with a tiny
  `chunk_rows`: chunked and unchunked output identical, same SHA-256; a mismatched chunk
  schema fails; the sidecar is right.
- **DDL generator:** snapshot tests on synthetic arrow schemas, and a deliberately over-wide
  schema that must fail the preflight.
- **Correction resolution:** an R reference implementation over data frames, tested on
  synthetic cases: applied, stale, `NA` matching `NULL`, two accepted (latest wins),
  rejected (ignored), baked (not applied). **The generated SQL is restricted to an ANSI
  subset** (`CASE`, `LEFT JOIN`, `ROW_NUMBER()`), so CI runs it on duckdb and asserts it
  agrees with the reference. SQL Server runs only in an integration test gated on an
  environment variable, following `HVTI_ORACLE_DIR`.
- **Real data:** gated, asserting shape and verdicts only, with every failure message checked
  for what it prints.

The ANSI restriction is a design decision as well as a testing convenience. It is what lets
the view move to HVTR's engine without its logic being rewritten.

**PHI:**

- The parquet, the warehouse tables and the corrections live **outside this repository**.
  `.gitignore` already blocks `*.parquet`.
- The legacy facts are **read from `bd.data.master.sas` at run time and written to the
  warehouse**, never transcribed into a script, fixture, test message or transcript. That is
  the vars-port rule, "identifiers are read, never transcribed".
- The `dev/masters/cardiac/` scripts carry no identifiers and are excluded by
  `.Rbuildignore`, so they do not bump the version. The `snapshot_oracle()` change ships, so
  it earns a `NEWS.md` entry under the unreleased heading.

## 9. Open questions

- [ ] **Who runs the DDL and the load**: us, or data engineering. The design works either
      way; the answer decides who is on the critical path.
- [ ] **Load throughput** of `dbAppendTable()` at 36 GB, with `bcp` as the fallback.
- [ ] **SAS user format catalogs.** `haven` reads format names, not the value labels behind
      them, unless given the `.sas7bcat`. Where the rollup's catalog lives has not been
      checked.
- [ ] **The external CSV** the build reads: a source, or a corrections file.
- [ ] **The release catalog (§4.4)**: register the snapshots with `publish_dataset()`,
      given that it copies bytes and does not accept parquet, or record them another way.
- [ ] **Backfill or abandon for the child masters.** Settled for the rollup (backfill);
      the mitral spec asks it again, where the weight is.

## 10. Out of scope

- The mitral master, which is the next spec and builds on `master_cardiac`.
- The `bd` and `vars` templates, and the migration of existing studies (specs 3 to 5).
- The three masters with no warehouse source: external-system, submission-file, and any
  REDCap-held registry. Each needs a load step before a view can see it.
- HVTR integration, beyond keeping the corrections contract storage-independent.
