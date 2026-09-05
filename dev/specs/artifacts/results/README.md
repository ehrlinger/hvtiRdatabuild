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
match. All four below used 1.1.9 over `/studies`.

| file | scan | run at |
|---|---|---|
| `imputation-scan.json` | which methods appear in the stem-matched jobs | 2026-09-04 15:19 |
| `callsite-scan.json` | who **calls** those jobs | 2026-09-04 16:58 |
| `nimpute-scan.json` | what `NIMPUTE` reaches `PROC MI` | 2026-09-05 07:33 |
| `census-reconcile.json` | why the scans and the job census disagree | 2026-09-05 07:41 |
| `reconcile-scan.json` | which macro names disagree, and at what cost | 2026-09-05 14:43 |
| `studylocal-scan.json` | ⭐ NIMPUTE per the calling study's own copy | 2026-09-05 14:59 |

## `nimpute-scan.json` is the corrected re-run

Replaced 2026-09-05 after the three resolver fixes from
[#36](https://github.com/ehrlinger/hvtiRdatabuild/pull/36). ⭐ The correction was
large: 39 conflicting macro defaults across 5 names govern **622 of 939 calls**,
which the first run had silently resolved against whichever copy it read first.
The evidence base is **317 calls, not 939**, and the headline is 97.2% rather
than 98.5%. The direction is unchanged.

⚠️ One split is still missing from this file and decides whether §2 ticks:
whether those 622 conflicted calls straddle `NIMPUTE = 1` or sit entirely above
it. The scan now emits `conflicting_default_all_gt1` and
`conflicting_default_mixed`; **this file predates those fields.**

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

## 🔴 `nimpute-scan.json` is still provisional

#41 corrected a positional-argument defect shared by three scans: a value
supplied positionally in a call that also carried a keyword argument read as
omitted.

⚠️ **An earlier version of this section declared the flag lifted, on the grounds
that `studylocal-scan.json` reports `from_argument` at 292, identical to the
corpus-wide scan which ran without the fix. That argument does not hold.** The
study-local scan changed a second thing at the same time: it selects parameter
names and positions from the calling study's own copy rather than one
corpus-wide definition. So a newly recognised mixed call could be offset by a
call classified differently for that unrelated reason, and the totals would still
match. ⭐ Two aggregates agreeing across two different algorithms is not evidence
that either change was inert.

Settling it needs a direct measurement rather than an inference: rerun
`imputation-nimpute-scan.R` with the fixed parser, or count mixed calls
explicitly. Until then the 292 / 25 / 622 split is provisional.

## Not yet run

Nothing. Every scan in `../` has been run against `/studies` and its output is
here.
