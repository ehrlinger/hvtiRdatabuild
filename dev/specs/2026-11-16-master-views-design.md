# Master datasets as live warehouse views, and study builds from them

**Date:** 2026-11-16
**Status:** design, approved in conversation 2026-11-16, section by section. Not yet planned.
**Amends:** `2026-09-23-cardiac-master-view-design.md`. Where the two disagree, this spec
wins; the sections it leaves alone (phase 0 snapshot, the DDL generator, the load log, the
corrections contract in §5.1 and §5.2) stand.
**Reads alongside:** issue #101 (corrections gaps G1 to G7, and the 2026-11-05 decision that
corrections move to the registry design) and `2026-09-24-mitral-master-lift-design.md`.

> **Redacted for public release**, as the specs it amends. Individuals are named by role,
> internal paths are placeholders, and **no patient value or identifier appears here.**

---

## 1. What changes, and why

The September spec made a master a **frozen base table** loaded from a SAS snapshot, with a
corrections view over it, and deferred the rebuild from warehouse sources to a "phase 3".
Studies would have read a copy of the March 2026 SAS build for as long as phase 3 took.

This spec reverses the order. **The master is a live view computed from the warehouse
sources, and no copy of it is kept as data.** A study reads current data, and the SAS
snapshot survives only as the answer key the view is checked against.

Decisions, each dated 2026-11-16 and made by the maintainer:

1. **Masters are live views, not cached datafiles.** Studies get up-to-date data directly
   from the warehouse, whatever system that becomes.
2. **Reproducibility is the study's, at pull time.** The view is always current. A study
   build freezes what it pulled and records how (§6). The warehouse holds no dated copies.
3. **The rules are plain SQL model files**, one `SELECT` per file, laid out as a dbt project
   would be, and deployed to the current SQL Server first. dbt is an option, not a plan:
   whether to adopt it is a cost/benefit evaluation for the registry (HVTR) work. The
   layout costs nothing now and keeps that option cheap if it is taken.
4. **Corrections live in interim SQL Server tables** under the §5.1 contract, with gaps G1
   and G7 from #101 folded in. The registry replaces the tables later; the SQL model that
   reads them does not change.
5. **Corrections apply to source values, before the derivations** (§3.2). This replaces the
   September spec's corrections over the finished master.
6. **The cardiac rollup and the mitral master are designed together**, the cardiac built
   first and the mitral used as the stress test before the design is frozen.
7. **Data engineering sets up the warehouse side** (§4). The September spec left this open.
8. **hvtiRdatabuild is the statistical programmers' tool for building study datasets from
   the master views** (§5, §6), plus the parity and intake tooling. It does not record
   corrections itself (the 2026-11-05 decision stands).

## 2. Where this sits

The registry program runs three to five years, and its first year produces a design, not
code. The masters cannot wait for it. Everything here is built in the current SQL Server
warehouse and shaped to be handed over: a standard SQL subset, a dbt-compatible layout, and
a corrections contract independent of storage.

The registry design records, as open, where a correction sits relative to the derivations
that read it. §3.2 is this design's answer for the interim; it is offered to the registry
design as input, not imposed on it.

## 3. The layers

### 3.1 Objects in the warehouse

Names are indicative; the schema layout is agreed with data engineering.

| Layer | Object | Does |
|---|---|---|
| Source | `stg_<source>` views | One per warehouse source table: select, rename, cast. Nothing else. Replaces the `dwpull` SAS step and the `dw_pull()` module queries. |
| Corrections | `corrections`, `correction_decisions` tables; `stg_<source>_corrected` views | Append-only, §5.1 contract. A corrected view is its source view with accepted, current corrections applied to its cells. |
| Rules | `int_<master>_<step>` views, then `<master>` | `bd.data.master.sas` split into named derivation steps, one SQL file each, joined into the wide master. |
| Review | `<master>_corrections_stale`, `<master>_corrections_conflicts` views | For data management. Never read by a study build. |
| Answer key | `<master>_oracle_<date>` table | A SAS build over the gate's database snapshot, loaded by `load_oracle()`, which publishes nothing. Restricted; read only by the parity gate (§7). |

**Amended 2026-11-17 (plan 2a).** These decisions change the table above.

- **Corrections tables are per source:** `<source>_corrections` and
  `<source>_correction_decisions`, not one shared pair. A source's key columns are typed and
  the corrected view joins on them, so a shared table would need text-encoded keys and a
  cast in every join.
- **`master.yml` declares the sources and the deciders:** `sources: {<view>: {key: [...]}}`
  and `deciders: [...]`. The SQL repository's model metadata (plan 3) becomes the authority
  later, and the yml mirrors it until then.
- **Lineage is a contract with plan 3.** `<master>_lineage` (`master_column`, `source`,
  `source_column`) lists exactly the master columns that pass a source column through by
  rename only. A source's key columns carry the same names in the master, and therefore in a
  frozen pull.
- **Intake stores a canonical text form.** Each value is parsed against the source column's
  type and written back as canonical text, so text agreement (G1) is value agreement, and
  `"3.0"` and `"3"` corroborate.
- **Names and keys compare exactly on SQL Server.** The generated views and intake
  compare variable names and character keys with `Latin1_General_BIN2` collation
  plus a `DATALENGTH` check, in every comparison, join, distinct count and `GROUP BY`. A
  key that differs only in case or trailing spaces is a different key, as in the R
  reference. Decisions compare `correction_id`, not keys or variable
  names: the SQL lookup uses the default collation, and the R `match()` that follows makes
  the comparison exact.
- **The views assume intake-canonical values.** They cast stored text with `TRY_CAST` at the
  column's declared type, and intake refuses any value that does not cast back unchanged.
  If a column's type changes after a correction is accepted, the SQL may round where the R
  reference does not. The two agree only on intake-canonical values.

### 3.2 Corrections apply to source values

A correction made to a derived value goes stale whenever its derivation changes, and a
correction made to a source value can be overwritten by a derivation that recomputes from an
uncorrected input. The mitral master has reached the point where this, not storage, limits
maintaining it.

So a correction names **a cell of a source view**: a `stg_<source>` key and column. The
rules read only the `_corrected` views, and every derivation recomputes from corrected
inputs.

This amends the §5.1 contract's record fields: `master`, `ccfid`, `surgery_date` (and the
eMRN pair) become **`source`** (the `stg_` view) and **that view's key columns**, and
`variable` names a column of that view. Every other field stands.

- **A correction to a derived variable is refused at intake** with the verdict
  `derived_variable`. A graded scale collapsed to four levels, or a study-specific
  definition such as posterior-only prolapse versus posterior-only repair, is a named
  derivation in the rules layer, not a series of corrections.
- **The legacy inline fixes** (18 in the cardiac build, many more in the mitral) are
  backfilled as in §5.4 of the September spec, but each must be re-expressed against a
  source column. One that only makes sense against a derived variable becomes a derivation.
  The re-expression is done by reading the SAS program at run time; identifiers are read,
  never transcribed.

### 3.3 Correction semantics, amended

§5.3 of the September spec stands (compare-and-swap on `expected_prior`, `TRY_CAST`, the
stale reasons) with these changes:

- **Every correctable column is covered ahead of time.** The September view joined only
  columns that already had a correction, so a column's first correction needed a view
  regeneration. Here each `stg_<source>_corrected` view is generated from the full column
  list of its `stg_<source>` view, as one pivot of the resolved winners per source, and is
  regenerated only when the `stg_` model itself is deployed. A first correction to a
  previously untouched column is therefore live on the next query with no deployment. A
  correction naming a column the source view does not have is refused at intake
  (`no_variable`).
- **`as_of` is not a view parameter.** An ordinary view cannot take one. Provenance comes
  from the pull (§6), and the historical record is the study's frozen release, not a
  replayed view. An inline table-valued function for replay is deferred until a use needs it.

And two from #101:

- **G1. Disagreeing accepted corrections conflict.** Two accepted corrections to one cell
  with different `new_value`s do not resolve to the latest. Neither applies, the cell keeps
  its source value, and the pair appears in the conflicts view until a `supersede` decision
  settles it. Accepted corrections that agree corroborate and apply.
- **G7. Fill-ins retire themselves.** A correction whose `expected_prior` was missing, where
  the source now holds a value, is split into `filled_upstream_agrees` (the source holds the
  correction's value: retired automatically with a `bake` decision) and
  `filled_upstream_disagrees` (a different value: to the conflicts view).
- **Status order.** A cell gets the first status that holds, in this order: `no_variable`,
  `no_record`, `ambiguous_record` (the key now matches several source rows, so none is
  changed; intake refuses such a key, but a refresh can break uniqueness after a correction
  is accepted), `accepted_disagree` (G1), `prior_unknown`, `does_not_cast`,
  `filled_upstream_agrees` or `filled_upstream_disagrees` (G7), `prior_mismatch`, then
  `apply`. The stale view lists `no_variable` through `prior_mismatch` plus
  `filled_upstream_agrees`; the conflicts view lists `accepted_disagree` and
  `filled_upstream_disagrees`.

G2 (no self-acceptance, a named deciding role) is enforced at the decision step (§3.4). G5
gets an interim helper (§3.5). G3 and G6 remain registry design input and are out of scope
here.

### 3.4 Adding a correction as it is found

Because the master is a view, **a correction is live on the next query once it is accepted.**
Nothing is rebuilt or re-released. The path:

1. **Found.** A statistical programmer, fellow or chart reviewer finds a wrong or missing
   source value.

   Each `stg_` model declares its unique key in model metadata. An encounter-level source's
   key includes the encounter date; a patient-level source's key is the MRN alone, and its
   template rows carry no encounter date, because inventing one would address a study
   encounter rather than that source cell.
2. **Submitted** in a fixed template (G4), one row per cell: source view, **that view's
   declared complete unique key**, column, `expected_prior` (with its missing flag),
   `new_value` (with its missing flag), evidence type and reference, and who asserts it. A
   row without the full key is refused here, not discovered later.
3. **Validated.** `propose_corrections(file, dry_run = TRUE)` returns a verdict per row:
   `appendable`, `unknown_key`, `ambiguous_key`, `does_not_cast`, `rule_not_fact`,
   `derived_variable`, `unknown_source`, `invalid_field`, `no_variable` or `prior_mismatch`.
   It prints verdicts and counts, never values.

   - `unknown_source`: the row names a source `master.yml` does not declare.
   - `invalid_field`: a flag that is not 0 or 1, a flag that disagrees with its value, an
     unknown evidence type, or a blank evidence reference, asserter or variable.
   - `no_variable`: the source has no such column (§3.3), or it is a key column.
   - `prior_mismatch`: the stored prior no longer matches the source (§3.5).
   - `rule_not_fact`: a key or variable cell holding a pattern or comparison
     (`* % ? < > = , ;`) or the word `all` or `any`. It is a predicate, so it is a rule.
4. **Appended.** The same call with `dry_run = FALSE` appends the whole file to
   `corrections` in one transaction, and refuses the whole file if any row fails. Proposed
   corrections do not apply.
5. **Decided.** `decide_corrections()` records `accept`, `reject`, `supersede` or `bake`
   with decider, date and reason. The deciding role is named per master in `master.yml`.
   G2 covers every decision, not only `accept`: a decider who asserted the correction is
   refused (`self_accepted`), and so is one not listed in `deciders` (`not_decider`). One
   correction decided twice in one batch is refused (`repeated_correction`), because the
   rows share a `decided_on` and their order would be arbitrary. `retire_filled_corrections()`
   records the G7 `bake` decision, by the reserved decider `filled_upstream`, for every
   `filled_upstream_agrees` cell. A view cannot write, so "automatic" means one call that
   data management can schedule.
6. **Live.** The next query of `<master>` applies it. A study that already froze keeps its
   pull until it re-pulls, and its freeze record (§6) names the corrections it applied.

A model may help reshape a messy submission into the template, only on institutionally
approved tooling because the sheet carries identifiers. The loader then validates every row;
nothing a model writes reaches the table unvalidated.

**These are interim write tools in a package that is otherwise a reader.** They contradict
the 2026-11-05 decision only for as long as the registry has no intake of its own, and they
ship **already marked as superseded by it**: their help says so, and the registry takes over
the template and the tables unchanged. The existing single-cell `propose_correction()` and
`decide_correction()` stay deprecated; the batch functions replace them for the interim.

### 3.5 Study-side fixes travel up (G5, interim)

A fix made in a study's code leaves the study out of step with the master and every other
study. `study_correction_candidates()` compares a study's corrected analysis data with **the
study's own retained pull** (§6), never with the live view: sources are not time-travelable,
so a later read of the view would mistake upstream change for a study fix.

- A difference in a column the rules pass through from a source (a rename only, as declared
  by the `stg_` and rules models' column lineage) becomes a row of the §3.4 template, keyed by
  that source's declared key, with `expected_prior` taken from the retained pull and the
  study as evidence reference.
- A difference in a derived column is listed separately, as a candidate derivation, not a
  correction (§3.2).

If the source has changed since the pull, compare-and-swap at intake catches it: the
candidate's `expected_prior` no longer matches and the row is refused as `prior_mismatch`
with nothing written. A study fix that upstream has since made for itself is caught the same
way. The helper writes a file for a human to review and submit, never appends, and prints
counts, never values.

## 4. Ownership

- **Data engineering:** the schemas, the rights to deploy views, the corrections tables,
  and loading the answer-key table. A named warehouse engineer leads the setup.
- **The SQL models:** a new repository in the department's Azure DevOps organisation, beside
  the registry repository, laid out as `models/staging`, `models/intermediate`,
  `models/marts`. Data engineering deploys from it, and it moves into the registry later. A
  small deploy step turns each file into `CREATE OR ALTER VIEW`.
- **hvtiRdatabuild:** the study build (§5, §6), the parity gate (§7), and the correction
  interim correction intake (§3.4, §3.5).

## 5. Study builds from the master views

### 5.1 The cohort key is MRN plus encounter date

A study either brings a cohort or defines one, and either way **a cohort row is keyed by
MRN and encounter date, both required**. A patient with two operations is two candidate
rows. Today's `cohort_record` keys on a single `patient_id`; it gains the two-part key.

The master's alternate key (eMRN plus encounter date) is what the cohort joins on. Phase 0
of the September spec already asserts that key unique where non-null.

### 5.2 Two ways to get a cohort

1. **A cohort supplied as a list.** `dw_pull()` writes the key pairs into a **session temp
   table** (`#study_cohort`) and joins it to `<master>`, selecting only the study's columns.
   Any login can create a temp table, so no write right on a shared schema is needed, and it
   disappears at disconnect, so no patient list persists in the warehouse.
2. **A cohort defined by a query** against `<master>`: an epoch (for example January 2000 to
   July 2024) and a procedure predicate. The result is the first stage of the cohort record,
   with `source` naming the view and `provenance` recording the SQL commit and the applied
   correction ids (§6.1). From
   there it proceeds as path 1.

Only the cohort's rows and the study's columns cross the network.

### 5.3 The index operation is declared

A query-defined cohort declares its unit:

- **`index: first`** (default): one row per patient, the earliest qualifying operation in
  the epoch. Later operations remain reachable as follow-up events, for example reoperation.
- **`index: all`**: one row per qualifying operation.

With `first`, a patient whose qualifying operation in the epoch was preceded by another
before the epoch starts is a redo, not a first. The query reports these as **a counted
cohort stage** the study keeps or excludes. It never drops them silently.

### 5.4 Matching

Matching is exact on encounter date. The pull reports how many cohort rows matched no
master row and how many matched more than one, as counts, never values. More than one match
is an error, since the key is meant to be unique. A date-window match, for encounters that
are not surgeries, is out of scope until a study needs one.

## 6. The freeze record

### 6.1 A consistent pull

A pull is several statements: create `#study_cohort`, load it, read the applied corrections,
read the join. **They run in one transaction under snapshot isolation**, so every read sees the
warehouse as of the transaction's start, and a decision or deployment that commits meanwhile
is invisible to all of them alike. This needs `ALLOW_SNAPSHOT_ISOLATION` on the warehouse
database (§10).

The correction record is not a timestamp read beside the data. Inside the same transaction the pull
reads **the ids of the corrections it applied** to its cohort's rows, from a companion
`stg_<source>_corrections_applied` view generated beside each corrected view. Ids and counts
only, no values. That set is exact provenance whatever order decisions committed in, which a
timestamp or a max id is not.

### 6.2 The release

A study build is pull, then `build_dataset()` / `derive_vars()` and the cohort record, then
`publish_dataset()`. The release records and retains:

- **the pull itself**, as a checksummed, cohort-scoped parquet of what the view returned,
  before any study derivation. It is the baseline §3.5 compares against, and the only
  record of the source values the study saw;
- the SQL model repository commit the views were deployed from;
- the applied correction ids (§6.1) and the pull's transaction start time;
- the study configuration's checksum;
- the built dataset's SHA-256 and shape.

Sources are not time-travelable, so **the release, not the warehouse, is the record**. A
study can say which master logic, which corrections and which study logic produced its
numbers; its retained pull and built file are the data. The retained pull holds patient
values and lives in the study's data folder under the same rules as the built dataset,
never in a repository.

⚠️ `publish_dataset()` does not accept parquet today (§9 of the September spec). Accepting it,
and carrying a second file per release, is part of this work.

## 7. The parity gate

### 7.1 One source state for both sides

The answer key cannot be the March 2026 build: the rules view reads today's sources, and a
compare against March would mix port defects, legacy fixes and upstream change. Nor is "the
same day" enough. A SAS build at 09:00 and a comparison at 15:00 read different sources if
anything was loaded in between, and the gate could not tell that apart from a port defect.

**Both sides read one frozen source state.** For the gate run, data engineering creates a
read-only **database snapshot** of the warehouse database (`CREATE DATABASE … AS SNAPSHOT
OF`). `bd.data.master.sas` runs against the snapshot, and the rules models are deployed into
a gate schema that reads the same snapshot. Neither side ever sees a later write.

Where a database snapshot is not available (§10), the fallback fails closed: the gate records
a per-source change marker (row count and a `CHECKSUM_AGG` of a row hash, or change tracking
where enabled) before the SAS run and again after the comparison, and **any change voids the
run**. The verdicts and markers are kept as evidence, and the gate is rerun. A void run never
yields a pass.

### 7.2 Loading the oracle without publishing it

`lift_master()` as it stands loads a base table, checks it against its own parquet, records a
passing parity row, overwrites the master's metadata and repoints the master view at the
table (`.publish_views()`). Used on the oracle, it would replace the rules view with the
oracle and record a pass that compared no derivations.

So the gate gets its own two steps, and neither touches the master view, its metadata or its
parity records:

- **`load_oracle()`**: snapshot and load the SAS output as `<master>_oracle_<date>`,
  with the load-integrity check against its parquet recorded as *oracle integrity*, never as
  master parity. It shares the DDL and load code with `lift_master()` but not its publishing
  tail.
- **`parity_gate()`**: the full keyed comparison of the **deployed rules view** in the gate
  schema with the oracle, inside the database. Every differing cell must be explained by an
  activated legacy correction. Output is a verdict per column, never a value. A pass is
  recorded against **the SQL model commit and the deployment it tested**, and only a master
  deployed from that commit counts as gated.

The twelve historical snapshots remain the record of what SAS produced. They are not the gate.

A master whose current deployment has no passing gate record is not offered to study builds.

## 8. Failure handling

- A model that does not run on the synthetic fixtures is never deployed.
- A parity mismatch blocks the master from study builds (§7). A source change during a
  fallback gate run voids the run; it never passes.
- Loading the oracle or failing the gate never changes the master view, its metadata or its
  parity records (§7.2).
- A pull that cannot open its snapshot-isolation transaction stops; it does not fall back to
  separate reads (§6.1).
- Stale and conflicting corrections are surfaced in their views, not raised.
- Correction intake validates a whole file before writing anything, and refuses it if any
  row fails: `unknown_key`, `ambiguous_key`, `does_not_cast`, `rule_not_fact`,
  `derived_variable`, `unknown_source`, `invalid_field`, `no_variable` or `prior_mismatch`.
  A decision by the correction's own asserter is refused
  (`self_accepted`); decisions also refuse `not_decider` and `repeated_correction`. Verdicts only, no values in any message.
- A cohort match with duplicates stops the pull (§5.4).

## 9. Testing and PHI

- **SQL models** are restricted to a standard subset (`CASE`, `LEFT JOIN`, `ROW_NUMBER()`,
  no vendor functions beyond `TRY_CAST`) and run on duckdb against synthetic `stg_`
  fixtures in the SQL repository's pipeline.
- **Correction resolution** keeps its R reference implementation in hvtiRdatabuild's
  testthat suite, checked against the generated SQL on the same synthetic cases, now
  including G1 conflicts and the two G7 fill-in outcomes.
- **Correction intake:** every verdict on a synthetic template, whole-file refusal when one
  row fails, `self_accepted`, and `study_correction_candidates()` separating source-column
  candidates from derived-column ones.
- **Study builds:** the cohort temp-table join, index `first` and `all`, the pre-epoch stage,
  and duplicate-match failure, on duckdb with synthetic data.
- **First correction to an untouched column** is applied on the next query with no
  deployment, because the corrected view already covers every column (§3.3).
- **Source keys:** intake against a patient-level source (key without encounter date) and an
  encounter-level one.
- **Study-side candidates after upstream change:** a source cell changed after the study's
  pull is refused at intake as `prior_mismatch`, and a pass-through difference against the
  retained pull yields the right `expected_prior` (§3.5).
- **Consistent pull:** a decision committed during a pull is absent from both the data and
  the applied correction ids, on SQL Server in the integration rehearsal (duckdb has no
  snapshot isolation to test it with).
- **Gate isolation:** `load_oracle()` and a failing `parity_gate()` leave the master view,
  metadata and parity records untouched; a pass is bound to the tested commit, and a master
  deployed from another commit is not gated.
- **Gate rehearsal:** an upstream write between the SAS run and the comparison voids a
  fallback run; under a database snapshot it cannot reach either side.
- **Real data:** gated, shape and verdicts only, every failure message checked for what it
  prints.
- The SQL repository holds logic only. No identifier, fixture copied from real data, or
  credential enters it.

## 10. Open questions

- [ ] **Temp-table rights.** That statistical programmers' logins can create `#` tables in
      `tempdb` on the warehouse server. Normally granted; confirm with data engineering.
- [ ] **Deploy path.** Who runs the deploy step, and from which pipeline.
- [ ] **Read access to the masters.** Whether study builds read through a role granted on
      the views only, so no programmer needs rights on the source tables.
- [ ] **The mitral stress test.** Which of its derivations (the discharge echo is the known
      hard one) must be modelled before the cardiac design is frozen.
- [ ] **Encounter-date semantics** for masters whose encounter is not a surgery.
- [ ] **Snapshot isolation.** `ALLOW_SNAPSHOT_ISOLATION` on the warehouse database (§6.1).
- [ ] **Database snapshots for the gate.** Rights to create one, and whether SAS can read it
      through its existing connection (§7.1); otherwise the fail-closed fallback is the gate.
- [ ] **Corrected-view performance** of a pivot over every column of a wide source (§3.3),
      measured on the largest source before the design is frozen.

## 11. Out of scope

- Corrections gaps G3 and G6, which are registry design input.
- Masters with no warehouse source (external systems, submission files, REDCap registries).
- Whether to adopt dbt (a cost/benefit evaluation for the registry work), and the move to
  the registry's engine.
- The `vars` template and the migration of existing studies (specs 4 and 5 of the September
  plan), which build on §5 here.
