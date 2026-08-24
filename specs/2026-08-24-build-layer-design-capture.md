# hvtiRdatasets: build-layer design capture

**Date:** 2026-08-24
**Status:** Grounded 2026-08-24 by a session with the three primary `build.sas` /
`vars.sas` authors. Fork 3 answered and enlarged; Fork 2 partly answered; Fork 1 not
reached. See "What the session established", below.
**Package:** `hvtiRdatasets`
**Repo:** `github.com/ehrlinger/hvtiRdatasets`
**Extends:** `2026-08-04-hvtiRdatasets-design.md`, "Slice sequence" (S2, S3) and
"Open questions". Does not supersede it.

> **Redacted for public release.** This repository is public. The session below was
> recorded; **this document paraphrases it and quotes no one verbatim**, because
> participants did not agree to be quoted in a public repository. The recording and the
> quotations live in internal notes.
>
> This repository is public. Following the
> convention of the design spec this extends, internal infrastructure
> identifiers are placeholders, and **individuals are referred to by role, not
> by name**. Ownership of specific master tables and registries is recorded
> internally, not here.

## Why this document exists

S0 (verify) and S1 (pull) shipped. **S2 (`build_dataset()`) and S3
(`derive_vars()`) have a slice number and no shape.** The design spec assigns
them sources — `tp.bd.data.master.sas` and `tp.vars*.sas` — which says what to
port, not what the ported thing should look like.

The information needed to answer that is not in the SAS. It is held by the
**three primary `build.sas` / `vars.sas` authors**, who are also three of the
per-domain master-table owners. This document records the questions to put to
them, the forks each question settles, and where the answers land. It is
written **before** that session deliberately, for the same reason
`equivalence_signoff.yaml` records a `pending` resolution rather than a silent
default: an open question that is written down can be answered, and one that is
only in someone's head gets resolved by whoever writes the code first.

## Fork 1: where study-only logic lives

> **Not reached in the 2026-08-24 session.** The hour went to how a study is actually
> built, which was the right trade: the process turned out to be less uniform than this
> document assumed, and Fork 1's framing presumes a uniformity that does not exist. Re-ask
> it per-owner rather than as one question.


A `build.sas` holds three kinds of code at once:

1. **Block toggles** — `%macro skip` around an optional step.
2. **Shared derivations** — logic every study wants, copied in from a template.
3. **Study-only derivations** — logic that exists for one study and no other.

The declarative model handles (1) and (2): `modules:` and `derive:` in
`study.yaml` replace the toggles, and the shared derivations become the
package's catalogue. **(3) has no home in the current design.**

| Option | Study-only derivations live in | Consequence |
|---|---|---|
| **A** | the package catalogue, selected by `study.yaml` | Everything is reviewed and reusable. Every one-off ships to every user, and a new variable needs a package release. |
| **B** | a study-local R script beside `study.yaml` | Authors keep authorship and can move fast. The escape hatch is where the copy-paste problem returns. |

**This is the decision the rest of S2/S3 hangs from.** It cannot be made from
the code, because the code cannot say what fraction of a real `build.sas` is
category (3).

**What to measure, not ask abstractly:** for the most recent study each author
built, the split between the three categories above.

Related open question already on the design spec, which this fork subsumes:
*"Does the group want `study.yaml` to live in the study directory, the analysis
repo, or both?"*

## Fork 2: what a varset is

> **Partly answered 2026-08-24.** See "A varset is an overlay, not a layer", below. The
> grouping question stands; the *lifetime* question is settled.


`read_study_config()` parses and stores `varsets:` today. **Nothing consumes
it.** The key was left typed and undefined on purpose so its meaning could come
from the people who wrote `tp.vars.*` rather than be inferred from it.

The question is what the natural grouping is:

- by **clinical domain** (demographics, echo, outcomes),
- by **analysis role** (Table 1 variables vs model covariates),
- or by **source table**.

Two consequences fall out and need answering in the same session:

- **`%vars(in=, out=, transf=1)`** — what `transf` toggles, and whether it is
  ever study-specific. Decides whether transformation is a flag, an argument,
  or a varset in its own right.
- **Whether varsets may overlap** — i.e. whether one dataset ever needs two
  versions of the same variable. This changes the return shape and the naming
  rules, so it cannot be deferred past the first implementation.

S3 must still first resolve the existing open question of which `%vars` body is
canonical (`tp.vars.sas` vs `tp.vars_base_only.sas`). That is a prerequisite,
not a duplicate.

## Fork 3: the source of record

> **Answered 2026-08-24, and the answer is larger than the question.** The source of
> record is the master datasets, not the warehouse views — and "master dataset" names
> four different topologies. See "Four topologies, one name", below.


All five shipped modules target warehouse views. Every domain also carries a
**per-owner master dataset with its own hard-coded corrections**, and it is not
established whether `build.sas` reads that master table, rebuilds part of it, or
bypasses it for the views.

If the real source of record is a master table, **the module layer is aimed one
level too low** and `dw_pull()` is pulling the wrong thing. This is cheap to ask
and expensive to discover late.

Answering it also requires the **rebuild cadence** for each master table, which
determines whether `pull_date` is sufficient provenance or a master-table
version stamp is needed alongside it — the same argument `snapshot_oracle()`
makes about SAS datasets on a shared volume, applied one level up.

## Scope question: registries are not studies

Everything shipped models a **study**: one cohort, one `pull_date`, one
`study.yaml`, one built dataset, verified once against a frozen oracle and then
done. At least one owner instead holds **registries** as SAS datasets — a
mitral registry and an endocarditis registry among them.

|  | study dataset | registry |
|---|---|---|
| Lifetime | one analysis | indefinite |
| Built | once, then frozen | continuously |
| Corrections | applied in `build.sas`, then lost | accumulate *in* the artifact; they are its value |
| Consumers | one paper | many studies, over years |
| Provenance | `pull_date` suffices | needs a version, and a checksum at each use |
| Source | warehouse views | warehouse, REDCap, or hand curation |

**A registry could attach to the pipeline in three places** — as a source
feeding `dw_pull()`, as an output of `build_dataset()`, or as both. Position
three is the likely truth and the most work: it makes a registry simultaneously
an input and an output of the same package, at which point **versioning it is
mandatory rather than optional**, because a study citing a registry must be able
to record which build of it it pulled.

⚠️ **Some registries may not be reachable at all.** At least one is held in
REDCap under its own IRB authorization. `dw_connect()` is DBI over ODBC; REDCap
is an HTTP API. **That is a connector gap, not a configuration one**, and no
migration path should be claimed for such a registry until its source is
confirmed.

**Not in scope for S2/S3.** Recorded here so the scope boundary is explicit
rather than discovered when a registry owner asks why the package does not fit.

## The corrections write-back gap

The design spec's data flow is one-directional: warehouse to built dataset.
**Corrections flow the other way and currently do not arrive.** They are made
downstream — in REDCap, in a SAS dataset, or inline in a `build.sas` — and do
not return to the warehouse, so the designated source of record stays knowably
wrong and the same value is re-found and re-fixed by different people.

A partial mechanism exists: preliminary work on the REDCap API by one of the
warehouse engineers. **It ingests.** It does not merge, adjudicate, record
provenance, or decide what happens when an arriving value disagrees with the
stored one. A correction made in a SAS dataset or inline in `build.sas` has no
route back at all.

### Two positions this package should hold

**1. Rules and facts are different objects and need different homes.**

- A **rule** is systematic and reproducible — *a negative length of stay is a
  data-entry error, set `NA`*. It belongs in code and applies to future data
  for free. In the model above, a rule is a `derive:` entry.
- A **fact** is a one-off — *the chart was pulled and the surgery date is
  known*. It is not derivable from anything. It can only be stored, and it is
  worthless without its evidence.

Today both live tangled in `build.sas`, where a rule is invisible to the next
study and a fact is chart-review effort that dies with the file. **Only rules
belong in `derive_vars()`.** Facts need a store this package does not have and
should not invent unilaterally.

**2. A correction is an assertion about a value, and it goes stale.**

`snapshot_oracle()` exists because a SAS dataset on a shared volume can be
regenerated at any time, and if it changes mid-migration **every previously
passing comparison silently becomes meaningless** — so the file is pinned with a
SHA-256 and the write-up cites the checksum.

A correction carries the identical hazard one level down. It was asserted
against warehouse value *V*. If the warehouse now holds *W* — fixed upstream, or
broken differently — the correction may be obsolete, or may re-break a value
that is now right. Applying it blind is the same silent failure in a new place.

**So a correction record must carry the prior value it expected to be
correcting.** On mismatch it does not apply silently; it surfaces for
re-adjudication. This is a compare-and-swap, and that it is the *same argument
the package already makes about oracles* is evidence it is the right shape
rather than a new invention.

### What ingest does not do

| Missing piece | The question it has to answer |
|---|---|
| Identity | Which warehouse record does this correction refer to? Non-trivial: `masterid` has not been stable since April 2023, which is why the `snapshotpull` / `ccfpull` re-pull variants exist and are deliberately unported. |
| Merge policy | The arriving value disagrees with the stored one. Which wins: always the correction, only if newer, only from certain sources? |
| Provenance | Who asserted it, when, on what evidence? Without this a correction is indistinguishable from a typo. |
| Staleness | Was the value being corrected still the value there when the correction landed? See above. |
| Adjudication | Two parties correct the same cell differently. Who decides, and is the losing assertion retained? |
| Authorization | **Not an engineering decision.** REDCap projects sit under their own IRB authorizations; moving data out of one is a governance act. |

**Explicitly outside this package.** Recorded because `derive_vars()` will be
asked to carry corrections, and the answer needs to be a reasoned "rules yes,
facts no, here is why" rather than an ad-hoc refusal.

## ⚠️ The target language is not settled

How the `build.sas` authors move off SAS is undecided, and **may be Python
rather than R**. This does not block the capture, and the reason is structural
rather than optimistic:

| Artifact | Language-bound? |
|---|---|
| `study.yaml` | No — it is YAML. |
| Module definitions | No — SQL, shipped as data *specifically* so they change independently of what executes them. |
| Varset taxonomy | No — a grouping decision about clinical variables. |
| Master-table boundary | No — a question about what the source of record is. |
| Rules/facts split | No — a data model, and its harder half is governance. |
| `equivalence_signoff.yaml` | No — a record of human decisions. |
| `dw_connect()`, `dw_pull()` | **Yes** — the executor. Also the smallest part. |
| `snapshot_oracle()`, `compare_built()` | **Code yes, method no.** Freeze with a checksum, compare per variable, resolve every difference in writing — all of that transfers. |
| `vignette("coming-from-sas")` | **Partly.** pandas has its own analogous traps with different specifics; the list would need rewriting. |

**Consequence to resolve before S2/S3 are built:** if the stat programmers move
to Python, this package's users are the biostatisticians rather than the
`build.sas` authors, and the reader persona shifts with them. Building a build
layer for an audience that will not use it is the failure mode worth avoiding.

## Where answers land

- **Design decisions** — amend this document, dated, in the style of the design
  spec's own amendments. Do not silently edit a fork into a decision; record
  which option was chosen and why the other was not.
- **SAS/R divergences** — `equivalence_signoff.yaml`, with a `resolution` of
  `matches`, `r_defect` or `intentional_divergence`. The `echo` window entry is
  already open there with `resolution: pending` and null `decided_by` /
  `decided_on`; it is a question the code cannot answer, and it is exactly the
  kind of thing this session can close.
- **Anything about registries, corrections write-back, or the target language**
  — not this repository. Those are organizational decisions with package
  consequences, and recording them here would imply an ownership this package
  does not have.

---

## What the session established

A session with the three primary `build.sas` / `vars.sas` authors, 2026-08-24, ~65 minutes.
Findings are paraphrased; see the redaction note at the top.

### Four topologies, one name

This document, and the design spec it extends, both assumed a study pulls from warehouse
views. **It usually does not.** A study starts from a *master dataset*, and that term
covers four structurally different things:

| Shape | How it is built | What it means for the design |
|---|---|---|
| **Warehouse rollup** | A cardiac-surgery master assembled from warehouse views, carrying 700–800 adjudicated variables. Rebuilt periodically; five months between rebuilds at the time of the session. | The only shape the current module layer fits. |
| **Child of a master** | A mitral master built *on top of* the cardiac-surgery master, adding domain derivations, corrections, and refreshed follow-up. | The chain is at least two deep. A study's provenance is not one pull; it is a pull plus a rebuild plus a rebuild. |
| **External-system master** | Device and mechanical-support masters assembled from Intermacs, Phoenix, a sunset system still readable, and REDCap. **No warehouse pull at any point.** | `dw_pull()` is irrelevant here. Nothing in S1 reaches these sources. |
| **Submission-file master** | A quality-group training dataset built from STS submission files and a de-identified multi-site extract, not from the warehouse. | Different variable names, an owner-written mapping, and no join key back to the cardiac-surgery master. |

**Consequence.** `study.yaml`'s `cohort_table` + `modules` model describes the first shape
only. A design that assumes one shape is wrong for three of the four. The unit that S2
must accept is **a master dataset of unknown provenance**, not a set of freshly pulled
warehouse tables.

⚠️ **Two data-integrity findings surfaced in passing, both worth their own work:**

- **The same STS variable can differ between the warehouse and the STS submission files.**
  This was known to the group and was enough, during an earlier version-translation
  effort, for the data not to be trusted. Any equivalence claim that crosses this boundary
  is measuring two different things.
- **There is no join key between the submission-file master and the cardiac-surgery
  master.** A field has to be added upstream before the two can be combined at all. This
  is currently blocking a real study.

### A varset is an overlay, not a layer

Usage of `%vars` is **not uniform**, and the variation is not stylistic:

- one owner does little in `vars` and treats it as the statisticians' surface;
- one works in it substantially;
- one does not use it at all — the built dataset is handed off, and variable creation
  happens downstream in the analyst's own descriptive programs.

The distinction that matters was stated plainly and is a design answer rather than a
preference: **variables created in `build` are permanent members of the built dataset;
variables created in `vars` exist only if the caller invokes the macro.**

**So a varset is a transient, opt-in overlay applied at analysis time — not part of the
built dataset.** That settles the lifetime question for `derive_vars()`: it must return a
dataset the caller chose to derive, and must not be a mandatory stage between
`build_dataset()` and the analyst. The *grouping* question — domain, analysis role, or
source table — is still open, and given the usage spread it may not have one answer.

### The build process, as actually run

All three descriptions converge on the same spine, with different sources feeding it:

1. **Cohort first.** Usually from REDCap, which is also where study-specific variables not
   in the warehouse are collected. It can also be driven from the warehouse given
   parameters, and for some work an upstream analyst has already defined the population.
2. **Join the cohort to a master dataset**, plus any REDCap variables.
3. **A small number of cohort-specific derivations** — intervals, study-specific timings.
4. **Output the built dataset.**
5. **Descriptive tables and EDA plots** — categorical, continuous, scatter, follow-up.
6. **Send those to the investigator**, who checks them against charts and returns
   corrections, which are then programmed back in.

Roughly a two-to-three-day loop.

⚠️ **Step 5 is the data-quality instrument, and the design should treat it as one.** The
descriptive table is not a deliverable that happens to come after the build; it is *how
errors are found*. The division of labour is deliberate — the investigator owns the chart
review because it is their study and they have more time for it than the programmer does.
Any pipeline that produces a built dataset without producing that report has removed the
step where the data actually gets checked.

### Corrections: the door is bolted, not missing

This document previously described the write-back gap as a half-built mechanism. **That
understates it.** Corrections accumulate in the master datasets specifically so they do
not have to be re-made every time — and they do not reach the warehouse because **the
group has been told they cannot put them back.**

That reframes the problem entirely:

- It is **not** an engineering gap awaiting a merge policy. It is a **standing governance
  decision** with an owner somewhere outside this group.
- Every position in this document about compare-and-swap, provenance and adjudication is
  still correct, and **all of it is downstream of reversing that decision.** Designing the
  mechanism first would be building a door for a wall someone has already decided to keep
  solid.
- The corrections currently living in the master datasets are therefore **the only copy**.
  A migration that loses them loses adjudication work measured in years.

**Recommendation:** treat "may corrections return to the source of record, and under what
governance" as a **question to be escalated, not designed around**. It gates the value of
everything else here.

### Updating a master is the hard part, and there is a number

Building a master dataset was described as tractable. **Updating one is not**, and the
difficulty is specific: a refreshed pull must not overwrite a value that has already been
cleaned. Doing this by hand, through spreadsheet round-trips, cost roughly **100 hours**
for one device master — and that owner has declined to repeat it, which pushed the work
onto data-engineering to rebuild the collection surface instead.

**This is an acceptance criterion in the owner's own terms: a master must be updatable in
well under 100 hours.** It is a sharper and more testable goal than anything this document
proposed, and S2 should be measured against it.

⚠️ **The non-overwrite rule is the same compare-and-swap position** stated earlier for
corrections, arrived at independently from operational pain. A refresh must know which
values were cleaned and leave them alone, or surface the conflict — never silently
overwrite. That convergence is evidence the position is right.

### Re-pull is brittle today, with evidence

- A warehouse-pull program that runs about **once a year** failed on its next run because
  **the server name had changed between runs**. The failure presented as "nothing works"
  and took time to diagnose.
- Refreshing follow-up currently requires re-pulling a large set of variables in order to
  compare a small number of status fields against newly abstracted follow-up. This was
  described as reinventing the wheel, and it is: the comparison needs a status and a date,
  not the whole pull.

**Both are arguments for the manifest-and-checksum posture this package already takes**,
and the second is a concrete, well-scoped candidate for an early win: a follow-up *delta*
operation rather than a full re-pull.

### Scope additions

- **Aorta and dissection** — a REDCap registry with a continually updated cohort, named in
  the session as needing to be in scope.
- Imaging-data collection and transcatheter-valve registries were named as further
  candidates, without detail.

### Direction stated in the session

Recorded because it constrains the design, not because it is settled:

- The warehouse is being replaced by a repository that will hold these registries.
- The intended shape for the master datasets is **database views, continually updated** —
  which makes the "you pulled, then the master changed" problem a first-class governance
  concern rather than an edge case, and is the mechanism by which corrections could
  eventually return.
- A **cohort builder** is in progress: procedure plus date range, with exclusion counts and
  metadata carried through so the cohort diagram can be generated.
- The intent is for every completed data request to return an EDA report alongside the
  dataset — which is the step-5 instrument above, moved upstream.
- A stated design constraint, from the failure of an earlier in-house system: **whatever is
  built must not be so clever that only its authors can maintain it.**

### 🔴 Language: the participants were told to look at Python

The target-language section above records the question as open. In the session it was put
to the participants directly: **look at Python; it may be where this lands; it has not been
decided.** One participant already works in a GitHub repository whose variable definitions
are in Python.

**This does not change what to capture** — the table above still holds, and the artifacts
that survive a language change are the same ones. **It does change who to build for**, and
that question is now live rather than hypothetical. It should be resolved before S2 is
implemented, not after.

## Open questions, revised 2026-08-24

Superseding the list above.

- [ ] 🔴 **Escalate:** may corrections return to the source of record? A standing decision
      says no. Everything else about write-back is downstream of it.
- [ ] What does S2 accept as input, given that a *master dataset of unknown provenance* is
      the real starting point rather than freshly pulled warehouse tables?
- [ ] How is a master refreshed without overwriting cleaned values — and can it be done in
      well under 100 hours?
- [ ] Varset **grouping** — domain, analysis role, or source table. Lifetime is settled;
      grouping is not, and may differ per owner.
- [ ] Fork 1, re-asked per owner rather than once.
- [ ] Add the field needed to join the submission-file master to the cardiac-surgery
      master. Currently blocking a study.
- [ ] Reconcile STS fields that differ between the warehouse and the submission files.
- [ ] A follow-up delta operation, to replace full re-pulls done only to compare status.
- [ ] Target language, before S2 is implemented.
- [ ] `echo` window — still open in `equivalence_signoff.yaml`; not raised in this session.

## Open questions, as written before the session

> Superseded by the revised list above. Kept to show what was assumed going in.

- [ ] Fork 1 — Option A or B, and on what measured evidence.
- [ ] Fork 2 — what a varset is; what `transf` toggles; may varsets overlap.
- [ ] Fork 3 — warehouse views or master tables as source of record; rebuild
      cadence; whether a master-table version stamp is required.
- [ ] Who builds the study cohort table today, and can it be a warehouse object
      rather than a SAS step?
- [ ] Does `compare_built()`'s per-variable verdict with no overall pass/fail
      match how a built dataset is actually checked and signed off today, or is
      it answering a question nobody asks?
- [ ] `echo` window — close the `pending` entry in `equivalence_signoff.yaml`.
- [ ] Registry attachment position, if registries come into scope at all.
- [ ] Target language, before S2/S3 implementation begins.
