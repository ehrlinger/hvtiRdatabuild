# HVTI R Package Family: Naming Convention

**Date:** 2026-08-27
**Status:** Approved. Wave 1 is planned in
[`specs/plans/2026-08-27-hvtiRdatabuild-rename.md`](plans/2026-08-27-hvtiRdatabuild-rename.md)
and implemented in [PR #19](https://github.com/ehrlinger/hvtiRdatabuild/pull/19); it shipped
2026-08-27. Wave 2 shipped 2026-08-27. Wave 4 is replanned in
[`specs/plans/2026-08-27-wave-4-governance.md`](plans/2026-08-27-wave-4-governance.md),
because the one-paragraph description below understates it — a survey after Wave 2 found
11 `AGENTS.md`-class files rather than four, and two defects that are functional rather
than prose. Wave 3 is postponed by maintainer decision, still behind the upstream
`boostmtree` sync.
**Scope:** Family-wide — 12 `hvti*` repos plus two roster members outside the prefix
**Drafted in:** `hvtiRdatasets/specs`, because Wave 1 is this repo's own rename. The
normative text migrates to `house-style/sources/r-package-structure.md` in Wave 4, which
is where the convention is enforced. This document is the design record; the house style
is the rule.

## Context

The family grew one package at a time, and its names record that history rather than any
decision. Ten repos hold R packages, one holds a Quarto book, and one held a Python
project. Package names use three different shapes, two repos disagree with the package
inside them, and two separate registries exist partly to carry that disagreement.

State at the time of writing:

| Package | Repo | Deviation |
|---|---|---|
| `hvtiR` | `hvtiverse` | repo ≠ package |
| `hvtiRutilities` | `hvtiRutilities` | — |
| `hvtiRdatasets` | `hvtiRdatasets` | name promises data, delivers a pipeline |
| `hvtiRtables` | `hvtiRtables` | — |
| `hvtiRtemplates` | `hvtiRtemplates` | — |
| `hvtiRlifetables` | `hvtiRlifetables` | — |
| `hvtiRbootstrap` | `hvtiRbootstrap` | — |
| `hvtiRpropensity` | `hvtiPropensityScores` | repo ≠ package |
| `hvtiPlotR` | `hvtiPlotR` | trailing `R` |
| `hvtiBoostmtree` | `hvtiBoostmtree` | no `R` |
| `TemporalHazard` | `temporal_hazard` | repo ≠ package, `snake_case` |
| `ggRandomForests` | `ggRandomForests` | — (CRAN) |
| — (Quarto book) | `hvti_graphics` | `snake_case` |
| — (Python) | `hvtiEDAreports` | not an R project at all |

Two facts make this a good moment to fix it. **Nothing in the family imports
`hvtiRdatasets`** — the only intra-family dependency edges are `hvtiRutilities` ←
`hvtiRdatasets` and `hvtiRutilities` ← `hvtiRtemplates` — so renaming it triggers no
cascade. And **no family package is on CRAN**; none carries a `Repository: CRAN` field,
so no published name is at stake.

## The convention

**Clause 1 — a package is named `hvtiR<domain>`.** The `hvtiR` prefix is literal, and is
also the umbrella package's own name, so the brand string and the namespace prefix are one
thing. `<domain>` is lowercase, noun-shaped, and may be a compound word (`lifetables`,
`databuild`).

**Clause 2 — the GitHub repo name is exactly the package name.** One string per package:
what you `library()`, what follows `ehrlinger/` in `pak::pak()`, and what the pkgdown URL
is built from.

**Clause 3 — a package published on CRAN keeps its published name.** Renaming a CRAN name
orphans installs and breaks citations, so the convention yields to it. This binds nothing
inside the family today, and protects `ggRandomForests` in the roster. It protects the
*package* name only; a CRAN package's repo still follows Clause 2.

**Clause 4 — `hvtiPlotR` is the one grandfathered exception.** It is at v2.7.10, the most
mature and most-used package in the family, and its `hv_*` functions are called across
every downstream analysis. The cost of invalidating those call sites exceeds the cost of
the inconsistency. This reason is recorded so a future sweep does not "fix" it. No new
exception may be added without an argument of the same shape.

### Why `hvtiRdatabuild`

The package exports six functions — `dw_connect()`, `dw_modules()`, `dw_pull()`,
`read_study_config()`, `snapshot_oracle()`, `compare_built()` — and no data object. It has
no `data/` directory. In R, a `…datasets` name says the package *ships* data
(`nycflights13`, `datasets`), so the current name promises a payload and delivers a
process.

`hvtiRdatabuild` keeps `data` as the term anyone would search the family for, and lets the
`build` suffix do the disambiguating. It avoids reading as package-build tooling the way a
bare `hvtiRbuild` would, next to CRAN's `pkgbuild`. At 14 characters it is mid-range for
the family, shorter than `hvtiRlifetables`, `hvtiRpropensity` and `hvtiRboostmtree`, and
`databuild` is the same two-word lowercase compound shape as `lifetables` — so it keeps
the family's noun rhythm rather than breaking it as a bare verb would.

The name encodes the action every user performs. It does **not** imply that verification
is secondary or temporary, and an earlier draft of this document argued exactly that —
wrongly. Studies are revisited for reproducibility long after their original analysis, and
proving that a rebuild matches the original is both durable and, today, the hard part.
`snapshot_oracle()` and `compare_built()` are permanent, first-class API, not migration
scaffolding, and nothing here contemplates splitting them out.

The name is chosen on discoverability instead: `databuild` keeps `data` as the term
someone hunting for their study data would search, while `build` disambiguates against the
"ships a payload" reading. It undersells verification, which is a real and accepted cost —
package names rarely carry a guarantee, and no candidate covered both halves without
either re-inviting the payload misreading or going abstract enough to be unsearchable.

Two consequences follow, both outside this document's scope and recorded as follow-on
work. The roxygen prose is written as if the window closes — `snapshot_oracle()` is titled
"Freeze a *SAS-built* dataset" and warns about drift "*mid-migration*" — and needs
re-framing around reproducibility. And `snapshot_oracle()` takes a `sas_path` and calls
`.read_sas_dataset()`, so an R-built data frame cannot be frozen as a future reference.
That signature is the only real gap: `compare_built()` takes two data frames and is
already oracle-source-agnostic, and the `manifest` hook already registers snapshots with
`hvtiRutilities::update_manifest()` so `verify_manifest()` can "later detect a drifted
oracle" — the longitudinal case is anticipated in the code even where the prose denies it.

## The rename map

| Today | Becomes | Clause |
|---|---|---|
| pkg + repo `hvtiRdatasets` | **`hvtiRdatabuild`** | 1 |
| repo `hvtiverse` (pkg `hvtiR`) | repo → **`hvtiR`** | 2 |
| repo `hvtiPropensityScores` (pkg `hvtiRpropensity`) | repo → **`hvtiRpropensity`** | 2 |
| pkg + repo `hvtiBoostmtree` | **`hvtiRboostmtree`** | 1 |
| repo `temporal_hazard` (pkg `TemporalHazard`) | repo → **`TemporalHazard`** | 2, 3 |
| repo `hvti_graphics` (book) | repo → **`hvtiGraphics`** | — |
| `hvtiRutilities`, `hvtiRtables`, `hvtiRtemplates`, `hvtiRlifetables`, `hvtiRbootstrap` | unchanged | 1, 2 |
| `hvtiPlotR` | unchanged | 4 |
| `ggRandomForests` | unchanged | 3 |
| `hvtiEDAreports` | **archived** | see below |

`hvtiBoostmtree` is renamed despite being a fork of CRAN's `boostmtree` with
Ishwaran/Pande/Kogalur retained as `aut`. The fork itself is not on CRAN, so Clause 3 does
not reach it, and the decision was taken explicitly rather than by default. Its rename is
sequenced behind an upstream sync — see Wave 3.

`hvti_graphics` becomes `hvtiGraphics`, not `hvtiRgraphics`. It is a Quarto book, and the
bare `hvti` prefix is the signal that the `R` in `hvtiR` means "an R package you can
`library()`". The rename kills the only `snake_case` separator in the family without
claiming the book is a package — a claim its own `AGENTS.md` explicitly forbids.

## Retiring `hvtiEDAreports`

`hvtiEDAreports` is a **Python project**, not a Quarto book: `pyproject.toml`, `cli.py`,
`eda/`, `tests/conftest.py`, an `.egg-info`. The `eda_report.qmd` at its root is a template
its CLI renders. Last commit 2026-07-02.

It is retired by **archiving on GitHub** — `gh repo archive`. History, issues and PRs are
preserved, the repo becomes read-only and stays browsable, and the action is reversible
with `gh repo unarchive`. It is not deleted. The local clone is left in place.

This also resolves a governance question rather than deferring it: `house-style` defines
exactly three profiles — `package-internal`, `package-cran`, `book` — and none fits a
Python project. Governing it would have required inventing a fourth profile for a repo
with no active work.

Three files outside the repo name it and are updated to record the retirement with its
date: `hvtiverse/README.md`, `hvtiverse/design/2026-08-19-design.md`, and
`hvtiverse/design/2026-08-19-plan.md`.

## Where the convention lives, and what collapses

The convention goes into `house-style/sources/r-package-structure.md` as a `## Naming`
section beside the existing `## DESCRIPTION` and `## Versioning` sections. That file
composes into every governed repo's `.claude/house-style.md`, and every governed repo runs
`house-style.yaml` in CI, which fails on drift. This is the difference between a
convention that is documented and one that is checked. Twelve hand-maintained `AGENTS.md`
copies would drift; one composed source with a drift check does not.

Two registries carry the package→repo mapping today, and Clause 2 makes both derivable:

| Registry | Today | After |
|---|---|---|
| `hvtiverse/R/members.R` | hand-aligned parallel `package` and `repo` vectors | `repo = paste0("ehrlinger/", package)` |
| `house-style/repos.yml` | `name:` and `path:` per entry | `path` derived from `name` |

Neither is removed — `members()` still needs the roster, `repos.yml` still needs profiles
and personas. But the parallel-vector index alignment in `members.R`, which must be
maintained by hand across two eleven-element vectors, stops being a thing that can silently
break.

### Closing the governance gap

`repos.yml` governs ten repos and omits four. With `hvtiEDAreports` archived, the
remaining three are added as `package-internal`, matching their siblings
(`default_persona: a`, `secondary_personas: [c]`):

- `hvtiRtemplates`
- `hvtiRlifetables`
- `hvtiR` (the umbrella, formerly `hvtiverse`)

After this, every non-archived repo in the family is governed.

## Execution

Four waves, ordered so nothing is broken between them. GitHub keeps rename redirects
indefinitely, so `pak::pak("ehrlinger/hvtiverse")` continues to resolve after Wave 2.

**Wave 1 — this repo.** `hvtiRdatasets` → `hvtiRdatabuild`. 72 references across 27 files
carry the old name; the five dated documents under `specs/` are left alone as historical
record, per *Not done* below. The 27: `DESCRIPTION` (`Package`, `URL`, `BugReports`, and
later `Version`/`Date`), `git mv R/hvtiRdatasets-package.R`, four further `R/` files
carrying the name in code or roxygen, `tests/testthat.R` and three sibling test files,
three regenerated `man/` files, `README.md`, `NEWS.md`, `vignettes/coming-from-sas.qmd`,
`AGENTS.md`, `CLAUDE.md`, `_pkgdown.yml`, `codecov.yml`, six workflow files, and the
composed `.claude/house-style.md`. The last of these is never hand-edited — two of its
seven occurrences are written from the registry entry's `name` field, so they are fixed by
recomposing after the directory rename, not by search-and-replace. `equivalence_signoff.yaml`
also carries the name, in a citation of a historical filename, and is deliberately left
unchanged, the same way as the specs citation in `README.md`. Branch, then PR.

**Wave 2 — repo-only renames.** No package name changes, so no namespace breaks:
`hvtiverse`→`hvtiR`, `hvtiPropensityScores`→`hvtiRpropensity`,
`hvti_graphics`→`hvtiGraphics`, `temporal_hazard`→`TemporalHazard`. Each is a
`gh repo rename` plus its own `URL:`, `BugReports:` and `_pkgdown.yml` update.

**Wave 3 — `hvtiBoostmtree` → `hvtiRboostmtree`. Blocked on an upstream sync, and the
rename must come second.** The repo carries an `upstream` remote at `cran/boostmtree`, and
the fork was taken at upstream **1.5.1 (2022-03-10)**. Upstream has since released
**boostmtree 2.0.0 (2026-04-08)**, which the fork has never merged. The gap is a
substantial refactor, not a patch — 25 files and roughly +4,175/−5,928 lines across `R/`
and `src/`, with files split apart (`boostmtree_math.R`, `boostmtree_object.R`,
`boostmtree_preprocess.R`, `boostmtree_response.R` are new upstream) and renamed
(`marginalPlot.R`→`marginal_plot.boostmtree.R`, `partialPlot.R`→
`partial_plot.boostmtree.R`, `vimpPlot.R`→`plot.vimp.boostmtree.R`).

Sync first, rename second. A rename touches `DESCRIPTION`, `NAMESPACE`, `man/`, `tests/`
and every `R/` file that names the package — precisely the files the upstream refactor
rewrites — so renaming first maximises the conflict surface against the merge, and renames
code that is about to be replaced wholesale.

Two things must be checked rather than assumed during that sync, and neither is a naming
question:

- **The fork's own 2.0.1 fixes may not survive.** They are in `vimpPlot()` and
  `plot.boostmtree()`; upstream *deleted* `vimpPlot.R` and rewrote `plot.boostmtree.R`.
  Each fix is either already handled upstream, or needs re-porting into the new layout.
- **The version numbers collide and mean different things.** The fork's `2.0.0` was its
  own rename release, built on upstream `1.5.1`; upstream's `2.0.0` is unrelated content.
  So `hvtiBoostmtree 2.0.1` reads as newer than `boostmtree 2.0.0` while actually sitting
  four years behind it. Post-sync numbering cannot reuse a taken number, and choosing it
  rolls a minor or major digit — the maintainer's call, not to be taken by default.

The sync gets its own design and plan. This document records only that Wave 3 depends on
it and follows it.

**Wave 4 — the umbrella and the cross-references.** Add the `## Naming` section to the
house-style source and recompose; update `members()` and `repos.yml`, including the three
new governance entries; archive `hvtiEDAreports`; fix the sibling files that name
`hvtiRdatasets` in prose (`hvtiPlotR/README.md`, four `AGENTS.md` files,
`hvtiRutilities/NEWS.md`).

Waves 2 and 3 differ in kind, not size. A repo rename is invisible to R — redirects absorb
it and no `library()` call changes. A package rename is a namespace change no redirect can
paper over. They are separated so Wave 2 can move fast and Wave 3 gets the care.

### Not done

Five documents under `specs/` keep the old name and are not rewritten:
`2026-08-04-hvtiRdatasets-design.md`, `2026-08-24-build-layer-design-capture.md`,
`plans/2026-08-04-hvtiRdatasets-s0.md`, `plans/2026-08-06-hvtiRdatasets-s1.md`, and this
document. The first four are dated records of what was decided on those days; rewriting
them would falsify the record, and this document supersedes them by reference. This one
names the old package because that is its subject.

## Risks

**pkgdown 404s — the one thing GitHub does not redirect.** Pages serves from a repo's own
`gh-pages` branch under its *current* name, so every renamed repo's documentation URL dies
at the moment of rename. A green pkgdown workflow is not evidence the site is served; that
failure mode has already occurred in this family. Each wave verifies its site with an
actual fetch against the Pages API, not a green check.

**Old and new packages coexist in a library.** Nothing uninstalls `hvtiRdatasets`, so a
stale script keeps working against a dead namespace instead of failing loudly. A
deprecation shim package is rejected: nothing imports this package, it is 0.x with an
explicitly unfrozen API, and a shim is a permanent artifact bought against a temporary
problem.

**Version bump is deliberately left open.** House rule is patch-only, with minor and major
reserved to the maintainer. Mechanically Wave 1 is `0.1.2 → 0.1.3`, and the plan will
carry that. But renaming the package is the most breaking change it can undergo, and
`0.2.0` would say so. Flagged for the maintainer's call at PR time; not decided here.

## Success criteria

- Every non-archived family repo's name equals its package name, or is a documented
  exception with its reason recorded.
- `devtools::test()` and `devtools::check()` are clean in every renamed package —
  0 errors, 0 warnings, 0 notes.
- Every pkgdown site resolves at its new URL, verified by fetch rather than by badge.
- `hvtiR::status()` and `hvtiR::doctor()` run clean against the renamed roster.
- `house-style` `check_repo()` passes for all thirteen governed repos.
- No file outside `specs/` still refers to `hvtiRdatasets` or `hvtiBoostmtree`, excepting
  historical citations of a real filename (for example `README.md`'s pointer to
  `specs/2026-08-04-hvtiRdatasets-design.md`, and `equivalence_signoff.yaml`'s citation of
  the same document) and changelog records — a `NEWS.md` heading for a release made under
  the old name, and prose describing what changed in a release, both of which must name the
  old package to remain useful to a reader.
