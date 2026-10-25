* `write_analysis_set()` refuses to build a set from a working read of the study dataset
  (`HVTI_DATA=working`, or a dataset with no dated version). An analysis set is reused by
  other jobs, so it is built from registered data only. It stops and writes nothing. Requires
  hvtiRutilities 1.5.3, which signals a working read.
* A study whose dataset was registered before dated versions (a manifest entry with no
  `parquet`) has no dated version, so `write_analysis_set()` now stops for it too. Run
  `hvtiRutilities::update_manifest()` once to convert it; sets already written read as before.
