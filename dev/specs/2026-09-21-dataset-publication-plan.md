# Dataset Publication Implementation Plan (hvtiRdatabuild)

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the producer half of the approved dataset-release contract:
publish an immutable dated dataset, register it atomically in
`dataset-catalog.yml`, and withdraw a release without changing or deleting its
bytes.

**Architecture:** A new `R/dataset_publication.R` owns catalog validation,
draft staging, dated release naming, catalog locking, atomic catalog writes,
idempotent retry, orphan recovery, and withdrawal. `publish_dataset()` copies
the draft bytes rather than converting them, then re-reads the staged copy with
the supported clinical-data reader before taking the catalog lock. The lock is
held only while deriving identity and committing the file/catalog pair.
`withdraw_dataset_release()` changes catalog metadata under the same lock and
never touches the release file. The version-1 fixture is copied verbatim from
the consumer package so both implementations are tested against the same
schema.

**Tech Stack:** R, yaml, digest, filelock and hvtiRutilities (Imports);
testthat 3e and parallel for tests.

**Approved specification:**
`hvtiRutilities/dev/specs/2026-09-21-dataset-release-contract-design.md`
at commit `main` after PR #139. This plan implements only the producer-owned
parts of that cross-package contract.

## Global Constraints

- Drafts remain mutable and invisible. Only catalog entries are releases.
- Published bytes are immutable. No success or failure path rewrites or
  removes a published release.
- `dataset-catalog.yml` is in the supplied logical datasets directory;
  catalog filenames are basenames relative to that directory.
- `dataset_id` is lower-case letters, digits and underscores, beginning with
  a letter. It also supplies the default release filename stem.
- Supported draft formats are the formats accepted by
  `hvtiRutilities::read_clinical_data()`: `.sas7bdat`, `.csv`, `.xlsx`,
  `.xls`, and `.rds`. Publication preserves the original extension and bytes.
- The public publisher interface is
  `publish_dataset(draft, dataset_id, datasets_dir, extract_date = Sys.Date(),
  source = NULL, file_stem = dataset_id)`.
- The public withdrawal interface is
  `withdraw_dataset_release(dataset_id, release_id, datasets_dir, reason,
  replacement_release_id = NULL)`.
- The first release on a date is `<file_stem>_YYYYMMDD.<ext>`; later releases
  are `<file_stem>_YYYYMMDD_rN.<ext>`.
- Release IDs are `<dataset_id>-YYYYMMDD-rN`; sequence is global within one
  logical dataset and revision restarts at 1 for each extract date.
- Publishing the same checksum again for the same dataset and extract date is
  idempotent and returns the existing record.
- If the next expected final path is an unregistered orphan with matching
  bytes, retry registers it. Different bytes at that path are an integrity
  error.
- Use `filelock` for a cross-process lock beside the catalog. Do not implement
  a home-grown lock directory or silently break a stale lock.
- All fixtures are synthetic. Errors report paths, release IDs, checksums and
  dimensions only; never print row values.
- Roxygen markdown is enabled. Lines are at most 100 characters.
- Every export goes in `_pkgdown.yml`.
- Add `# hvtiRdatabuild (unreleased)` and a user-facing NEWS entry. Do not bump
  `Version:` in the feature PR.
- Require `hvtiRutilities (>= 1.3.1)` so the producer and consumer contract
  versions move together. Merge/release hvtiRutilities 1.3.1 before opening
  this implementation PR.

## File Map

| File | Action | Purpose |
|---|---|---|
| `R/dataset_publication.R` | create | catalog writer, publisher and withdrawal |
| `tests/testthat/helper-dataset-publication.R` | create | synthetic draft/catalog helpers |
| `tests/testthat/test-dataset-publication.R` | create | producer contract tests |
| `tests/testthat/fixtures/dataset-catalog-v1.yml` | create | shared consumer/producer fixture |
| `DESCRIPTION` | modify | add `filelock`; require utilities 1.3.1 |
| `NAMESPACE` | regenerate | export the two public functions |
| `man/publish_dataset.Rd` | generate | publisher reference |
| `man/withdraw_dataset_release.Rd` | generate | withdrawal reference |
| `_pkgdown.yml` | modify | add a Dataset publication section |
| `NEWS.md` | modify | describe the shipped producer API |

---

### Task 0: Record the plan and protect the baseline

**Files:**
- Create: `dev/specs/2026-09-21-dataset-publication-plan.md`

- [ ] Confirm the isolated branch starts at current `origin/main` and the
  ordinary checkout's `spec/lst-exposure` changes remain untouched.
- [ ] Run `Rscript -e 'devtools::test()'`.
- [ ] Expected baseline: `FAIL 0 | WARN 0 | SKIP 11 | PASS 288`.
- [ ] Commit this plan:

```sh
git add dev/specs/2026-09-21-dataset-publication-plan.md
git commit -m "docs: plan immutable dataset publication"
```

### Task 1: Freeze and validate the version-1 catalog contract

**Files:**
- Create: `tests/testthat/fixtures/dataset-catalog-v1.yml`
- Create: `tests/testthat/helper-dataset-publication.R`
- Create: `tests/testthat/test-dataset-publication.R`
- Create: `R/dataset_publication.R`

**Interfaces:**
- Internal `.publication_catalog_path(datasets_dir)` returns
  `<datasets_dir>/dataset-catalog.yml`.
- Internal `.publication_read_catalog(path, allow_missing = FALSE)` returns a
  normalized version-1 catalog or errors with a `dataset catalog:` prefix.
- Internal `.publication_validate_release()` enforces the consumer's required
  fields and scalar types.
- Test helper `local_publication_dir()` returns a temporary directory.
- Test helper `write_synthetic_draft()` writes invented rows only.

- [ ] Copy `tests/testthat/fixtures/dataset-catalog-v1.yml` byte-for-byte from
  the hvtiRutilities consumer fixture.
- [ ] Write failing tests that accept the shared fixture and reject:
  unknown versions; invalid dataset IDs; missing required fields; invalid
  dates/timestamps/checksums; duplicate release IDs, sequences or files;
  non-increasing sequences; non-contiguous same-date revisions; path traversal;
  withdrawn releases without a reason; and unknown replacement IDs.
- [ ] Test that a missing catalog is allowed only when `allow_missing = TRUE`,
  returning `list(format_version = 1L, datasets = list())`.
- [ ] Run:

```sh
Rscript -e 'devtools::test(filter = "dataset-publication")'
```

  Expected: FAIL because `.publication_read_catalog()` does not exist.
- [ ] Implement the minimum validator needed to pass. Keep it private; do not
  call unexported hvtiRutilities functions with `:::`.
- [ ] Run the focused test. Expected: PASS.
- [ ] Commit:

```sh
git add R/dataset_publication.R tests/testthat/helper-dataset-publication.R \
  tests/testthat/test-dataset-publication.R \
  tests/testthat/fixtures/dataset-catalog-v1.yml
git commit -m "test: freeze dataset catalog producer contract"
```

### Task 2: Stage and inspect a mutable draft

**Files:**
- Modify: `R/dataset_publication.R`
- Modify: `tests/testthat/test-dataset-publication.R`

**Interfaces:**
- Internal `.publication_validate_request()` validates paths, IDs, date,
  optional source and filename stem before creating a file.
- Internal `.publication_stage_draft()` copies the draft into a unique
  temporary file inside `datasets_dir`, re-reads it with
  `hvtiRutilities::read_clinical_data()`, and returns path, extension, SHA-256,
  row count and column count.
- Internal `.publication_identity()` derives sequence, revision, release ID
  and final basename from validated catalog state.

- [ ] Write failing tests for missing drafts, unsupported extensions, invalid
  IDs, invalid dates, unsafe stems, and a datasets path that is not a directory.
- [ ] Test that staging preserves the draft checksum exactly and derives shape
  from a second read of the staged file.
- [ ] Inject a draft rewrite after the first read and assert that the staged
  copy, not the later draft state, supplies the published checksum and shape.
- [ ] Test first-release and same-date naming, revision reset on a later date,
  and sequence continuing across dates.
- [ ] Assert failures contain no synthetic row value from the fixture.
- [ ] Run the focused tests. Expected: FAIL on the first missing helper.
- [ ] Implement validation, byte-preserving staging, cleanup with `on.exit()`,
  and pure identity derivation.
- [ ] Run the focused tests. Expected: PASS.
- [ ] Commit:

```sh
git add R/dataset_publication.R tests/testthat/test-dataset-publication.R
git commit -m "feat: stage and identify dataset releases"
```

### Task 3: Publish under a catalog lock

**Files:**
- Modify: `DESCRIPTION`
- Modify: `R/dataset_publication.R`
- Modify: `tests/testthat/test-dataset-publication.R`

**Interfaces:**
- Internal `.with_catalog_lock(path, code, timeout = 10000)` obtains a
  `filelock` lock at `<catalog>.lock` and always releases it.
- Internal `.publication_write_catalog()` writes YAML to a temporary neighbor,
  validates the temporary catalog, then atomically renames it over the target.
- Exported `publish_dataset()` returns the release record invisibly.

- [ ] Add `filelock` to Imports and raise hvtiRutilities to `>= 1.3.1`.
- [ ] Write a failing first-publication test. Assert:
  release bytes equal draft bytes; catalog metadata and checksum match the
  file; required fields are present; source is omitted when `NULL`; no draft
  path is stored; and no temporary file remains.
- [ ] Write failing tests for a second same-day release and a later-date
  release.
- [ ] Write a failing idempotency test: a repeated publication of identical
  bytes returns the existing record and creates neither a new release nor a
  new file.
- [ ] Write a failing overwrite test: different bytes at the next final path
  produce an integrity error and leave both file and catalog unchanged.
- [ ] Write a failing orphan-recovery test by injecting catalog-write failure
  after the final file move. Retry the same bytes and assert that it registers
  the orphan without rewriting it.
- [ ] Write a two-worker `parallel` test that publishes two different drafts
  for one dataset/date. Assert exactly two valid catalog entries, unique
  sequences/revisions/files, and both files' checksums.
- [ ] Run the focused tests. Expected: FAIL because `publish_dataset()` does
  not exist.
- [ ] Implement the lock-bounded commit in this order:
  re-read/validate catalog; return an identical same-date release if present;
  derive identity; reconcile an orphan; rename staged bytes; atomically append
  catalog; return the record.
- [ ] On catalog failure after file move, retain the orphan for retry and emit
  an error naming the orphan path. On every earlier failure, remove only the
  unpublished temporary file.
- [ ] Run the focused tests repeatedly, including the concurrency test.
  Expected: PASS on at least three consecutive runs.
- [ ] Commit:

```sh
git add DESCRIPTION R/dataset_publication.R \
  tests/testthat/test-dataset-publication.R
git commit -m "feat: publish immutable dataset releases"
```

### Task 4: Withdraw without mutating a release

**Files:**
- Modify: `R/dataset_publication.R`
- Modify: `tests/testthat/test-dataset-publication.R`

**Interfaces:**
- Exported `withdraw_dataset_release()` returns the updated release record
  invisibly.

- [ ] Write failing tests that publish a release, record its bytes/checksum,
  withdraw it, and assert only catalog metadata changed.
- [ ] Test rejection of empty reasons, unknown dataset/release IDs, an unknown
  replacement, a replacement from another dataset, self-replacement, and a
  second withdrawal.
- [ ] Test a valid replacement and assert `replacement_release_id` is stored.
- [ ] Test lock contention so withdrawal cannot race publication.
- [ ] Run focused tests. Expected: FAIL because
  `withdraw_dataset_release()` does not exist.
- [ ] Implement withdrawal as one locked catalog read/validate/update/atomic
  write. Never open the release file for writing and never remove it.
- [ ] Run focused tests. Expected: PASS.
- [ ] Commit:

```sh
git add R/dataset_publication.R tests/testthat/test-dataset-publication.R
git commit -m "feat: withdraw published dataset releases"
```

### Task 5: Document the producer boundary

**Files:**
- Modify: `R/dataset_publication.R`
- Modify: `_pkgdown.yml`
- Modify: `NEWS.md`
- Generate: `NAMESPACE`
- Generate: `man/publish_dataset.Rd`
- Generate: `man/withdraw_dataset_release.Rd`

- [ ] Add roxygen documentation with synthetic examples. Explain mutable
  drafts, immutable releases, same-day revisions, idempotent retry, orphan
  recovery, catalog locking, withdrawal, and explicit study adoption in
  hvtiRutilities.
- [ ] Document that `publish_dataset()` validates readability and dimensions,
  but does not certify clinical correctness.
- [ ] Add both exports to a `Dataset publication` pkgdown section.
- [ ] Add an unreleased NEWS entry describing the producer workflow and its
  dependency on hvtiRutilities 1.3.1.
- [ ] Run `Rscript -e 'devtools::document()'`.
- [ ] Run `git diff --check` and inspect every generated diff.
- [ ] Commit:

```sh
git add R/dataset_publication.R DESCRIPTION NAMESPACE man _pkgdown.yml NEWS.md
git commit -m "docs: explain dataset publication workflow"
```

### Task 6: Verify and open the implementation PR

- [ ] Run the complete test suite:

```sh
Rscript -e 'devtools::test()'
```

- [ ] Install before lint so cross-file references resolve, then run lint:

```sh
R CMD INSTALL --no-docs .
Rscript -e 'print(lintr::lint_package())'
```

- [ ] Run documentation again and require no generated diff:

```sh
Rscript -e 'devtools::document()'
git diff --exit-code -- DESCRIPTION NAMESPACE man
```

- [ ] Run the full package check. Expected: 0 errors, 0 warnings, 0 notes.

```sh
Rscript -e 'devtools::check()'
```

- [ ] Build the PDF manual:

```sh
R CMD Rd2pdf --output=/tmp/hvtiRdatabuild-manual.pdf .
```

- [ ] Run `git status --short`, `git diff --check`, and inspect the branch diff
  against `origin/main` for PHI, credentials, accidental fixtures and unrelated
  edits.
- [ ] Confirm the original `spec/lst-exposure` checkout still has exactly its
  pre-existing two modified files.
- [ ] Push `codex/dataset-publication` and open a PR. Do not merge or bump the
  package version in this feature PR.

### Task 7: Release sequencing after the feature merges

- [ ] In a new branch from updated databuild `main`, rename the unreleased NEWS
  heading to `# hvtiRdatabuild 0.2.3`, set `Version: 0.2.3`, and set the date.
- [ ] Re-run the complete release gates and open a release-only PR.
- [ ] After hvtiRdatabuild 0.2.3 merges, refresh hvtiR's package catalog so it
  records `hvtiRutilities 1.3.1` and `hvtiRdatabuild 0.2.3`.
- [ ] In a separate hvtiR release branch, run its repository-specific gates,
  then bump hvtiR from 1.2.0 to 1.2.1 and open the release PR.

## Review Focus

Before implementation, confirm these two implementation choices:

1. `filelock` is acceptable as a new hard dependency for cross-process
   publication safety.
2. `withdraw_dataset_release()` is the desired public name for the catalog-only
   withdrawal operation.
