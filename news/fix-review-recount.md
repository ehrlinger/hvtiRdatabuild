* After chart review moves a unit back to the criterion that routed it, `apply_review()`
  rebuilds each later criterion's met, not met and undetermined tally from the units
  that reached it, so a stage's provenance agrees with its counts. The figures evaluated
  at the pull are kept beside the tally, labelled, where they differ. `pull_master()`
  keeps each unit's outcome at every warehouse and local criterion in `review$outcomes`.
