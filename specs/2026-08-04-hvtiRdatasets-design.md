# hvtiRdatasets: SAS Dataset-Building Migration

**Date:** 2026-08-04
**Status:** Approved design, pending implementation plan
**Package:** `hvtiRdatasets` (new)
**Repo:** `github.com/ehrlinger/hvtiRdatasets`. Drafted in `hvtiRutilities/specs`
alongside the Phase 0 spec it amends; moved here when the repo was created. The
Phase 0 amendment itself remains in `hvtiRutilities`.
**Supersedes:** the `bd`/`vars`/`dt` → `hvtiRutilities` ownership line in
`2026-07-10-sas-macro-canonicalization-design.md`

> **Redacted for public release.** This repository is public, so internal
> infrastructure identifiers are replaced with placeholders throughout:
> `<DW-SERVER>`, `<PORT>`, `<DW-DB>`, `<SCHEMA>`, `<warehouse>`, `<Module>`,
> `<AD-DOMAIN>`, `<dbcreds>.sas`. The real values are in the SAS templates on
> the internal volume; they are not needed to follow the design, and publishing
> a production database host, its port, and the location of a plaintext
> credential file would be gratuitous. Keep it that way when editing.

## Context

The CORR group is reimplementing its legacy SAS library in the `hvti*` R
packages. Counting template files under `development/template`:

| Stage | R / Quarto templates | Owner |
|---|---|---|
| `graphs/` | 66 | `hvtiPlotR` |
| `analyses/` | 34 | assigned |
| `descriptive/` | 13 | assigned |
| `documents/` | 3 | assigned |
| `distributions/` | **0** (35 `.sas`) | `TemporalHazard` / `hvtiPlotR` per Phase 0 |
| `estimates/` | 0 (no code; README only) | — |
| **`datasets/`** | **0** (37 `.sas`) | **none** |

Two code-bearing stages have no R at all. `distributions/` is already assigned
by the Phase 0 phase plan — its `ac`/`nd`/`cd` prefixes map to `TemporalHazard`,
`dp` to `hvtiPlotR`. **`datasets/` is the only stage with neither R nor an
owner**, and it sits upstream of every other stage.

Everything downstream already runs in R. The bridge is `tp.bd.SAStoR.sas`,
step 7 of the documented workflow. So this is not one more port among many — it
is the missing first link, and closing it is what lets SAS leave the building.

This work is **independent of the Phase 1 SAS oracle** described in the macro
canonicalization spec. See *The oracle already exists*.

## Problem

### The corpus is three populations, not one

Measured across `development/template/datasets/templates`:

| Kind | Files | Signature | Ports to |
|---|---|---|---|
| **Variable-list fragments** | `tp.vars.aorta`, `.cabg`, `.cadmainpo`, `.vlvanatpath`, `.vlvrpr`, `.supplemental` | 26–189 lines, **0 macros, 0 procs** | package **data** |
| **Macro libraries** | `tp.vars.sas` (`%vars`), `tp.bd_sgroups` (`%bdsgroups`), `tp.bd.mult.imput` (`%before`/`%imput`/`%after`) | parameterized, callable | **functions** |
| **Straight-line scripts** | `tp.bd.data.master` (1134 ln), `.fup`, `.geoid`, `.ses`, `.repeated.events`, `.snipits`, `tp.dt.check` | data steps + procs, top to bottom | **study scaffold** |

Treating these uniformly is the primary design error available here. The
variable-list fragments are *data* with literature citations attached
(`tp.vars.aorta.sas` cites Svensson et al.); rendering them as R code would
discard the citations and gain nothing.

### `%macro skip` is a block-comment idiom, not a helper

`%skip` is called **zero** times in `tp.bd.data.master.sas`. Code is wrapped in
`%macro skip; … %mend skip;` to *disable* it. This is why
`%macro build; /* PROTECT THESE! */` exists at line 935 — a nine-line wrapper
whose only purpose is to sit outside a skip block so it actually executes.

Measured:

| File | Total | Live | Disabled | `%macro skip` blocks | Share disabled |
|---|---|---|---|---|---|
| `tp.bd.data.master.sas` | 1134 | 950 | 174 | 5 | **15.3%** |
| `tp.vars.sas` | 938 | 742 | 195 | 1 | **20.8%** |

(Totals include the `%macro skip` / `%mend skip` delimiter lines, which are
neither live nor disabled.)

These templates are therefore not pipelines. They are **catalogs of optional
steps**, where each analyst uncomments the subset their study needs.

### The consequence: study configuration is invisible and unrecoverable

Because enabling a step means editing a copied script, the record of *what a
given study actually ran* exists only as a diff against a template nobody
retained. There is no manifest of enabled modules, no record of which variable
sets were pulled, and no way to reconstruct a build six months later except by
reading the analyst's copy of the script.

This — not translation difficulty — is the strongest argument for the port. The
R design must make study configuration **explicit, declarative, and committed**.

### Documented signatures do not match code

`tp.vars.sas` documents ten calling arguments in its header block: `IN, OUT,
IMPUTE, MISSING, PROPEN, PROPENDS, TRANSF, MATCH, MATCHDS, ID`. The actual
definition is:

```sas
%macro vars(in=built, out=built, missing=0,
            propen=0, propends=library.propen, transf=1,
            match=0, matchds=library.matches, id=ccfid);
```

**`IMPUTE=` does not exist.** The header documents a parameter the macro does
not accept. Header blocks are claims, not ground truth. (Recorded here because
`sas_macro_signature()` in Phase 0 parses exactly these blocks; see
*Amendments*.)

### The templates corpus was never triaged

Phase 0 counted `development/template` (229 files) but triaged only
`macro.library`. `%vars` already has **two divergent bodies** in the templates
corpus — `tp.vars.sas` (938 lines) and `tp.vars_base_only.sas` (663 lines) —
confirmed by normalized body hash. Slice S3 must resolve which is canonical.

### The pull is not SAS logic

`tp.stXXXX_dwpull.sas` connects by ODBC to SQL Server and passes T-SQL through
verbatim:

```sas
CONNECT TO ODBC (noprompt="driver=ODBC Driver for SQL Server;
  server=<DW-SERVER>,<PORT>; database=<DW-DB>; ...");
CREATE TABLE WORK.base AS
SELECT * FROM connection to ODBC
  (select c.*, s.* from <DW-DB>.<SCHEMA>.stXXXX_cohort c
   inner join <warehouse>.dbo.vw_<Module>_Base s on c.masterid = s.masterid);
```

SAS is a dumb ODBC client. Porting the pull is lifting the inner SQL into
`DBI::dbGetQuery()` against the same driver and server — the easiest part of the
migration, not the hardest.

### The 8-character constraint is an XPORT artifact

`tp.bd.data.master.sas` opens with: *"Use only 8-character variable names and
40-character labels for compatability with hazard program."* The actual bridge
is `tp.bd.SAStoR.sas:232`: `libname out xport "&STUDY/datasets/built.xpt"`, read
with `foreign::read.xport()`. SAS Transport v5 enforces exactly 8-character
names and 40-character labels.

Confirmed with the group: the hazard program does **not** independently enforce
this, and a path exists to release the constraint regardless. It dies with
XPORT. See *Variable naming policy* for the sequencing.

## Goals

Ship an R package that builds a study's analysis-ready dataset from the data
warehouse, with per-variable proof that it matches the SAS-built dataset.

## Non-goals

- No propensity matching. `tp.bd.gmatch_greedy_mayo`, `.opt_match`,
  `.permpairs`, `.permfullcohort`, `.propen.before_after` → `hvtiPropensityScores`.
- No replacement for `tp.bd.SAStoR.sas`. It dies by construction.
- No SAS execution, on any host, at any point.
- No relocation of governance functions out of `hvtiRutilities`.
- No R implementation of any macro outside `datasets/`.

## Design

### Package boundary

New package `hvtiRdatasets`. One job: **warehouse → analysis-ready dataset,
with proof it matches SAS.**

```
Imports:  hvtiRutilities, DBI, odbc, haven, dplyr, yaml
Suggests: arrow, testthat (>= 3.0.0), withr, knitr, quarto
```

Not a CRAN target, so the 10-minute check budget does not apply. The rest of
the release gate does.

**Governance stays in `hvtiRutilities`.** `verify_manifest()` guards any
extract, not just built datasets, and `hvti_graphics/data_governance.qmd`
already teaches `data_dictionary()`, `label_map()`, `update_manifest()`, and
`verify_manifest()` as one unit. Relocating them would force `hvtiPlotR` to
depend on a package carrying DBI and odbc in order to call `label_map()`,
pushing the database stack from a leaf into the base of the dependency tree.

The dependency is nearly free. Of `hvtiRutilities`'s imports, `haven`, `dplyr`,
and `yaml` are needed here regardless; `digest` is needed for oracle checksums;
`labelled` is needed for label handling; `tools` ships with R. The marginal cost
is `readxl`.

### Execution environment

R runs on **the same Linux server as SAS**, against the same volumes and the
same network position. Three consequences:

1. Warehouse reachability and ODBC driver availability are given, not risks.
2. PHI containment is structural. No data crosses a machine boundary; the
   existing access controls apply unchanged.
3. **`keyring` is not the default credential mechanism.** It assumes a Secret
   Service daemon, which a headless server does not have.

### Credentials

`%include "/home/XXXX/<dbcreds>.sas"` — a plaintext password interpolated into a
connection string — is not ported.

Analysts reach the server through **RStudio Server**, which spawns an ordinary
per-user R session and so honours R's normal startup files. That makes several
mechanisms available; they are not equally safe.

`dw_connect()` resolves credentials in this order, stopping at the first hit:

1. **Kerberos integrated auth** against the AD domain (`<AD-DOMAIN>`), via
   the Microsoft ODBC driver and an existing ticket. No stored secret at all.
   Availability is unconfirmed — SAS used `uid`/`pwd` — and is an open question
   below. If available, it is strictly the best option and the others become
   fallbacks.
2. **A named ODBC DSN** in `~/.odbc.ini` (mode `600`), where the *driver* holds
   the credentials.
3. `HVI_DW_UID` / `HVI_DW_PWD` from `~/.Renviron` (mode `600`).
4. `keyring`, if configured. Documented, not default: it assumes a Secret
   Service daemon that a headless server does not provide.
5. Interactive prompt, when the session is interactive.

**Why the DSN outranks `.Renviron`.** `.Renviron` places the password in the R
process environment, where `Sys.getenv()` prints it and any handler that dumps
the environment on error captures it. A DSN password is read by the driver and
never enters R's memory. `Sys.getenv()` cannot leak what it never held.

`dw_connect()` **checks the file mode of whichever source it uses and errors if
it is more permissive than `600`.**

**RStudio Server hazards, both handled by the scaffold.** R reads exactly one
user `.Renviron`, and a project-level file **overrides** the home one rather
than merging with it — so a stray `.Renviron` in a study repo silently shadows
`~/.Renviron`, presenting as "my credentials vanished." Project-level
`.Renviron` files are also precisely the kind of file that gets committed by
accident. `use_study_dataset()` therefore writes `.Renviron` and `.odbc.ini`
into the scaffold's `.gitignore`, and `dw_connect()` warns when a project-level
`.Renviron` is shadowing the user one. Separately, `.Renviron` is read only at
session start: after editing it, the R session must be restarted.

Credentials never appear in a function argument, a `study.yaml`, a log line, or
an error message. Connection strings are never echoed. Nothing credential-shaped
is committed.

### Configuration model

This is the load-bearing decision. The SAS catalog-of-optional-steps becomes an
explicit, committed `study.yaml`:

```yaml
study: st1234
cohort_table: <DW-DB>.<SCHEMA>.st1234_cohort
pull_date: 2026-08-04
modules: [base, valve, cabg, cardsurg, surgproc, pocomp, fup, events, echo]
varsets: [core, aorta]
derive:
  missing: true
  transform: true
  propensity: false
```

Enabling a step becomes a diffable config change rather than an uncommented
block. This mirrors the YAML conventions already in `R/manifest.R`.

`study.yaml` is validated against a schema on load. An unknown key is an error,
not a warning — a typo'd module name must not silently disable a module.

### Units

| Unit | Signature | Responsibility |
|---|---|---|
| `read_study_config()` | `(path)` → `study_config` | Load and validate `study.yaml`. |
| `dw_connect()` | `(dsn, ...)` → `DBIConnection` | Resolve credentials, open connection. |
| `dw_pull()` | `(config, conn)` → `list` of raw tables + pull manifest | Execute per-module queries. |
| `build_dataset()` | `(raw, config)` → `built` | Joins, `ccfidu`, dates, labels, competing risks. |
| `derive_vars()` | `(built, config)` → analysis-ready | The `%vars` port. |
| `build_followup()` | `(built, events, config)` → fup + listing | The `tp.bd.fup` port. |
| `snapshot_oracle()` | `(sas_path, out)` → checksummed parquet | One-time oracle conversion. |
| `compare_built()` | `(oracle, r, id, tolerance)` → verdict table | Per-variable equivalence. |
| `use_study_dataset()` | `(path)` → files written | Scaffold `study.yaml` + Quarto skeleton. |

Variable-list fragments ship as **package data** under `inst/extdata/varsets/`,
one YAML per set, carrying variable names, labels, source module, and the
literature citations present in the SAS originals.

### Data flow

```
study.yaml
  → read_study_config()          → validated config
  → dw_connect()                 → DBI connection (credentials never in config)
  → dw_pull()                    → raw module tables + pull manifest
  → build_dataset()              → built
  → derive_vars()                → analysis-ready
  → build_followup()             → fup + listing
        │
        ▼
  compare_built() ◄── snapshot_oracle() ◄── library.built (.sas7bdat, in place)
        │
        ▼
  per-variable verdict table
```

### The oracle already exists

The Phase 0 spec treats the SAS oracle as an open problem — cross-system
execution, transfer mechanisms, whether a human must be in the loop. That is
true for **macros**. It is not true for **datasets**.

Every completed study already has `library.built` on disk as a `.sas7bdat`.
`haven::read_sas()` reads it. Dataset equivalence is a purely local diff:
rebuild in R, read the SAS output, compare. **No SAS execution, no cross-system
transfer, and no PHI leaving the volume it already lives on.**

This decouples the dataset track from the Phase 1 blocker entirely.

### Oracle format: checksummed parquet snapshots

`snapshot_oracle()` reads each study's `library.built` **once** with `haven`,
writes `arrow::write_parquet()`, and records path, row count, column count, and
a SHA-256 hash via `update_manifest()`.

Rationale:

- **Immutability.** `library.built` can be regenerated. A mid-migration SAS
  rebuild would silently change the reference and turn yesterday's green red for
  reasons unrelated to the R code. A checksummed snapshot is a citable fixed
  point.
- **Speed.** The oracle is re-read hundreds of times across test iterations.
- **Isolation.** It confines `haven` to a single audited step. Encoding has
  already bitten this codebase once (`183a1cb`, Latin-1 in SAS sources).

**Parquet does not remove `haven` from the chain.** A misread is faithfully
preserved. `snapshot_oracle()` therefore validates the conversion against
SAS-side `PROC CONTENTS` / `PROC MEANS` output captured at snapshot time, and
records the comparison alongside the checksum. A conversion that cannot be
validated is an error, not a warning.

**Label round-trip must be tested, not assumed.** `arrow` preserves R attributes
through R-specific parquet metadata, so labels survive R → R but are invisible
to a non-R reader. Given `label_map()`'s role, an explicit round-trip test is a
deliverable.

`arrow` is in **Suggests**: snapshotting is a one-time developer operation, not
something every user runs, and `arrow` is a large binary dependency.

### Verification

`compare_built(oracle, r, id = "ccfidu")` joins on the study identifier and
classifies **each variable**:

| Verdict | Meaning |
|---|---|
| `identical` | Exact match across all rows. |
| `within_tolerance` | Numeric, differs by less than `tolerance`. Reports max absolute and relative difference. |
| `differs` | Reports differing row count (`n_differ`). Identifiers are deliberately **not** reported — `ccfidu` is a medical record number concatenated with a date of surgery, which is PHI. |
| `absent_in_r` / `absent_in_sas` | Present on one side only. |
| `type_mismatch` | Shared name, incompatible class. |

Comparison rules: numerics by `all.equal` with an explicit tolerance; characters
exact after `trimws()`; dates after normalizing the SAS 1960-01-01 origin;
factors by level *and* label. No SAS special missing values (`.A`–`.Z`) appear
in `tp.vars.sas` or `tp.bd.data.master.sas`, so plain `NA` handling suffices —
asserted by a test so the assumption fails loudly if a future study violates it.

Row-set differences are reported separately from value differences: an `id` in
one side and not the other is a cohort discrepancy, a different class of problem
from a miscomputed variable, and conflating them hides both.

**`compare_built()` returns a table and does not emit a single pass/fail.** A
tool that collapses 500 variables to one boolean launders real differences into
a green check. This follows Rule 6 of the Phase 0 spec and `.auto_count_rows()`
in `R/manifest.R`: refuse to guess.

Acceptance is a human reading the verdict table and recording a decision in
`equivalence_signoff.yaml` — one entry per variable that is not `identical`.
Same closed loop as `macro_overrides.yaml`.

**A signoff carries a `resolution`, not just a reason.** A correct R port can
legitimately fail equivalence, because SAS semantics differ from R's in ways
that produce wrong answers in SAS. The canonical case: **in SAS a missing
numeric sorts below every number**, so `if bmi < 18.5 then underweight = 1;`
classifies missing BMI as underweight. In R, `NA < 18.5` is `NA` and the row is
excluded. R is right; the numbers differ.

Three resolutions are therefore permitted:

| `resolution` | Meaning |
|---|---|
| `matches` | Difference is cosmetic or within tolerance. Explain and accept. |
| `r_defect` | R is wrong. Fix R; the entry is temporary and must disappear. |
| `intentional_divergence` | **SAS was wrong.** R is correct and deliberately differs. Requires a description of the SAS defect and its effect on published results. |

Without the third category the harness silently pressures the port to reproduce
SAS defects in order to show green, which inverts the purpose of the exercise.
Every `intentional_divergence` is a finding the group needs to see, because it
may affect already-published analyses.

```yaml
- variable: underweight
  resolution: intentional_divergence
  sas_defect: >
    `if bmi < 18.5` treats missing BMI as underweight, because SAS orders
    missing numerics below all values. 34 of 2,918 patients affected.
  r_behaviour: Missing BMI yields NA, not 1.
  affects_published: unknown — flag to study team
  decided_by: JE
  decided_on: 2026-08-04
```

### Variable naming policy

The 8-character constraint dies with XPORT, but **not before equivalence is
established**. `compare_built()` joins by variable name; renaming `dt_surg` to
`date_of_surgery` makes every variable read `absent_in_sas` and destroys the
ruler.

Therefore:

- **S0–S4 preserve SAS variable names exactly.** Non-negotiable.
- New variables with no SAS counterpart may use descriptive names immediately.
- A post-equivalence rename pass is driven by an explicit map in `study.yaml`,
  applied *after* `compare_built()` is green, so the mapping is auditable and
  the equivalence result stays reproducible.

### Slice sequence

Each slice ends with `compare_built()` green — or every difference explained and
signed off — against one real completed study.

| Slice | Content | Source |
|---|---|---|
| **S0** | `snapshot_oracle()`, `compare_built()` | extends `compare_datasets()` |
| **S1** | Pull: `dw_connect()`, `dw_pull()`, pull manifest | `tp.stXXXX_dwpull`, `ccfpull`, `snapshotpull` |
| **S2** | Assemble: joins, `ccfidu`, dates, labels, competing risks | `tp.bd.data.master.sas` |
| **S3** | Derive: `%vars` port, varsets as data | `tp.vars*.sas` |
| **S4** | Follow-up | `tp.bd.fup`, `tp.bd.fuplist` |
| **S5** | Repeated events / longitudinal restructuring | `tp.bd.repeated.events*` |
| **S6** | Multiple imputation | `tp.bd.mult.imput*` |
| **S7** | Geocoding and SES enrichment | `tp.bd.geoid`, `tp.bd.ses` |

**S0 ships first.** Equivalence proven on a real study is a stated requirement,
and it is unachievable if the differ arrives last. Build the ruler before the
thing being measured.

**S6 needs a different acceptance criterion.** `mice` and `PROC MI` will not
produce identical draws. Equivalence there means agreement in distribution and
in downstream estimates, not value equality. Naming this now rather than
discovering it at slice 6.

**S3 must first resolve the `%vars` divergence** between `tp.vars.sas` and
`tp.vars_base_only.sas`.

### Documentation

Two documents, with different audiences and different jobs. Both are package
vignettes so they are versioned with the code and rebuilt by `R CMD check`.

**`vignette("building-a-study-dataset")` — how to use the package.** Task-shaped,
following one study end to end: `use_study_dataset()`, editing `study.yaml`,
`dw_connect()`, `dw_pull()`, `build_dataset()`, `derive_vars()`, then
`compare_built()` against the oracle and reading the verdict table. Runs against
**synthetic data with a mocked connection**, so it builds anywhere, carries no
PHI, and needs no warehouse. Written for someone who already knows what they
want and needs to know which function does it.

**`vignette("coming-from-sas")` — the migration guide.** Concept-shaped, for an
analyst fluent in the SAS templates who now has to read and write R. Its job is
not to teach R; it is to **make the group's existing SAS knowledge transferable,
and to inoculate against the specific ways a naive translation silently gives
wrong answers.** Four parts:

1. **The model shift.** SAS mutates a dataset through sequential steps, and the
   program *is* the record of what happened. R passes values through functions,
   and `study.yaml` is the record. This is why `%macro skip` toggling becomes
   config: the thing that was invisible becomes the thing that is committed.

2. **Idiom translation**, in the group's own vocabulary:

   | SAS | `hvtiRdatasets` / R |
   |---|---|
   | `%include "<dbcreds>.sas"` + `CONNECT TO ODBC` | `dw_connect()` |
   | `PROC SQL; SELECT … FROM connection to ODBC` | `dw_pull(config, conn)` |
   | `libname library "&STUDY/datasets"` | paths in `study.yaml` |
   | `%macro skip; … %mend skip;` | `modules:` / `derive:` toggles in `study.yaml` |
   | `%vars(in=built, out=built, transf=1)` | `derive_vars(built, config)` |
   | `data x; set y; … run;` | `dplyr` pipeline |
   | `PROC CONTENTS` | `hvtiRutilities::data_dictionary()` |
   | `label x = 'Age at surgery';` | `labelled` + `hvtiRutilities::label_map()` |
   | `first.id` / `last.id` | `group_by()` + `slice_head()` / `slice_tail()` |
   | `libname out xport` → `read.xport()` | parquet, or just return the object |

3. **The traps** — the core of the document, because each one produces a
   *plausible wrong number* rather than an error:

   - **Missing sorts low.** `if x < 5` includes missing `x` in SAS, excludes it
     in R. The most common source of real divergence, and the reason
     `intentional_divergence` exists above.
   - **Blank-padded character comparison.** `'a' = 'a '` is true in SAS, false
     in R. Bites on merges keyed by character IDs.
   - **`MERGE` is not a join.** A data-step `MERGE` on a non-unique BY key does
     not error; it produces undefined results. Worked example: the documented
     defect in `tp.bd.data.master.sas` — *"07/03/23: Changed the join logic for
     the FUP dataset to correct many-to-1 join problem when patient has multiple
     surgeries."* R's `dplyr::left_join()` warns on many-to-many; that warning is
     a feature, and must not be suppressed.
   - **Date origins differ**: SAS 1960-01-01, R 1970-01-01. `haven` handles it;
     hand-rolled conversions silently shift by 3,653 days.
   - **Automatic variables.** `_N_`, `_FREQ_`, `_TYPE_` have no R equivalent and
     must be constructed explicitly. Phase 0 already found a bug of exactly this
     class: `keep _freq_ tau` versus `keep freq tau`.
   - **`length 4`** truncates numeric precision on write. Values read back from
     an old dataset may not match a freshly computed R value, and the SAS side
     is the lossy one.

4. **Verifying your own port**, using `compare_built()` on a study the reader
   already knows — closing the loop, so the guide ends with a habit rather than
   a fact.

The traps section is the deliverable that justifies the document. Everything
else is convenience; that section prevents wrong published numbers.

## Error handling

Following the established house philosophy: expensive or uncertain operations
are opt-in and fail loudly.

- An unknown key in `study.yaml` is an error. A typo must not silently disable
  a module.
- A credential file (`~/.odbc.ini`, `~/.Renviron`) more permissive than `600` is
  an error, not a warning.
- A project-level `.Renviron` shadowing the user-level one produces a warning
  naming both paths, because the failure otherwise presents as vanished
  credentials.
- A `dw_pull()` module returning zero rows is an error unless the config
  explicitly declares it optional.
- An oracle whose recorded checksum does not match the file on disk is an error.
  Verification against a drifted oracle is worse than no verification.
- A `snapshot_oracle()` conversion that cannot be validated against SAS-side
  `PROC CONTENTS` / `PROC MEANS` is an error.
- `compare_built()` never reduces to a boolean and never silently drops a
  variable. A variable absent from both sides is itself reported.
- No credential value ever appears in an error message or log line.

## Testing

`testthat`, edition 3. Fixtures are small synthetic datasets containing **no
PHI**, generated by `hvtiRutilities::generate_survival_data()` where possible.

| Fixture / test | Exercises |
|---|---|
| Synthetic SAS-shaped `.sas7bdat` | `snapshot_oracle()` round-trip |
| Labelled data frame → parquet → read | **Label round-trip through arrow** |
| Identical frames | `compare_built()` reports all `identical` |
| One variable perturbed below tolerance | `within_tolerance`, correct max diff |
| One variable perturbed above tolerance | `differs`, correct `n_differ`; no identifiers reported (PHI: an identifier here is a medical record number concatenated with a date of surgery) |
| Frames with disjoint `id` sets | Row-set difference reported separately |
| Renamed variable | `absent_in_r` + `absent_in_sas`, not a false match |
| Numeric vs character same name | `type_mismatch` |
| Date column with SAS origin | Origin normalization |
| Special missing `.A` present | Asserts the no-special-missings assumption fails loudly |
| `study.yaml` with unknown key | Error |
| Credential file at mode `644` | Error |
| Project-level `.Renviron` present | Shadowing warning names both paths |
| Scaffold written by `use_study_dataset()` | `.gitignore` covers `.Renviron` and `.odbc.ini` |
| Mocked DBI connection | `dw_pull()` without a live warehouse |

Critical assertions:

1. **`compare_built()` never returns a scalar verdict.**
2. **Labels survive the parquet round-trip.**
3. **A renamed variable is never reported as matching.**
4. **No test requires warehouse access.** Every DB path is mocked, so the suite
   runs anywhere.
5. **No credential appears in any test output.**

## Deliverables

1. `hvtiRdatasets` package skeleton: `DESCRIPTION`, `NAMESPACE`, `LICENSE`,
   pkgdown config, GitHub Actions check workflow.
2. `R/compare_built.R`, `R/snapshot_oracle.R` (S0).
3. `R/dw_connect.R`, `R/dw_pull.R`, `R/study_config.R` (S1).
4. `inst/templates/` — `study.yaml` skeleton and Quarto build document.
5. `inst/extdata/varsets/` — variable-list fragments as data, with citations.
6. `equivalence_signoff.yaml` — the human decision record for S0, with the
   three-way `resolution` field.
7. `vignettes/building-a-study-dataset.qmd` — task-shaped usage guide, synthetic
   data, mocked connection, builds anywhere.
8. `vignettes/coming-from-sas.qmd` — the migration guide, including the traps
   section.
9. Amendment to `2026-07-10-sas-macro-canonicalization-design.md`, retained in
   the `hvtiRutilities` repo.

## Success criteria

- One completed study rebuilt in R, with `compare_built()` reporting every
  variable `identical`, `within_tolerance`, or signed off with a reason.
- Re-running `snapshot_oracle()` reproduces a byte-identical checksum.
- The full test suite passes with no warehouse access and no SAS.
- Both vignettes build with no warehouse access, no SAS, and no PHI.
- Every `intentional_divergence` in `equivalence_signoff.yaml` names the SAS
  defect, quantifies the patients affected, and states whether published results
  are implicated.
- `R CMD check` clean at 0/0/0.
- No credential appears in the repository, any log, or any error message.
- Every enabled step in a study build is recoverable from a committed
  `study.yaml`.

## Open questions

- **Is Kerberos integrated auth available** against `<AD-DOMAIN>` for the
  warehouse service account? One question to whoever administers the DSN. A yes
  removes stored credentials from the design entirely and makes the rest of the
  credential ladder dead code worth deleting.
- Which completed study is the first equivalence target? Needs one that is
  finished, representative, and whose `library.built` is intact.
- Which `%vars` body is canonical — `tp.vars.sas` or `tp.vars_base_only.sas`?
  Resolved in S3.
- Does the group want `study.yaml` to live in the study directory, the analysis
  repo, or both?
- Acceptance criterion for S6, stated precisely: which downstream estimates must
  agree, and within what interval.
- Disposition of `tp.bd.snipits.sas` (225 lines of miscellany) and
  `tp.bd_sgroups.sas` (669 lines, `%bdsgroups`) — neither is clearly in or out
  of a slice.

## Amendments to the Phase 0 spec

`2026-07-10-sas-macro-canonicalization-design.md` requires two changes:

1. **Package ownership.** The `bd`/`vars`/`dt` → `hvtiRutilities` mapping
   becomes `bd`/`vars`/`dt` → `hvtiRdatasets`.
2. **`skip` needs its own rule.** Rule 6 would flag `skip` as "11 divergent
   bodies → ambiguous" and route eleven non-decisions to human review. `skip`
   bodies are dead code by construction — the macro is never called. A macro
   that is defined but never invoked anywhere in the corpus should be classified
   `disabled-code` and excluded from adjudication.

A third item is recorded but deliberately **not** changed here: header blocks
document parameters that do not exist (`IMPUTE=` in `%vars`).
`sas_macro_signature()` should treat the documented signature as a claim to be
diffed against the parsed `%macro` line, reporting mismatches as findings. That
is a Phase 0 change and belongs in a Phase 0 revision, not this spec.
