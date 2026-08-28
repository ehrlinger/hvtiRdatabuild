# Wave 4 — the umbrella, the cross-references, and the governance gap

**Date:** 2026-08-27
**Status:** Planned, not started.
**Design:** [`dev/specs/2026-08-27-hvti-naming-convention-design.md`](2026-08-27-hvti-naming-convention-design.md)
**Depends on:** Waves 1 and 2 (both landed). **Not** blocked by Wave 3.

## Why this plan exists

The design describes Wave 4 in one paragraph:

> Add the `## Naming` section to the house-style source and recompose; update `members()`
> and `repos.yml`, including the three new governance entries; archive `hvtiEDAreports`;
> fix the sibling files that name `hvtiRdatasets` in prose (`hvtiPlotR/README.md`, four
> `AGENTS.md` files, `hvtiRutilities/NEWS.md`).

A family-wide survey on 2026-08-27, after Wave 2 landed, found that description to be
substantially incomplete. It is not wrong about what Wave 4 must do; it is wrong about
how much there is, and it classifies two **functional defects** as prose.

Measured, over live files only (excluding `specs/`, `design/`, `docs/superpowers/`,
`inst/dev/`, `NEWS.md`, and generated `.claude/house-style.md`) — the three
development-record directories named here were the portfolio's conventions at
the time of measurement, and all three are `dev/specs/` now:

| Spec says | Survey finds |
|---|---|
| four `AGENTS.md` files | **11** `AGENTS.md` / `CLAUDE.md` / `.claude/CLAUDE.md` files across 9 repos |
| `hvtiPlotR/README.md` | hvtiPlotR: **22** `R/` files + 24 generated `man/` + 4 more |
| prose fixes | two defects that are **functional**, not prose |

## The two functional defects

These are the reason Wave 4 is not cosmetic and should not be deferred.

### 1. `hvtiR`'s registry cannot resolve the Wave 1 rename

`hvtiR/R/members.R` still lists the package as `hvtiRdatasets`. `hvtiRdatabuild` does not
appear anywhere in the registry. `R/install.R` resolves members by package name:

```r
build_specs <- function(registry, packages) {
  index <- match(packages, registry$package)
  if (anyNA(index)) {
    unknown <- packages[is.na(index)]
    cli::cli_abort("{.pkg {unknown}} {?is/are} not an hvtiR member.")
  }
  registry$repo[index]
}
```

So today:

- `install_members("hvtiRdatabuild")` aborts with *"is not an hvtiR member"*.
- `install_members("hvtiRdatasets")` resolves to a repo that redirects, then installs a
  package whose actual name is `hvtiRdatabuild` — so any subsequent
  `library(hvtiRdatasets)` fails.

`inst/extdata/catalog.csv` carries the same staleness, plus stale repo slugs for
`TemporalHazard`, `hvtiRpropensity` and the recipes book.

This is precisely the case the design says redirects cannot absorb: *"A package rename is
a namespace change no redirect can paper over."* Wave 1 deferred `members()` to Wave 4,
and that is exactly where the gap opened. It has been live since Wave 1 merged.

### 2. hvtiPlotR carries ~46 files of dead documentation links

hvtiPlotR's roxygen links to the recipes book, e.g. `R/upset-plot.R:99`:

```r
#'   \url{https://ehrlinger.github.io/hvti_graphics/upset.html}.
```

Verified 2026-08-27: `https://ehrlinger.github.io/hvti_graphics/` returns **404**;
`https://ehrlinger.github.io/hvtiGraphics/` returns **200**. GitHub redirects the repo, but
**GitHub Pages does not redirect on a rename** — the same lesson Wave 1 recorded.

The fix is in `R/`, not `man/`: 22 roxygen source files, then regenerate the 24 `man/`
files from them. Editing `man/` directly would revert on the next `roxygenise()`.

## Scope, by kind

### A. Functional — must fix

| Repo | File | What |
|---|---|---|
| `hvtiR` | `R/members.R` | package roster: `hvtiRdatasets` → `hvtiRdatabuild`; repo slugs |
| `hvtiR` | `inst/extdata/catalog.csv` | 4 stale name/slug pairs |
| `hvtiR` | `R/install.R` | 1 reference |
| `hvtiR` | `tests/testthat/test-members.R`, `test-install.R`, `test-install-helpers.R` | 7 hits total; these pin the roster |
| `hvtiPlotR` | 22 files under `R/` | book URLs in roxygen |
| `hvtiPlotR` | `README.md`, `_pkgdown.yml`, `DESCRIPTION`, `vignettes/plot-functions.qmd` | same dead book URLs — see the note below |
| `hvtiGraphics` | `.github/workflows/version-check.yml:56` | the mapping `TemporalHazard:temporal_hazard` |
| `hvtiGraphics` | `packages.bib:161` | citation URL, now 404 |

#### A README is not prose

An earlier draft of this plan filed hvtiPlotR's `README.md`, `_pkgdown.yml`, `DESCRIPTION`
and vignette under "config and prose". That was wrong, and the same misjudgement had
already caused a live defect: `TemporalHazard/README.md` was deferred as prose during
Wave 2, and pkgdown then rendered 16 stale references onto the front page of the published
docs — the site badge plus **all eight vignette links**, every one a 404
([TemporalHazard#188](https://github.com/ehrlinger/TemporalHazard/pull/188)).

A README's badges and links are live, and pkgdown publishes them. Treat any file
containing a URL as functional, regardless of how much prose surrounds it. Prose is text
that names a thing; a link is text that has to resolve.

### B. Generated — regenerate, never hand-edit

| Repo | File | Generated from |
|---|---|---|
| `hvtiPlotR` | 24 files under `man/` | the `R/` roxygen above |
| `hvtiR` | `man/members.Rd` | `R/members.R` |
| every governed repo | `.claude/house-style.md` | `house-style/repos.yml` + vault sources |

The composed artifact draws from **two** sources — the registry entry's `name:` field and
the vault prose. Recomposing after the source edit fixes both; a search-and-replace fixes
neither durably.

### C. Config and prose

- 11 `AGENTS.md` / `CLAUDE.md` / `.claude/CLAUDE.md` files: `hvtiRpropensity` (4+2),
  `hvtiRlifetables` (4), `hvtiBoostmtree` (3), `hvtiR` (3), `hvtiRtables` (2),
  `hvtiRbootstrap/.claude/CLAUDE.md` (2), `TemporalHazard` (1+1), `hvtiGraphics` (1),
  `hvtiRtemplates` (1).
- `hvtiR`: `README.md` (3), `vignettes/hvtiR.qmd` (4) — check both for links before
  treating either as prose.

hvtiPlotR's `README.md`, `_pkgdown.yml`, `DESCRIPTION` and vignette were listed here in an
earlier draft; they carry dead links and have moved to section A.

### D. The convention's home

Add `## Naming` to `house-style/sources/r-package-structure.md`
(`~/Documents/ObsidianVault/memory/r-package-structure.md`), beside the existing
`## DESCRIPTION` (line 586) and `## Versioning` (line 593) sections. Then recompose the
family. This is what turns a documented convention into a checked one — every governed
repo runs `house-style.yaml` in CI and fails on drift.

### E. Closing the governance gap

`repos.yml` governs 10 repos. Add three as `package-internal`
(`default_persona: a`, `secondary_personas: [c]`):

- `hvtiRtemplates`
- `hvtiRlifetables`
- `hvtiR`

Archive `hvtiEDAreports` (currently **not** archived; last push 2026-07-22). After this,
every non-archived repo in the family is governed.

### F. The simplification Wave 2 unlocked

The design's Clause 2 proposes deriving the mapping rather than hand-maintaining it:

```r
repo = paste0("ehrlinger/", package)
```

Verified: as of Wave 2 this holds for **every** member — `hvtiRdatabuild`,
`hvtiRpropensity`, `TemporalHazard`, `hvtiPlotR`, `hvtiBoostmtree` and the rest. It was
not true before Wave 2. Adopting it removes the hand-aligned parallel vectors in
`members.R`, which are the mechanism by which the roster can silently misalign.

Do this in the same PR as the roster fix, not separately — the fix and the reason the fix
was needed belong together.

## Explicitly not done

Left carrying old names, deliberately:

- `hvtiRdatabuild/README.md:122` — the `dev/specs/2026-08-04-hvtiRdatasets-design.md` citation.
- `hvtiRdatabuild/equivalence_signoff.yaml` — a historical filename citation.
- `hvtiRutilities/.github/workflows/lint.yaml:65` — a comment recording past behaviour.
- Every `NEWS.md`, and everything under `dev/specs/`, `design/`, `dev/`, `inst/dev/`,
  `docs/superpowers/` — dated records of what was decided when.
- `TemporalHazard/R/parity-helpers.R` — `temporal_hazard.binary`,
  `temporal_hazard.hazpred_binary`, `TEMPORAL_HAZARD_BIN` are user-facing API. Renaming
  them is a breaking change with its own version decision.
- `TemporalHazard` test comments citing `temporal_hazard#143` — issue refs still resolve.

## One decision needed before starting

`hvtiGraphics/temporal_hazard.qmd` is a book chapter named after the package, listed in
`_quarto.yml:34`. Renaming the file changes its published URL from
`/temporal_hazard.html` to `/TemporalHazard.html`.

That is not a mechanical fix. hvtiPlotR links to sibling chapters by filename
(`upset.html`, `survival.html`, …), and any external link to the chapter breaks with no
redirect — Pages does not provide one. Options: rename and accept the break; rename and
add a stub at the old path; or leave the filename and fix only the URLs inside it.

**Recommendation:** leave the filename. The chapter's *name* is not part of the naming
convention, which governs repos and packages. Renaming it buys tidiness and costs a dead
URL, and this wave already has two dead-link defects to clean up.

## Order of work

Nothing here is blocked by Wave 3. Suggested sequence, each its own PR:

1. **house-style** — `## Naming` source section, three governance entries, archive
   `hvtiEDAreports`. Land first: it is what the rest is checked against.
2. **Move the `house-style-v1` tag.** Merging (1) does not publish it. Consumers pin the
   tag, not `main`. Verify by reading `HEAD is now at <sha>` in a runner's checkout log —
   the `[new tag]` line appears either way and proves nothing.
3. **hvtiR** — roster, catalog, `install.R`, tests, Clause 2 derivation, then regenerate
   `man/`. This closes the live install defect; do it before the cosmetic passes.
4. **hvtiPlotR** — 22 `R/` files, then `roxygenise()`, then `DESCRIPTION`/README/pkgdown/vignette.
5. **hvtiGraphics** — `version-check.yml`, `packages.bib`, and the chapter decision.
6. **Prose sweep** — the 11 `AGENTS.md`/`CLAUDE.md` files, then recompose the family.

## Verification

Not "the workflow is green" — check the artifact:

- `hvtiR`: `install_members("hvtiRdatabuild")` resolves; `install_members("hvtiRdatasets")`
  fails with a clear message rather than installing something misnamed. Its own tests pin
  the roster, so they must be updated deliberately, not mechanically.
- `hvtiPlotR`: fetch two or three of the regenerated book URLs and confirm **200**, not
  merely that the string changed.
- Family: `compose-house-style.R --check` reports `OK` for every governed repo, including
  the three newly added ones.
- `hvtiEDAreports`: confirm `isArchived=true` via the API.
- Confirm no `man/` file was hand-edited: `roxygenise()` twice should be a no-op the
  second time.

## Wave 3

`hvtiBoostmtree` → `hvtiRboostmtree` remains **blocked and postponed** (maintainer
decision, 2026-08-27). It is a genuine package rename — `DESCRIPTION` reads
`Package: hvtiBoostmtree`, and 35 files carry the name — so it is a namespace change, not
a repo-only rename like Wave 2's.

It stays behind the upstream `boostmtree` sync (fork at upstream 1.5.1, upstream now
2.0.0, ~25 files and ±10k lines apart, with files split and renamed). Renaming first would
rename code the sync replaces wholesale.

After Wave 4, `hvtiBoostmtree` is the single repo off-convention. That is a documented,
deliberate exception, not drift.
