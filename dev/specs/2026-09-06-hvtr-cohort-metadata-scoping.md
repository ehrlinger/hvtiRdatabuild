# Scoping HVTR's cohort metadata, from measurement

**Date:** 2026-09-06
**Status:** scoping. **Not a design.**
⚠️ **Retitled in scope 2026-09-06:** an earlier draft framed HVTR as a cohort
metadata layer and cast the lead question as descriptive versus prescriptive
cohort definition. HVTR is larger than that. It is the governed clinical data
platform for HVTI, successor to CVIR then SemanticDB then HVI_DM, pulling EMR and
registries into one model with consistent variable definitions, provenance and
IRB-governed access, replacing a patchwork of one-off extracts with a single
trustworthy upstream. Cohort metadata is one slice. The measurements below still
apply; the framing in §5 was too narrow and is marked where it is.
HVTR has no shape yet, and this note is
deliberately a collection of what has been measured plus the questions that
measurement cannot settle.
**Repo:** written into `hvtiRdatabuild` because every measurement it cites was
produced here. The thing it scopes lives elsewhere.
**Why now:** the `vars.sas` design note
([2026-09-02](2026-09-02-vars-port-and-attrition-design.md)) §5 logged four
decisions "for the HVTR cohort-metadata spec" and noted that the
spec does not exist and has not been brainstormed. It now has a live consumer,
so those four need answering rather than filing.

⚠️ **No study, patient or variable identifier appears here.** Every figure comes
from a scan output committed under
[`artifacts/results/`](artifacts/results/).

This note is self-contained. It assumes no memory of the session that produced
it.

---

## 1. The one measurement that most shapes the problem

`vars.sas` is the per-study file that defines a study's cohort: its derivations
and its exclusions. There is no institutional one. A census of one clinical area
found 85 of them, from 158 to 1160 lines.

The corpus-wide macro census on 2026-09-06 puts numbers on that:

| `vars` | |
|---|---|
| copies | 5,055 |
| studies | 1,299 |
| distinct signatures | 269 |
| ⭐ **distinct bodies** | **39** |

⭐ **Cohort definitions vary enormously in how they are parameterised and very
little in what they do.** Five thousand copies reduce to thirty-nine behaviours.
That is the opposite shape to every other family in the census, where the drift
is overwhelmingly in the body, and it is the single most encouraging number for
a metadata layer: thirty-nine behaviours can be described, catalogued and
reasoned about, and five thousand cannot.

⚠️ It is one number from one scan and it deserves a second look before anything
is built on it. The obvious follow-up is whether the 269 signatures cluster,
because a metadata layer describes the *parameters* and the parameters are where
the variation is.

## 2. What else measurement already says

| finding | source |
|---|---|
| 1,064 of the 1,444 multi-copy macro names have copies that disagree | `macro-drift.json` |
| 1,062 of those 1,064 disagree **below** the header | `macro-drift.json` |
| `mult_imput` has 1,555 copies corpus-wide | `macro-drift.json` |
| the scan looking only in files *named* after it found 423 | `reconcile-scan.json` |
| 129 of 939 imputation calls have no method recoverable from code | `studylocal-scan.json` |
| the job census counts by **first dot-delimited field** | `census-reconcile.json` |
| 227,783 `.sas` files under `/studies` | `macro-drift.json` |

Four consequences for anything HVTR does.

**There is no canonical institutional definition of anything.** Three quarters of
repeated macro names have drifted, and they drift in behaviour. A design that
assumes one true version of a job, a variable or a cohort rule is starting from a
premise the corpus refutes.

⭐ **The corpus is not self-describing, and cannot be made so retrospectively.**
129 imputation calls have no answer in the code about which method they ran. That
is not a gap a better scan closes; it is a property of what was written down. Any
metadata HVTR holds about the past is either recovered from saved *outputs* or is
absent, and it must be able to say which.

⚠️ **A filename pattern is not a fact.** Four separate errors in one week came
from treating one as evidence: the two-letter prefix rule, `imputsub` counts read
as runs rather than copies, `mult_imput`'s definitions assumed to live in files
named after it, and the job census's prefix-versus-dot-field rule. HVTR will be
tempted to key on names, because names are what the corpus offers cheaply.

**Divergence is the normal case, so it has to be first-class.** This is what §5
of the `vars` note already proposed, and the census supports it: a design that
treats disagreement as an error state will spend its life in the error state.

## 3. The four decisions logged for this spec, and where they stand

From `2026-09-02-vars-port-and-attrition-design.md` §5, written from the
downstream end and explicitly marked as proposals to be accepted or overturned
deliberately.

1. **Divergence is reported, not forbidden.** A study may exclude beyond what
   HVTR passes down, and the reconciliation surfaces the difference. ⭐ The census
   strengthens this from a preference to a requirement.
2. **The interchange format is `hvtiPlotR`'s CONSORT tracker, not a new schema.**
   Whatever HVTR passes must be expressible as `predicate ~ "Reason"` rules.
   ⚠️ Blocked in practice on [hvtiPlotR#131](https://github.com/ehrlinger/hvtiPlotR/issues/131),
   which is on that package's 3.0 roadmap.
3. **Reasons are free text, flagged as a known weakness.** CONSORT arms want a
   controlled vocabulary; retrofitting one across this corpus is expensive, and
   inventing one before seeing HVTR's is how two ends drift apart. **This is the
   one the new consumer changes**: if HVTR is being designed now, the vocabulary
   question is live rather than deferred.
4. **Rule ordering is significant and recorded.** First match wins, matching the
   sequential `if ... then delete` being ported.

## 4. What the two remaining scans could answer, and for whom

⚠️ **`build.sas` and `.lst` have not been scanned. The scan for each depends on
which consumer it serves, and the two want different things over the same files.**

### `build.sas`, built 2026-09-06

⚠️ An earlier version of this section said the databuild and HVTR scans would be
different, on the reading that HVTR wanted cohort criteria. With HVTR understood
as the governed upstream, both consumers want the same description, for different
reasons.

[`artifacts/build-structure-scan.R`](artifacts/build-structure-scan.R) describes
a build rather than interpreting it:

| it reports | who needs it |
|---|---|
| step SHAPES against distinct bodies | ⭐ S2: how many builds to implement |
| DATA steps and which PROCs, by study | S2: what `build_dataset()` must cover |
| whether builds compose (`%include`, macros) | both |
| ⭐ which LIBREFS builds read from | HVTR: what a governed upstream replaces |

⭐ **The step-shape count is the one to read first.** It fingerprints the ordered
sequence of steps rather than the text, so two builds doing the same things in
the same order are one shape however their variable names differ. If it comes
back small, as `vars`'s 39 behaviours did, the build layer is describable.

⚠️ It does not attempt cohort criteria, derivations or variable semantics. Those
need a decision about what HVTR is before a scan can count the right thing, and a
scan that guessed would produce a number answering neither consumer.

⚠️ Librefs are emitted only above a frequency floor (`--min-libref`, default 5
studies). A library alias used by one study is not an institutional source, and
emitting it would widen the contract past what the scan claims.

### `.lst`

| built for | asks |
|---|---|
| databuild | what values a port can be checked against |
| HVTR | what was actually filed, as opposed to what the code would produce |

[`artifacts/lst-listing-scan.R`](artifacts/lst-listing-scan.R), built
2026-09-06, is the rung-3 counterpart to the log scan's rung-1 figure: how many
studies hold a model listing whose coefficients a port could be checked against.

🔴 **Its contract is stricter than the log scan's, for a stronger reason.** A
`.log` may contain patient values incidentally. **A `.lst` IS the printed output**,
and a `PROC PRINT` listing is patient data by design rather than by accident. So
the scan never retains a line, reads no number, and ⚠️ **detects `PROC PRINT`
output in order to count it without reading it.** Knowing how many listings are
patient-level print-outs matters: those are the ones nobody should open
casually.

### `.log`, run 2026-09-06

⭐ **79% of studies holding SAS code kept a log that recorded a dataset shape and
did not error**: 1,180 studies of the 1,487 that hold any `.sas` file. Of the
1,204 studies that kept any log at all, 1,180 kept a usable one, so retention is
close to all-or-nothing per study rather than patchy within one.

That is a far better position than the `vars` note feared, and it is the number
its §6 has been asking for since 2026-09-02. For HVTR it bounds how much of the
past can be described from evidence rather than inferred from code.

⚠️ **Three limits, and the first is the largest.**

**"Usable" means a shape was recorded, not that THE shape was.** Rung 1 wants
rows and variables for a study's specific analysis dataset. This measures whether
shape information exists in the study's logs at all, which is necessary and not
sufficient. **79% is a ceiling on verifiability rather than an estimate of it.**

🔴 **`vars` logs are useless for this, and the reason generalises.** 46 logs carry
a `vars` stem, across a corpus holding 5,055 `vars.sas` copies, and **not one
recorded a dataset shape**. The information exists, in the 48,209 logs under
other names, because `vars.sas` is included into a larger job and its datasets
are recorded in that job's log. ⭐ **Log naming does not follow the code that
created the dataset**, so anything joining a port to its evidence has to work by
content rather than by filename. That is the same lesson as `mult_imput`'s
definitions, arriving from a different direction.

**It measures logs that exist now, not logs that were produced.** A study that
ran cleanly and was later tidied is indistinguishable from one that never kept a
log. 38 logs were also skipped for exceeding the 200 MB ceiling.

### `.log`, the scan

[`artifacts/log-verifiability-scan.R`](artifacts/log-verifiability-scan.R)
measures the fraction of studies that could have a port verified at rung 1, which
is the number §6 of the `vars` note says nobody has. Running as this was written.
⭐ It matters to HVTR for a different reason than to databuild: it bounds how much
of the past can be described from evidence rather than from code.

## 5. Questions that are decisions, not measurements

No scan settles these, and they should be settled before the remaining scans are
built, because they change what those scans should count.

- 🔴 **Is HVTR descriptive or prescriptive?** Does it record what studies did, or
  define what they should do? Everything else follows from this. The corpus can
  only support the first; the second is a policy the corpus would be measured
  against.
- **Does it own cohort definitions, or index them?** Owning means a study's
  cohort is derived from HVTR. Indexing means HVTR points at the study's own
  `vars.sas` and describes it. The 39-behaviours finding makes owning more
  plausible than the raw copy count suggested, but it is still a choice.
- **What is the unit?** A study, a cohort, or a single criterion. The CONSORT
  tracker's rules are per-criterion, which pulls toward the third.
- **Retrospective, forward, or both?** §2 says the past is partly unrecoverable.
  A forward-only design avoids that and abandons twenty-five years of studies; a
  retrospective one has to represent "unknown" honestly and everywhere.
- **Free-text reasons or a controlled vocabulary**, per §3 item 3.

## 6. What this note deliberately does not do

It proposes no schema, no entity model and no interface. HVTR's shape is the
open question, and a scoping note that quietly proposed one would foreclose it
while appearing to inform it. The measurements above are inputs to that
conversation, not constraints derived from it.

## Definition of done for this note

- [ ] §5's first question answered: descriptive or prescriptive
- [ ] The `log-verifiability-scan.R` result folded into §2, with the fraction it
      measures
- [ ] The 269 `vars` signatures examined for clustering, per §1
- [ ] A decision on which `build.sas` scan to build, per §4
- [ ] Only then: a brainstorm, and a design
