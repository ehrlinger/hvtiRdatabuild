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

## 5. Where this is heading

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
have drifted the same way, and the same scan shape (read the definitions, join
them to the call sites, report where the copies disagree) would find it. The
`conflicting_defaults` field exists for that, and reporting it should be the
default posture for a corpus scan, not an afterthought.

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
