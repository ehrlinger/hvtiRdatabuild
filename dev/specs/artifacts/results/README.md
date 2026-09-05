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
match. All three below used 1.1.9 over `/studies`.

| file | scan | run at |
|---|---|---|
| `imputation-scan.json` | which methods appear in the stem-matched jobs | 2026-09-04 15:19 |
| `callsite-scan.json` | who **calls** those jobs | 2026-09-04 16:58 |
| `nimpute-scan.json` | what `NIMPUTE` reaches `PROC MI` | 2026-09-04 18:56 |

## ⚠️ `nimpute-scan.json` predates three resolver corrections

Review of [#36](https://github.com/ehrlinger/hvtiRdatabuild/pull/36) found three
defects in `imputation-nimpute-scan.R` after this run. All are fixed; the corpus
run has not been repeated. **Two of them can move the numbers in this file:**

- conflicting macro **defaults** were invisible to the conflict check, so
  `conflicting_redefinitions: 0` here is weaker evidence than it reads as — and
  69% of the calls in this file resolved from a default;
- `%let` resolution ignored statement order, so a later assignment could decide
  an earlier call.

The third — definitions settling `NIMPUTE` with no caller entering the call
denominator — cannot affect this file: `binding_literal`, `binding_local` and
`settled_by_definition_alone` are all 0 in it.

**Replace this file from a fresh run before citing it as settled**, and expect
the new output to carry fields this one does not (`conflicting_defaults`,
`macros_conflicted`, `unresolved_conflicting_default`, `definition_settled`).

The first two files are unaffected by those corrections.

## Not yet run

`census-reconcile.json` — output of `../imputation-census-reconcile.R`, which
explains why these scans and the job census disagree about `mult_imput`
(506 files / 277 studies here against a census of 411 / 242, *higher* than a
census that should be a superset). The scan is written and tested; it has not
been run.
