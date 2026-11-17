* `propose_corrections()` now checks that each key survives the warehouse's cast to its
  key column unchanged, as it already did for values. Before, an integer key `1.2` loaded
  as `1`, so a correction could name, and after acceptance change, a different row. Such
  a key is now `unknown_key`.
* `study_correction_candidates()` refuses a missing key in the pull or in `data`
  (`missing_key`); before, a missing key read as the text `"NA"` and could match a real
  key of that value. Its composite keys are now collision-safe, whatever the values
  contain.
