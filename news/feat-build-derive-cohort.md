- Add a patient-safe `cohort_record` for ordered inclusion, exclusion, and
  attrition history.
- Add `build_dataset()` to join patient-level modules and retain repeated-event
  tables.
- Add `derive_vars()` for study-specific R code with ordered, recorded
  exclusions.
- Document the synthetic build, study-code, and attrition workflow in the SAS
  migration vignette.
- Preserve duplicate source identifier columns for audit, keep patient
  identifiers stable across joins, and redact callback diagnostics and
  structural inspection.
