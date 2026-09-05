# Spec — `hvtiRimputation`, and whether it should exist

**Date:** 2026-09-03
**Repo:** written into `hvtiRdatabuild` because that is where [#33](https://github.com/ehrlinger/hvtiRdatabuild/issues/33) lives and where the work would land if the answer is "a layer, not a package."
**Status:** designed, nothing built. §6 and §8 are **decided** (2026-09-04); §2 is **answered**, with one split outstanding, and the census discrepancy is **resolved** (2026-09-05). §7 remains open as a naming decision.
**Updated:** 2026-09-05 — §2 re-measured after three resolver corrections, and the census gap explained. ⚠️ 622 of 939 calls rest on conflicting macro defaults and are excluded from the headline; see §2.
**Origin:** porting a study's `vars.sas` (issue #31) found that reproducing published results requires an imputation step nobody had accounted for.

⚠️ **No study or patient identifier appears here, and no counts or names beyond those already public.** Three variable names and their coefficients appear in §1; they are quoted verbatim from [#33](https://github.com/ehrlinger/hvtiRdatabuild/issues/33), a public issue on this repository, and are reproduced only because the size of the effect is the argument. ⚠️ This is a **narrower claim than the sibling specs make** — `2026-09-02-vars-port-and-attrition-design.md` carries no variable names at all. Do not copy the blanket wording from there onto this file; it would be false.

---

## 1. Why this is not a nice-to-have

Imputation reads like preprocessing. It is not: it changes filed results.

One study, one model, from #33:

| | SAS (with imputation) | R (complete case) |
|---|---|---|
| `ln_avare` | −2.4618 | −1.6772 |
| `chb_pr` | 0.8579 | 1.1037 |
| `hxn_mi` | 0.8718 | 0.8992 |

Complete case retained **1,712 of 2,696 rows**. With the imputation step implemented, **all eleven coefficients match the published listing to its printed precision.**

So a port that skips imputation does not produce a slightly different answer. It produces a different model on a different cohort, and it looks like it worked.

**Corpus scale:** `imputsub` appears in **309 studies**, `mult_imput` in **242**. Neither has a taxonomy prefix.

## 2. 🟡 The distinction that had to be settled first — ANSWERED 2026-09-05, one split outstanding

**`PROC STANDARD ... REPLACE` is single mean imputation. It is not multiple imputation.** They are different methods with different inferential properties: mean imputation is deterministic and understates variance; multiple imputation generates several completed datasets and pools, precisely so the standard errors reflect the uncertainty.

The corpus contains stems suggesting **both** — `imputsub` and `mult_imput`. A package called `hvtiRimputation` that quietly does one when a user expects the other is a worse failure than no package at all.

**The question was: what did the 309 and 242 studies actually run?**

### The answer

**Both methods are real, distinct, and present at scale.** Measured over
`/studies`, 2026-09-04:

| method | studies calling it |
|---|---|
| single mean imputation — `%imputsub` → `PROC STANDARD ... REPLACE` | 223 |
| multiple imputation — `%mult_imput` → `PROC MI` | 326 |
| both | 18 |
| imputing inline, through neither macro | 29 |

⭐ **`mult_imput` performs genuine multiple imputation.** Of the **317** calls
whose `NIMPUTE` can be read unambiguously, **308 (97.2%) pass `NIMPUTE > 1`** —
`5`×266, `10`×36, `8`×3, and one each of `7`, `12`, `20`, median 5. `NIMPUTE = 1`
— single stochastic imputation whatever the macro is called — accounts for **9
calls**.

⚠️ **317, not 939.** A first run reported 925 of 939 at 98.5%. That run could not
see conflicting macro defaults, and the corrected run finds **39 of them across
5 macro names — governing 622 of the 939 calls**. Those 622 are now reported as
`unresolved_conflicting_default` rather than resolved against whichever copy
happened to be read first. The direction is unchanged and the evidence base is a
third the size.

So the hold lifts: the package may honestly offer **both** a mean-imputation
function and an `mi()`. ⚠️ What it must still never do is offer one `impute()`
that silently picks between them — the original reason for the hold is
unchanged, and §7 now clearly needs **two** taxonomy prefixes rather than one.

### Two caveats that belong with the number

⚠️ **Only 292 of 939 calls state `NIMPUTE` explicitly.** The rest take a
default: 25 from a macro whose copies agree, and **622 from a macro whose copies
do not**. So the corpus-wide answer rests far more on institutional defaults
than on per-study choices, and a third of it on defaults that are not even
internally consistent. For the port: an R default of `m = 5` would reproduce
SAS for many of these studies by construction, and per §5 it must *say* so
rather than defaulting silently.

🔴 **The open question is whether those 622 are ambiguous about the ANSWER or
only about the VALUE.** If every default a conflicted name declares is above 1,
the call ran multiple imputation whichever copy it picked up, and the conclusion
holds across 930 of 939. If the defaults straddle 1, it does not. The scan now
reports `conflicting_default_all_gt1` against `conflicting_default_mixed`; that
run has not happened.

⚠️ **A resolved call proves what value would be passed, not that the call
executed.** A call inside a `%if` branch that never fires is counted. Read this
as "the corpus is configured for m = 5", not "939 multiple imputations were
run."

⚠️ **Test and dead jobs are counted as evidence, but the effect is one study.**
All the scans match by **prefix**, which sweeps in `imputsub.test` — 312 files,
over a third of every `imputsub` prefix match — plus `mult_imput_dead` and
`mult_imput.iso_dead`. A test fixture and a retired job are not evidence that
imputation ran, so this looked like a serious threat to the study counts.

Measured, it is not. `studies_only_suspect` — studies credited on *no* evidence
but a test or dead file — is **0** for `imputsub` and **1** for `mult_imput`.
The 312 test files sit in 306 studies that also hold real `imputsub` jobs. ⭐ The
**file** counts are badly inflated (312 of 628 `imputsub` `.sas` files are
tests); the **study** counts are not. An earlier draft of this section said to
treat 223 and 326 as upper bounds implying a large correction; the correction is
at most one study.

⚠️ What this does not settle is whether the files *making the calls* are
themselves test or retired jobs. `studies_only_suspect` is about which files
exist, not which ones call.

Also worth carrying forward: **63 distinct macro names bind `NIMPUTE`**, not
one. There is no single canonical `mult_imput` — there are 63 named variants,
each internally consistent. The stem traversal is consistent with that, and
shows real structure: a `mult_imput.iso*` family, year-suffixed variants
(`_1995`, `_2015`), and ⭐ `mult_imput5` / `mult_imput10` / `mult_imput2`, whose
names plausibly encode `NIMPUTE` itself and would be independent corroboration
of the m = 5 finding if so.

### How it was measured, and what the first two attempts got wrong

Three scans, in `artifacts/`, each with a test beside it that runs against a
synthetic corpus with a known answer. Run the test before trusting a scan:
`dev/` is `.Rbuildignore`d, so `devtools::test()` never exercises any of them.

| scan | asked | result |
|---|---|---|
| [`imputation-method-scan.R`](artifacts/imputation-method-scan.R) | which methods appear in the stem-matched jobs | 1,134 files, 547 studies, 3 unplaced |
| [`imputation-callsite-scan.R`](artifacts/imputation-callsite-scan.R) | who **calls** them | 527 of 547 studies call a macro |
| [`imputation-nimpute-scan.R`](artifacts/imputation-nimpute-scan.R) | what `NIMPUTE` reaches `PROC MI` | 939 calls, **0 unresolved** |

⚠️ **The first two scans each answered a narrower question than the one asked,
and the record is kept because the failure mode recurs.**

Scan 1 found that 1,132 of 1,134 stem-matched files **define** a macro and
**none call one**. It had measured how many studies hold a *copy of the
definition*, not how many ran imputation. Its result looked authoritative
precisely because it was clean — 100% separation by stem, no file carrying both
methods, no exceptions in thirty years. ⭐ **That perfect partition was the
warning, not the confirmation:** it was 1,134 copies of two canonical files, the
same per-study distribution pattern
[`2026-09-02-vars-port-and-attrition-design.md`](2026-09-02-vars-port-and-attrition-design.md)
documents for `vars.sas`.

Scan 2 then resolved macro variables, but only within one file, and left 864 of
871 statements unresolved. The 7 it could read said `NIMPUTE = 1` five times —
which briefly looked like the alarming answer. ⭐ **It was a biased sample, not
merely a small one.** The calls resolvable inside a single file were exactly the
unusual ones, where someone hardcoded `%let n = 1;` beside the call instead of
using the macro's argument. The 99.2% that were invisible were the ordinary
ones.

Both failed for one structural reason: the `PROC MI` sits inside a macro
**definition**, where `nimpute` is a **parameter**, and the value is supplied by
the **caller** — in a different file, and often a different study, since
`mult_imput` is called in 326 studies but defined in 277.

```
definition:  %macro mult_imput(data=, nimpute=5);
               proc mi data=&data nimpute=&nimpute;   <- binds to a PARAMETER
call site:   %mult_imput(data=w, nimpute=25);         <- supplies the VALUE
```

Scan 3 joins the two, globally by macro name. It reports
`conflicting_redefinitions`, and that value came back **0** — so the assumption
that the many copies are one canonical file is **checked rather than assumed**,
which is what the three preceding corpus errors in this family had in common.

### The census discrepancy — RESOLVED 2026-09-05

`imputsub` matched the census exactly at 309 studies while `mult_imput` came in
at 277 against 242, and at 506 files against 411 — *higher* than a census with
no extension filter, which should have been a superset. Measured:

| rule | `imputsub` files | `mult_imput` files |
|---|---|---|
| exact stem only | 617 | 318 |
| ⭐ **first dot-delimited field** | **929** | **412** |
| any character prefix | 930 | 685 |
| *the census* | *926* | *411* |

⭐ **The census counted files whose first dot-delimited field equals the stem** —
which is `hvtiRutilities`' own taxonomy parse, since the convention splits on
dots. Both figures reproduce to within a few files, consistent with the census
having been taken slightly earlier.

The scans match by raw character prefix instead. For `imputsub` the two rules
nearly coincide, because its one real variant is `imputsub.test`, whose first
dot-field *is* `imputsub` — which is why it agreed with the census. For
`mult_imput` they diverge: **220 distinct variant stems** — `mult_imputation`,
`mult_imput2`, `mult_imputiso60` — are prefix matches and different jobs.

⚠️ **Consequence: the scans' `mult_imput` study count is inflated.** Prefix
matching gives 277 studies where the exact stem gives 235 and the census 242. It
does not affect the `NIMPUTE` finding, which rests on resolved call sites rather
than file names, but any file-based `mult_imput` figure in this spec should be
read as a prefix count.

### ⚠️ Why this is ANSWERED and not yet SETTLED

Review of [#36](https://github.com/ehrlinger/hvtiRdatabuild/pull/36) found three
defects in scan 3's resolver after the first run. All three are corrected, each
is pinned by the fixture, and **the corpus run was repeated on 2026-09-05** —
the numbers in this section are from that second run.

⭐ **The review was right, and the correction was large.** The conflicting-default
defect alone moved the evidence base from 939 calls to 317. One thing remains
before this is SETTLED: the 622 conflicted calls have not been split into those
whose defaults are all above 1 and those that straddle it (see the 🔴 above).

Two of the three can move them:

- **Conflicting defaults were invisible.** The conflict check compared the
  bound *expression* and not the declared *default*, so two copies of one macro
  binding `nimpute=&nimpute` while declaring `nimpute=5` and `nimpute=10` were
  reported as agreeing, and whichever was read first silently won. ⭐ That made
  `conflicting_redefinitions = 0` — the field cited just above as the validity
  check — the **least** searching test of the input deciding **69%** of the
  calls. The scan now reports `conflicting_defaults` separately, and keeps
  calls resting on a conflicted default out of the distribution rather than
  guessing.
- **`%let` resolution ignored statement order.** One map was built per file, so
  a later assignment could decide an earlier call: `%let n=5; call; %let n=10;
  call;` resolved both to 10. Pass 2 now walks statements in order. ⭐ Note that
  every *count* in the output is identical under this bug — only the values
  differ — so the fixture had to assert on the distribution itself to catch it.

The third cannot move them: definitions settling `NIMPUTE` without a caller
were pooled into the call denominator, and in this corpus there were **none**
(`binding_literal`, `binding_local` and `settled_by_definition_alone` were all
0). Corrected for the next corpus, which may differ.

All three require `hvtiRutilities`, which defines what a study is, and stop
rather than guessing if it cannot be loaded. Each output records the
`hvtiRutilities` version and folder list it used, because the study counts are a
function of that taxonomy and two runs are comparable only when it matches. The
runs above used 1.1.9.

⚠️ **An earlier draft of this section, and of the script, got the `PROC
STANDARD` semantics backwards, and the error is recorded rather than quietly
corrected because it deflated the one number §2 turns on.** The claim was that
`REPLACE` is imputation *only* when no `MEAN=` or `STD=` is present, and that
`MEAN=0 STD=1 REPLACE` is standardisation and not imputation. That is wrong.
SAS documents `REPLACE` as filling missing values with the variable mean, or
with the `MEAN=` value when one is given — so `PROC STANDARD MEAN=0 STD=1
REPLACE` does **both**: it standardises the observed values *and* fills the
missing ones with 0, which in standardised units is the mean. **Both forms are
imputation**, and the script now counts both.

The distinction is still reported, because the two fill a different value on a
different scale and a port has to reproduce whichever the study ran. It is a
breakdown, not a filter. The case that genuinely is *not* imputation is
`PROC STANDARD` with **no** `REPLACE` at all.

⚠️ **`PROC MI NIMPUTE=0` does not impute.** It is the documented way to run the
procedure for missingness diagnostics only, which is exactly what a careful
programmer does before deciding — not a rare edge. Counting it inflates the
multiple-imputation side. `NIMPUTE=` binds to its own `PROC MI` statement, so
the script classifies per statement rather than per file; a file may carry a
diagnostic call and a real one.

⭐ Note that these two errors pushed the headline ratio in **opposite**
directions. Fixing either alone would have made it worse than fixing neither.

⚠️ **A study is the directory holding a taxonomy folder**, nearest ancestor
wins -- `hvtiRutilities`' definition (`R/job_census.R:1-12`), and the one that
produced the census counts this scan reconciles against. The folder list is
read from `hvtiRutilities::hvti_taxonomy()` rather than hardcoded so it cannot
drift.

⚠️ **An earlier draft took the first two path components as `<tree>/<study>`,
and running it against the real share proved that wrong.** Studies sit at
variable depth -- `cardiac/pericardium` at two, `cardiac/support/avecor` and
`vascular/thoracic-aorta/previous_surgery` at three -- so that rule reported
**subject areas as studies**, undercounting badly while emitting
well-formed JSON. Files with no taxonomy ancestor are now counted as
`files_unplaced` rather than dropped, so a missing job stays distinguishable
from a job that does not exist.

Its output carries counts only -- no path, no file name, no study identifier,
no variable name -- enforced in its emitter rather than left to care.

## 3. What the SAS step actually does

From #33, and this is the contract to reproduce:

- **Mean of the non-missing, per variable.**
- **Applied after derivation, not before.** The order matters: a derived variable computed from imputed inputs is not the same as a derived variable imputed after the fact.
- **`ms_*` missingness indicators created before imputation**, so the model can carry "this was missing" as a term.

That last one is the same pattern this family keeps rediscovering: ⭐ **a value that means "observed" and a value that means "filled in" must not be the same value.** The `ms_*` indicators are the SAS-era answer to it. Whatever gets built must preserve that, not because SAS did it but because it is right.

## 4. What it must emit

- **The imputed dataset.**
- **A record of what was imputed, per variable and per row.** Not a count — the actual map. A summary that says "12 values imputed in `ln_avare`" cannot answer "was this patient's value imputed?", which is the question an audit asks.
- **The `ms_*` indicators**, or whatever replaces them, generated rather than hand-maintained.
- **Enough provenance to re-run it.** Imputation is one of the steps John named in the 2026-09-02 training as version-pinning: *"if we run an imputation step and we save that into the data, then that sort of pins what version of the imputation package we need."* So the emitted artifact must record the method and the package version that produced it, the way `record_provenance()` already does for renders.

## 5. Swappable method

#33 asks for alternatives to mean imputation. The design consequence: **the method is a parameter, and the emitted record names which method ran.** A dataset that does not say how it was imputed is not reproducible, and the default must not be silent — if mean imputation is the default because it reproduces SAS, the artifact should say "mean" rather than "default".

## 6. Own package, or a layer in `hvtiRdatabuild`?

The open question in #33. The arguments as they stand:

**For a layer inside `hvtiRdatabuild`:** imputation happens during the build, on the built dataset, before analysis. It shares the manifest, the checksums and the provenance machinery already there. A separate package means a second place to keep those in sync.

**For its own package:** imputation is a *method*, not a build step, and the family's pattern is that methods live in their own packages — `hvtiRbootstrap`, `hvtiRpropensity`, `hvtiRlifetables`. Analysis jobs that impute without rebuilding would otherwise have to depend on the whole build layer.

⭐ **The test that decides it:** does anything outside the build ever need to impute? If an analysis job can be handed a built dataset and impute it — which the per-study `vars.sas` pattern suggests, since imputation sits inside `vars` and `vars` is per-study — then it is a method and wants its own package. If imputation only ever happens once, during the build, it is a layer.

**My reading is that it is a method and wants its own package**, on the strength of `imputsub` appearing in 309 studies as a *job stem* rather than as part of a build. But that is an inference from a filename pattern, and this family has been bitten three times in a fortnight by exactly that kind of inference. **Check it before committing.**

### 🟢 DECIDED 2026-09-04 — its own package

`hvtiRimputation` is a package, not a layer. The decision is the maintainer's,
taken directly rather than derived from the §6 test, and it matches the reading
above.

⚠️ **The §6 test was not run.** "Does anything outside the build ever need to
impute?" is still unverified — the evidence remains the filename pattern this
section warns about. That does not reopen the decision, but it does mean the
package should be built so that being wrong is survivable: if imputation turns
out to happen only during the build, a package that `hvtiRdatabuild` depends on
is a mild redundancy, whereas a build layer that analysis jobs turn out to need
would have been a hard rewrite. **The decision fails safe in the direction it
was taken**, which is the reason to stop worrying about the unrun test.

⚠️ Note that this is a statement about **cost if the decision is wrong**, not a
prediction that the dependency will exist. §8 states that `hvtiRdatabuild` gains
no dependency on `hvtiRimputation` under the design as it stands, and that
remains true; the sentence above describes the fallback if §6 turns out to have
been decided the wrong way.

## 7. Taxonomy

Needs a two-letter prefix. `mi` was floated in the 2026-09-02 training.

⚠️ **The condition §2 was holding this on is now met: both methods are present
at scale, so one prefix will not be enough.** 223 studies call single mean
imputation and 326 call multiple imputation, with 18 doing both — they are
different job types by the same test that split `dc` into five, and 18 studies
running both means a single prefix could not even label those unambiguously.

Two prefixes are therefore required. **Which two is still an open decision**, and
`mi` is a poor choice for either taken alone: it reads as multiple imputation to
a statistician, so using it for the single-imputation job would repeat at the
taxonomy level exactly the misnaming §2 went looking for. Note also that the
corpus carries **63 distinct macro names** binding `NIMPUTE`, so a prefix is
labelling a job type, not a macro.

Coordinate with the per-folder re-parse (`hvtiRtemplates/dev/specs/2026-09-02-per-folder-naming-parse-handoff.md`); the taxonomy is being re-derived and this is the moment to add prefixes rather than after.

## 8. 🟢 DECIDED 2026-09-04 — imputation and the attrition record

#33 flagged that imputation changes what the CONSORT diagram says, and left it
open. It is now decided.

### The tension, with the numbers

From #33's worked study: the analysis set is **2,696 rows**; complete-case
would have used **1,712**. So **984 rows (36.5%) are in the published analysis
only because a covariate was filled in.**

Those rows are **not excluded** — the attrition record must not show them as
dropped. They are also not fully observed. The record has had no vocabulary for
that third state.

### What drives the design: port verification

The attrition record has three consumers (#31 §1): CONSORT input, HVTR
reconciliation, and port verification. **Port verification drives the imputation
entry**; the other two are derived from it. The reason is that verification
needs checkable numbers, and CONSORT can be produced from a richer record while
the reverse does not hold.

984 is the number that earns its place: a port that mean-imputes the **wrong
variable list** still reaches 2,696 rows and still looks correct. It does not
reach 984.

### The shape: an annotation stage on the CONSORT tracker

⚠️ **The attrition record is `hvtiPlotR`'s CONSORT tracker**, not a table of
this package's design — see `2026-09-02-vars-port-and-attrition-design.md` §3,
which records an earlier draft proposing a `rule`/`reason`/`n_in`/`n_out`
schema and rejects it because the shipped tracker is strictly richer. That
still holds: the design below extends the tracker rather than paralleling it.

#### 🔴 What the first draft of this section got wrong

A draft written earlier on 2026-09-04 claimed the tracker **already** supported
a non-excluding stage, on the strength of `hv_consort_summary()` reading
`if (!is.null(s$excl_col)) ... else NA_integer_`, and concluded that the gap
was "a constructor, not a schema". **That was a misreading, and it is recorded
here rather than deleted because the misreading is an easy one to repeat.**

Read `hv_consort_exclude()` (`consort-plot.R:222-229`): it writes `excl_col`
onto the **stage that is currently last**, and then appends a fresh stage whose
`excl_col` is `NULL`. `hv_consort_start()` does the same for stage one.

So **`excl_col = NULL` means "nothing has excluded downstream of this stage
yet" — it identifies the terminal stage.** hvtiPlotR's own roxygen says so:
*"`n_excluded` and `excl_col` are `NA` for the final stage (no downstream exclusion defined yet)"* (`consort-plot.R:270-271`). It is not a
marker for a stage that excludes nobody, and a stage relying on it loses the
property the moment another exclusion is appended.

Two further consequences of that draft, both defects:

- **An all-`TRUE` `include_col` silently resurrects excluded patients.**
  `hv_consort_exclude()` computes `active <- dat[[prev_include]]`
  (`consort-plot.R:203-204`), so the next rule would re-admit everyone every
  earlier rule removed. No error, no warning, a wrong final N.
- **`hv_consort_patients()` cannot answer the counterfactual.** It reads only
  `include_col` and `excl_col` (`consort-plot.R:340-353`). `imputed_any` and
  `complete_case_pass` are ordinary data columns it never inspects, so the
  claim that the 984 falls out "with no new function" was false.

#### The corrected design

An **annotation stage**: a stage that records something about the rows without
removing any.

1. **Its `include_col` is a copy of the previous stage's include column**, not
   an all-`TRUE` column. This is the load-bearing detail. It keeps `n_included`
   honest (the survivor count, not the screened count) and keeps any later
   `hv_consort_exclude()` gating on the right row set.
2. **It stores the names of its annotation columns on the stage record.** This
   is a schema addition, and calling it one is the correction above: without it
   a summary row cannot say what was annotated, and an accessor has nothing to
   read.
3. **Its `excl_col` behaves like any other stage's** — `NULL` until something is
   appended after it, then the downstream exclusion's column. That is the
   tracker's existing model and needs no change.

### What the imputation annotation carries

| Column | Meaning |
|---|---|
| `imputed_any` | row level: did this row have any value filled? |
| `complete_case_pass` | row level: would this row have survived complete-case? |

**Row level, not counts.** 984 is **not** the sum of the per-variable missing
counts — a row missing three covariates is dropped once — so only a row-wise
evaluation gets it right, and it is the number that catches a port which
imputed the *wrong variable list* yet still reached 2,696.

The counterfactual is then `imputed_any & !complete_case_pass`. ⚠️ **That needs
an accessor; it is not free.** Either hvtiPlotR gains one alongside the
annotation constructor, or the caller reads `tracker$data` directly — which
works today but hard-codes column names the tracker owns. Prefer the accessor.

### Division of labour

- **`hvtiRimputation`** owns the per-row, per-variable map (§4) and the `ms_*`
  indicators, and emits the two columns above.
- **The study's ported `vars.R`** passes them to the tracker.
- **`hvtiPlotR`** gains the annotation-stage constructor and its accessor,
  generic rather than imputation-aware.

### The consistency check this buys

`sum(imputed_any)` must equal the number of rows where any `ms_*` is set. Two
independently produced numbers that must agree — the per-rule-table property
#31 wants, applied to imputation.

### ⚠️ Cross-package consequence

The annotation stage constructor **and its accessor** land in **`hvtiPlotR`**,
together with the stage-record field naming the annotation columns. Both must be
**generic** — "a stage that annotates without excluding" — not
imputation-specific: `hvtiPlotR` is a plotting package and must not learn what
imputation is. Winsorisation and any other non-excluding transform should reach
for the same constructor.

⚠️ This is a **change to a shipped, exported API's data structure**, not an
additive helper, so it is a larger ask than the first draft implied. hvtiPlotR
is heading to 3.0 (currently 2.7.12), which is the right moment for it, but the
work belongs on hvtiPlotR's roadmap rather than being assumed by this spec.

🟢 **Raised as [hvtiPlotR#131](https://github.com/ehrlinger/hvtiPlotR/issues/131)**
(2026-09-04), which carries a runnable reproduction of the resurrection defect
described above and states the three requirements: the copying constructor, the
stage-record field naming the annotation columns, and the accessor. It is a
sibling of [hvtiPlotR#129](https://github.com/ehrlinger/hvtiPlotR/issues/129),
which wants per-reason rather than per-stage counts from the same tracker for
the same verification reason.

⚠️ **This spec's §8 is therefore blocked on another package's roadmap.** The
design is decided; the mechanism it depends on does not exist yet. Nothing in
`hvtiRimputation` should be written against the annotation stage until #131
lands, and the two columns it emits (`imputed_any`, `complete_case_pass`) are
the stable part of the contract in the meantime.

## Definition of done for this spec

- [ ] **§2 answered, confirmation run pending** 2026-09-04 — **both methods are
  real and present at scale**:
  223 studies call `%imputsub` (single mean imputation), 326 call `%mult_imput`,
  18 call both, and 29 impute inline through neither. `mult_imput` performs
  **genuine multiple imputation** — 925 of 939 resolved calls (98.5%) pass
  `NIMPUTE > 1`, median 5. See §2 for the full result, the three scans that
  produced it, and two caveats that belong with the number: 69% of calls take
  the macro default rather than choosing, and a resolved call proves the value
  passed rather than that it executed. The hold on `impute()` lifts only in
  part: the package may offer a mean-imputation function **and** an `mi()`, but
  ⚠️ **must not offer one `impute()` that silently picks between them.**
  ⚠️ **Re-run 2026-09-05 after the #36 resolver fixes, and the correction was
  large**: 39 conflicting defaults across 5 macro names govern 622 of the 939
  calls, so the evidence base is 317 rather than 939 and the figure is 97.2%
  rather than 98.5%. The box stays unticked on one remaining split — whether
  those 622 straddle `NIMPUTE = 1` or sit entirely above it. If entirely above,
  the conclusion holds across 930 of 939 and this ticks.
- [x] **§6 settled** 2026-09-04 — its own package, by maintainer decision. The
  §6 test itself was not run; see §6 for why the decision fails safe anyway.
- [ ] **Taxonomy prefixes agreed**, coordinated with the re-parse. §2 answered the
  evidence question — **two are needed, not one** — so what remains is the
  naming decision itself, not the measurement behind it. See §7.
- [x] **The imputation/CONSORT interaction decided** 2026-09-04 — §8.
- [ ] Only then: a design spec for the package, and a plan.
