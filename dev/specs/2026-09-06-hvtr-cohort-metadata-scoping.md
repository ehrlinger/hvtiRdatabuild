# Scoping HVTR's cohort metadata, from measurement

**Date:** 2026-09-06
**Status:** scoping. **Not a design.** HVTR has no shape yet, and this note is
deliberately a collection of what has been measured plus the questions that
measurement cannot settle.
**Repo:** written into `hvtiRdatabuild` because every measurement it cites was
produced here. The thing it scopes lives elsewhere.
**Why now:** the `vars.sas` design note
([2026-09-02](2026-09-02-vars-port-and-attrition-design.md)) §5 logged four decisions "for the HVTR cohort-metadata spec" and noted that the
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

### `build.sas`

| built for | asks |
|---|---|
| databuild S2 | what steps recur, and how stereotyped, so `build_dataset()` knows what to build |
| HVTR | what a study asserts about who is in and out, and how it expresses that |

These are different scans. The first is a structure census in the shape of
`macro-drift-scan.R`. The second reads cohort criteria, which is harder, and runs
into §2's warning immediately: criteria expressed in code are only recoverable
where the code says them plainly.

### `.lst`

| built for | asks |
|---|---|
| databuild | what values a port can be checked against |
| HVTR | what was actually filed, as opposed to what the code would produce |

⚠️ **`.lst` carries printed output and so may carry patient values**, exactly as
`.log` does. `log-verifiability-scan.R` sets the pattern for that: a contract
about what the scan is *capable* of emitting rather than what it chooses to,
never retaining a line, and detecting the presence of a number without reading
it. Any `.lst` scan inherits that or does not get written.

### `.log`, already built

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
