* Documentation sweep before 0.3.5. `apply_review()` and `review_list()` gain a runnable
  example on synthetic data. The README's status section lists the stages that ship,
  `build_dataset()` and `derive_vars()` among them, which it still called future work; it
  links `vignette("master-datasets")`, and says a stale analysis set is read with a note in
  a draft and refused in a final render. `vignette("master-datasets")` calls
  `propose_correction(var_col =)`, so it no longer prints a deprecation warning, and points
  to `pull_master()` and `build_from_master()` for reading a master into a study.
  `vignette("coming-from-sas")` says `compare_built()` matches ids exactly, without
  trimming, and that a row whose `exclude` rule is `NA` is kept and counted in `n_na_kept`,
  with the rule to write when the SAS step deleted it.
