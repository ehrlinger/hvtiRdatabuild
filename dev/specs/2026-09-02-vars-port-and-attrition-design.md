# Porting `vars.sas`, and the attrition record it should emit

**Date:** 2026-09-02
**Status:** designed; layer 1 being built in a study, nothing in this package yet
**Origin:** a parity comparison in `hvtiRtemplates` batch 2a phase 3 needed a study's
analysis dataset reproduced in R. Reproducing it means porting that study's `vars.sas`,
and the shape of that port is a decision this package will inherit.

This note is self-contained. It assumes no memory of the session that produced it.

⚠️ **No study, variable or patient identifier appears here.** Study-specific counts and
names live in that study's own spec, on the share. This file records the design and the
obligations it places on work that has not been written yet.

---

## 1. What this decides

That a ported `vars.sas` emits **two** things, not one: the prepared data, and an
**attrition record** naming each exclusion rule, its reason, and the row count before and
after it.

It decides nothing about the HVTR cohort-metadata spec, which does not exist. It records
what that spec will have to honour or deliberately overturn (§5).

---

## 2. The problem, stated once

Every study carries its own `vars.sas`: a data-prep macro that derives analysis variables
and applies the study's cohort exclusions. They are **not** a shared institutional file.
A census of one clinical area found 85 of them, ranging from 158 to 1160 lines. A study's
own is the only statement of how its analysis dataset was formed.

Two consequences:

- **A port is per-study.** There is no single `vars` to write. What generalises is the
  *shape*: derivations, exclusions, and the record of what each removed.
- **A port is only checkable where the study kept its outputs.** The SAS log records the
  row and variable counts before and after; a deterministic model listing on the prepared
  data checks the derived *values*. Where a study kept neither, a port can be written and
  cannot be verified.

⚠️ **This does NOT expire with the SAS licence, and an earlier draft of this note said it
did.** The claim was that a port can only be validated while SAS still runs. It is wrong:
the saved `.sas7bdat`, `.log` and `.lst` artifacts are the ground truth, and a verification
was in fact carried out against them with no SAS involved. What is true is narrower and
measurable: verification is possible for studies whose outputs were saved, and the coverage
of that across the corpus is a number nobody has yet.

---

## 3. Layer 1: what a ported `vars.R` looks like

Built in the study first, extracted here only once it works.

**Exclusions are declarative.** A table of `rule`, `reason`, and the predicate, rather than
a sequence of `if ... then delete`. The wall of conditionals is what a SAS data step makes
natural; it is not what a CONSORT arm or a metadata reconciliation can read.

**Identifiers are read, never transcribed.** A study's exclusion list may name patients
directly. The port reads that list out of the study's own `vars.sas` at run time, so the
ported code carries no identifier even on the share, and the list cannot drift from its
source.

**The attrition record is a first-class output**, with one row per rule: `rule`, `reason`,
`n_in`, `n_out`. Ordering is significant and is recorded, because `n_in`/`n_out` reconcile
only against a fixed sequence: two studies applying the same rules in a different order
produce different intermediate counts and identical final ones.

### Why the record, and not just the filtered data

It serves three purposes that would otherwise need three mechanisms.

1. **It is the CONSORT input.** A diagram needs a reason and a count per step. Filtered
   data cannot produce one after the fact.
2. **It is the reconciliation surface** for cohort criteria arriving from upstream (§5).
3. **It is how the port is verified.** A log's aggregate count is one number. A per-rule
   table is many. A port that reaches the right final count through two compensating
   errors passes the aggregate and fails the table.

---

## 4. Verification, in three strengthening steps

Against artifacts the study already holds. No SAS is run.

1. **Shape.** Rows and variables before and after, from the SAS log.
2. **Per-rule attrition.** As above: turns one checkable number into one per rule.
3. **Values.** A deterministic model listing fitted on the prepared data. Matching
   coefficients means the derived variables are right, not merely that the row count is.

Only after all three may a port feed a parity comparison. Otherwise a transcription slip in
the port presents as a failure of whatever is being compared, which is the specific error
this ordering exists to prevent.

`hvtiRutilities::compare_parity()` already exists and is the natural primitive; a parity
engine spanning the package space is a live idea and is not scoped here.

⚠️ **Follow this package's PHI idiom when any of this lands here.** `HVTI_ORACLE_DIR`
already establishes it: real study data lives outside the repository, the test runs only
when pointed at it, and assertions are **on shape and verdicts only**, with no patient
value in a failure message. Check what an assertion prints when it fails, not only what it
compares.

---

## 5. Decisions logged for the HVTR cohort-metadata spec

⚠️ **That spec is unwritten and unbrainstormed. These are proposals from the downstream
end, recorded so the upstream work can accept or overturn them deliberately rather than
inherit them by accident.**

1. **Divergence is reported, not forbidden.** A study may exclude beyond the criteria HVTR
   passes down. The reconciliation surfaces the difference. Forbidding it would either
   block legitimate study-local exclusions or force upstream to carry per-study trivia.
2. **The attrition record is the interchange format, and it is per-rule.** Aggregate counts
   cannot drive a CONSORT diagram.
3. **Reasons are free text for now, and this is a known weakness.** CONSORT arms will want
   a controlled vocabulary. Retrofitting one across a corpus of this size is expensive, and
   inventing one before seeing HVTR's is how two ends drift apart. Flagged, not solved.
4. **Rule ordering is significant and recorded.** See §3.

---

## 6. The translator question, as a measurement rather than a plan

Hand-porting every study is infeasible at corpus scale, so a translator reading `vars.sas`
and emitting R is worth considering. It is worth *measuring* first.

**The number to get: what fraction of studies retain outputs sufficient to verify a port?**
A translator that cannot be checked against a study's own saved results is a machine for
producing unverifiable data preparation, which is worse than no translator. That fraction
also bounds how much of the corpus is recoverable by any means, hand-written included.

A second measurement, cheaper: how stereotyped are these files? 85 files spanning 158 to
1160 lines may be one grammar with varying content, or may not be.

Neither number exists. Until they do, a translator is an idea rather than a plan.

---

## 7. Out of scope

- The HVTR metadata spec itself.
- A controlled vocabulary for exclusion reasons (§5.3).
- The parity engine spanning packages.
- Any code in this package. Layer 1 is built in a study; extraction here follows only once
  a second study has exercised the same shape, which is the same gate `hvtiRtemplates`
  applies to a template.
