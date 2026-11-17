* `cohort_query()` takes `criteria`: inclusion and exclusion criteria evaluated in the
  warehouse inside `pull_master()`'s transaction, each a counted cohort stage. A
  criterion (`criterion()`) wraps a test: `master_row()`, `view_rows()` (rows of another
  view in a day window, judged by `pick = "any"`, `"all"` or `"nearest"`), or
  `any_of()` / `all_of()`. Only keys and flags leave the database.
* No clinical defaults: `role`, `undetermined`, `window`, `pick`, `date_col` and, with
  `index = "first"`, `index_on` are required. `index_on = "eligible"` lets a patient's
  later encounter be the index when an earlier one is excluded.
* A unit a criterion cannot decide follows its `undetermined` route: exclude, keep, or
  chart review. `review_criterion()`, `review_list()` and `apply_review()` record review
  decisions from a checksummed file with declared reason codes, as `review` stages.
  `build_from_master()` and `freeze_study_pull()` refuse a pull awaiting review.
* `local_criterion()` decides a criterion in R from a file outside the warehouse, after
  the snapshot, and records the file's SHA-256.
* `review` is a fourth cohort stage source.
* `pull_master()` checks that every candidate unit matches one master row before any
  criterion runs, so a criterion can no longer filter a duplicate key out of sight.
