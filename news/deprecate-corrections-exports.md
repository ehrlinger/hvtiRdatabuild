* `backfill_corrections()`, `propose_correction()` and `decide_correction()` are
  deprecated. Corrections to master datasets move to the HVTR registry, and
  hvtiRdatabuild will read corrected data from it rather than record corrections
  itself. The functions still work and warn on every call with class
  `deprecatedWarning`; set `options(hvtiRdatabuild.warn_deprecated_corrections = FALSE)`
  to silence the warning (#101).
