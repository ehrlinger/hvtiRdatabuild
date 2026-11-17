# Record chart-review decisions on a pull

Reads a decisions file with one row per entry of
[`review_list()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/review_list.md):
`cohort_unit`, `criterion_id`, `outcome` (`"met"` or `"not_met"`) and
`reason_code`. An outcome that excludes the unit (not met on an include
criterion, or met on an exclude criterion) needs a code from
`reason_codes`. Codes, never free text: chart notes are PHI.

## Usage

``` r
apply_review(pull, path, reason_codes)
```

## Arguments

- pull:

  A `master_pull` awaiting review.

- path:

  Character. The decisions file, as CSV.

- reason_codes:

  Character. The study's declared reason codes.

## Value

The `master_pull`, with the review stages appended and `data` filtered.

## Details

A routed unit is settled at the criterion that routed it, so the stage
counts stay sequential: if review excludes it, the exclusion is recorded
at that criterion and no later stage counts the unit, whether or not a
later criterion also excluded it; if review keeps it, every later
outcome stands. The criterion's provenance records how many were
excluded at review and the decisions file's checksum. Each review
criterion is then its own stage, with source `review`. The file's
SHA-256 is recorded in the pull's metadata, and the pull is then
complete.

Each later criterion's tally of met, not met and undetermined units is
rebuilt from the units that reached it, using the outcomes
[`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md)
keeps in `review$outcomes`. A pull saved before that field existed has
none, so decisions that would change a counted stage are refused with an
error of class `hvtiRdatabuild_review_outcomes_missing`: pull again with
[`pull_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/pull_master.md)
and apply the decisions to the new pull. Decisions that change no
counted stage are applied as usual.

## See also

[`review_list()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/review_list.md),
[`review_criterion()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/review_criterion.md)
