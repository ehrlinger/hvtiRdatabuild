* `write_analysis_set()` checks for a dated version before it reads the study dataset. A parent
  with none, including one registered before dated versions, stops at once and names
  `hvtiRutilities::update_manifest()`; reading it first let hvtiRutilities' legacy cache write a
  parquet and rewrite the manifest entry before the refusal. A refusal under `HVTI_DATA=working`
  on a registered dataset now says to unset `HVTI_DATA` and no longer suggests registering.
* The README says `vignette("registered-datasets", package = "hvtiRutilities")` ships with
  hvtiRutilities 1.5.12 and later.
