# Scan outputs

The immutable evidence behind the §2 numbers in
`../../2026-09-03-imputation-package-spec.md`. Committed so a claim in the spec
can be checked against the artifact that produced it rather than taken on trust,
and so a later run can be diffed against this one.

⚠️ **Counts only.** No path, file name, study identifier, variable name, macro
name or parameter name appears in any of these files. That is the scans' privacy
contract, and it is why they are safe to hold in the repository at all.

Every file records, in its own `_provenance` block, the root, the scope, the
`hvtiRutilities` version and the taxonomy folder list it used. **The study counts
are a function of that taxonomy**, so two runs are comparable only when those
match. All six below used 1.1.9 over `/studies`.

| file | scan | run at |
|---|---|---|
| `imputation-scan.json` | which methods appear in the stem-matched jobs | 2026-09-04 15:19 |
| `callsite-scan.json` | who **calls** those jobs | 2026-09-04 16:58 |
| `nimpute-scan.json` | what `NIMPUTE` reaches `PROC MI` | 2026-09-05 17:04 |
| `census-reconcile.json` | why the scans and the job census disagree | 2026-09-05 07:41 |
| `reconcile-scan.json` | which macro names disagree, and at what cost | 2026-09-05 14:43 |
| `studylocal-scan.json` | ⭐ NIMPUTE per the calling study's own copy | 2026-09-05 14:59 |

## `nimpute-scan.json` has been rerun twice, and this is the third file

The version committed here is the **2026-09-05 17:04** run. Two earlier ones were
replaced, and the reasons are worth keeping because both changed how the result
should be read.

**First rerun**, after the three resolver fixes from
[#36](https://github.com/ehrlinger/hvtiRdatabuild/pull/36). ⭐ The correction was
large: 39 conflicting macro defaults across 5 names govern **622 of 939 calls**,
which the original run had silently resolved against whichever copy it read
first. The evidence base fell from 939 to 317. The direction did not change.

**Second rerun**, this file, adding the four-way conflict split from
[#42](https://github.com/ehrlinger/hvtiRdatabuild/pull/42) and the
positional-argument counters. It carries
`conflicting_default_all_gt1` / `_straddles_1` / `_all_le1` / `_unresolvable`,
and the three counters below.

⚠️ **Read the 317 with `studylocal-scan.json` beside it.** The 622 look
undeterminable in THIS file because it resolves each call against a map keyed by
macro name across the whole corpus. Resolved against the copy in the calling
study, 518 of them settle, leaving 129. Neither file is wrong; they answer
different questions, and the study-local one is the question that matches how the
code ran.

`census-reconcile.json` resolves the census gap: the census counted files whose
first dot-delimited field equals the stem, which reproduces 926 and 411 to within
a few files. It also shows `studies_only_suspect` at 0 and 1 — so test and dead
jobs inflate the FILE counts badly and the STUDY counts barely at all.

## `reconcile-scan.json` was regenerated 2026-09-05 14:43

The first copy was produced before the serializer fix in
[#41](https://github.com/ehrlinger/hvtiRdatabuild/pull/41): an unnamed R list was
emitted as a JSON object, so all five worksheet rows carried the key `""` and a
parser kept **one**. Replaced with the array form. ⭐ Every number is identical to
the 14:09 run, which is the expected result of a serialization-only change, and
confirms that the figures quoted in section 4a of
`2026-09-05-divergent-macro-copies.md` -- read from the raw text at the time --
were right.

## The positional-argument question is settled, by measurement

#41 corrected a defect shared by three scans: a value supplied positionally in a
call that also carried a keyword argument read as omitted.

⚠️ **An earlier version of this section lifted the flag on the grounds that
`studylocal-scan.json` reports `from_argument` at 292, identical to the
corpus-wide scan which ran without the fix. That argument does not hold**, and is
recorded rather than deleted. The study-local scan changed a second thing at the
same time, selecting parameter names from the calling study's copy rather than
one corpus-wide definition, so an offsetting pair would leave the totals matching
either way. ⭐ Two aggregates agreeing across two different algorithms is not
evidence that either change was inert.

**Measured instead.** `nimpute-scan.json` was rerun 2026-09-05 17:04 with
counters for exactly the population the old gate discarded:

| field | value |
|---|---|
| `mixed_form_calls` | **0** |
| `nimpute_from_positional` | **0** |
| `positional_in_mixed_call` | **0** |

⚠️ **Scoped to the population this scan counts, which is not the whole corpus.**
The counters increment only for calls to a macro this scan found binding
`NIMPUTE` through a parameter, within the studies that carry a stem-matched
definition. So zero establishes that **none of the 939 parameterised `NIMPUTE`
calls** is mixed-form or supplies its value by position. It does **not**
establish that no mixed positional-and-keyword macro call exists anywhere in the
corpus, and this counter should not be reused as a corpus-wide syntax census.

Within that population the defect was inert, and a full diff of the rerun against
the previous one moves nothing but the timestamp and those three fields. The
292 / 25 / 622 split stands, on evidence this time.

## Not yet run

`macro-drift.json` -- output of `../macro-drift-scan.R`, which asks whether the
copy drift found in the imputation macros is a property of imputation or of the
corpus. ⚠️ Run its `--count-only` mode first: the corpus size beyond the 547
imputation studies is unmeasured.
