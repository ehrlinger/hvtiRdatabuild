# Divergent macro copies, and the ceiling they put on reproducing SAS

**Date:** 2026-09-05
**Status:** finding, measured at both the definition and the call level. What any
individual run did is not, and cannot be, recovered from the code alone.
**Origin:** the §2 scans in
[`2026-09-03-imputation-package-spec.md`](2026-09-03-imputation-package-spec.md),
which set out to ask which studies ran single and which ran multiple imputation.

⚠️ **No study, patient or variable identifier appears here.** The counts below
come from the scan outputs in [`artifacts/results/`](artifacts/results/), which
carry integers only.

This note is self-contained. It assumes no memory of the session that produced
it.

---

## 1. The finding, stated once

We went looking for what the corpus ran. We found that for a large part of it,
**the corpus does not contain a single answer to that question.**

Sixty-three macro names in the studies share hold a `PROC MI` whose `NIMPUTE`
comes from a macro parameter. Five of those names exist in copies that **declare
different defaults from one another**. Not different names, not different
bodies. The same macro, called the same way, with a different number behind it
depending on which copy a study happened to load.

Three of the five disagree across the line that matters:

| what the copies declare | how many of the five |
|---|---|
| every copy above 1 | 2 |
| copies on both sides of 1 | **3** |
| every copy at 1 or below | 0 |
| a copy with no readable default | 0 |

The defaults actually seen on those five names are `1` three times, `5` five
times, `8` once, `10` twice and `20` once.

`NIMPUTE = 1` is single imputation. It produces one completed dataset, and the
standard errors that follow from it understate the uncertainty in the same way
mean imputation does. `NIMPUTE = 5` is multiple imputation. So for a call that
omits the argument and lands on one of those three names, the honest answer to
"did this study multiply impute?" is **we cannot tell**, and no amount of
further reading of the code will change that.

## 2. Why this is a ceiling and not a bug

A port that cannot reproduce a SAS result usually means the port is wrong. This
is the other case. Here the **source** is not self-consistent, so there is no
single behaviour to reproduce.

Of 939 calls that take `NIMPUTE` from a parameter, **622 fall back on a
default** rather than passing a value, and those 622 land on the five divergent
names. Only 292 calls state the number outright, and a further 25 take a default
from a macro whose copies agree.

Weighted by how often each macro is invoked, the 622 fall out as:

| | calls |
|---|---|
| every copy above 1, so multiple imputation whichever was loaded | 3 |
| ⭐ **copies on both sides of 1, so undeterminable** | **619** |
| every copy at 1 or below | 0 |
| a copy with no readable default | 0 |

So **619 of 939 calls, 66%, cannot be attributed to either method.** The
undeterminable share is not a rounding error at the edge of the result. It is
two thirds of it.

That sets a hard bound on the migration. **A reproduction guarantee can be
offered for the calls that state their value, and cannot be offered for the
ones that do not.** The bound is a property of the corpus. It is not something a
better scan, a better resolver or a better port will lift.

⚠️ What we know is that the **definitions** disagree. What any individual run
actually did is a different question, and the code cannot answer it. Only that
study's saved `.log` and `.lst` can, which is the same ground truth
[`2026-09-02-vars-port-and-attrition-design.md`](2026-09-02-vars-port-and-attrition-design.md)
§4 relies on for verifying a `vars.sas` port.

## 3. Where the divergence comes from

Nothing here is a surprise once you look at how the corpus is laid out. Every
study carries its **own copy** of the jobs it runs. The `vars.sas` note recorded
that pattern for data preparation: a census of one clinical area found 85
copies, running from 158 to 1160 lines, and no shared institutional file behind
them.

This is the same pattern, measured one layer down and with a consequence
attached. Of 1,134 stem-matched imputation files across 547 studies, 1,132
**define** a macro and none call one. They are copies of a canonical file, each
sitting in its own study, and over thirty years the copies drifted.

⭐ **A copy is not a version.** Copying a file to a study gives that study a
private fork with no record that it forked and no mechanism to notice when the
original moves. The drift is invisible from either end: the study cannot see the
canonical file change, and nobody maintaining the canonical file can see the
copies. That the drift reached the `NIMPUTE` default, and so reached filed
results, is the part worth carrying forward.

## 4. What this changes for `hvtiRimputation`

The imputation spec already requires that the emitted artifact record the method
and the package version that produced it (§4), and that the method be a
parameter whose value the record names rather than defaulting silently (§5).
This finding sharpens the second one.

**There is no "the SAS default" for the port to adopt.** An R implementation
defaulting to `m = 5` would match the most common declared value, and would
match it the way a coin match happens: five of the twelve declared defaults on
these names are 5, and three are 1. So a default of 5 is a reasonable choice,
and it must be documented as *our* choice rather than as reproducing what SAS
did, because SAS did more than one thing.

For the same reason, a study being re-run in R needs its `m` supplied from that
study's own saved output, not inferred from the macro it called.

## 4a. The worksheet, run 2026-09-05, and what it overturns

| macro | copies | declared defaults | spans 1 | distinct bodies |
|---|---|---|---|---|
| `mult_imput` | **423** | 1x4, 5x390, 10x27, 20x2 | yes | **381** |
| `mult_imputiso60` | 6 | 1x3, 5x3 | yes | 2 |
| `mult_imput_dead` | 4 | 5x3, 8x1 | no | 4 |
| `mult_imput_mv` | 2 | 5x1, 10x1 | no | 2 |
| `multimput` | 2 | 1x1, 5x1 | yes | 2 |

🔴 **`mult_imput` has 423 copies and 381 distinct bodies, 380 of them still
distinct once the header is removed.** So §5's framing below, written before this
ran, is wrong about the dominant case. These are not copies of one canonical file
that drifted in a default. They are **381 different programs sharing a name**,
and there is no canonical version to converge on. Reconciling `mult_imput` is not
a one-line edit per copy, and it is not a merge either.

⚠️ **But the exposure is far narrower than the straddle suggests.** Only **4 of
423** copies declare `nimpute=1`; 390 declare 5. Across every macro binding
`NIMPUTE`, 460 of 506 readable defaults are 5 and 11 are 1. The three names that
span 1 do so on a handful of outliers, and two of the five (`mult_imput_dead`,
which is a retired job, and `mult_imput_mv`) do not span 1 at all.

⭐ **And the framing of the ambiguity was wrong too, which matters more.** Every
study carries its own copy, so a call in a study resolves against **that study's
copy**, not against a population of 423. The scans built a map keyed by macro
name globally, deliberately, because `mult_imput` is called in 326 studies and
defined in 277. That global map is what makes the 619 calls look undeterminable.
A **study-local** resolution, joining each call to the copy in its own study,
would determine most of them.

⚠️ That is an inference, not proof: which copy SAS actually loaded depends on the
autocall path and `%include` order at run time, not merely on which file sits in
the study directory. It is a strong inference and a testable one, against the
studies that kept their logs.

**So the next step is not reconciliation.** It is a study-local resolution pass,
which is cheaper, needs no institutional decision, and may collapse the 619 to
something small. Reconciliation, if it is still wanted afterwards, applies to
whatever is left.

## 4b. The study-local pass, run 2026-09-05, and what it recovers

4a argued that the ambiguity was partly an artifact of asking the question
corpus-wide. Measured, it mostly was.

| route | calls |
|---|---|
| the call states the value | 292 |
| ⭐ **the calling study's own copy settles it** | **518** |
| the study's own copies disagree | 38 |
| the study holds no copy, and the corpus-wide map conflicts | 91 |
| unresolved | 0 |

**Determinate: 810 of 939, 86%.** Of those, **798 are multiple imputation and 12
are single.** The undeterminable share falls from 619 to **129**.

⭐ **The first run of all this claimed 925 of 939, 98.5%. We arrive at 798 of
810, also 98.5%.** The number never moved. What changed is that it is now earned:
86% coverage measured, rather than 100% coverage assumed.

⚠️ **The residual 129 has two halves that need different remedies, and neither
is reconciling the five.** Only 38 are **calls** whose study holds copies that
disagree with each other. The other 91 are calls from studies that hold **no
copy at all**,
which is the gap between `mult_imput` being called in 326 studies and defined in
277: those calls reach a definition from somewhere this scan cannot see, and the
corpus-wide map is not a substitute.

⚠️ The inference stands as an inference. A study's own copy is strong evidence of
what its calls ran and is not proof; the autocall path decides at run time. The
output records that in its provenance block so it travels with the numbers.

⭐ **One thing settled alongside this, and settled the second time round.** #41
corrected a defect that discarded a `NIMPUTE` value supplied by position in a
call that also carried a keyword argument. Whether it had changed any of these
numbers was first argued from `from_argument` coming back at 292 in both scans,
which does not follow: the study-local pass changed a second thing at the same
time, so an offsetting pair would leave the totals identical either way.

Measured instead, by a rerun on 2026-09-05 at 17:04 emitting counters for it:
**`positional_in_mixed_call` is 0**, and so are `mixed_form_calls` and
`nimpute_from_positional`.

⚠️ **Scoped to what those counters count.** They increment only for calls to a
macro binding `NIMPUTE` through a parameter, inside the studies carrying a
stem-matched definition. So zero says none of the **939 parameterised `NIMPUTE`
calls** is mixed-form or supplies its value by position. It does not say that no
mixed positional-and-keyword call exists anywhere in the corpus, and it must not
be quoted as a syntax census.

Within that population the defect was inert. A full diff of that run against the
previous one moves nothing but the timestamp and the three new fields.

### 4c. The wide-definition reruns, 2026-09-06

Section 4b's residual was judged against definitions taken from files NAMED after
the stems. Rerun with `--defs-scope corpus`, reading all 227,783 `.sas` files:

| route | stem scope | corpus scope |
|---|---|---|
| calls | 939 | 1,769 |
| the call states the value | 292 | 561 |
| the calling study's own copy settles it | 518 | 1,113 |
| the study's own copies disagree | 38 | 54 |
| ⭐ the study holds no copy | **91** | **40** |
| determinate | 810 (86%) | **1,674 (95%)** |

⭐ **Of the 1,674 determinate calls, 1,665 are multiple imputation and 9 are
single.** The undeterminable share falls from 129 to 94.

⚠️ **My prediction was wrong and is on the record.** Before the run I said the 91
would fall "only modestly", reasoning from pass 1 that the wider scope adds
copies rather than macros. It more than halved, to 40. Those studies did hold
their own definitions, in files not named after the stem.

### 4d. The same calls, resolved two ways

The corpus-wide run over the same 1,769 calls reports **587 determinate, 33%**,
against the study-local run's **1,674, 95%**.

⭐ **That is the whole thesis in one comparison.** Nothing about the corpus
changed between those two numbers. The only difference is whether a call is
resolved against a map keyed by macro name across the whole corpus or against
the copy sitting in the study that made it. The first manufactures ambiguity that
the second does not have.

⚠️ Two things the corpus-wide run adds that the stem-scoped one could not see,
and both are worse rather than better news about the code:

- `conflicting_redefinitions` is **5**, where the stem scope reported **0**. Five
  macro names bind `NIMPUTE` to a different EXPRESSION across their copies, not
  merely to a different default.
- `conflicting_default_straddles_1` collapses from 619 to 5, and
  `conflicting_default_unresolvable` rises from 0 to 1,174. The wider scope finds
  copies declaring an EMPTY `nimpute=`, so for those macros the candidate values
  cannot even be enumerated. ⭐ That is a worse epistemic position than a
  straddle, not a better one: "ambiguous between known values" became "the values
  are not knowable from the definitions".

⚠️ **These two runs used the COUPLED build, and their denominators are not
comparable with the committed stem-scope results.** `--defs-scope` moved the call
population as well as the definition population, from 104,666 candidate files to
226,957, which is why `calls` is 1,769 rather than 939. The wider call population
is the better measurement, since 939 was itself scoped by the assumption this
work disproved. But the improvement from 86% to 95% cannot be attributed to the
definition fix alone, because both changed at once. `--calls-scope` now decouples
them for any future run.

## 5. Where this is heading

⚠️ **This section and section 6 were written before the worksheet and the
study-local pass ran, and both overturned them. They are kept as written, and
this box says what is no longer true, because the wrong turns are the point of
the record.**

| said below | actually |
|---|---|
| reconciling is "small, finite" | 423 copies, 381 distinct bodies (4a) |
| "the only route to lifting the bound" | the study-local pass lifted most (4b) |
| 320 determinate, 619 open (section 6) | **810 determinate, 129 open** |
| the worksheet has not been run | run 2026-09-05, as has 4b's pass |

**The current next step is neither reconciliation nor another scan.** The
residual 129 splits into 38 calls whose study holds copies that disagree, and 91
calls from studies holding no copy, and those need different remedies. Both are
small enough to leave alone unless a specific study needs its own answer, in
which case that study's saved log settles it directly.

Three things follow, in order of how tractable they are.

**Reconcile the five.** This is a small, enumerable, finite piece of work. Five
macro names, twelve declared defaults between them, and a decision about which
copy is canonical. It would settle §2 properly rather than through another scan,
and it is the only route to lifting the bound in §2 for future work.

⭐ **Nothing above can name the five.** Every scan here emits counts only, so the
output says five macros disagree and not which. Reconciling starts with
identifying them, so
[`artifacts/imputation-reconcile-scan.R`](artifacts/imputation-reconcile-scan.R)
does, under a narrower privacy contract stated in its header: it emits **macro
names and declared defaults, and no study locations**. Deciding a canonical
default needs the names and the numbers. Going and editing the copies needs the
paths, and that is a separate decision with the study owners.

Per conflicted name it reports each declared default with how many copies
declare it, how many calls reach the name and how many rely on its default, and
⭐ **whether the copies differ only in the default or in the body too**. That
last one sizes the work: if the bodies agree once the header is removed,
reconciling is a one-line edit per copy; if they do not, it is a merge and the
default is only the visible part of the divergence. It also reports what every
macro binding `NIMPUTE` declares, unnamed, because the institutional norm is an
argument for what canonical ought to be.

`--no-calls` runs the definitions only, in seconds over 1,134 files, which is
where the decision content is.

**State the bound rather than the headline.** Until then, anything downstream
that quotes an imputation figure from this corpus should quote it against the
calls whose method can be determined, and say how many could not. The first run
of the scan reported "98.5% of 939", which was the headline; each correction
since has moved it toward a smaller and more honest number.

**Repeat the measurement elsewhere.** We found this because §2 forced us to
resolve a value across a definition and a call site. Nothing about the mechanism
is specific to imputation. Any macro family distributed as per-study copies can
have drifted the same way.

[`artifacts/macro-drift-scan.R`](artifacts/macro-drift-scan.R) asks it of every
macro name in the corpus rather than one family: how many names exist in several
copies, how many of those copies are not identical, and ⭐ **whether they differ
only in the header or below it**. The first is a signature or a default drifting,
which is what bit the imputation macros. The second is what the macro DOES
drifting, which is worse.

**The corpus is 227,783 `.sas` files** under `/studies`, from the scan's own
`--count-only` on 2026-09-06. A little over twice the imputation walk, so a full
pass runs in about an hour and the whole corpus can be covered in one go.

⚠️ That also retires two wrong numbers, one of them mine. A comment in the first
scan called the corpus "millions of files", written without measuring. A later
draft of this section put it at 3,847,221 and called it measured; it was not
measured by this scan, and the count above is.

⭐ **If it ever does need bounding, bound by root rather than by file count.**
Detecting drift means comparing every copy of a name against the others, so a
subset of FILES undercounts it: copies outside the subset are invisible and the
name reads as more consistent than it is. A clinical tree is a complete
population for the question, and gives a lower bound rather than a biased
estimate.

### Run 2026-09-06, and the drift is the corpus's, not imputation's

227,783 files, 1 unreadable, 315,871 macro definitions, 2,449 distinct names.

| | names |
|---|---|
| defined in one copy only | 1,005 |
| defined in several copies | 1,444 |
| ⭐ **of those, copies that are not identical** | **1,064 (74%)** |
| differing below the header | 1,062 |
| differing in the header only | 2 |

⭐ **Three quarters of every macro name that exists in more than one copy has
copies that disagree, and almost all of them disagree in what the macro DOES,
not merely in how it is declared.** Imputation is not a special case. It is an
ordinary instance of the corpus's normal condition, and it only came to notice
because §2 forced a value to be resolved across a definition and a call site.

The scale dwarfs the imputation finding. `skip` exists in **81,813 copies across
1,396 studies with 46,763 distinct bodies**; `mult_imput`'s 421 distinct bodies
place it nineteenth. ⚠️ Note against reading the top of that list as an artifact:
`plots` has 20,159 copies and only 765 distinct bodies, 4% unique. A body-slicing
defect would inflate every name alike, and it does not.

⭐ **`vars` is the interesting exception, and it is the family the port work
depends on.** 5,055 copies, 269 distinct bodies, but only **39** below the
header. Its copies drift in their signature far more than in their work, which
is the opposite shape to everything above it.

### 🔴 The result also reopens a scope question in §2

`mult_imput` is defined in **1,555 copies** corpus-wide. The reconciliation
worksheet in 4a counted **423**, and both scans read the same `/studies`.

The difference is what each looked at. Every imputation scan took its definitions
from files whose NAME matches `^(imputsub|mult_imput)`, which is 1,134 files.
This one reads all 227,783. So `%macro mult_imput` is defined in a great many
files not named after it, and ⚠️ **the imputation scans' definition population was
under-scoped by roughly a factor of four.**

Three consequences, none yet measured:

- 4a's per-macro figures are **lower bounds**, not counts.
- The five conflicting names and 39 conflicting defaults were found among 933
  copies drawn from stem-named files. A wider definition population may hold
  more.
- 🔴 Most consequentially, section 4b's **91 calls from studies holding "no local
  copy"** were judged against the same stem-matched population. A study whose
  `mult_imput` definition sits in a differently-named file would have been
  recorded as having none. That number, and the 129 undeterminable it feeds, may
  be smaller than reported.

⚠️ This does not move the direction of §2: the 292 calls that state their value
are untouched, and nothing here suggests the 798-of-810 split is wrong. What it
touches is the denominators and the residual. Settling it means rerunning the
imputation definition pass over all `.sas` files rather than the stem-matched
ones, which the drift scan has now shown is about an hour of work rather than
the prohibitive job it was assumed to be.

## 6. What is measured, and what is not

Kept explicit so a later reader does not have to reconstruct it.

**Measured**, from `artifacts/results/nimpute-scan.json` and the pass 1 verdict
of the 2026-09-05 run:

- 63 macro names bind `NIMPUTE` to a parameter; 5 have copies declaring
  different defaults; 3 of those 5 straddle 1; none has an unreadable default.
- 939 calls take `NIMPUTE` from a parameter. 292 state it, 25 take an agreeing
  default, 622 take a divergent one.
- Of the 317 calls resolvable to a value, 308 exceed 1 and 9 equal 1.

- The per-call split of those 622: 3 above 1, 619 straddling, 0 at or below 1,
  0 unreadable.
- Of the 320 calls whose METHOD can be determined (317 resolved to a value, plus
  3 known to exceed 1 without a known value), 311 are multiple imputation and 9
  are single.

**Not measured:**

- Which copy any given study loaded, which the code cannot say.
- Whether the same drift affects other macro families. Nobody has looked.

## Definition of done for this note

- [x] The divergence measured and its size stated
- [x] The consequence for the migration stated as a bound
- [x] Per-call weighting filled in from the completed 2026-09-05 run
- [ ] The worksheet run (`imputation-reconcile-scan.R`)
- [ ] A canonical default agreed per name, recorded here
- [ ] The five names reconciled on the share, or a decision recorded not to
- [ ] The same measurement run against one other macro family
