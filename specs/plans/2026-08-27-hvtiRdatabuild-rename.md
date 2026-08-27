# hvtiRdatabuild Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the package and repository `hvtiRdatasets` to `hvtiRdatabuild`, leaving
`devtools::check()` at 0/0/0 and every CI workflow green.

**Architecture:** Wave 1 of
[`specs/2026-08-27-hvti-naming-convention-design.md`](../2026-08-27-hvti-naming-convention-design.md).
Six tasks. Task 1 lands in a *different repository* and is a hard prerequisite. Tasks 2–5
are ordinary branch commits here. Task 6 is out-of-repo GitHub and filesystem work that
cannot be done on a branch and needs maintainer authorisation.

**Tech Stack:** R (>= 4.1.0), roxygen2 8.1.0 with markdown, testthat edition 3, quarto
vignettes, pkgdown, GitHub Actions, the `house-style` composer.

## Global Constraints

- **Lines are 100 characters** in this repo. Read `.lintr`; do not assume a family default.
- **Roxygen markdown is enabled** (`Roxygen: list(markdown = TRUE)`) — write markdown, not
  Rd markup, in roxygen blocks.
- **testthat edition 3**; test files are `test-*.R` with a hyphen.
- **Definition of done:** `devtools::test()` passes and `devtools::check()` is **0 errors,
  0 warnings, 0 notes**; `devtools::document()` has been run with `man/` and `NAMESPACE`
  committed alongside the source change.
- **No real data and no patient value** enters the repo, a test, or a failure message.
- **Never push to `main`.** Branch, open a PR, let the maintainer merge. `main` is
  protected by a server-side ruleset; a rejected push is not a local hook.
- **Versions are straight three digits.** Never a `.9000` suffix or a fourth digit. Patch
  digit only — minor and major are the maintainer's decision.
- **The exact new name is `hvtiRdatabuild`.** The exact old name is `hvtiRdatasets`.
- **Do not rewrite anything under `specs/`.** Five documents there carry the old name as
  historical record. They are deliberately excluded from every search-and-replace in this
  plan.

## File Structure

Twenty-six files outside `specs/` carry the old name, 65 occurrences total.

| Group | Files | Handled in |
|---|---|---|
| Package identity | `DESCRIPTION`, `R/hvtiRdatasets-package.R` | Task 2 |
| Code | `R/dw_modules.R`, `R/dw_credentials.R`, `R/snapshot_oracle.R`, `R/print_built_comparison.R` | Task 2 |
| Tests | `tests/testthat.R`, `tests/testthat/test-package.R`, `tests/testthat/test-dw_modules.R`, `tests/testthat/helper-fixtures.R` | Task 2 |
| Generated docs | `man/hvtiRdatasets-package.Rd`, `man/print.built_comparison.Rd`, `man/snapshot_oracle.Rd` | Task 2 (regenerated, never hand-edited) |
| Prose | `README.md`, `vignettes/coming-from-sas.qmd`, `AGENTS.md`, `CLAUDE.md` | Task 3 |
| Config and CI | `_pkgdown.yml`, `codecov.yml`, `equivalence_signoff.yaml`, six `.github/workflows/*.yaml` | Task 4 |
| Release | `DESCRIPTION` (`Version`, `Date`), `NEWS.md` | Task 5 |
| Out of repo | GitHub repo name, `house-style-v1` tag, local clone directory | Task 6 |

---

## Task 1: Update the house-style registry (PREREQUISITE, different repo)

**Do this first.** `.github/workflows/house-style.yaml` in this repo greps the upstream
registry for a literal path and **exits 1 with an explicit error** when it is absent. Until
the registry is updated *and published*, the house-style job cannot pass under the new name.

**Files:**
- Modify: `~/Documents/GitHub/house-style/repos.yml` (the `hvtiRdatasets` entry)

**Interfaces:**
- Produces: registry entry `name: hvtiRdatabuild`, `path: ~/Documents/GitHub/hvtiRdatabuild`.
  Task 4 hard-codes both strings into this repo's workflow; they must match exactly.

**Why publication is separate:** the workflow checks out house-style at `ref: house-style-v1`,
which is an **annotated tag**, not a branch. Merging to `main` changes nothing for any
consumer until the tag is moved. That is deliberate — it is what stops a registry edit from
breaking ten repos at once — and it is why moving the tag is Task 6, not this task.

- [ ] **Step 1: Branch in the house-style repo**

```bash
cd ~/Documents/GitHub/house-style && git checkout main && git pull && git checkout -b rename/hvtiRdatabuild
```

- [ ] **Step 2: Confirm the tag currently matches main, so moving it later publishes only this change**

```bash
cd ~/Documents/GitHub/house-style && git diff --stat house-style-v1..main
```

Expected: **empty output**. If it is not empty, stop and report — moving the tag in Task 6
would publish unrelated source changes and could trigger drift failures in every governed
repo.

- [ ] **Step 3: Edit the registry entry**

In `repos.yml`, change exactly these two lines:

```yaml
  - name: hvtiRdatasets
    path: ~/Documents/GitHub/hvtiRdatasets
```

to:

```yaml
  - name: hvtiRdatabuild
    path: ~/Documents/GitHub/hvtiRdatabuild
```

Leave `profile: package-internal`, `default_persona: a` and `secondary_personas: [c]`
unchanged.

- [ ] **Step 4: Verify no other occurrence remains**

```bash
cd ~/Documents/GitHub/house-style && grep -rn "hvtiRdatasets" repos.yml
```

Expected: **no output**.

- [ ] **Step 5: Commit and open the PR**

```bash
cd ~/Documents/GitHub/house-style && git add repos.yml && git commit -m "chore: rename hvtiRdatasets to hvtiRdatabuild in the registry"
```

```bash
cd ~/Documents/GitHub/house-style && gh pr create --fill
```

Do not merge it yourself. Report the PR URL and continue to Task 2 — Tasks 2–5 do not
depend on it being merged, only Task 6 does.

---

## Task 2: Rename the package identity, code and tests

This is one task because a half-renamed package does not build. `DESCRIPTION` and every
`system.file(package = ...)` call must move together or `devtools::test()` fails.

**Files:**
- Modify: `DESCRIPTION:1`, `DESCRIPTION:15`, `DESCRIPTION:16`
- Rename: `R/hvtiRdatasets-package.R` → `R/hvtiRdatabuild-package.R`
- Modify: `R/dw_modules.R:36`, `R/dw_credentials.R:87`, `R/snapshot_oracle.R:35`,
  `R/print_built_comparison.R:16`, `R/print_built_comparison.R:25`
- Modify: `tests/testthat.R:2`, `tests/testthat.R:4`,
  `tests/testthat/test-package.R:2`, `tests/testthat/test-dw_modules.R:39,57,78`,
  `tests/testthat/helper-fixtures.R:19`
- Test: `tests/testthat/test-print_built_comparison.R` (new test added below)
- Delete: `man/hvtiRdatasets-package.Rd` (roxygen writes `man/hvtiRdatabuild-package.Rd`)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: package name `hvtiRdatabuild`; option name `hvtiRdatabuild.show_ids` (logical,
  default `FALSE`), read by `print.built_comparison(x, ..., show_ids)`.

**On the option rename — read this before Step 5.** `print.built_comparison()` defaults
`show_ids` to `getOption("hvtiRdatasets.show_ids", FALSE)`. That option is **PHI-gated**;
its own documentation says "Enabling this may emit PHI." Renaming it means a user with
`options(hvtiRdatasets.show_ids = TRUE)` in their `.Rprofile` is silently ignored.

**No compatibility fallback is built, deliberately.** The failure direction of the rename is
that identifiers *stop* printing, which is the conservative direction for a PHI flag. A
fallback that kept honouring the old name would preserve the setting that emits PHI, which
is the wrong thing to make resilient. The change is recorded in `NEWS.md` in Task 5.

- [ ] **Step 1: Branch**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && git checkout main && git pull && git checkout -b rename/hvtiRdatabuild
```

- [ ] **Step 2: Write the failing test for the renamed option**

Append to `tests/testthat/test-print_built_comparison.R`:

```r
test_that("show_ids defaults to the hvtiRdatabuild.show_ids option", {
  o <- data.frame(ccfidu = c("1234567820200115", "A2"), age = c(65, 70))
  r <- data.frame(ccfidu = "A2", age = 70)

  res <- compare_built(o, r, id = "ccfidu")

  withr::with_options(list(hvtiRdatabuild.show_ids = TRUE), {
    out <- paste(capture.output(print(res)), collapse = "\n")
    expect_match(out, "1234567820200115", fixed = TRUE)
  })

  withr::with_options(list(hvtiRdatabuild.show_ids = FALSE), {
    out <- paste(capture.output(print(res)), collapse = "\n")
    expect_false(grepl("1234567820200115", out, fixed = TRUE))
  })
})
```

This follows the file's existing pattern exactly: fixtures are built inline with
`compare_built()`, not from a helper, and absence is asserted with `expect_false(grepl(...))`
as the neighbouring test at line 26 does. `withr` is already in `Suggests`.

**The identifiers are invented**, matching the synthetic MRN-plus-date shape the existing
tests use so the assertion exercises the real PHI-redaction path. Do not substitute a real
one — `tests/testthat/helper-fixtures.R` opens "No PHI: ids and values are invented", and
this assertion prints its subject on failure.

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && Rscript -e 'devtools::load_all(); testthat::test_file("tests/testthat/test-print_built_comparison.R")'
```

Expected: FAIL on the first `expect_match`. The code still reads
`getOption("hvtiRdatasets.show_ids", FALSE)`, so setting the *new* option name has no
effect, `show_ids` stays `FALSE`, and the identifier is correctly withheld from the output.
The second block passes already — it asserts absence, which is the current behaviour
regardless of the option name. A run where *both* blocks pass means Step 5 was done early.

- [ ] **Step 4: Rename the package in DESCRIPTION**

`DESCRIPTION:1`:

```
Package: hvtiRdatabuild
```

`DESCRIPTION:15` and `DESCRIPTION:16`:

```
URL: https://github.com/ehrlinger/hvtiRdatabuild, https://ehrlinger.github.io/hvtiRdatabuild/
BugReports: https://github.com/ehrlinger/hvtiRdatabuild/issues
```

Leave `Version` and `Date` alone — they change in Task 5.

- [ ] **Step 5: Rename the option in `R/print_built_comparison.R`**

Line 16, inside the roxygen block:

```r
#'   side. Defaults to the `hvtiRdatabuild.show_ids` option, itself `FALSE`.
```

Line 25, in the formal argument default:

```r
                                   show_ids = getOption(
                                     "hvtiRdatabuild.show_ids", FALSE
                                   )) {
```

- [ ] **Step 6: Rename the package-level roxygen file**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && git mv R/hvtiRdatasets-package.R R/hvtiRdatabuild-package.R
```

Its contents need no edit — it is `#' @keywords internal` followed by `"_PACKAGE"`, and
roxygen takes the name from `DESCRIPTION`.

- [ ] **Step 7: Update the three remaining code references**

`R/dw_modules.R:36`:

```r
  dir <- system.file("extdata", "modules", package = "hvtiRdatabuild")
```

`R/snapshot_oracle.R:35` (inside the `@examples` block):

```r
#'                      package = "hvtiRdatabuild")
```

`R/dw_credentials.R:87`:

```r
         "protection can never be confirmed here. hvtiRdatabuild targets ",
```

- [ ] **Step 8: Update the tests**

`tests/testthat.R:2` and `tests/testthat.R:4`:

```r
library(hvtiRdatabuild)

test_check("hvtiRdatabuild")
```

`tests/testthat/test-package.R:2`:

```r
  expect_true(requireNamespace("hvtiRdatabuild", quietly = TRUE))
```

`tests/testthat/helper-fixtures.R:19`:

```r
  system.file("extdata", "oracle_small.sas7bdat", package = "hvtiRdatabuild")
```

`tests/testthat/test-dw_modules.R`, lines 39, 57 and 78 — each is a `system.file()` call;
change only the `package =` string:

```r
    system.file("extdata", "modules", package = "hvtiRdatabuild"),
```

```r
  dir <- system.file("extdata", "modules", package = "hvtiRdatabuild")
```

```r
                      package = "hvtiRdatabuild")
```

- [ ] **Step 9: Confirm no code or test reference remains**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && grep -rn "hvtiRdatasets" R/ tests/ DESCRIPTION
```

Expected: **no output**.

- [ ] **Step 10: Regenerate the documentation and drop the stale Rd**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && Rscript -e 'devtools::document()'
```

```bash
cd ~/Documents/GitHub/hvtiRdatasets && git rm --cached man/hvtiRdatasets-package.Rd && rm -f man/hvtiRdatasets-package.Rd && ls man/hvtiRdatabuild-package.Rd
```

Expected: `man/hvtiRdatabuild-package.Rd` exists. Roxygen names the package Rd file from
`DESCRIPTION`, so it writes the new one and leaves the old one orphaned; `R CMD check`
reports an orphaned Rd as a NOTE, which would break the 0/0/0 gate.

- [ ] **Step 11: Confirm no reference survives outside prose, config and specs**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && grep -rn "hvtiRdatasets" man/ NAMESPACE
```

Expected: **no output**.

- [ ] **Step 12: Run the full test suite**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && Rscript -e 'devtools::test()'
```

Expected: PASS, including the new option test from Step 2. If `arrow` is not installed some
tests skip — that is expected, and a skip is not a pass. Report any skips rather than
reading green as complete.

- [ ] **Step 13: Commit**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && git add -A && git commit -m "refactor!: rename package hvtiRdatasets to hvtiRdatabuild

The package exports six verbs and no data object, so a ...datasets name
promised a payload and delivered a pipeline.

Renames the PHI-gated print option hvtiRdatasets.show_ids to
hvtiRdatabuild.show_ids with no compatibility fallback. The failure
direction of the rename is that identifiers stop printing, which is the
conservative direction for a flag whose own docs warn it may emit PHI."
```

---

## Task 3: Update the prose

**Files:**
- Modify: `README.md` (10 occurrences, lines 1, 3, 4, 6, 8, 10, 28, 41, 74, 122)
- Modify: `vignettes/coming-from-sas.qmd:14`, `vignettes/coming-from-sas.qmd:105`
- Modify: `AGENTS.md:1`
- Modify: `CLAUDE.md:13`

**Interfaces:**
- Consumes: package name `hvtiRdatabuild` from Task 2.
- Produces: nothing later tasks read.

- [ ] **Step 1: Replace every occurrence in the four prose files except the specs citation**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && sed -i '' 's/hvtiRdatasets/hvtiRdatabuild/g' README.md vignettes/coming-from-sas.qmd AGENTS.md CLAUDE.md
```

- [ ] **Step 2: Restore the one citation that must keep the old name**

`README.md:122` cites a historical design document by its real filename. Step 1 will have
corrupted it. Set that line back to:

```markdown
See `specs/2026-08-04-hvtiRdatasets-design.md`.
```

- [ ] **Step 3: Verify the badge URLs and the citation**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && grep -n "hvtiRdatasets\|hvtiRdatabuild" README.md
```

Expected: nine `hvtiRdatabuild` lines (1, 3, 4, 6, 8, 10, 28, 41, 74) and exactly one
`hvtiRdatasets` line — 122, the specs citation. Every badge URL must read
`github.com/ehrlinger/hvtiRdatabuild` or `codecov.io/gh/ehrlinger/hvtiRdatabuild`.

- [ ] **Step 4: Confirm the vignette still renders**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && Rscript -e 'devtools::load_all(); quarto::quarto_render("vignettes/coming-from-sas.qmd")'
```

Expected: renders without error. `VignetteBuilder` is **quarto**, not knitr — if `quarto`
is not installed this step cannot run; say so rather than skipping silently.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && git add README.md vignettes/coming-from-sas.qmd AGENTS.md CLAUDE.md && git commit -m "docs: rename hvtiRdatasets to hvtiRdatabuild in prose

Leaves the specs/2026-08-04 citation in README pointing at the real
historical filename."
```

---

## Task 4: Update config and CI

**Files:**
- Modify: `_pkgdown.yml:1`, `_pkgdown.yml:13`
- Modify: `codecov.yml:1`
- Modify: `.github/workflows/house-style.yaml:56`, `:57`, `:68`, `:74`
- Modify: `.github/workflows/R-CMD-check.yaml:55`, `:66`
- Modify: `.github/workflows/check-manual.yaml:45`, `:58`
- Modify: `.github/workflows/lint.yaml:25`
- Modify: `.github/workflows/pkgdown.yaml:45`
- Modify: `.github/workflows/test-coverage.yaml:34`
- Leave alone: `equivalence_signoff.yaml:3` (a specs citation — see Step 2)

**Interfaces:**
- Consumes: the registry strings produced by Task 1 — `name: hvtiRdatabuild` and
  `path: ~/Documents/GitHub/hvtiRdatabuild`. `house-style.yaml` hard-codes both.

**Expect one red check on this PR.** After this task, the house-style job greps the
published registry for `path: ~/Documents/GitHub/hvtiRdatabuild`. The `house-style-v1` tag
still points at the old entry until Task 6 moves it, so the job fails with the workflow's
own explicit error. **That failure is expected and correct.** Do not "fix" it by reverting
this task or by loosening the grep — the check exists precisely so a registry mismatch is
loud. It clears when Task 6 moves the tag and the job is re-run.

- [ ] **Step 1: Replace in config and workflows**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && sed -i '' 's/hvtiRdatasets/hvtiRdatabuild/g' _pkgdown.yml codecov.yml .github/workflows/*.yaml
```

- [ ] **Step 2: Confirm `equivalence_signoff.yaml` was not touched**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && grep -n "hvtiRdatasets" equivalence_signoff.yaml
```

Expected: line 3 still reads `# specs/2026-08-04-hvtiRdatasets-design.md, "A signoff carries a`.
It is a citation of a real historical filename and Step 1's file list deliberately excludes
it. If it was changed, restore it.

- [ ] **Step 3: Verify the pkgdown reference index entry matches the new Rd**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && grep -n "package" _pkgdown.yml && ls man/hvtiRdatabuild-package.Rd
```

Expected: `_pkgdown.yml:13` reads `  - hvtiRdatabuild-package` and the matching Rd exists.
A reference index naming a topic with no Rd file fails the pkgdown build.

- [ ] **Step 4: Verify the house-style workflow's three strings agree**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && grep -n "hvtiRdatabuild" .github/workflows/house-style.yaml
```

Expected four lines: the `grep -qF` guard (56), its error message (57), the `sed`
replacement (68) — all three containing `path: ~/Documents/GitHub/hvtiRdatabuild` — and
`--repo hvtiRdatabuild` (74). The guard and the `sed` pattern must be character-identical or
the guard passes and the `sed` silently matches nothing.

- [ ] **Step 5: Run the full check**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && Rscript -e 'devtools::check()'
```

Expected: **0 errors, 0 warnings, 0 notes**. An orphaned `man/hvtiRdatasets-package.Rd`
surviving Task 2 Step 10 shows up here as a NOTE.

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && git add _pkgdown.yml codecov.yml .github/workflows && git commit -m "ci: rename hvtiRdatasets to hvtiRdatabuild in config and workflows

The house-style job will fail until the house-style-v1 tag is moved to
publish the renamed registry entry. That failure is expected."
```

---

## Task 5: Bump the version and write the changelog

`AGENTS.md` requires that a change which ships bumps the version, refreshes `Date`, and adds
the matching `NEWS.md` entry **in the same commit** — a test greps `NEWS.md` for the exact
`DESCRIPTION` version.

**Files:**
- Modify: `DESCRIPTION` (`Version`, `Date`)
- Modify: `NEWS.md` (new entry at the top; existing headings left alone)

**Interfaces:**
- Consumes: the option rename from Task 2, which this entry documents.

**On the version number.** This plan writes `0.1.3`, the patch bump the house rule
prescribes. **Flag it to the maintainer at PR time rather than assuming it is settled.**
Renaming the package is the most breaking change it can undergo and `0.2.0` would say so,
but minor digits are the maintainer's call and must not be rolled by an implementer.

**On the historical headings.** `NEWS.md` lines 13 and 68 read `# hvtiRdatasets 0.1.1` and
`# hvtiRdatasets 0.1.0`. Leave them. They record what the package was called at those
releases, and rewriting them would falsify the changelog the same way rewriting `specs/`
would. Line 6 is different — it is instructional prose telling a reader how to call
`utils::news()`, and it is now wrong.

- [ ] **Step 1: Fix the instructional line in the 0.1.2 entry**

`NEWS.md:6` — change only the package string inside the call:

```markdown
  history. It ships with the package, so `utils::news(package = "hvtiRdatabuild")`
```

- [ ] **Step 2: Add the new entry at the top of `NEWS.md`**

```markdown
# hvtiRdatabuild 0.1.3

## Breaking Changes

* Package renamed from `hvtiRdatasets` to `hvtiRdatabuild`. The package exports six
  functions and no data object, so a `...datasets` name promised a payload and delivered a
  pipeline. Update `library()` calls and any `hvtiRdatasets::` prefixes. The repository
  moved to `github.com/ehrlinger/hvtiRdatabuild`; GitHub redirects the old URL, so an
  existing `remotes::install_github("ehrlinger/hvtiRdatasets")` keeps resolving.
* The print option `hvtiRdatasets.show_ids` is now `hvtiRdatabuild.show_ids`. There is no
  fallback to the old name: a stale `options(hvtiRdatasets.show_ids = TRUE)` is ignored and
  identifiers are not printed. That is the conservative direction for a flag whose own
  documentation warns it may emit PHI.

No function changed behaviour, so results are identical to 0.1.2.
```

- [ ] **Step 3: Bump `DESCRIPTION`**

```
Version: 0.1.3
Date: 2026-08-27
```

- [ ] **Step 4: Verify the NEWS-versus-DESCRIPTION grep the test relies on**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && grep -m1 "^Version:" DESCRIPTION && grep -m1 "^# hvtiRdatabuild" NEWS.md
```

Expected: `Version: 0.1.3` and `# hvtiRdatabuild 0.1.3` — the version strings must match
exactly.

- [ ] **Step 5: Run the tests**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && Rscript -e 'devtools::test()'
```

Expected: PASS, including any version-consistency test.

- [ ] **Step 6: Commit and open the PR**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && git add DESCRIPTION NEWS.md && git commit -m "chore: release 0.1.3 with the hvtiRdatabuild rename"
```

```bash
cd ~/Documents/GitHub/hvtiRdatasets && gh pr create --fill
```

In the PR body, state two things explicitly: that the house-style check is expected to fail
until the `house-style-v1` tag moves, and that `0.1.3` is a patch bump the maintainer may
wish to make `0.2.0`.

---

## Task 6: Rename the repository and publish the registry (MAINTAINER AUTHORISATION REQUIRED)

Every step here is outward-facing or destructive to local paths, and **none of it may be
done without the maintainer explicitly approving it.** Moving a published tag is a
force-update that changes what ten other repositories read from CI.

**Files:** none in this repository.

**Interfaces:**
- Consumes: Task 1's merged registry change; Tasks 2–5 merged here.

- [ ] **Step 1: Confirm both PRs are merged before touching anything**

```bash
cd ~/Documents/GitHub/house-style && git checkout main && git pull && grep -n "hvtiRdatabuild" repos.yml
```

Expected: the renamed `name:` and `path:` lines. If not, stop — the tag must not move ahead
of the registry.

- [ ] **Step 2: Rename the GitHub repository**

```bash
gh repo rename hvtiRdatabuild --repo ehrlinger/hvtiRdatasets
```

GitHub keeps a redirect indefinitely, so `remotes::install_github("ehrlinger/hvtiRdatasets")`
and existing clones keep working.

- [ ] **Step 3: Point the local clone's origin at the new name**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && git remote set-url origin git@github.com:ehrlinger/hvtiRdatabuild.git && git remote -v
```

- [ ] **Step 4: Move the `house-style-v1` tag to publish the registry change**

```bash
cd ~/Documents/GitHub/house-style && git tag -f -a house-style-v1 -m "Publish hvtiRdatabuild rename" main && git push --force origin house-style-v1
```

- [ ] **Step 5: Re-run the failed house-style check and confirm it now passes**

```bash
cd ~/Documents/GitHub/hvtiRdatasets && gh run list --workflow=house-style.yaml --limit 3
```

Expected: a green run. If it still fails on the `grep -qF` guard, the tag did not move or
the two path strings differ — compare Task 4 Step 4's output against `repos.yml`.

- [ ] **Step 6: Rename the local clone directory**

**Read this before running it.** Renaming the working directory invalidates every absolute
path that points at the old one: any open shell's working directory, and the Claude project
memory directory at
`~/.claude/projects/-Users-ehrlinj-Documents-GitHub-hvtiRdatasets/`, which is keyed to the
project path and will no longer be found under the new one. The memory files are not lost —
they are still on disk under the old key — but they must be moved to be picked up again.

```bash
cd ~/Documents/GitHub && mv hvtiRdatasets hvtiRdatabuild && ls -d hvtiRdatabuild
```

```bash
mv ~/.claude/projects/-Users-ehrlinj-Documents-GitHub-hvtiRdatasets ~/.claude/projects/-Users-ehrlinj-Documents-GitHub-hvtiRdatabuild
```

- [ ] **Step 7: Verify the pkgdown site is actually served, not merely deployed**

```bash
gh api repos/ehrlinger/hvtiRdatabuild/pages --jq '.html_url, .status'
```

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://ehrlinger.github.io/hvtiRdatabuild/
```

Expected: `built` from the Pages API and `200` from the fetch. **A green pkgdown workflow is
not evidence the site is served** — that exact failure has already occurred in this family.
If the fetch returns 404, re-run the pkgdown workflow and check the Pages API again; the
`gh-pages` branch follows the repo rename but Pages sometimes needs a rebuild to pick it up.

- [ ] **Step 8: Verify the family roster still resolves**

```bash
cd ~/Documents/GitHub/hvtiverse && Rscript -e 'devtools::load_all(); print(status())'
```

Expected: this **will** show `hvtiRdatasets` as a member pointing at the redirected repo.
That is correct for now — updating `hvtiR::members()` is Wave 4, not Wave 1. Record the
output and do not change `members.R` here.

---

## Self-Review

**Spec coverage.** Wave 1 of the design covers `DESCRIPTION`, the package roxygen file,
tests, four roxygen blocks, `README.md`, `NEWS.md`, `_pkgdown.yml`, `codecov.yml`,
`equivalence_signoff.yaml`, the vignette, six workflows, `AGENTS.md` and `CLAUDE.md`. All
appear in Tasks 2–5. The spec's *Not done* clause — leave `specs/` alone — is enforced in
the Global Constraints and re-checked at Task 3 Step 2 and Task 4 Step 2. The spec's pkgdown
risk is Task 6 Step 7; its version-bump open question is Task 5's preamble.

**Two items the spec did not anticipate, added here.** The PHI-gated option rename
(Task 2), which no plain search-and-replace would have flagged as an API change; and the
`house-style-v1` tag coupling (Tasks 1, 4 and 6), which makes a second repository a hard
prerequisite and produces one expected red check.

**Not in scope.** `hvtiR::members()`, `house-style` governance additions, the archive of
`hvtiEDAreports` and the sibling repos' prose references are Wave 4. The roxygen
re-framing around reproducibility and the `snapshot_oracle()` SAS-only signature are
follow-on work recorded in the spec, not this plan.
