* `dw_pull()` now has an example that runs, pulling the `base` module from synthetic
  views in DuckDB, whose in-memory catalog resolves the module SQL's three-part names.
  `dw_connect()`'s example is real code under `\dontrun{}`, since it needs the ODBC driver
  and warehouse credentials, in place of a commented-out call. Both examples were
  comments only.
* DESCRIPTION spells out CORR (Cardiovascular Outcomes, Registries and Research) and HVTI
  (Heart, Vascular and Thoracic Institute), matching hvtiRutilities.
