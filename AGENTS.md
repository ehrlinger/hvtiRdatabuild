# hvtiRdatasets

Builds analysis-ready clinical datasets from the HVTI data warehouse and verifies them against
the legacy SAS datasets they replace. Six exports: `dw_connect()`, `dw_modules()`, `dw_pull()`,
`read_study_config()`, `snapshot_oracle()` and `compare_built()`.

**This is the package that touches PHI and warehouse credentials.** Most of its rules are
about not leaking either, and they are not negotiable for convenience.

This file is the operational contract and applies in full. It is tool neutral, so Codex and
any other agent read the same rules. Claude Code affordances live in `CLAUDE.md`, which
imports this file.

## Definition of done

- `devtools::test()` passes.
- `devtools::check()` is **0 errors, 0 warnings, 0 notes**. Verified 2026-08-20 at 0.1.1
  (25s with `--no-manual` and vignettes skipped; the manual has its own gate).
- `devtools::document()` has been run and `man/` and `NAMESPACE` are committed with the
  source change.
- No real data, and no patient value, has entered the repository or a test message.

## The automated gates

| workflow | fails on |
|---|---|
| `R-CMD-check.yaml` | `R CMD check` across platforms |
| `check-manual.yaml` | the PDF manual build |
| `lint.yaml` | `lintr::lint_package()` |
| `pkgdown.yaml` | the site build |
| `house-style.yaml` | the composed house style |
| `test-coverage.yaml` | coverage upload |

## PHI and credentials — the rules that matter most

- **Fixtures are synthetic, and say so.** `tests/testthat/helper-fixtures.R` opens
  "No PHI: ids and values are invented." Any new fixture is invented the same way. Do not
  reduce a real dataset and call it a fixture — a subset of PHI is still PHI.
- **`.gitignore` blocks `*.sas7bdat` and `*.parquet` globally**, with exactly one deliberate
  exception (`inst/extdata/oracle_small.sas7bdat`) plus `oracle/`. If a data file needs to be
  committed, that is a decision to raise, never a `git add -f`.
- **The real-study integration test never copies from the study.**
  `test-integration-real-study.R` runs only when `HVTI_ORACLE_DIR` points at real SAS
  datasets, a directory that holds PHI and lives outside this repository. Its assertions are
  on **shape and verdicts only**, and **no patient value may appear in a failure message**.
  When adding an assertion there, check what it prints on failure, not just what it compares.
- **The credential ladder order is fixed by design, and the reason is subtle.** `dw_connect()`
  stops at the first resolvable source: **Kerberos** (no stored secret at all) → **ODBC DSN**
  (the driver holds the credential) → **`HVI_DW_UID`/`HVI_DW_PWD` in `~/.Renviron`** →
  **`keyring`** (documented, not default; it assumes a Secret Service daemon a headless server
  does not have).
  A DSN outranks `.Renviron` because `.Renviron` puts the password in the R process
  environment, where `Sys.getenv()` prints it and any handler dumping the environment on error
  captures it. **A DSN password is read by the driver and never enters R's memory.** Do not
  reorder this ladder for convenience, and do not add a source that holds a secret in R.

## Rules for this repo

- **A SAS oracle must be a checksummed snapshot, not a live path.** `snapshot_oracle()` reads
  a SAS dataset once with haven, writes parquet, and records a SHA-256. The reason: a SAS
  dataset on a shared volume can be regenerated at any time, and if it changes mid-migration
  **every previously passing comparison silently becomes meaningless**. Compare against the
  snapshot, cite the checksum.
- **The snapshot does not remove haven from the chain of custody — it confines it to one
  audited step.** A misread is faithfully preserved in the parquet. Use `expect` to validate
  the conversion; do not treat "it round-tripped" as "it read correctly".
- **Roxygen markdown is ENABLED** (`Roxygen: list(markdown = TRUE)`), so write markdown in
  roxygen blocks.
  ⚠️ `hvtiRutilities` and `hvtiRtemplates` have no such field and need Rd markup instead.
- **Lines are 100 characters here.** ⚠️ A fourth value in the family: 80 in `hvtiRutilities`,
  120 in `hvtiPlotR`, 135 in `hvtiRtemplates`. Read `.lintr` rather than assuming.
- **`object_usage_linter` is excluded for `test-integration-real-study.R` only** — a file key,
  not a directory key. Keep exclusions per-file.
- **`testthat` edition 3**, with snapshots under `tests/testthat/_snaps`. Review a snapshot
  diff rather than accepting it reflexively.
- Test files are `test-*.R` with a hyphen. ⚠️ `hvtiPlotR` uses `test_*.R`.

## Gotchas

- The package is **0.x**: its API is not yet frozen, but the PHI and credential rules above
  are, and predate the version.
- `VignetteBuilder` is **quarto**, not `knitr`.
- `arrow` is a soft dependency — the real-study test skips when it is absent
  (`skip_if_not_installed("arrow")`), so a green local run does not prove that path ran.

## Git and versioning

- **Never push to `main`.** Branch, then open a PR and let the maintainer merge.
- **`main` is protected by a GitHub ruleset, and nothing in this repo records that.** A clone
  shows no trace of it, so it is stated here. The ruleset is named `protect main`, is
  identical across all twelve repositories in the HVTI R package family, and enforces four
  rules on the default branch: no deletion, no force-push, pull-request-only, and an
  **automatic Copilot code review** on every PR. A rejected push comes from the server, not a
  local hook.
  ⚠️ It currently requires **zero approvals**. `require_code_owner_review` is set but inert
  because no repository in the family has a `CODEOWNERS` file, so a PR can merge unreviewed.
- Versions are **straight three digits** (`0.1.1`). Never a `.9000` suffix or a fourth digit.
- **Patch-digit bumps only**, as fixes land. Minor and major are the maintainer's decision.
- **A change that ships bumps the version.** Bump `DESCRIPTION`, refresh its `Date`, and add
  the matching `NEWS.md` entry in the same commit. "Ships" means the file lands in the built
  tarball: `R/`, `man/`, `NAMESPACE`, `inst/`, `tests/`, `vignettes/`, `README.md`.
- **Repo-governance files do not bump the version.** `AGENTS.md`, `CLAUDE.md`, `.github/`,
  `specs/`, `.lintr`, `_pkgdown.yml` and `equivalence_signoff.yaml` are all listed in
  `.Rbuildignore`, so they never reach an installed package, and a bump would announce a
  change no user can observe. The test is mechanical, so read `.Rbuildignore` rather than
  judging by feel: if the file is excluded there, no bump and no `NEWS.md` entry. The
  docs-only commits already on `main` (`6ca1faa`, `ee28201`, `1f7d99a`) follow this.

## Change discipline

1. **Think before coding.** Do not assume, ask. If the request is ambiguous or a name, path
   or signature is uncertain, surface the confusion rather than running with a guess.
2. **Simplicity first.** Write the minimum that solves the stated problem.
3. **Surgical changes.** Touch only what the task requires. Raise nearby problems separately.
4. **Goal-driven execution.** State what done looks like before starting, and use tests as the
   criterion. For anything touching PHI or credentials, "done" includes checking what the code
   prints on failure.

## Prose

Documentation prose follows the house voice. Examples and vignettes here must use synthetic
data — an example is documentation that runs, and `R CMD check` runs it on machines that are
not yours.
