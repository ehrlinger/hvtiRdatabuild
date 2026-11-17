* After chart review moves a unit back to the criterion that routed it, `apply_review()`
  rebuilds each later criterion's met, not met and undetermined tally from the units
  that reached it, so a stage's provenance agrees with its counts. The figures evaluated
  at the pull are kept beside the tally, labelled, where they differ. `pull_master()`
  keeps each unit's outcome at every warehouse and local criterion in `review$outcomes`.
* A pull saved while awaiting review before `review$outcomes` existed cannot have its
  stages recounted. `apply_review()` refuses decisions that would change a counted stage
  on such a pull (`hvtiRdatabuild_review_outcomes_missing`); pull again with
  `pull_master()` and apply the decisions to the new pull. Decisions that change no
  counted stage are applied as before.
