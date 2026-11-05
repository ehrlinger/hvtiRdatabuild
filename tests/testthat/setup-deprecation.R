# The corrections exports are deprecated and warn on every call. The suites
# that exercise their behaviour run with the warning silenced;
# test-corrections-deprecation.R turns it back on to check the warning itself.
withr::local_options(
  hvtiRdatabuild.warn_deprecated_corrections = FALSE,
  .local_envir = testthat::teardown_env()
)
