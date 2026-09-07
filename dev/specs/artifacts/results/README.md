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
match. All fourteen below used 1.1.9 over `/studies`.

| file | scan | run at |
|---|---|---|
| `imputation-scan.json` | which methods appear in the stem-matched jobs | 2026-09-04 15:19 |
| `callsite-scan.json` | who **calls** those jobs | 2026-09-04 16:58 |
| `nimpute-scan.json` | what `NIMPUTE` reaches `PROC MI` | 2026-09-05 17:04 |
| `census-reconcile.json` | why the scans and the job census disagree | 2026-09-05 07:41 |
| `reconcile-scan.json` | which macro names disagree, and at what cost | 2026-09-05 14:43 |
| `studylocal-scan.json` | ⭐ NIMPUTE per the calling study's own copy | 2026-09-05 14:59 |
| `macro-drift.json` | is the copy drift imputation's or the corpus's | 2026-09-06 09:17 |
| `nimpute-wide.json` | as `nimpute-scan`, definitions from all `.sas` | 2026-09-06 13:19 |
| `studylocal-wide.json` | as `studylocal-scan`, definitions from all `.sas` | 2026-09-06 13:22 |
| `log-verifiability.json` | ⭐ what fraction of studies could be verified | 2026-09-06 14:04 |
| `studylocal-defsonly.json` | ⭐ the definition scope alone, calls held fixed | 2026-09-06 14:08 |
| `lst-listing.json` | ⭐ what was filed, and can it check a port at rung 3 | 2026-09-06 16:02 |
| `build-structure.json` | ⭐ what a build is made of, counts only | 2026-09-06 16:29 |
| `direct-procmi.json` | ⭐ does anyone run `PROC MI` without the macro | 2026-09-06 19:35 |

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

## 🔴 `macro-drift.json` reopens the scope of the imputation scans

Run 2026-09-06 over all 227,783 `.sas` files. Its headline is that copy drift is
the corpus's normal condition rather than imputation's peculiarity: 1,064 of the
1,444 macro names existing in several copies have copies that disagree, and 1,062
of those disagree below the header.

⚠️ It also counts **1,555 copies of `mult_imput`** where
`reconcile-scan.json` counted **423**, over the same root. Every imputation scan
drew its definitions from files NAMED `^(imputsub|mult_imput)`, 1,134 of them;
this one reads every `.sas`. So the imputation scans' definition population was
under-scoped by roughly four, which makes the per-macro figures lower bounds and
puts the "no local copy" population in `studylocal-scan.json` in doubt. See
section 4b of `../../2026-09-05-divergent-macro-copies.md`.

## The two `-wide` files, and why their denominators differ

`nimpute-wide.json` and `studylocal-wide.json` (2026-09-06) rerun their scans
with `--defs-scope corpus`, taking definitions from all 227,783 `.sas` files
rather than the 1,134 named after the stems.

⚠️ **They used the coupled build, so their call population widened too**, from
104,666 candidate files to 226,957. That is why `calls` reads 1,769 rather than
939, and it means a change between a `-wide` file and its stem-scope counterpart
cannot be attributed to the definition scope alone. `--calls-scope` decouples the
two for any future run; these predate it. The wider call population is the better
measurement regardless, since 939 was itself scoped by the assumption this work
disproved.

⭐ The comparison worth reading is between the two `-wide` files themselves, over
the SAME 1,769 calls: the corpus-wide map settles 587 of them, the study-local
map settles 1,674.

`studylocal-defsonly.json` is the controlled version, run after `--calls-scope`
existed: wide definitions, calls held at 939. It isolates the definition scope,
which halves the undeterminable residual from 129 to 65 on its own.

## `log-verifiability.json` and the 38 it skipped

⚠️ 38 of 50,608 logs exceeded the 200 MB ceiling and were skipped, so every
figure in that file excludes them. The count is in the provenance rather than
absorbed silently. An earlier attempt without the ceiling pinned a core for
twenty minutes on one large log; the prefilter did most of the eventual speedup
and the ceiling caught the remainder.

## 🔴 `build-structure.json` was committed and withdrawn

⚠️ **It disclosed identifiers, against its own scan's stated contract.** It
emitted `/home/mgoormas`, a personal home directory naming an individual, and
`st1027`, a study identifier used as a libref by 247 studies. A background
security review caught it; I did not.

⭐ **The frequency floor was the wrong instrument, and that is the lesson.** It
assumed an identifying name is a RARE name. A shared reference to one study's
library is common AND identifying, so no floor could ever have caught it, and
`st1027` cleared a floor of 5 by a factor of fifty.

The scan now rejects the shapes that can be enumerated (personal directories,
study identifiers) and, because that list cannot be complete, ⭐ **emits no names
at all by default**. `--emit-names` turns them on for someone who will read the
output before committing it, and rejected entries are counted so a reader knows
something was withheld rather than absent.

⚠️ The file was removed from the working tree but remains in this repository's
git history, in the commits between `b2c6ad8` and its removal.

**Replaced 2026-09-06 16:29 by a counts-only rerun**, which is the file committed
here. ⭐ **The filter caught six identifying names on real data**: three librefs
and three `LIBNAME` targets that cleared the frequency floor, so four more than
the two spotted by eye would have gone out.

## The fingerprint overflow changed nothing, now measured

The withdrawn run emitted `NAs produced by integer overflow` from the body
fingerprint: `v * seq_along(v)` on an integer vector overflows once an element
exceeds 2^31, needing a file of roughly 17 million characters. It was recorded
here as an undercount of `distinct_bodies` "by an unmeasured amount".

⭐ **Measured: the amount is zero.** The corrected rerun returns 22,989 distinct
bodies and 6,994 step shapes, identical to the run that warned. The warning was
real and no count moved.

`macro-drift.json` used the same function, and the same reasoning applies with
more margin, since macro bodies are far smaller than whole files. It has not been
rerun and does not need to be on this account.

## Not yet run

⚠️ **Every committed artifact predates the review fixes of 2026-09-06 17:15 and
should be regenerated before its numbers are quoted further.** Specifically:

- `build-structure.json` and `macro-drift.json` used a fingerprint with
  DEMONSTRATED collisions (`abba` and `baab` produced the same value), so their
  `distinct_bodies` are undercounts with no bound. Both now use md5 where
  `digest` is available.
- `log-verifiability.json` and `lst-listing.json` attributed studies AFTER
  skipping oversized files, so `with_any_log` (1,204) and `with_any_listing`
  (1,267) can undercount studies whose only file was oversized.
- `build-structure.json` also described its population as "builds" when it is
  every `.sas` file under `datasets/`; the field is renamed and now reports how
  many carry a DATA or PROC step at all.

⭐ **`direct-procmi.json` closes the question it was built for, in the opposite
direction to the suspicion that prompted it.** 1,650 of the corpus's 1,655
`PROC MI` statements sit inside a `%macro` body; 5 do not, across 2 studies. The
macro-call scoping in the imputation spec's §2 was right, and the 822 studies
`build-structure.json` reports for `PROC MI` are studies holding a file that
CONTAINS one, which is a count of definitions rather than of runs.

## The rung 1 / rung 3 join, and why it needed its own scan

⚠️ **Neither `log-verifiability.json` nor `lst-listing.json` can be joined to the
other, and no rerun changes that.** Both reduce their study set with
`length(unique(...))` before writing, so 1,180 and 676 are the sizes of two sets
whose members no longer exist anywhere. The overlap could be anything from 0 to
676.

⭐ **`rung-overlap-scan.R` computes the join where the data lives and emits a
scalar.** The obvious alternative -- emit both study lists and intersect them --
would put roughly 1,900 study identifiers into a committed artifact, which is
the class `st1027` belonged to and a larger disclosure than the one withdrawn
above. Aggregating inside the walk is what makes it safe; a filter on the way
out is what failed on 2026-09-06.

🔴 **It copies three detection patterns from the two scans it joins, so the copy
is guarded rather than trusted.** `test-rung-overlap-scan.R` evaluates
`RE_SHAPE`, `RE_ERROR` and `RE_MODEL` out of all three scripts and fails if any
pair differs. A drifted copy would still run and would report the overlap of two
populations that are not the ones these artifacts describe -- which is the
defect this whole body of work measured, in 1,064 macro names.

The scan is written, tested and staged; **`rung-overlap.json` does not exist
yet**, and no figure from it is quoted anywhere.
