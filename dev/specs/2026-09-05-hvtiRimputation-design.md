# Designing `hvtiRimputation`

**Date:** 2026-09-05
**Status:** design. Nothing is built, and the function names are placeholders
pending the taxonomy prefixes (§7 of the package spec).
**Repo:** written into `hvtiRdatabuild` because the spec it follows lives here.
The package it designs does not, and will not.
**Follows:** [`2026-09-03-imputation-package-spec.md`](2026-09-03-imputation-package-spec.md),
whose §6 and §8 are decided and whose §2 is answered as a bound, and
[`2026-09-05-divergent-macro-copies.md`](2026-09-05-divergent-macro-copies.md),
which sets the limit on what this package can promise.

⚠️ **No study, patient or variable identifier appears here.**

This note is self-contained. It assumes no memory of the session that produced
it.

---

## 1. What it is, in one paragraph

A package that takes a data frame, fills its missing values by a stated method,
and hands back the filled data together with a record of exactly what it
changed. It knows nothing about the warehouse, the build, or any study. That is
the whole scope.

## 2. What it is not, and why the boundary is there

**It does not depend on `hvtiRdatabuild`, and `hvtiRdatabuild` does not depend on
it.** §6 of the package spec settled that imputation is a *method* rather than a
build step, and the family's pattern is that methods live in their own packages.
A method package that took a build-layer dependency would drag the warehouse
credential ladder, the manifest and the snapshot machinery into every analysis
job that wanted to fill a column.

So the input is a data frame and the output is a data frame plus a record. Any
study, manifest or provenance context belongs to the caller.

⚠️ **The §6 test was never run.** "Does anything outside the build ever need to
impute?" is still unverified, and the evidence remains a filename pattern. The
decision was taken knowing that, on the argument that it fails safe in the
direction taken. This design keeps it failing safe: nothing here reaches into a
build, so if imputation does turn out to happen only during one, the cost is a
package `hvtiRdatabuild` depends on rather than a rewrite.

## 3. Two entry points, not one

§7 of the package spec is settled on the evidence: **two taxonomy prefixes are
needed, not one.** 223 studies call single mean imputation, 326 call multiple
imputation, and 18 call both. They are different methods with different
inferential properties.

So the package exposes **two functions**, not one function with a `method=`
argument:

- one that fills each missing value with its variable's mean, returning **one**
  completed dataset;
- one that generates **m** completed datasets and is used with a pooling step.

⭐ **The reason is the failure the package spec opens with.** A single `impute()`
that quietly does one when the caller expects the other is a worse failure than
no package at all, and a `method=` argument with a default is exactly that
failure wearing an argument name. Two functions cannot be confused by omission.

⚠️ Names are deliberately absent here. They are gated on the taxonomy prefixes,
which are open, and `mi` is a poor choice for either taken alone because it
reads as multiple imputation to a statistician. Inventing names now is how they
become permanent.

## 4. `m` is an argument, never an inherited default

This is the one place where the corpus findings change the API rather than the
documentation.

The corpus does not contain a single answer to "how many imputations did SAS
run". Five macro names exist in copies declaring different `NIMPUTE` defaults,
three of them spanning 1, so for a call that relies on a default there may be no
fact of the matter. Where the value can be read, 798 of 810 determinate calls
exceed 1, with a median of 5.

Three consequences:

- **`m` is an explicit argument** on the multiple-imputation function.
- **If it has a default, that default is ours.** Documenting it as "matches
  SAS" would be false: SAS did more than one thing. If the default is 5 because
  735 of 810 determinate calls used 5, the documentation says exactly that, and
  says it is a choice.
- ⭐ **A study being reproduced takes its `m` from that study's own saved
  output, not from the macro it called.** The macro cannot tell you; the log
  can. This is the same rule
  [`2026-09-02-vars-port-and-attrition-design.md`](2026-09-02-vars-port-and-attrition-design.md)
  §4 applies to verifying a `vars.sas` port, for the same reason.

## 5. What it returns

Two things, always, and neither is optional.

### The completed data

For single mean imputation, one data frame. For multiple imputation, m of them,
in whatever container the pooling step consumes.

### The record of what was changed

⭐ **A logical matrix, parallel to the input: one row per row, one column per
imputed variable, `TRUE` where the value was filled.**

Not a count. §4 of the package spec is explicit about why: a summary saying
"12 values imputed in this variable" cannot answer *"was this patient's value
imputed?"*, which is the question an audit asks. The matrix answers it directly
and can be reduced to any count, while the reverse is impossible.

The matrix form is chosen over a long data frame deliberately. It is parallel to
the data, so a row of the matrix lines up with a row of the data without a join,
and it stays small for a wide dataset with many rows. A long form is friendlier
to read and much larger, and the reading is what a summary method is for.

### Missingness indicators, generated

The SAS corpus creates `ms_*` indicator variables before imputing, so a model
can carry "this was missing" as a term. That practice is established rather than
incidental: 562 studies have them.

⭐ **The package generates its own indicators from the record above, rather than
adopting the SAS naming.** The reason is the one this family keeps relearning: a
convention adopted for parity becomes permanent, and `ms_<var>` would then be
ours to maintain forever because a study depends on it. Generating from the
record means one source of truth, and a caller reproducing a SAS analysis can
rename to `ms_*` in one step.

⚠️ The underlying principle is not negotiable and predates the naming:
**a value that means "observed" and a value that means "filled in" must not be
the same value.** The indicators are how that survives into a model.

## 6. Provenance travels with the artifact

Whatever is emitted records the method, the value of `m`, the package version
that produced it, and the seed where the method is stochastic. §4 and §5 of the
package spec require this; the corpus findings make it load-bearing rather than
tidy.

The argument in one line: an imputed dataset that does not say how it was
imputed cannot be reproduced, and this corpus is the proof: thirty years of
imputed datasets whose method is now only partly recoverable, and only by
scanning the code that produced them.

## 7. What it promises about reproducing SAS, and what it does not

⚠️ **Two tiers, and the package must not blur them.**

**Known.** 292 calls state their `NIMPUTE` value outright. For those the method
and `m` are facts, and an R implementation can be checked against the study's
saved output.

**Inferred, pending validation.** 518 more are settled by the copy of the macro
in the calling study. That is strong evidence and not proof: which copy SAS
loaded depends on the autocall path and `%include` order at run time, and the
scan that produced these records exactly that in its provenance. Reproducing one
of these studies means confirming `m` against that study's saved log FIRST. The
package should not present an inferred `m` as a known one, and neither should
its documentation.

**Not promised.** A general "reproduces the SAS corpus" guarantee. 129 of 939
calls cannot be attributed to a method from the code at all. 38 because the
study's own copies disagree with each other, and 91 because the calling study
holds no copy and the corpus-wide definitions conflict.

⚠️ That bound is a property of the corpus, not of this package, and no
implementation choice lifts it. It belongs in the package documentation rather
than only here, because a user reproducing an old study needs to know before
they start whether their study is inside it.

## 8. Relationship to the attrition record

Decided in §8 of the package spec and unchanged here: imputation enters the
CONSORT tracker as an **annotation stage** carrying row-level `imputed_any` and
`complete_case_pass`, not as an exclusion.

The reason is arithmetic. Rows kept only because a covariate was filled in are
not excluded, and they are not fully observed either, and a record with no
vocabulary for that third state will misreport one or the other.

⚠️ This is **blocked** on [hvtiPlotR#131](https://github.com/ehrlinger/hvtiPlotR/issues/131),
which is on that package's 3.0 roadmap. Nothing here should be built against a
guess at that interface.

## 9. Deferred, deliberately

- **The pooling step.** Multiple imputation is only multiple imputation if the
  results are pooled, and Rubin's rules are a separate piece of work with their
  own verification. Naming it here so it is not forgotten; not designing it.
- **Methods beyond mean imputation and `PROC MI`'s default.** Issue
  [#33](https://github.com/ehrlinger/hvtiRdatabuild/issues/33) asks for
  alternatives. The design above makes the method a parameter and the record
  name it, which is what a third method needs; choosing one is later work.
- **An implementation plan.** The `vars.sas` note gates extraction on a second
  study exercising the same shape, and the same discipline applies: the plan
  follows a first real use rather than accompanying the design.

## Definition of done for this note

- [ ] Function names agreed, once the taxonomy prefixes are
- [ ] The `hvtiPlotR` annotation-stage interface exists, so §8 can be built to it
- [ ] A first real use, in one study, exercising §5's return shape
- [ ] Only then: an implementation plan
